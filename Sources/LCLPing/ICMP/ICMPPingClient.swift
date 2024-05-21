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

public class ICMPPingClient {

    public let eventLoopGroup: EventLoopGroup
    private var state: PingState
    private let configuration: LCLPing.PingConfiguration
    private var scheduledWrites: [Scheduled<Void>]
    private var handler: ICMPHandler

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton, configuration: LCLPing.PingConfiguration) {
        self.eventLoopGroup = eventLoopGroup
        self.state = .ready
        self.configuration = configuration
        self.scheduledWrites = []
        self.scheduledWrites.reserveCapacity(Int(self.configuration.count))
        self.handler = ICMPHandler(totalCount: self.configuration.count, promise: self.eventLoopGroup.any().makePromise(of: [PingResponse].self))
    }
    
    deinit {
        self.shutdown()
    }

    public func start() -> EventLoopFuture<PingSummary> {
        
        logger.logLevel = .debug
        let resolvedAddress = try! SocketAddress(ipAddress: "142.250.69.206", port: 0)
        return self.connect(to: resolvedAddress).flatMap { channel in
            for cnt in 0..<self.configuration.count {
                let scheduled = channel.eventLoop.scheduleTask(in: .seconds(Int64(cnt) * Int64(self.configuration.interval))) {
                    channel.write((UInt16(0xbeef), UInt16(cnt)), promise: nil)
                }
                self.scheduledWrites.append(scheduled)
            }
            
            return self.handler.futureResult.flatMap { pingResponse in
                let summary = summarizePingResponse(pingResponse, host: resolvedAddress)
                return channel.eventLoop.makeSucceededFuture(summary)
            }
        }
    }
    
    public func cancel() {
        self.scheduledWrites.forEach { scheduled in
            scheduled.cancel()
        }
        self.handler.shouldCloseHandler()
    }
    
    private func connect(to address: SocketAddress) -> EventLoopFuture<Channel> {
        return makeBootstrap(address).connect(to: address)
    }
    
    private func makeBootstrap(_ resolvedAddress: SocketAddress) -> DatagramBootstrap {
        return DatagramBootstrap(group: self.eventLoopGroup)
            .protocolSubtype(.init(.icmp))
            .channelInitializer { channel in
                let handlers: [ChannelHandler] = [
                 IPDecoder(),
                 ICMPDecoder(),
                 ICMPDuplexer(configuration: self.configuration, resolvedAddress: resolvedAddress, handler: self.handler)
                ]
                do {
                    try channel.pipeline.syncOperations.addHandlers(handlers)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }
    
    private func shutdown() {
        do {
            try self.eventLoopGroup.syncShutdownGracefully()
            handler.reset()
        } catch {
            logger.error("Cannot shut down ICMP Ping Client gracefully: \(error)")
        }
    }
}
