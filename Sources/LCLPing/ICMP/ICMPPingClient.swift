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

/// The Ping client that initiates ping test via the ICMP protocol.
/// Caller needs to provide a configuration that set the way the ICMP client initiates tests.
/// Caller can also cancel the test via `cancel()`.
public final class ICMPPingClient: Pingable {

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

    /// Initialize the ICMP Ping client.
    ///
    /// - Parameters:
    ///     - eventLoopGroup: the event loop group through which the test will be conducted. 
    ///                        By default, a singleton event loop group will be used.
    ///     - configuration: the configuration that instructs how ICMP Ping client should perform the ping test.
    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton, configuration: Configuration) {
        self.eventLoopGroup = eventLoopGroup
        self.state = .ready
        self.configuration = configuration
        self.promise = self.eventLoopGroup.next().makePromise(of: [PingResponse].self)
        self.handler = ICMPHandler(totalCount: self.configuration.count, promise: promise)
    }

    #if INTEGRATION_TEST
    convenience init(networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration,
                     rewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject]?,
                     configuration: Configuration) {
        self.init(configuration: configuration)
        self.networkLinkConfig = networkLinkConfig
        self.rewriteHeaders = rewriteHeaders
    }
    #endif

    deinit {
        self.shutdown()
    }

    public func start() -> EventLoopFuture<PingSummary> {
        let resolvedAddress = self.configuration.endpoint.resolvedAddress!
        return self.stateLock.withLock {
            switch self.state {
            case .ready:
                self.state = .running

                return self.connect(to: resolvedAddress).flatMap { channel in
                    self.channel = channel
                    channel.closeFuture.whenComplete { result in
                        switch result {
                        case .success:
                            self.handler.reset()
                        case .failure:
                            self.state = .error
                        }
                    }

                    for cnt in 0..<self.configuration.count {
                        channel.eventLoop.scheduleTask(in: cnt * self.configuration.interval) {
                            channel.write(
                                ICMPPingClient.Request(
                                    sequenceNum: UInt16(cnt),
                                    identifier: self.identifier
                                ),
                                promise: nil
                            )
                        }
                    }

                    return self.promise.futureResult.flatMap { pingResponse in
                        let summary = pingResponse.summarize(host: resolvedAddress)
                        self.stateLock.withLockVoid {
                            self.state = .finished
                        }
                        return channel.eventLoop.makeSucceededFuture(summary)
                    }
                }
            default:
                preconditionFailure("Cannot run ICMP Ping when the client is not in ready state.")
            }
        }
    }

    /// Cancel the running ICMP ping test
    ///
    /// - Note: Calling this method before the test starts of after the test ends results in a no-op.
    public func cancel() {
        print("[\(#fileID)][\(#line)][\(#function)]: Cancel icmp ping!")
        self.stateLock.withLockVoid {
            switch self.state {
            case .ready:
                self.state = .cancelled
                self.promise.fail(PingError.taskIsCancelled)
                print("shut down => from ready state")
                shutdown()
            case .running:
                self.state = .cancelled
                print("shut down => from running state")
                shutdown()
            case .error:
                print("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in error state.")
            case .cancelled:
                print("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in cancelled state.")
            case .finished:
                print("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when test is finished.")
            }
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
                guard let networkLinkConfig = self.networkLinkConfig else {
                    preconditionFailure("Test should initialize NetworkLinkConfiguration")
                }
                let handlers: [ChannelHandler] = [
                    TrafficControllerChannelHandler(networkLinkConfig: networkLinkConfig),
                    InboundHeaderRewriter<AddressedEnvelope<ByteBuffer>>(rewriteHeaders: self.rewriteHeaders),
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
                    self.stateLock.withLockVoid {
                        self.state = .error
                    }
                    return channel.eventLoop.makeFailedFuture(error)
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }

    private func shutdown() {
        if let channel = self.channel, channel.isActive {
            logger.debug("shut down icmp ping client")
            self.channel?.close(mode: .all).whenFailure { error in
                print("Cannot close channel: \(error)")
            }
        }
    }
}

extension ICMPPingClient {

    /// The configuration that will be used to configure the ICMP Ping Client.
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

    /// The type of endpoint target, either in IPv4 or IPv6.
    public enum EndpointTarget {
        case ipv4(String, Int?)
        case ipv6(String, Int?)

        /// the resolved address given the string representation of the endpoint target.
        /// If the address or port cannot be resolved, then `resolvedAddress` will be nil.
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
