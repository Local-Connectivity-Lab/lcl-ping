//
//  ICMPPing.swift
//  
//
//  Created by JOHN ZZN on 8/26/23.
//

import Foundation
@_spi(AsyncChannel) import NIOCore
import NIO
import NIOPosix
import Logging

typealias ICMPOutboundIn = (UInt16, UInt16)

fileprivate let ICMPPingIdentifier: UInt16 = 0xbeef

internal struct ICMPPing: Pingable {
    
    internal init() { }
    
    var status: PingState {
        get {
            pingStatus
        }
    }
    
    
    var summary: PingSummary? {
        get {
            // return empty if ping is still running
            switch pingStatus {
            case .ready, .running, .failed:
                return .empty
            case .stopped, .finished:
                return pingSummary
            }
        }
        set {
            
        }
    }
    private var asyncChannel: NIOAsyncChannel<PingResponse, ICMPOutboundIn>?
    private var task: Task<(), Error>?
    private var pingStatus: PingState = .ready
    private var pingSummary: PingSummary?
    private let logger: Logger = Logger(label: "com.lcl.lclping")
    
//    mutating func start(with configuration: LCLPing.Configuration) throws {
//        print("non async start")
//    }
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        pingStatus = .running
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let bootstrap = DatagramBootstrap(group: group)
            .protocolSubtype(.init(.icmp))
            .channelInitializer { channel in
                channel.pipeline.addHandlers(
                [
                    IPDecoder(), ICMPDecoder(), ICMPDuplexer(configuration: configuration)
                ]
                )
            }
        
        let host: String
        switch configuration.endpoint {
        case .ipv4(let h, _):
            host = h
        default:
            pingStatus = .failed
            throw PingError.invalidConfiguration("ICMP with IPv6 is currently not supported")
        }

        do {
            let channel = try await bootstrap.connect(host: host, port: 0).get()
            asyncChannel = try await withCheckedThrowingContinuation { continuation in
                channel.eventLoop.execute {
                    do {
                        let asyncChannel = try NIOAsyncChannel<PingResponse, ICMPOutboundIn>(synchronouslyWrapping: channel)
                        continuation.resume(with: .success(asyncChannel))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            pingStatus = .failed
            throw PingError.hostConnectionError(error)
        }

        guard let asyncChannel = asyncChannel else {
            throw PingError.failedToInitialzeChannel
        }
        
        print("Channel intialized")

        task = Task(priority: .background) { [asyncChannel] in
            var cnt: UInt16 = 0
            var nextSequenceNumber: UInt16 = 0
            do {
                while !Task.isCancelled && cnt != configuration.count {
                    print("sending #\(cnt)")
                    try await asyncChannel.outboundWriter.write((ICMPPingIdentifier, nextSequenceNumber))
                    cnt += 1
                    nextSequenceNumber += 1
                    try await Task.sleep(nanoseconds: configuration.interval.nanosecond)
                }
            } catch {
                // pingStatus = .failed
                throw PingError.sendPingFailed(error)
            }
        }
        
        var pingResponses: [PingResponse] = []
        for try await pingResponse in asyncChannel.inboundStream {
            print("received ping response: \(pingResponse)")
            pingResponses.append(pingResponse)
        }
        
        pingSummary = summarizePingResponse(pingResponses, host: host)

        if pingStatus == .running {
            pingStatus = .finished
        }
        print("summary is \(String(describing: pingSummary))")
        
    }
    
    mutating func stop() {
        pingStatus = .stopped
        task?.cancel()
        asyncChannel?.channel.close(mode: .all, promise: nil)
    }
}
