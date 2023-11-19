//
//  HTTPPing.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation
import NIO
import NIOCore
import NIOPosix
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
    }

    private(set) var pingStatus: PingState = .ready
    private var pingSummary: PingSummary?
    private let httpOptions: LCLPing.PingConfiguration.HTTPOptions
    
    internal init(httpOptions: LCLPing.PingConfiguration.HTTPOptions) {
        self.httpOptions = httpOptions
    }
    
    // TODO: implement non-async version
    
    mutating func start(with pingConfiguration: LCLPing.PingConfiguration) async throws {
        let addr: String
        var port: UInt16
        switch pingConfiguration.endpoint {
        case .ipv4(let address, .none):
            addr = address
            port = 80
        case .ipv4(let address, .some(let p)):
            addr = address
            port = p
        case .ipv6(_):
            throw PingError.operationNotSupported("IPv6 currently not supported")
        }
        
        logger.debug("[\(#function)]: using address: \(addr), port: \(port)")
        
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
        port = enableTLS && port == 80 ? 443 : port
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try! eventLoopGroup.syncShutdownGracefully()
        }
        
        let resolvedAddress = try SocketAddress.makeAddressResolvingHost(host, port: Int(port))
        print(resolvedAddress)
        
        pingStatus = .running
        do {
            let pingResponses = try await withThrowingTaskGroup(of: PingResponse.self, returning: [PingResponse].self) { group in
                var pingResponses: [PingResponse] = []
                
                for cnt in 0..<pingConfiguration.count {
                    if pingStatus == .stopped {
                        logger.debug("group task is cancelled")
                        group.cancelAll()
                        return pingResponses
                    }

                    group.addTask {
                        let asyncChannel = try await ClientBootstrap(group: eventLoopGroup).connect(to: resolvedAddress) { channel in
                            channel.eventLoop.makeCompletedFuture {
                                if enableTLS {
                                    do {
                                        let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                                        let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                                        try channel.pipeline.syncOperations.addHandlers(tlsHandler)
                                    } catch {
                                        throw PingError.httpUnableToEstablishTLSConnection
                                    }
                                }
                                
                                try channel.pipeline.syncOperations.addHTTPClientHandlers(position: .last)
                                try channel.pipeline.syncOperations.addHandlers([HTTPTracingHandler(configuration: pingConfiguration, httpOptions: httpOptions), HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: pingConfiguration)], position: .last)
                                
                                return try NIOAsyncChannel<PingResponse, HTTPOutboundIn>(wrappingChannelSynchronously: channel)
                            }
                        }
                        
                        // Task.sleep respects cooperative cancellation. That is, it will throw a cancellation error and finish early if its current task is cancelled.
                        try await Task.sleep(nanoseconds: UInt64(cnt) * pingConfiguration.interval.nanosecond)
//                        logger.trace("write packet #\(cnt)")
                        let result = try await asyncChannel.executeThenClose { inbound, outbound in
                            try await outbound.write(cnt)
                            
                            var asyncItr = inbound.makeAsyncIterator()
                            guard let next = try await asyncItr.next() else {
                                throw PingError.httpMissingResult
                            }
                            return next
                        }
                        
                        return result
                    }
                }
                
                do {
                    while pingStatus != .stopped, let next = try await group.next() {
                        pingResponses.append(next)
                    }
                } catch is CancellationError {
                    logger.info("Task is cancelled while waiting")
                } catch {
                    throw error
                }
                
                if pingStatus == .stopped {
                    logger.debug("[\(#function)]: ping is cancelled. Cancel all other tasks in the task group")
                    group.cancelAll()
                }
                
                return pingResponses
            }
            
            switch pingStatus {
            case .running:
                pingStatus = .finished
                fallthrough
            case .stopped:
                pingSummary = summarizePingResponse(pingResponses, host: resolvedAddress)
            case .finished, .ready, .error:
                fatalError("wrong state: \(pingStatus)")
            }

            if let pingSummary = pingSummary {
                printSummary(pingSummary)
            }
        } catch {
            pingStatus = .error
            throw PingError.sendPingFailed(error)
        }

        
        
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
        switch pingStatus {
        case .ready, .running:
            pingStatus = .stopped
        case .error, .stopped, .finished:
            logger.debug("already in ending state. no need to stop")
        }
    }
}
