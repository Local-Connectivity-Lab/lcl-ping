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

internal struct LatencyEntry {
    var requestStart: TimeInterval = .zero
    var responseStart: TimeInterval = .zero
    var responseEnd: TimeInterval = .zero
    var serverTiming: TimeInterval = .zero
    var latencyStatus: LatencyEntry.Status

    let seqNum: UInt16

    init(seqNum: UInt16) {
        self.seqNum = seqNum
        self.latencyStatus = .waiting
    }
}

extension LatencyEntry {
    internal enum Status: Equatable {
        case finished
        case timeout
        case error(UInt) // status code (similar to HTTP status code)
        case waiting
    }
}

internal struct HTTPLatency {
    var requestStart: TimeInterval = .zero
    var responseStart: TimeInterval = .zero
    var responseEnd: TimeInterval = .zero
    var serverTiming: TimeInterval = .zero
    var latencyStatus: HTTPLatency.Status
    var seqNum: UInt16

    init(latencyStatus: HTTPLatency.Status = .waiting) {
        self.latencyStatus = latencyStatus
        self.seqNum = 0
    }
}

extension HTTPLatency {
    enum Status {
        case finished
        case timeout
        case error(PingError)
        case waiting
    }
}
