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

/// Responses for each ping test.
///
/// There are 4 categories of responses, each of which maps to one potential circumstance during the test
internal enum PingResponse: Equatable {
    static func == (lhs: PingResponse, rhs: PingResponse) -> Bool {
        switch (lhs, rhs) {
        case (PingResponse.ok(let lSequenceNum, let lLatency, let lTime), PingResponse.ok(let rSequenceNum, let rLatency, let rTime)):
            return lSequenceNum == rSequenceNum && lLatency == rLatency && lTime == rTime
        case (PingResponse.duplicated(let lSequenceNum), PingResponse.duplicated(let rSequenceNum)):
            return lSequenceNum == rSequenceNum
        case (PingResponse.timeout(let lSequenceNum), PingResponse.timeout(let rSequenceNum)):
            return lSequenceNum == rSequenceNum
        case (PingResponse.error(.some(let lSequenceNum), .some(let lError)), PingResponse.error(.some(let rSequenceNum), .some(let rError))):
            return lError.localizedDescription == rError.localizedDescription && lSequenceNum == rSequenceNum
        default:
            return false
        }
    }

    /// Test finishes as expected. The sequence number, latency, and timestamp when the test finishes will be reported.
    case ok(UInt16, Double, TimeInterval)

    /// Test is a duplicate of a previously finished test. The sequence number of the test will be reported.
    case duplicated(UInt16)

    /// Test timed out (no response is received during the period of a some wait time, specified in the configuration).
    /// The sequence number of the test will be reported.
    case timeout(UInt16)

    /// Test failed with some error. If error occurs during a specific test, 
    /// then the sequence number of the test will be reported.
    /// Otherwise, only the error will be reported.
    case error(UInt16?, Error?)
}
