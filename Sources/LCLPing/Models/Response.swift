//
// This source file is part of the LCLPing open source project
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

internal enum PingResponse: Equatable {
    static func == (lhs: PingResponse, rhs: PingResponse) -> Bool {
        switch (lhs, rhs) {
        case (PingResponse.ok(let lSequenceNum, let lLatency, let lTime), PingResponse.ok(let rSequenceNum, let rLatency, let rTime)):
            return lSequenceNum == rSequenceNum && lLatency == rLatency && lTime == rTime
        case (PingResponse.duplicated(let lSequenceNum), PingResponse.duplicated(let rSequenceNum)):
            return lSequenceNum == rSequenceNum
        case (PingResponse.timeout(let lSequenceNun), PingResponse.timeout(let rSequenceNum)):
            return lSequenceNun == rSequenceNum
        case (PingResponse.error(.some(let lError)), PingResponse.error(.some(let rError))):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
    
    case ok(UInt16, Double, TimeInterval)
    case duplicated(UInt16)
    case timeout(UInt16)
    case error(Error?)
}
