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

internal struct HTTPLatency {
    var requestStart: TimeInterval = .zero
    var responseStart: TimeInterval = .zero
    var responseEnd: TimeInterval = .zero
    var serverTiming: TimeInterval = .zero
    var state: HTTPLatency.State
    var seqNum: UInt16

    init(latencyStatus: HTTPLatency.State = .waiting) {
        self.state = latencyStatus
        self.seqNum = 0
    }
}

extension HTTPLatency {
    enum State {
        case finished
        case timeout
        case error(Error)
        case waiting
    }
}
