//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOCore
import NIO
import NIOHTTP1
import NIOSSL
import NIOConcurrencyHelpers

final class NIOHTTPClient: Pingable {
    private let eventLoopGroup: EventLoopGroup
    private let configuration: HTTPPingClient.Configuration
    private let resultPromise: EventLoopPromise<PingSummary>

    private var state: PingState
    private var channels: NIOLockedValueBox<[Channel]>
    private var responses: NIOLockedValueBox<[PingResponse]>
    private var resolvedAddress: SocketAddress?
    private let stateLock = NIOLock()

#if INTEGRATION_TEST
    private var networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?
#endif

    public init(eventLoopGroup: EventLoopGroup,
                configuration: HTTPPingClient.Configuration,
                resolvedAddress: SocketAddress,
                promise: EventLoopPromise<PingSummary>) {
        self.eventLoopGroup = eventLoopGroup
        self.resultPromise = promise
        self.resolvedAddress = resolvedAddress
        self.state = .ready
        self.configuration = configuration
        self.channels = .init([])
        self.responses = .init([])
    }

    #if INTEGRATION_TEST
    convenience init(eventLoopGroup: EventLoopGroup,
                     configuration: HTTPPingClient.Configuration,
                     resolvedAddress: SocketAddress,
                     networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?,
                     promise: EventLoopPromise<PingSummary>) {
        self.init(eventLoopGroup: eventLoopGroup, configuration: configuration, resolvedAddress: resolvedAddress, promise: promise)
        self.networkLinkConfig = networkLinkConfig
    }
    #endif

    deinit {
        self.shutdown()
    }

    func start() throws -> EventLoopFuture<PingSummary> {
        return self.stateLock.withLock {
            switch self.state {
            case .ready:
                self.state = .running
                guard let resolvedAddress = self.resolvedAddress else {
                    self.resultPromise.fail(PingError.httpMissingHost)
                    self.state = .error
                    return self.resultPromise.futureResult
                }
                for cnt in 0..<self.configuration.count {
                    let promise = self.eventLoopGroup.next().makePromise(of: PingResponse.self)
                    self.connect(to: resolvedAddress, promise: promise).whenComplete { result in
                        switch result {
                        case .success(let channel):
                            self.channels.withLockedValue { channels in
                                channels.append(channel)
                            }

                            logger.debug("Scheduled #\(cnt) request")
                            channel.eventLoop.scheduleTask(in: self.configuration.readTimeout * cnt) {
                                let request = self.configuration.makeHTTPRequest(for: cnt)
                                channel.write(request, promise: nil)
                            }
                        case .failure(let error):
                            promise.fail(error)
                            self.stateLock.withLockVoid {
                                self.state = .error
                            }
                        }
                    }

                    promise.futureResult.whenComplete { res in
                        self.channels.withLockedValue { channels in
                            if !channels.isEmpty {
                                channels.removeFirst()
                            }
                        }
                        switch res {
                        case .success(let response):
                            self.responses.withLockedValue {
                                $0.append(response)
                                if $0.count == self.configuration.count {
                                    self.resultPromise.succeed($0.summarize(host: resolvedAddress))
                                }
                            }
                        case .failure(let error):
                            self.resultPromise.fail(error)
                        }
                    }
                }

                return self.resultPromise.futureResult.always { result in
                    switch result {
                    case .success:
                        self.stateLock.withLockVoid {
                            self.state = .finished
                        }
                    case .failure:
                        self.stateLock.withLockVoid {
                            self.state = .error
                        }
                    }
                }
            default:
                preconditionFailure("Cannot run HTTP NIO Ping when the client is not in ready state.")
            }
        }
    }

    public func cancel() {
        self.stateLock.withLockVoid {
            switch self.state {
            case .ready:
                self.state = .canceled
                self.resultPromise.fail(PingError.taskIsCancelled)
            case .running:
                self.state = .canceled
                guard let resolvedAddress = self.resolvedAddress else {
                    self.resultPromise.fail(PingError.httpMissingHost)
                    return
                }
                self.responses.withLockedValue {
                    self.resultPromise.succeed($0.summarize(host: resolvedAddress))
                }
                shutdown()
            case .error:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when HTTP Client is in error state.")
            case .canceled:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when HTTP Client is in canceled state.")
            case .finished:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when test is finished.")
            }
        }
    }

    private func connect(to address: SocketAddress,
                         promise: EventLoopPromise<PingResponse>) -> EventLoopFuture<Channel> {
        return makeBootstrap(address, promise: promise).connect(to: address)
    }

    private func makeBootstrap(_ resolvedAddress: SocketAddress,
                               promise: EventLoopPromise<PingResponse>) -> ClientBootstrap {
        return ClientBootstrap(group: self.eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(self.configuration.connectionTimeout)
            .channelInitializer { channel in
                if self.configuration.schema.enableTLS {
                    do {
                        let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                        let tlsHandler = try NIOSSLClientHandler(context: sslContext,
                                                                 serverHostname: self.configuration.host)
                        try channel.pipeline.syncOperations.addHandlers(tlsHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }

                do {
                    try channel.pipeline.syncOperations.addHTTPClientHandlers(position: .last)
                    try channel.pipeline.syncOperations.addHandler(
                        HTTPTracingHandler(configuration: self.configuration, promise: promise),
                        position: .last
                    )

#if INTEGRATION_TEST
                    guard let networkLinkConfig = self.networkLinkConfig else {
                        preconditionFailure("Test should initialize NetworkLinkConfiguration")
                    }
                    try channel.pipeline.syncOperations.addHandler(
                        TrafficControllerChannelHandler(networkLinkConfig: networkLinkConfig),
                        position: .first
                    )
#endif
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
                
                if let device = self.configuration.device {
                    #if canImport(Darwin)
                    switch device.address {
                    case .v4:
                        return channel.setOption(.ipOption(.ip_bound_if), value: CInt(device.interfaceIndex))
                    case .v6:
                        return channel.setOption(.ipv6Option(.ipv6_bound_if), value: CInt(device.interfaceIndex))
                    case .unixDomainSocket:
                        self.stateLock.withLock {
                            self.state = .error
                        }
                        return channel.eventLoop.makeFailedFuture(PingError.icmpBindToUnixDomainSocket)
                    default:
                        ()
                    }
                    #elseif canImport(Glibc)
                    return (channel as! SocketOptionProvider).setBindToDevice(device.name)
                    #endif
                }

                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }

    private func shutdown() {
        self.channels.withLockedValue { channels in
            channels.forEach { channel in
                channel.close(mode: .all).whenFailure { error in
                    logger.error("Cannot close HTTP Ping Client: \(error)")
                }
            }
            logger.debug("Shutdown!")
        }
    }
}
