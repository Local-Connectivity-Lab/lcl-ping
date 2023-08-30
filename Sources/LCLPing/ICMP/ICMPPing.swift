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

typealias ICMPOutboundIn = (UInt16, UInt16)

internal struct ICMPPing: Pingable {
    
    var summary: PingSummary?
    var asyncChannel: NIOAsyncChannel<PingResponse, ICMPOutboundIn>
    
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let client = NIORawSocketBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandlers(
                [
                    IPDecoder(), ICMPDecoder(), ICMPDuplexer(configuration: configuration)
                ]
                )
            }
        
        let host: String
        switch configuration.host {
        case .icmp(let h):
            host = h
        default:
            throw PingError.invalidConfiguration("Expect IP.ICMP host. But received \(configuration.host)")
        }
        
        do {
            let channel = try await client.connect(host: host, ipProtocol: .icmp).get()
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
            throw PingError.hostConnectionError(error)
        }
        
        // MARK: send ping message
        
    }
    
    func stop() {
        
    }
    

    

    
}
