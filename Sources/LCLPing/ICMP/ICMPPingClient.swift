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
        return self.stateLock.withLock {
            switch self.state {
            case .ready:
                self.state = .running

                return self.connect(to: self.configuration.resolvedAddress).flatMap { channel in
                    self.channel = channel
                    channel.closeFuture.whenComplete { result in
                        switch result {
                        case .success:
                            ()
                        case .failure:
                            self.stateLock.withLockVoid {
                                self.state = .error
                            }
                        }
                    }
                    
                    let sendPromise = channel.eventLoop.makePromise(of: Void.self)
                    sendPromise.futureResult.cascadeFailure(to: self.promise)
                    
                    func send(_ cnt: Int) {
                        if cnt == self.configuration.count {
                            sendPromise.succeed()
                            return
                        }
                        let el = self.eventLoopGroup.next()
                        let p = el.makePromise(of: Void.self)
                        logger.debug("Scheduled #\(cnt) request")
                        channel.eventLoop.scheduleTask(in: cnt * self.configuration.interval) {
                            channel.writeAndFlush(ICMPPingClient.Request(sequenceNum: UInt16(cnt), identifier: self.identifier), promise: p)
                        }.futureResult.hop(to: el).cascadeFailure(to: sendPromise)
                        
                        p.futureResult.cascadeFailure(to: sendPromise)
                        send(cnt + 1)
                    }
                    
                    send(0)
                    
                    return sendPromise.futureResult.and(self.promise.futureResult).flatMap { (_, pingResponse) in
                        let summary = pingResponse.summarize(host: self.configuration.resolvedAddress)
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
    }

    /// Cancel the running ICMP ping test
    ///
    /// - Note: Calling this method before the test starts of after the test ends results in a no-op.
    public func cancel() {
        logger.debug("[\(#fileID)][\(#line)][\(#function)]: Cancel icmp ping!")
        self.stateLock.withLockVoid {
            switch self.state {
            case .ready:
                self.state = .canceled
                self.promise.fail(PingError.taskIsCancelled)
                logger.debug("cancel from ready state")
                shutdown()
            case .running:
                self.state = .canceled
                logger.debug("cancel from running state")
                shutdown()
            case .error:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in error state.")
            case .canceled:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in canceled state.")
            case .finished:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when test is finished.")
            }
        }
    }

    private func connect(to address: SocketAddress) -> EventLoopFuture<Channel> {
        return makeBootstrap().connect(to: address)
    }

    private func makeBootstrap() -> DatagramBootstrap {
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
                    ICMPDuplexer(configuration: self.configuration, promise: self.promise)
                ]
                #else
                let handlers: [ChannelHandler] = [
                    IPDecoder(),
                    ICMPDecoder(),
                    ICMPDuplexer(configuration: self.configuration, promise: self.promise)
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
                    #elseif canImport(Glibc) || canImport(Musl)
                    return (channel as! SocketOptionProvider).setBindToDevice(device.name)
                    #endif
                }
                
                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }

    private func shutdown() {
        logger.info("Shutting down ICMPPing Client")
        if let channel = self.channel, channel.isActive {
            logger.debug("shut down icmp ping client")
            self.channel?.close(mode: .all).whenFailure { error in
                logger.error("Cannot close channel: \(error)")
            }
        }
    }
}

extension ICMPPingClient {

    /// The configuration that will be used to configure the ICMP Ping Client.
    ///
    /// - Throws:a SocketAddressError.unknown if we could not resolve the host, or SocketAddressError.unsupported if the address itself is not supported (yet).
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

        /// The resolved socket address
        public let resolvedAddress: SocketAddress
        
        /// The outgoing device associated with the given interface name
        public private(set) var device: NIONetworkDevice?

        public init(endpoint: EndpointTarget,
                    count: Int = 10,
                    interval: TimeAmount = .seconds(1),
                    timeToLive: UInt8 = 64,
                    timeout: TimeAmount = .seconds(1),
                    deviceName: String? = nil
        ) throws {
            self.endpoint = endpoint
            self.count = count
            self.interval = interval
            self.timeToLive = timeToLive
            self.timeout = timeout
            switch self.endpoint {
            case .ipv4(let addr, let port):
                self.resolvedAddress = try SocketAddress.makeAddressResolvingHost(addr, port: port ?? 0)
            case .ipv6(let addr, let port):
                self.resolvedAddress = try SocketAddress.makeAddressResolvingHost(addr, port: port ?? 0)
            }

            for device in try System.enumerateDevices() {
                if device.name == deviceName, let address = device.address {
                    switch (address.protocol, self.endpoint) {
                    case (.inet, .ipv4), (.inet6, .ipv6):
                        logger.info("device selcted is \(device)")
                        self.device = device
                    default:
                        continue
                    }
                }
                if self.device != nil {
                    break
                }
            }
        }
    }

    /// The type of endpoint target, either in IPv4 or IPv6.
    public enum EndpointTarget {
        case ipv4(String, Int?)
        case ipv6(String, Int?)
    }
}
