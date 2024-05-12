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

/**
    A Pingable protocol allows the caller to check the reachability of a host with a given ping configuration.
    It allows the caller to start the ping test asynchronously and check the measurement results.

    The implementer of this protocol needs to support 
        - initiating the ping test with a ping configuration, 
        - stop the test if the test is being cancelled,
        - correctly reflect the state of the ping test (`PingState`), and 
        - reporting the result in summary (`PingSummary`).

    The caller needs to check the `pingStatus` first before reading the test result from `summary`.
*/
protocol Pingable {

    /// Start the ping test with the given pingConfiguration asynchronously. Outstanding tests will be cancelled
    /// if error occurs during the test. 
    mutating func start(with pingConfiguration: LCLPing.PingConfiguration) async throws

    // TODO: need to handle fallback of start(callback)

    /// Stop the ping test. `pingStatus` will be set to `stopped` after calling this function. 
    /// The test result will be ready after calling this function.
    mutating func stop()

    /// Retrieve the test result. The summary may be nil if some error occurs in the middle of the test.
    var summary: PingSummary? { get }

    /// The status of the ping test. See `PingState` for more details.
    var pingStatus: PingState { get }
}
