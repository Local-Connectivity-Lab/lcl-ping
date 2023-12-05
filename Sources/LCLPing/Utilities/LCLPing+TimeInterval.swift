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

extension TimeInterval {
    
    /// The time interval in unsigned Int64
    var nanosecond: UInt64 {
        return UInt64(self * 1_000_000_000)
    }
}
