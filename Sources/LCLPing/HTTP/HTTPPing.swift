//
//  HTTPPing.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation
import NIO
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix
import NIOHTTP1
import NIOSSL
import Collections

typealias HTTPOutboundIn = UInt16


internal struct HTTPPing: Pingable {
    
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
        
        set {
            
        }
    }

    var pingStatus: PingState = .ready

    private var pingSummary: PingSummary?
    private let httpOptions: LCLPing.Configuration.HTTPOptions
    private var pingResponses: [PingResponse]
    
    internal init(options: LCLPing.Configuration.HTTPOptions) {
        self.httpOptions = options
        self.pingResponses = []
    }
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        pingStatus = .running
        let addr: String
        let port: UInt16
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
        
        guard let url = URL(string: addr) else {
            throw PingError.invalidIPv4URL
        }
        
        guard let host = url.host else {
            throw PingError.httpMissingHost
        }
        
        guard let schema = url.scheme, ["http", "https"].contains(schema) else {
            throw PingError.httpMissingSchema
        }
        
        let httpOptions = self.httpOptions
        let enableTLS = schema == "https"
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer {
            try! eventLoopGroup.syncShutdownGracefully()
        }
        
        let pingResponses = try await withThrowingTaskGroup(of: PingResponse.self, returning: [PingResponse].self) { group in
            var pingResponses: [PingResponse] = []
            for cnt in 0..<configuration.count {
                if pingStatus == .stopped {
                    group.cancelAll()
                    return pingResponses
                }
                group.addTask {
                    let asyncChannel = try await ClientBootstrap(group: eventLoopGroup).connect(host: host, port: Int(port)) { channel in
                        channel.eventLoop.makeCompletedFuture {
                            if enableTLS {
                                do {
                                    let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                                    let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                                    let tlsHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
                                    try channel.pipeline.syncOperations.addHandlers(tlsHandler)
                                } catch {
                                    fatalError("unable to initialize TLS. error: \(error)")
                                }
                            }
                            
                            try channel.pipeline.syncOperations.addHTTPClientHandlers(position: .last)
                            try channel.pipeline.syncOperations.addHandlers([HTTPTracingHandler(configuration: configuration, httpOptions: httpOptions), HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: configuration)], position: .last)
                            
                            return try NIOAsyncChannel<PingResponse, HTTPOutboundIn>(synchronouslyWrapping: channel)
                        }
                    }
                    try await Task.sleep(nanoseconds: UInt64(cnt) * configuration.interval.nanosecond)
                    try await asyncChannel.outboundWriter.write(cnt)
                    
                    var asyncItr = asyncChannel.inboundStream.makeAsyncIterator()
                    guard let next = try await asyncItr.next() else {
                        // TODO: make the error more explicit
                        fatalError()
                    }
                    
                    return next
                }
            }
            for try await result in group {
                pingResponses.append(result)
            }
            
            return pingResponses
        }
        
        pingSummary = summarizePingResponse(pingResponses, host: host)

        if pingStatus == .running {
            pingStatus = .finished
        }
        print("summary is \(String(describing: pingSummary))")
        
        
        // MARK: http executor on macOS/iOS
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
        if pingStatus != .error {
            pingStatus = .stopped
        }
    }
}
