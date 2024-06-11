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
import NIOHTTP1
import NIOSSL
import NIOConcurrencyHelpers

/// The Ping client that initiates ping test via the ICMP protocol.
/// Caller needs to provide a configuration that set the way the ICMP client initiates tests.
/// Caller can also cancel the test via `cancel()`.
public final class HTTPPingClient: Pingable {

    private let eventLoopGroup: EventLoopGroup
    private var state: PingState
    private let configuration: Configuration
    private var channels: NIOLockedValueBox<[Channel]>
    private var resultPromise: EventLoopPromise<PingSummary>
    private var responses: [PingResponse]
    private var resolvedAddress: SocketAddress?

    private let stateLock = NIOLock()

    #if INTEGRATION_TEST
    private var networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?
    #endif

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singletonMultiThreadedEventLoopGroup,
                configuration: Configuration) {
        self.eventLoopGroup = eventLoopGroup
        self.state = .ready
        self.configuration = configuration
        self.channels = .init([])
        self.resultPromise = self.eventLoopGroup.any().makePromise(of: PingSummary.self)
        self.responses = [PingResponse]()
    }

    #if INTEGRATION_TEST
    convenience init(configuration: Configuration,
                     networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration) {
        self.init(configuration: configuration)
        self.networkLinkConfig = networkLinkConfig
    }
    #endif

    deinit {
        self.shutdown()
    }

    public func start() throws -> EventLoopFuture<PingSummary> {
        self.resolvedAddress = try SocketAddress.makeAddressResolvingHost(self.configuration.host, port: self.configuration.port)
        return self.stateLock.withLock {
            switch self.state {
            case .ready:
                self.state = .running
                for cnt in 0..<self.configuration.count {
                    let promise = self.eventLoopGroup.any().makePromise(of: PingResponse.self)
                    guard let resolvedAddress = self.resolvedAddress else {
                        self.resultPromise.fail(PingError.httpMissingHost)
                        self.state = .error
                        return self.resultPromise.futureResult
                    }

                    self.connect(to: resolvedAddress, resultPromise: promise).whenComplete { result in
                        switch result {
                        case .success(let channel):
                            self.channels.withLockedValue { channels in
                                channels.append(channel)
                            }

                            channel.eventLoop.scheduleTask(in: self.configuration.readTimeout * cnt) {
                                let request = self.configuration.makeHTTPRequest(for: UInt16(cnt))
                                channel.write(request, promise: nil)
                            }
                        case .failure(let error):
                            promise.fail(error)
                            self.stateLock.withLockVoid {
                                self.state = .error
                            }
                        }
                    }

                    promise.futureResult.whenComplete { res in
                        self.channels.withLockedValue { channels in
                            if !channels.isEmpty {
                                channels.removeFirst()
                            }
                        }
                        switch res {
                        case .success(let response):
                            self.responses.append(response)
                            if self.responses.count == self.configuration.count {
                                self.resultPromise.succeed(self.responses.summarize(host: resolvedAddress))
                            }
                        case .failure(let error):
                            self.resultPromise.fail(error)
                        }
                    }
                }

                self.resultPromise.futureResult.whenComplete { result in
                    switch result {
                    case .success:
                        self.stateLock.withLockVoid {
                            self.state = .finished
                        }
                    case .failure:
                        self.stateLock.withLockVoid {
                            self.state = .error
                        }
                    }
                }

                return self.resultPromise.futureResult
            default:
                preconditionFailure("Cannot run ICMP Ping when the client is not in ready state.")
            }
        }
    }

    public func cancel() {
        self.stateLock.withLockVoid {
            switch self.state {
            case .ready:
                self.state = .cancelled
                self.resultPromise.fail(PingError.taskIsCancelled)
            case .running:
                self.state = .cancelled
                guard let resolvedAddress = self.resolvedAddress else {
                    self.resultPromise.fail(PingError.httpMissingHost)
                    return
                }
                self.resultPromise.succeed(self.responses.summarize(host: resolvedAddress))
                shutdown()
            case .error:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in error state.")
            case .cancelled:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when ICMP Client is in cancelled state.")
            case .finished:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when test is finished.")
            }
        }
    }

    private func connect(to address: SocketAddress,
                         resultPromise: EventLoopPromise<PingResponse>) -> EventLoopFuture<Channel> {
        return makeBootstrap(address, resultPromise: resultPromise).connect(to: address)
    }

    private func makeBootstrap(_ resolvedAddress: SocketAddress,
                               resultPromise: EventLoopPromise<PingResponse>) -> ClientBootstrap {
        return ClientBootstrap(group: self.eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(self.configuration.connectionTimeout)
            .channelInitializer { channel in
                if self.configuration.schema.enableTLS {
                    do {
                        let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                        let tlsHandler = try NIOSSLClientHandler(context: sslContext,
                                                                 serverHostname: self.configuration.host)
                        try channel.pipeline.syncOperations.addHandlers(tlsHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }

                do {
                    let handler = HTTPHandler(useServerTiming: self.configuration.useServerTiming,
                                                             promise: resultPromise)
                    try channel.pipeline.syncOperations.addHTTPClientHandlers(position: .last)
                    try channel.pipeline.syncOperations.addHandler(
                        HTTPTracingHandler(configuration: self.configuration, handler: handler),
                        position: .last
                    )

                    #if INTEGRATION_TEST
                    guard let networkLinkConfig = self.networkLinkConfig else {
                        preconditionFailure("Test should initialize NetworkLinkConfiguration")
                    }
                    try channel.pipeline.syncOperations.addHandler(
                        TrafficControllerChannelHandler(networkLinkConfig: networkLinkConfig),
                        position: .first
                    )
                    #endif
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }

                return channel.eventLoop.makeSucceededVoidFuture()
            }
    }

    private func shutdown() {
        self.channels.withLockedValue { channels in
            channels.forEach { channel in
                channel.close(mode: .all).whenFailure { error in
                    logger.error("Cannot close HTTP Ping Client: \(error)")
                }
            }
            print("Shutdown!")
        }
    }
}

extension HTTPPingClient {

    /// The request that the HTTP Ping Client expects
    ///
    /// The information in this data will be used to construct the corresponding HTTP request.
    public struct Request {
        /// The sequence number of the ICMP test. This number should be monotonically increasing.
        let sequenceNumber: UInt16

        /// The request head that indicates the HTTP version, header information, and more.
        let requestHead: HTTPRequestHead
    }

    /// The configuration that will be used to configure the HTTP Ping Client.
    public struct Configuration {

        /// Default HTTP header
        public static let defaultHeaders: [String: String] =
            [
                "User-Agent": "lclping",
                "Accept": "application/json",
                "Connection": "close"
            ]

        /// The URL endpoint that HTTP Ping Client will try to connect to.
        public let url: URL

        /// Total number of packets sent. Default to 10 times.
        public var count: Int

        /// The amount of time that the HTTP Ping Client will wait for the response from the host. Default is 1s.
        public var readTimeout: TimeAmount

        /// The amount of time that the HTTP Ping Client will wait when connecting to the host. Default is 5s.
        public var connectionTimeout: TimeAmount

        /// The HTTP header information for the HTTP Request
        public var headers: [String: String]

        /// Indicate whether the HTTP Ping Client should take `ServerTiming` attribute
        /// from the reponse header into consideration when measuring the latency.
        public var useServerTiming: Bool

        /// Indicate whether the HTTP Ping Client should use native URLSession implementation.
        public var useURLSession: Bool

        /// The host that HTTP Ping Client will connect to for the ping test.
        public let host: String

        /// The schema used for the HTTP request.
        public let schema: Schema

        /// The port that the HTTP Ping Client will connect to for the ping test.
        public let port: Int

        /// The HTTP header that will be included in the HTTP request.
        public var httpHeaders: HTTPHeaders {
            let headerDictionary = self.headers.isEmpty ? Configuration.defaultHeaders : self.headers
            var httpHeaders = HTTPHeaders(headerDictionary.map {($0, $1)})
            if !httpHeaders.contains(name: "Host") {
                var host = self.host
                if self.port != self.schema.defaultPort {
                    host += ":\(self.port)"
                }
                httpHeaders.add(name: "Host", value: host)
            }
            return httpHeaders
        }

        /// Initialize a HTTP Ping Client `Configuration`.
        ///
        /// - Parameters:
        ///     - url: the URL indicating the endpoint target that the HTTP Ping Client will try to connect to.
        ///     - count: total number of packets that will be sent.
        ///     - readTimeout: the amount of time that the HTTP Ping Client will wait for the response from the host.
        ///     - connectionTimeout: the amount of time that the HTTP Ping Client will wait when connecting to the host.
        ///     - headers: the HTTP headers
        ///     - useServerTimimg: Indicate whether the HTTP Ping Client should take `ServerTiming` attribute
        /// from the reponse header.
        ///     - useURLSession: Indicate whether the HTTP Ping Client should use native URLSession implementation.
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///         -
        public init(url: URL,
                    count: Int = 10,
                    readTimeout: TimeAmount = .seconds(1),
                    connectionTimeout: TimeAmount = .seconds(5),
                    headers: [String: String] = Configuration.defaultHeaders,
                    useServerTiming: Bool = false,
                    useURLSession: Bool = false) throws {
            self.url = url
            self.count = count
            self.readTimeout = readTimeout
            self.connectionTimeout = connectionTimeout
            self.headers = headers
            self.useServerTiming = useServerTiming
            self.useURLSession = useURLSession

            guard let _host = url.host, !_host.isEmpty else {
                throw PingError.httpMissingHost
            }
            host = _host

            guard let s = url.scheme, !s.isEmpty else {
                throw PingError.httpMissingSchema
            }

            guard let _schema = Schema(rawValue: s.lowercased()) else {
                throw PingError.httpMissingSchema
            }
            self.schema = _schema

            port = url.port ?? schema.defaultPort
        }

        /// Initialize a HTTP Ping Client `Configuration`.
        ///
        /// - Parameters:
        ///     - url: the URL string indicating the endpoint target that the HTTP Ping Client will try to connect to.
        ///     - count: total number of packets that will be sent.
        ///     - readTimeout: the amount of time that the HTTP Ping Client will wait for the response from the host.
        ///     - connectionTimeout: the amount of time that the HTTP Ping Client will wait when connecting to the host.
        ///     - headers: the HTTP headers
        ///     - useServerTimimg: Indicate whether the HTTP Ping Client should take `ServerTiming` attribute
        /// from the reponse header.
        ///     - useURLSession: Indicate whether the HTTP Ping Client should use native URLSession implementation.
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///
        public init(url: String,
                    count: Int = 10,
                    readTimeout: TimeAmount = .seconds(1),
                    connectionTimeout: TimeAmount = .seconds(5),
                    headers: [String: String] = Configuration.defaultHeaders,
                    useServerTiming: Bool = false,
                    useURLSession: Bool = false) throws {
            guard let urlObj = URL(string: url) else {
                throw PingError.invalidURL(url)
            }

            try self.init(url: urlObj,
                          count: count,
                          readTimeout: readTimeout,
                          connectionTimeout: connectionTimeout,
                          headers: headers,
                          useServerTiming: useServerTiming,
                          useURLSession: useURLSession
                        )
        }

        /// Initialize a HTTP Ping Client `Configuration`.
        ///
        /// - Parameters:
        ///     - url: the URL string indicating the endpoint target that the HTTP Ping Client will try to connect to.
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///
        public init(url: String) throws {
            guard let urlObj = URL(string: url) else {
                throw PingError.invalidURL(url)
            }
            try self.init(url: urlObj)
        }

        /// Create the HTTP `Request` that will be used for the HTTP Ping Client
        ///
        /// - Parameters:
        ///     - for: the sequence number of the request
        /// - Returns: a `Request` object.
        public func makeHTTPRequest(for sequenceNumber: UInt16) -> Request {
            let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: url.uri, headers: self.httpHeaders)
            return Request(sequenceNumber: sequenceNumber, requestHead: requestHead)
        }
    }
}

extension URL {
    /// The URI string representation given the URL object.
    var uri: String {
        if self.path.isEmpty {
            return "/"
        }

        var base = URLComponents(url: self, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? self.path
        if let query = self.query {
            base += "?" + query
        }
        return base
    }
}
