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
import Collections

typealias HTTPOutboundIn = (UInt16, UInt16)


internal struct HTTPPing: Pingable {
    
    internal init(options: LCLPing.Configuration.HTTPOptions) {
        self.httpOptions = options
//        self.performenceEntryQueue = Deque()
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
        let addr: String
        var port: UInt16
//        var performenceEntryQueue: Deque<PerformanceEntry> = Deque(minimumCapacity: Int(configuration.count))
        switch configuration.endpoint {
        case .ipv4(let address, .none):
            addr = address
            port = 80
        case .ipv4(let address, .some(let p)):
            addr = address
            port = p
        case .ipv6(_):
            throw PingError.operationNotSupported("IPv6 currently not supported")
        }
        
        guard let url = URL(string: addr), let host = url.host, let schema = url.scheme else {
            throw PingError.invalidIPv4URL
        }
        
        let httpOptions = self.httpOptions
        let enableTLS = schema == "https"
        if enableTLS {
            port = port == 80 ? 443 : port
        }
        
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
//        let promise = group.next().makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                if enableTLS {
                    do {
                        let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                        let tlsHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        return channel.pipeline.addHandler(tlsHandler).flatMap {
                            channel.pipeline.addHTTPClientHandlers(position: .last)
                        }.flatMap {
                            channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: configuration), position: .last)
                        }.flatMap {
                            channel.pipeline.addHandler(HTTPTracingHandler(), position: .first)
                        }
                    } catch {
                        fatalError("error \(error)")
                    }
                    
                } else {
                    return channel.pipeline.addHTTPClientHandlers(position: .last).flatMap {
                        channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: configuration), position: .last)
                    }.flatMap {
                        channel.pipeline.addHandlers(HTTPTracingHandler(), position: .first)
                    }.flatMap {
                        channel.pipeline.addHandler(HTTPTracingHandler(), position: .first)
                    }
                }
            }

        defer {
//            try! promise.futureResult.wait()
            try! group.syncShutdownGracefully()
        }

        let asyncChannel: NIOAsyncChannel<PingResponse, HTTPOutboundIn>
        do {
            let channel = try await bootstrap.connect(host: host, port: Int(port)).get()
            print(channel.pipeline.debugDescription)
            asyncChannel = try await withCheckedThrowingContinuation { continuation in
                channel.eventLoop.execute {
                    do {
                        let asyncChannel = try NIOAsyncChannel<PingResponse, HTTPOutboundIn>(synchronouslyWrapping: channel)
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

        try await asyncChannel.outboundWriter.write((0,1))
        for try await res in asyncChannel.inboundStream {
            print(res)
        }
        
        
        
//        let httpExecutor = HTTPHandler(useServerTiming: false)
//
//        var pingResponses: [PingResponse] = []
//        do {
//            for try await pingResponse in try await httpExecutor.execute(configuration: configuration) {
//                print("received ping response: \(pingResponse)")
//                pingResponses.append(pingResponse)
//            }
//
//            if pingStatus == .running {
//                pingStatus = .finished
//            }
//
//            pingSummary = summarizePingResponse(pingResponses, host: host)
//            print("summary is \(String(describing: pingSummary))")
//        } catch {
//            pingStatus = .failed
//            print("Error \(error)")
//        }
        
    }
    
    mutating func stop() {
        if pingStatus != .failed {
            pingStatus = .stopped
        }
    }
}
