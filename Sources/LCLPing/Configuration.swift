//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOHTTP1
import NIOCore

extension LCLPing {

    /// The options that controls the overall behaviors of the LCLPing instance.
    public struct Options {
        /// Whether or not to output more information when the test is running. Default is false.
        public var verbose = false
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        /// Whether or not to use native URLSession implementation on Apple Platform if HTTP Ping test is selected.
        /// If ICMP Ping test is selected, then setting this variable results in an no-op.
        public var useNative = false
        #endif

        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        /// Initialize the `Options` with given verbose level and 
        /// given selections on HTTP implementation for HTTP Ping test.
        /// - Parameters:
        ///     - verbose: a boolean value indicating whether to output verbosely or not.
        ///     - useNative: a boolean value indicating whether to use native URLSession on Apple Platform or not.
        public init(verbose: Bool = false, useNative: Bool = false) {
            self.verbose = verbose
            self.useNative = useNative
        }
        #else // !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
        /// Initialize the `Options` with given verbose level.
        /// - Parameters:
        ///     - verbose: a boolean value indicating whether to output verbosely or not.
        public init(verbose: Bool = false) {
            self.verbose = verbose
        }
        #endif // !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
    }
}

extension LCLPing {

    /// The configuration for running each LCLPing test
    public struct PingConfiguration {

        /// Internet Protocol (IP) that LCLPing supports
        public enum IP {
            /// IPv4  address and port(optional)
            case ipv4(String, UInt16?)

            /// IPv6 address
            case ipv6(String)
        }

        /// Ping Type supported by LCLPing
        public enum PingType {
            /// Internet Control Message Protocol (ICMP) for IPv4 (RFC 792). IPv6 is currently not supported.
            case icmp

            /// Hypertext Transfer Protocol (HTTP) with a `HTTPOptions`.
            case http(HTTPOptions)
        }

        /// The configuration that defines the various behaviors of HTTP Ping test.
        public struct HTTPOptions {
            /// The default header used by LCLPing when sending HTTP request to the target destination.
            public static let DEFAULT_HEADER: [String: String] = [
                "User-Agent": "lclping",
                "Accept": "application/json",
                "Connection": "close"
            ]

            public var useServerTiming: Bool = false
            public var httpHeaders: [String: String] = DEFAULT_HEADER {
                didSet {
                    if httpHeaders.isEmpty {
                        httpHeaders = HTTPOptions.DEFAULT_HEADER
                    }
                }
            }

            public init() { }
        }

        public init(type: PingType,
                    endpoint: IP,
                    count: UInt16 = 10,
                    interval: TimeInterval = 1,
                    timeToLive: UInt16 = 64,
                    timeout: TimeInterval = 1
        ) {
            self.type = type
            self.endpoint = endpoint
            self.count = count
            self.interval = interval
            self.timeToLive = timeToLive
            self.timeout = timeout
        }

        /// The mechanism that LCLPing will use to ping the target host
        public var type: PingType

        /// The target host that LCLPing will send the Ping request to
        public var endpoint: IP

        /// Total number of packets sent. Default to 10 times.
        public var count: UInt16

        /// The wait time, in second, between sending consecutive packet. Default is 1s.
        public var interval: TimeInterval

        /// IP Time To Live for outgoing packets. Default is 64.
        public var timeToLive: UInt16

        /// Time, in second, to wait for a reply for each packet sent. Default is 1s.
        public var timeout: TimeInterval
    }
}

extension LCLPing {
    public enum PingType {
        case icmp
        case http
    }

    public struct HTTPConfiguration {

        public static let defaultHeaders: [String: String] =
            [
                "User-Agent": "lclping",
                "Accept": "application/json",
                "Connection": "close"
            ]

        public let url: URL
        public var count: Int
//        public var interval: TimeAmount
        public var timeout: TimeAmount

        public var headers: [String: String]
        public var useServerTiming: Bool

        public let host: String
        public let schema: Schema
        public let port: Int

        public init(url: URL, count: Int = 10, interval: TimeAmount = .seconds(1), timeout: TimeAmount = .seconds(1), headers: [String: String] = HTTPConfiguration.defaultHeaders, useServerTiming: Bool = false) throws {
            self.url = url
            self.count = count
//            self.interval = interval
            self.timeout = timeout
            self.headers = headers
            self.useServerTiming = useServerTiming

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

        public init(url: String) throws {
            guard let urlObj = URL(string: url) else {
                throw PingError.invalidURL
            }
            try self.init(url: urlObj)
        }

        public func makeHTTPRequest() -> HTTPRequestHead {
            var httpHeaders = self.makeHTTPHeaders()
            if !httpHeaders.contains(name: "Host") {
                var host = self.host
                if self.port != self.schema.defaultPort {
                    host += ":\(self.port)"
                }
                httpHeaders.add(name: "Host", value: host)
            }
            return HTTPRequestHead(version: .http1_1, method: .GET, uri: url.uri, headers: httpHeaders)
        }

        public func makeHTTPHeaders() -> HTTPHeaders {
            let headerDictionary = self.headers.isEmpty ? HTTPConfiguration.defaultHeaders : self.headers
            return HTTPHeaders(headerDictionary.map {($0, $1)})
        }
    }
}

extension URL {
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
