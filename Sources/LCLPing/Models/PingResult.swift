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

/// The result from each individual ping test.
///
/// `PingResult` represents the latency for each request/response pair
/// identified by its sequence number.
public struct PingResult: Equatable, Encodable {

    /// The sequence number that this `PingResult` represents.
    public let seqNum: UInt16

    /// The latency for the ping test.
    public let latency: Double

    /// The timestamp that marks when the ping test finishes.
    public let timestamp: TimeInterval
}
