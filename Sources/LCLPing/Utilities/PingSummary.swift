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

public struct PingSummary: Equatable, Encodable {
    public let min: Double
    public let max: Double
    public let avg: Double
    public let median: Double
    public let stdDev: Double
    public let jitter: Double
    public let details: [PingResult]
    public let totalCount: Int
    public let timeout: Set<UInt16>
    public let duplicates: Set<UInt16>
    public let errors: Set<ErrorSummary>
    public let ipAddress: String
    public let port: Int
    public let `protocol`: CInt
}

extension PingSummary {
    public struct ErrorSummary: Hashable, Encodable {
        public static func == (lhs: PingSummary.ErrorSummary, rhs: PingSummary.ErrorSummary) -> Bool {
            return lhs.seqNum == rhs.seqNum
        }

        public let seqNum: UInt16?
        public let reason: String
    }
}

extension PingSummary {
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
