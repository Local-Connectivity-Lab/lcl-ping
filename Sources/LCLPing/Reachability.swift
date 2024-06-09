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

extension LCLPing {

    /// Check if the target host is reachable or not
    ///
    /// - Parameters:
    ///     - via:  the `ReachabilityTestMethod` that will be used to run the reachability tes
    ///     - host: the endpoint host
    /// - Returns: true if the host is reachable; false otherwise.
    public static func reachable(via method: ReachabilityTestMethod, host: String) throws -> Bool {
        return try reachable(via: method, strategy: .multiple, host: host)
    }

    /// Check if the target host is reachable or not. 
    /// A simple majority of the successful test could be considered as reachable
    ///
    /// - Parameters:
    ///     - via:  the `ReachabilityTestMethod` that will be used to run the reachability tes
    ///     - strategy: the `TestStrategy` that indicates how many times the `LCLPing` should run to make the result reliable
    ///     - host: the endpoint host
    public static func reachable(via method: ReachabilityTestMethod, 
                                 strategy: TestStrategy,
                                 host: String
    ) throws -> Bool {
        switch method {
        case .http:
            let httpConfig = try HTTPPingClient.Configuration(url: host, count: strategy.count)
            let client = HTTPPingClient(configuration: httpConfig)
            let result = try client.start().wait()
            return result.isSimpleMajority()
        case .ipv4ICMP:
            let icmpConfig = ICMPPingClient.Configuration(endpoint: .ipv4(host, 0), count: strategy.count)
            let client = ICMPPingClient(configuration: icmpConfig)
            let result = try client.start().wait()
            return result.isSimpleMajority()
        }
    }

    public enum ReachabilityTestMethod {
        case ipv4ICMP
        case http
    }

    public enum TestStrategy {
        case single
        case multiple
        case extended

        // TODO: need to support continuous, stream of testing
//        case continuous

        var count: Int {
            switch self {
            case .single:
                return 1
            case .multiple:
                return 3
            case .extended:
                return 10
            }
        }
    }
}

extension PingSummary {
    /// Check if ping summary has a simple majority of successful results.
    ///
    /// - Returns: true if a simple majority of results are successful; false otherwise.
    public func isSimpleMajority() -> Bool {
        if self.totalCount == 0 {
            return false
        }
        let majority = self.totalCount % 2 == 0 ? self.totalCount / 2 : self.totalCount / 2 + 1
        return self.details.count >= majority
    }
}
