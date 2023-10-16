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
import Logging

typealias ICMPOutboundIn = (UInt16, UInt16)

fileprivate let ICMPPingIdentifier: UInt16 = 0xbeef

internal struct ICMPPing: Pingable {
    
    internal init() { }
    
    
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
    private let logger: Logger = Logger(label: "com.lcl.lclping")
    
    // TODO: implement non-async version
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        
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
        
        do {
            let pingResponses = try await withThrowingTaskGroup(of: Void.self, returning: [PingResponse].self) { group in
                var pingResponses: [PingResponse] = []
                for cnt in 0..<configuration.count {
                    if pingStatus == .error || pingStatus == .stopped {
                        print("cancel all subtasks")
                        group.cancelAll()
                        return pingResponses
                    }
                    
                    group.addTask {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(cnt) * configuration.interval.nanosecond)
                            print("sending #\(cnt)")
                            try await asyncChannel.outboundWriter.write((ICMPPingIdentifier, cnt))
                        } catch {
                            throw PingError.sendPingFailed(error)
                        }
                    }
                }
        
                for try await pingResponse in asyncChannel.inboundStream {
                    print("received ping response: \(pingResponse)")
                    pingResponses.append(pingResponse)
                }
                
                
                print("[before] group is cancelled? \(group.isCancelled)")
                if (pingStatus == .stopped || pingStatus == .error) && !group.isCancelled {
                    group.cancelAll()
                }
                
                print("[after] group is cancelled? \(group.isCancelled)")
                
                return pingResponses
            }
            
            pingSummary = summarizePingResponse(pingResponses, host: host)
            
            precondition(pingStatus == .running || pingStatus == .stopped)
            
            if pingStatus != .stopped {
                pingStatus = .finished
            }
            print("summary is \(String(describing: pingSummary))")
        } catch {
            pingStatus = .error
            throw error
        }
    }
    
    mutating func stop() {
        print("stopping the icmp ping")
        pingStatus = .stopped
        asyncChannel?.channel.close(mode: .all, promise: nil)
        print("icmp ping stopped")
    }
}
