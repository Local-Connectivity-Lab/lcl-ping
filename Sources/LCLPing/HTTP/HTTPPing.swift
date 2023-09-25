//
//  HTTPPing.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation
import NIO
@_spi(AsyncChannel) import NIOCore
import NIOHTTP1
import NIOSSL

typealias HTTPOutboundIn = (UInt16, UInt16)


internal struct HTTPPing: Pingable {
    
    internal init(options: LCLPing.Configuration.HTTPOptions) {
        self.httpOptions = options
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
    
    var status: PingState {
        get {
            pingStatus
        }
    }

    private var pingStatus: PingState = .ready
    private var pingSummary: PingSummary?
    private let httpOptions: LCLPing.Configuration.HTTPOptions
    
//    mutating func start(with configuration: LCLPing.Configuration) throws {
//
//    }
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        pingStatus = .running
        print(1)
        
        let host: String
        let port: UInt16
        switch configuration.endpoint {
            
        case .ipv4(let address, let p):
            host = address
            port = p ?? httpOptions.defaultPort
        case .ipv6(_, _):
            throw PingError.operationNotSupported("IPv6 currently not supported")
        }
        
        
//        let enableTLS = httpOptions.enableTLS
//
//        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
//        var bootstrap = ClientBootstrap(group: group)
//            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
//            .channelInitializer { channel in
//                
//                if enableTLS {
//                    do {
//                        let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
//                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
//                        let tlsHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
//                        return channel.pipeline.addHandler(tlsHandler, position: .first).flatMap {
//                            channel.pipeline.addHTTPClientHandlers(position: .last).flatMap {
//                                channel.pipeline.addHandler(HTTPDuplexer(), position: .last)
//                            }
//                        }
//                    } catch {
//                        fatalError("error \(error)")
//                    }
//                    
//                } else {
//                    return channel.pipeline.addHTTPClientHandlers(position: .last).flatMap {
//                        channel.pipeline.addHandler(HTTPDuplexer(), position: .last)
//                    }
//                }
//            }
//
//        defer {
//            try! group.syncShutdownGracefully()
//        }
//
//        let asyncChannel: NIOAsyncChannel<PingResponse, HTTPOutboundIn>
//        do {
//            let channel = try await bootstrap.connect(host: host, port: Int(port)).get()
//            print(channel.pipeline.debugDescription)
//            asyncChannel = try await withCheckedThrowingContinuation { continuation in
//                channel.eventLoop.execute {
//                    do {
//                        let asyncChannel = try NIOAsyncChannel<PingResponse, HTTPOutboundIn>(synchronouslyWrapping: channel)
//                        continuation.resume(with: .success(asyncChannel))
//                    } catch {
//                        continuation.resume(throwing: error)
//                    }
//                }
//            }
//        } catch {
//            pingStatus = .failed
//            throw PingError.hostConnectionError(error)
//        }
//
//        try await asyncChannel.outboundWriter.write((0,1))
//
//        for try await res in asyncChannel.inboundStream {
//            print(res)
//        }
        
        let httpExecutor = HTTPHandler(useServerTiming: false)

        var pingResponses: [PingResponse] = []
        do {
            for try await pingResponse in try await httpExecutor.execute(configuration: configuration) {
                print("received ping response: \(pingResponse)")
                pingResponses.append(pingResponse)
            }

            if pingStatus == .running {
                pingStatus = .finished
            }

            pingSummary = summarizePingResponse(pingResponses, host: host)
            print("summary is \(String(describing: pingSummary))")
        } catch {
            pingStatus = .failed
            print("Error \(error)")
        }
        
    }
    
    mutating func stop() {
        if pingStatus != .failed {
            pingStatus = .stopped
        }
    }
}
