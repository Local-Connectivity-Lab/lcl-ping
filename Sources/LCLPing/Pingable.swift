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

/**
    A Pingable protocol allows the caller to check the reachability of a host with a given ping configuration.
    It allows the caller to start the ping test asynchronously and check the measurement results.

    The implementer of this protocol needs to support 
        - initiating the ping test with a ping configuration, 
        - stop the test if the test is being canceled,
*/
protocol Pingable {

    /// Start the ping test asynchronously. Outstanding tests will be canceled
    /// if error occurs during the test. 
    ///
    /// - Returns: an eventloop future, when resolved, will be the summary of the ping test.
    func start() throws -> EventLoopFuture<PingSummary>

    /// Cancel and then stop the ping test.
    /// All outstanding tests will be canceled and results from them will be ignored
    func cancel()
}
