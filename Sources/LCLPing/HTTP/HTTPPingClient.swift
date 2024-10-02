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
import NIOPosix
import NIOHTTP1
import NIOSSL
import NIOConcurrencyHelpers

/// The Ping client that initiates ping test via the HTTP protocol.
/// Caller needs to provide a configuration that set the way the HTTP client initiates tests.
/// Caller can cancel the test via `cancel()`.
public final class HTTPPingClient: Pingable {

    private enum State {
        case idle
        case running
        case canceled
    }

    private let eventLoopGroup: EventLoopGroup
    private var state: NIOLockedValueBox<State>
    private let configuration: Configuration
    private var resultPromise: EventLoopPromise<PingSummary>
    private let pingClient: any Pingable

    #if INTEGRATION_TEST
    private var networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration?
    #endif

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singletonMultiThreadedEventLoopGroup,
                configuration: Configuration) {
        self.eventLoopGroup = eventLoopGroup
        self.state = .init(.idle)
        self.configuration = configuration
        self.resultPromise = self.eventLoopGroup.next().makePromise(of: PingSummary.self)
        if self.configuration.useURLSession {
            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            self.pingClient = URLSessionClient(config: self.configuration, socketAddress: self.configuration.resolvedAddress, promise: self.resultPromise)
            #else
            preconditionFailure("URLSession is not supported on non-Apple platforms")
            #endif
        } else {
            #if INTEGRATION_TEST
            self.pingClient = NIOHTTPClient(eventLoopGroup: self.eventLoopGroup, configuration: self.configuration, resolvedAddress: self.configuration.resolvedAddress, networkLinkConfig: self.networkLinkConfig, promise: self.resultPromise)
            #else
            self.pingClient = NIOHTTPClient(eventLoopGroup: self.eventLoopGroup, configuration: self.configuration, resolvedAddress: self.configuration.resolvedAddress, promise: self.resultPromise)
            #endif
        }
    }

#if INTEGRATION_TEST
    init(configuration: Configuration,
         networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration) {
        self.eventLoopGroup = MultiThreadedEventLoopGroup.singleton
        self.state = .init(.idle)
        self.configuration = configuration
        self.resultPromise = self.eventLoopGroup.next().makePromise(of: PingSummary.self)
        self.networkLinkConfig = networkLinkConfig
        if self.configuration.useURLSession {
            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            self.pingClient = URLSessionClient(config: self.configuration, socketAddress: self.configuration.resolvedAddress, promise: self.resultPromise)
            #else
            preconditionFailure("URLSession is not supported on non-Apple platforms")
            #endif
        } else {
            #if INTEGRATION_TEST
            self.pingClient = NIOHTTPClient(eventLoopGroup: self.eventLoopGroup, configuration: self.configuration, resolvedAddress: self.configuration.resolvedAddress, networkLinkConfig: self.networkLinkConfig, promise: self.resultPromise)
            #else
            self.pingClient = NIOHTTPClient(eventLoopGroup: self.eventLoopGroup, configuration: self.configuration, resolvedAddress: self.configuration.resolvedAddress, promise: self.resultPromise)
            #endif
        }
    }
#endif

    public func start() throws -> EventLoopFuture<PingSummary> {
        return try self.state.withLockedValue { state in
            switch state {
            case .idle:
                state = .running
                return try self.pingClient.start().always { _ in
                    self.state.withLockedValue { state in
                        state = .idle
                    }
                }
            default:
                preconditionFailure("Cannot run HTTP Ping when the client is not in ready state.")
            }
        }
    }

    public func cancel() {
        self.state.withLockedValue { state in
            switch state {
            case .idle:
                state = .canceled
                self.resultPromise.fail(PingError.taskIsCancelled)
            case .running:
                state = .canceled
                self.pingClient.cancel()
            case .canceled:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: No need to cancel when HTTP Client is in canceled state.")
            }
        }
    }
}

extension HTTPPingClient {

    /// The request that the HTTP Ping Client expects
    ///
    /// The information in this data will be used to construct the corresponding HTTP request.
    public struct Request {
        /// The sequence number of the ICMP test. This number should be monotonically increasing.
        let sequenceNumber: Int

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
        ///
        /// - Warning: on Linux platform, this attribute is always false, as URLSession is not fully supported in swift-corelibs-foundation.
        public var useURLSession: Bool

        /// The host that HTTP Ping Client will connect to for the ping test.
        public let host: String

        /// The schema used for the HTTP request.
        public let schema: Schema

        /// The port that the HTTP Ping Client will connect to for the ping test.
        public let port: Int

        /// The HTTP header that will be included in the HTTP request.
        public let httpHeaders: HTTPHeaders

        /// The DNS-resolved address according to the URL endpoint
        public let resolvedAddress: SocketAddress
        
        /// The outgoing device associated with the given interface name
        public private(set) var device: NIONetworkDevice?

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
        ///     - deviceName: the interface name for which the outbound data will be sent to.
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///         - a SocketAddressError.unknown if we could not resolve the host, or SocketAddressError.unsupported if the address itself is not supported (yet).
        public init(url: URL,
                    count: Int = 10,
                    readTimeout: TimeAmount = .seconds(1),
                    connectionTimeout: TimeAmount = .seconds(5),
                    headers: [String: String] = Configuration.defaultHeaders,
                    useServerTiming: Bool = false,
                    useURLSession: Bool = false,
                    deviceName: String? = nil) throws {
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
            self.host = _host

            guard let s = url.scheme, !s.isEmpty else {
                throw PingError.httpMissingSchema
            }

            guard let _schema = Schema(rawValue: s.lowercased()) else {
                throw PingError.httpMissingSchema
            }
            self.schema = _schema

            self.port = url.port ?? schema.defaultPort
            self.resolvedAddress = try SocketAddress.makeAddressResolvingHost(self.host, port: self.port)

            self.httpHeaders = {
                let headerDictionary = headers.isEmpty ? Configuration.defaultHeaders : headers
                var httpHeaders = HTTPHeaders(headerDictionary.map {($0, $1)})
                if !httpHeaders.contains(name: "Host") {
                    var host = _host
                    if let _port = url.port {
                        host += ":\(_port)"
                    }
                    httpHeaders.add(name: "Host", value: host)
                }
                return httpHeaders
            }()
            
            #if os(Linux)
            // NOTE: URLSession is not fully supported in swift-corelibs-foundation
            self.useURLSession = false
            #endif
            
            for device in try System.enumerateDevices() {
                if device.name == deviceName, let address = device.address {
                    switch (address.protocol, self.resolvedAddress.protocol) {
                    case (.inet, .inet), (.inet6, .inet6):
                        self.device = device
                    default:
                        continue
                    }
                }
                if self.device != nil {
                    break
                }
            }
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
        ///     - deviceName: the interface name for which the outbound data will be sent to
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///         - a SocketAddressError.unknown if we could not resolve the host, or SocketAddressError.unsupported if the address itself is not supported (yet).
        public init(url: String,
                    count: Int = 10,
                    readTimeout: TimeAmount = .seconds(1),
                    connectionTimeout: TimeAmount = .seconds(5),
                    headers: [String: String] = Configuration.defaultHeaders,
                    useServerTiming: Bool = false,
                    useURLSession: Bool = false,
                    deviceName: String? = nil) throws {
            guard let urlObj = URL(string: url) else {
                throw PingError.invalidURL(url)
            }

            try self.init(url: urlObj,
                          count: count,
                          readTimeout: readTimeout,
                          connectionTimeout: connectionTimeout,
                          headers: headers,
                          useServerTiming: useServerTiming,
                          useURLSession: useURLSession,
                          deviceName: deviceName)
        }

        /// Initialize a HTTP Ping Client `Configuration`.
        ///
        /// - Parameters:
        ///     - url: the URL string indicating the endpoint target that the HTTP Ping Client will try to connect to.
        ///
        ///     - Throws:
        ///         - httpMissingHost: if URL does not include any host information.
        ///         - httpMissingSchema: if URL does not include any valid schema.
        ///         - a SocketAddressError.unknown if we could not resolve the host, or SocketAddressError.unsupported if the address itself is not supported (yet).
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
        public func makeHTTPRequest(for sequenceNumber: Int) -> Request {
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
