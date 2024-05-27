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
import NIOConcurrencyHelpers

public final class ICMPPingClient {

    private let eventLoopGroup: EventLoopGroup
    private var state: PingState
    private let configuration: Configuration
    private var handler: ICMPHandler
    private var channel: Channel?
    private var promise: EventLoopPromise<[PingResponse]>

    private let stateLock = NIOLock()

    #if INTEGRATION_TEST
    private var networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?
    private var rewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject]?
    #endif

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton, configuration: Configuration) {
        self.eventLoopGroup = eventLoopGroup
        self.state = .ready
        self.configuration = configuration
        self.promise = self.eventLoopGroup.next().makePromise(of: [PingResponse].self)
        self.handler = ICMPHandler(totalCount: self.configuration.count, promise: promise)
    }

    #if INTEGRATION_TEST
    init(networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration, rewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject]?) {
        self.networkLinkConfig = networkLinkConfig
        self.rewriteHeaders = rewriteHeaders
    }
    #endif

    deinit {
        print("ICMPPingClient deinit called")
        self.shutdown()
    }

    public func start() -> EventLoopFuture<PingSummary> {
        switch self.state {
        case .ready:
            self.stateLock.withLock {
                self.state = .running
            }
            logger.logLevel = .debug
            let resolvedAddress = self.configuration.endpoint.resolvedAddress!
            return self.connect(to: resolvedAddress).flatMap { channel in
                self.channel = channel
                channel.closeFuture.whenComplete { result in
                    switch result {
                    case .success:
                        self.handler.reset()
                    case .failure:
                        self.stateLock.withLock {
                            self.state = .error
                        }
                    }
                }

                for cnt in 0..<self.configuration.count {
                    channel.eventLoop.scheduleTask(in: cnt * self.configuration.interval) {
                        channel.write(ICMPPingClient.Request(sequenceNum: UInt16(cnt), identifier: self.identifier), promise: nil)
                    }
                }

                return self.promise.futureResult.flatMap { pingResponse in
                    let summary = pingResponse.summarize(host: resolvedAddress)
                    self.stateLock.withLock {
                        self.state = .finished
                    }
                    return channel.eventLoop.makeSucceededFuture(summary)
                }
            }
        default:
            preconditionFailure("Cannot run ICMP Ping when the client is not in ready state.")
        }
    }

    public func cancel() {
        switch self.state {
        case .ready, .running:
            self.stateLock.withLock {
                self.state = .cancelled
            }
            shutdown()
        case .error:
            print("No need to cancel when ICMP Client is in error state.")
        case .cancelled:
            print("No need to cancel when ICMP Client is in cancelled state.")
        case .finished:
            print("No need to cancel when test is finished.")
        }
    }

    private func connect(to address: SocketAddress) -> EventLoopFuture<Channel> {
        return makeBootstrap(address).connect(to: address)
    }

    private func makeBootstrap(_ resolvedAddress: SocketAddress) -> DatagramBootstrap {
        return DatagramBootstrap(group: self.eventLoopGroup)
            .protocolSubtype(.init(.icmp))
            .channelInitializer { channel in
                #if INTEGRATION_TEST
                guard let networkLinkConfig = self.networkLinkConfig, let rewriteHeaders = self.rewriteHeaders else {
                    preconditionFailure("Test should initialize NetworkLinkConfiguration and Header Rewriter.")
                }
                let handlers: [ChannelHandler] = [
                    TrafficControllerChannelHandler(networkLinkConfig: networkLinkConfig),
                    InboundHeaderRewriter(rewriteHeaders: rewriteHeaders),
                    IPDecoder(),
                    ICMPDecoder(),
                    ICMPDuplexer(resolvedAddress: resolvedAddress, handler: self.handler)
                ]
                #else
                let handlers: [ChannelHandler] = [
                    IPDecoder(),
                    ICMPDecoder(),
                    ICMPDuplexer(resolvedAddress: resolvedAddress, handler: self.handler)
                ]
                #endif
                do {
                    try channel.pipeline.syncOperations.addHandlers(handlers)
                } catch {
                    self.stateLock.withLock {
                        self.state = .error
                    }
                    return channel.eventLoop.makeFailedFuture(error)
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }

    private func shutdown() {
        do {
            try self.channel?.close(mode: .all).wait()
            try self.eventLoopGroup.any().syncShutdownGracefully()
        } catch {
            logger.error("Cannot shut down ICMP Ping Client gracefully: \(error)")
        }
    }
}

extension ICMPPingClient {
    public struct Configuration {
        /// The target host that LCLPing will send the Ping request to
        public let endpoint: EndpointTarget

        /// Total number of packets sent. Default to 10 times.
        public var count: Int

        /// The wait time, in second, between sending consecutive packet. Default is 1s.
        public var interval: TimeAmount

        /// IP Time To Live for outgoing packets. Default is 64.
        public var timeToLive: UInt8

        /// Time, in second, to wait for a reply for each packet sent. Default is 1s.
        public var timeout: TimeAmount

        public init(endpoint: EndpointTarget,
                    count: Int = 10,
                    interval: TimeAmount = .seconds(1),
                    timeToLive: UInt8 = 64,
                    timeout: TimeAmount = .seconds(1)
        ) {
            self.endpoint = endpoint
            self.count = count
            self.interval = interval
            self.timeToLive = timeToLive
            self.timeout = timeout
        }
    }

    public enum EndpointTarget {
        case ipv4(String, Int?)
        case ipv6(String, Int?)

        var resolvedAddress: SocketAddress? {
            switch self {
            case .ipv4(let addr, let port):
                return try? SocketAddress.makeAddressResolvingHost(addr, port: port ?? 0)
            case .ipv6(let addr, let port):
                return try? SocketAddress.makeAddressResolvingHost(addr, port: port ?? 0)
            }
        }
    }
}