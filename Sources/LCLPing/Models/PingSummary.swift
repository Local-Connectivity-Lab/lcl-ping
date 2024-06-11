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
import NIOCore

/// A summary of the ping test, including the min, max, average, median, standard deviation,
/// and detailed view of each test result.
public struct PingSummary: Equatable, Encodable {
    /// The minimum in the test results.
    public let min: Double

    /// The maximum in the test results.
    public let max: Double

    /// The average of the test results.
    public let avg: Double

    /// The median in the test results.
    public let median: Double

    /// The standard deviation of the test results.
    public let stdDev: Double

    /// The variation in the delay of received packets. It is the deviation from the expected arrival time of data packets.
    public let jitter: Double

    /// A array of detailed view of each successful ping test.
    public let details: [PingResult]

    /// The total number of tests conducted
    public let totalCount: Int

    /// A set of requests, identified by their sequence number, that timed out during the test.
    public let timeout: Set<UInt16>

    /// A set of requests, identified by their sequence number, that the test client received multuple duplicates during the test.
    public let duplicates: Set<UInt16>

    /// A set of errors generated during the test.
    public let errors: Set<ErrorSummary>

    /// The IP address of the host machine where the test is run against to.
    public let ipAddress: String

    /// The port on the host machine where the test is run against to.
    public let port: Int

    /// the protocol used by the test
    public let `protocol`: CInt
}

extension PingSummary {

    /// The summary of error message occurred during the test
    /// `ErrorSummary` could be identified by the sequence number, if some error occurs during a specific test.
    /// If some generic error occurs, then the sequence number is null.
    public struct ErrorSummary: Hashable, Encodable {
        public static func == (lhs: PingSummary.ErrorSummary, rhs: PingSummary.ErrorSummary) -> Bool {
            return lhs.seqNum == rhs.seqNum
        }

        /// The sequence number at which the error occurs.
        public let seqNum: UInt16?

        /// The reason of the error.
        public let reason: String
    }
}

extension PingSummary {

    /// An empty summary.
    static let empty = PingSummary(
        min: .zero,
        max: .zero,
        avg: .zero,
        median: .zero,
        stdDev: .zero,
        jitter: .zero,
        details: [],
        totalCount: .zero,
        timeout: .init(),
        duplicates: .init(),
        errors: .init(),
        ipAddress: "",
        port: 0,
        protocol: 0
    )
}
