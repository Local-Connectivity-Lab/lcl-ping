//
// This source file is part of the LCLPing open source project
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
import NIOCore
import NIOPosix
import NIO
import NIOPosix


typealias ICMPOutboundIn = (UInt16, UInt16)

fileprivate let ICMPPingIdentifier: UInt16 = 0xbeef

internal struct ICMPPing: Pingable {
    var summary: PingSummary? {
        get {
            // return empty if ping is still running
            switch pingStatus {
            case .ready, .running, .error:
                return .empty
            case .stopped, .finished:
                return pingSummary
            }
        }
    }
    
    private(set) var pingStatus: PingState = .ready
    private var asyncChannel: NIOAsyncChannel<PingResponse, ICMPOutboundIn>?
    private var pingSummary: PingSummary?
    private var task: Task<(), Error>?
    
    internal init() { }
    
    // TODO: implement non-async version
    
    mutating func start(with pingConfiguration: LCLPing.PingConfiguration) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        defer {
            try! group.syncShutdownGracefully()
        }
        
        let host: String
        switch pingConfiguration.endpoint {
        case .ipv4(let h, _):
            host = h
        default:
            pingStatus = .error
            throw PingError.operationNotSupported("ICMP with IPv6 is currently not supported")
        }
        
        let resolvedAddress = try SocketAddress.makeAddressResolvingHost(host, port: 0)
        
        do {
            asyncChannel = try await DatagramBootstrap(group: group)
               .protocolSubtype(.init(.icmp))
               .connect(to: resolvedAddress) { channel in
                   channel.eventLoop.makeCompletedFuture {
                       try channel.pipeline.syncOperations.addHandlers(
                           [
                            IPDecoder(),
                            ICMPDecoder(),
                            ICMPDuplexer(configuration: pingConfiguration)
                           ]
                       )
                       return try NIOAsyncChannel<PingResponse, ICMPOutboundIn>(wrappingChannelSynchronously: channel)
               }
           }
        } catch {
            pingStatus = .error
            throw PingError.hostConnectionError(error)
        }

        guard let asyncChannel = asyncChannel else {
            pingStatus = .error
            throw PingError.failedToInitialzeChannel
        }
        
        precondition(pingStatus == .ready, "ping status is \(pingStatus)")
        pingStatus = .running
        logger.debug("pipeline is \(asyncChannel.channel.pipeline.debugDescription)")
        
        let pingResponses = try await asyncChannel.executeThenClose { inbound, outbound in
            task = Task {
                var cnt: UInt16 = 0
                do {
                    while !Task.isCancelled && cnt != pingConfiguration.count {
                        if cnt >= 1 {
                            try await Task.sleep(nanoseconds: pingConfiguration.interval.nanosecond)
                        }
                        logger.debug("sending packet #\(cnt)")
                        print("sending packet #\(cnt)")
                        try await outbound.write((ICMPPingIdentifier, cnt))
                        print("packet #\(cnt) sent DONE")
                        cnt += 1
                    }
                } catch is CancellationError {
                    logger.info("Task is cancelled while waiting")
                } catch {
                    throw PingError.sendPingFailed(error)
                }
            }
            
            var pingResponses: [PingResponse] = []

            for try await pingResponse in inbound {
                logger.debug("received ping response: \(pingResponse)")
                pingResponses.append(pingResponse)
            }
            
            return pingResponses
        }
        
        let taskResult = await task?.result
        switch taskResult {
        case .success:
            self.pingSummary = summarizePingResponse(pingResponses, host: resolvedAddress)
            
            precondition(pingStatus == .running || pingStatus == .stopped)
            
            if self.pingStatus != .stopped {
                pingStatus = .finished
            }

            if let pingSummary = pingSummary {
                printSummary(pingSummary)
            }
            
        case .failure(let failure):
            pingStatus = .error
            throw failure
        case .none:
            pingStatus = .error
            fatalError("No task result found")
        }
    }
    
    mutating func stop() {
        switch pingStatus {
        case .ready, .running:
            logger.debug("stopping the icmp ping")
            self.asyncChannel?.channel.close(mode: .all, promise: nil)
            self.task?.cancel()
            self.pingStatus = .stopped
            logger.debug("icmp ping stopped")
        case .error, .stopped, .finished:
            logger.debug("already in end state. no need to stop")
        }
    }
}
