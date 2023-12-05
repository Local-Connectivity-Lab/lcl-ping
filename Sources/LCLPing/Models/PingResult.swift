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

public struct PingResult : Equatable, Encodable {
    public let seqNum: UInt16
    public let latency: Double
    public let timestamp: TimeInterval
}
