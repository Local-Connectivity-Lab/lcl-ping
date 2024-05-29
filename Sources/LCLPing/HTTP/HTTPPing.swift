//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import Collections

typealias HTTPOutboundIn = UInt16
typealias HTTPOuboundInput = (UInt16, HTTPRequestHead)

internal struct HTTPPing: Pingable {

    var summary: PingSummary? {
        get {
            // return empty if ping is still running
            switch pingStatus {
            case .ready, .running, .error:
                return .empty
            case .cancelled, .finished:
                return pingSummary
            }
        }
    }

    private(set) var pingStatus: PingState = .ready
    private var pingSummary: PingSummary?
    private let httpOptions: LCLPing.PingConfiguration.HTTPOptions

#if INTEGRATION_TEST
    private var networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?
    internal init(httpOptions: LCLPing.PingConfiguration.HTTPOptions, networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration) {
        self.httpOptions = httpOptions
        self.networkLinkConfig = networkLinkConfig
    }
#endif

    internal init(httpOptions: LCLPing.PingConfiguration.HTTPOptions) {
        self.httpOptions = httpOptions
    }

    // TODO: implement non-async version

    mutating func start(with pingConfiguration: LCLPing.PingConfiguration) async throws {
        let addr: String
        var port: UInt16
        switch pingConfiguration.endpoint {
        case .ipv4(let address, .none):
            addr = address
            port = 80
        case .ipv4(let address, .some(let p)):
            addr = address
            port = p
        case .ipv6:
            throw PingError.operationNotSupported("IPv6 currently not supported")
        }

        logger.debug("[\(#function)]: using address: \(addr), port: \(port)")

         guard let url = URL(string: addr) else {
            throw PingError.invalidURL
        }

        guard let host = url.host else {
            throw PingError.httpMissingHost
        }

        guard let schema = url.scheme, ["http", "https"].contains(schema) else {
            throw PingError.httpMissingSchema
        }

        let httpOptions = self.httpOptions
#if INTEGRATION_TEST
        let networkLinkConfig = self.networkLinkConfig
#endif
        let enableTLS = schema == "https"
        port = enableTLS && port == 80 ? 443 : port
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try! eventLoopGroup.syncShutdownGracefully()
        }

        let resolvedAddress = try SocketAddress.makeAddressResolvingHost(host, port: Int(port))
        logger.debug("resolved address is \(resolvedAddress)")

        if pingStatus == .cancelled || pingStatus == .error {
            return
        }

        pingStatus = .running
        do {
            let pingResponses = try await withThrowingTaskGroup(of: PingResponse?.self, returning: [PingResponse].self) { group in
                var pingResponses: [PingResponse] = []

                for cnt in 0..<pingConfiguration.count {
                    if pingStatus == .cancelled {
                        logger.debug("group task is cancelled")
                        group.cancelAll()
                        return pingResponses
                    }

                    logger.debug("added task #\(cnt)")
                    _ = group.addTaskUnlessCancelled {
                        // NOTE: Task.sleep respects cooperative cancellation. That is, it will throw a cancellation error and finish early if its current task is cancelled.
                        try await Task.sleep(nanoseconds: UInt64(cnt) * pingConfiguration.interval.nanosecond)

                        guard Task.isCancelled == false else {
                            return nil
                        }

                        let channel = try await ClientBootstrap(group: eventLoopGroup).connect(to: resolvedAddress).get()
                        logger.debug("in event loop: \(channel.eventLoop.inEventLoop)")
                        let asyncChannel: NIOAsyncChannel<PingResponse, HTTPOutboundIn> = try await channel.eventLoop.submit {
                            if enableTLS {
                                do {
                                    let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                                    let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                                    let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                                    try channel.pipeline.syncOperations.addHandlers(tlsHandler)
                                } catch {
                                    throw PingError.httpUnableToEstablishTLSConnection
                                }
                            }

#if INTEGRATION_TEST
                            try channel.pipeline.syncOperations.addHandler(TrafficControllerChannelHandler(networkLinkConfig: networkLinkConfig!))
#endif

                            try channel.pipeline.syncOperations.addHTTPClientHandlers(position: .last)
                            try channel.pipeline.syncOperations.addHandlers([HTTPTracingHandler(configuration: pingConfiguration, httpOptions: httpOptions), HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: pingConfiguration)], position: .last)

                            return try NIOAsyncChannel<PingResponse, HTTPOutboundIn>(wrappingChannelSynchronously: channel)
                        }.get()

                        asyncChannel.channel.pipeline.fireChannelActive()

                        logger.debug("pipeline is: \(asyncChannel.channel.pipeline.debugDescription)")

                        logger.debug("write packet #\(cnt)")

                        let result = try await asyncChannel.executeThenClose { inbound, outbound in
                            try await outbound.write(cnt)
                            defer {
                                outbound.finish()
                            }

                            var asyncItr = inbound.makeAsyncIterator()
                            return try await asyncItr.next()
                        }

                        logger.debug("async channel received result: \(String(describing: result))")
                        return result
                    }
                }

                do {
                    while pingStatus != .cancelled, let next = try await group.next() {
                        guard let next = next else {
                            continue
                        }
                        logger.debug("received \(next)")
                        pingResponses.append(next)
                    }
                } catch is CancellationError {
                    logger.debug("Task is cancelled while waiting")
                } catch {
                    print("received error: \(error)")
                    throw error
                }

                if pingStatus == .cancelled {
                    logger.debug("[\(#function)]: ping is cancelled. Cancel all other tasks in the task group")
                    group.cancelAll()
                }

                return pingResponses
            }
            logger.debug("received result from the channel: \(pingResponses)")
            switch pingStatus {
            case .running:
                pingStatus = .finished
                fallthrough
            case .cancelled:
                pingSummary = summarizePingResponse(pingResponses, host: resolvedAddress)
            case .finished, .ready, .error:
                fatalError("wrong state: \(pingStatus)")
            }
        } catch {
            pingStatus = .error
            throw PingError.sendPingFailed(error)
        }

        // MARK: http executor on macOS/iOS
//        let httpExecutor = HTTPHandler(useServerTiming: false)
//
//        var pingResponses: [PingResponse] = []
//        do {
//            for try await pingResponse in try await httpExecutor.execute(configuration: configuration) {
//                print("received ping response: \(pingResponse)")
//                pingResponses.append(pingResponse)
//            }
//
//            if pingStatus == .running {
//                pingStatus = .finished
//            }
//
//            pingSummary = summarizePingResponse(pingResponses, host: host)
//            print("summary is \(String(describing: pingSummary))")
//        } catch {
//            pingStatus = .failed
//            print("Error \(error)")
//        }

    }

    mutating func stop() {
        switch pingStatus {
        case .ready, .running:
            pingStatus = .cancelled
        case .error, .cancelled, .finished:
            logger.debug("already in ending state. no need to stop")
        }
    }
}
