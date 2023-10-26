//
//  ICMPPing.swift
//  
//
//  Created by JOHN ZZN on 8/26/23.
//

import Foundation
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix
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
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        defer {
            try! group.syncShutdownGracefully()
        }
        
        let host: String
        switch configuration.endpoint {
        case .ipv4(let h, _):
            host = h
        default:
            pingStatus = .error
            throw PingError.operationNotSupported("ICMP with IPv6 is currently not supported")
        }
        
        do {
            asyncChannel = try await DatagramBootstrap(group: group)
               .protocolSubtype(.init(.icmp))
               .connect(host: host, port: 0) { channel in
                   channel.eventLoop.makeCompletedFuture {
                       try channel.pipeline.syncOperations.addHandlers(
                           [IPDecoder(), ICMPDecoder(), ICMPDuplexer(configuration: configuration)]
                       )
                       return try NIOAsyncChannel<PingResponse, ICMPOutboundIn>(synchronouslyWrapping: channel)
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
        
        task = Task(priority: .background) { [asyncChannel] in
            var cnt: UInt16 = 0
            do {
                while !Task.isCancelled && cnt != configuration.count {
                    if cnt >= 1 {
                        try await Task.sleep(nanoseconds: configuration.interval.nanosecond)
                    }
                    logger.debug("sending packet #\(cnt)")
                    try await asyncChannel.outboundWriter.write((ICMPPingIdentifier, cnt))
                    cnt += 1
                }
                
                if Task.isCancelled {
                    asyncChannel.channel.close(mode: .all, promise: nil)
                }
            } catch {
                throw PingError.sendPingFailed(error)
            }
        }
        
        var pingResponses: [PingResponse] = []

        for try await pingResponse in asyncChannel.inboundStream {
            logger.debug("received ping response: \(pingResponse)")
            pingResponses.append(pingResponse)
        }
        
        let taskResult = await task?.result
        switch taskResult {
        case .success:
            self.pingSummary = summarizePingResponse(pingResponses, host: host)
            
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
            self.task?.cancel()
            self.pingStatus = .stopped
            self.asyncChannel?.channel.close(mode: .all, promise: nil)
            logger.debug("icmp ping stopped")
        case .error, .stopped, .finished:
            logger.debug("already in end state. no need to stop")
        }
    }
}
