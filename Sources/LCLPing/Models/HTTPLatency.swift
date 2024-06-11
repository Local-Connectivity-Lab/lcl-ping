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

/// `HTTPLatency` represents the latency information from a HTTP request/response pair.
/// It is similar to `PerformanceResourceTiming` in the WebAPI that tracks the start and the end of a request/response
/// timing for analyzing loading the remote resources,
internal struct HTTPLatency {

    /// The time before the client starts requesting the resource from the server.
    var requestStart: TimeInterval = .zero

    /// The time before the client starts receiving the resources from the server.
    var responseStart: TimeInterval = .zero

    /// The time after the client finishes receiving all the resources from the server.
    var responseEnd: TimeInterval = .zero

    /// The  aggregated`ServerTiming` information, if specified in the HTTP header.
    var serverTiming: TimeInterval = .zero

    /// The state of fulfilling each piece of information in `HTTPLatency`.
    var state: HTTPLatency.State

    /// The sequence number of the request related to this `HTTPLatency`.
    var seqNum: UInt16

    init(latencyStatus: HTTPLatency.State = .waiting) {
        self.state = latencyStatus
        self.seqNum = 0
    }
}

extension HTTPLatency {

    /// The state of fulfilling each piece of information in the `HTTPLatency`.
    enum State {

        /// HTTP response is received and no error occured.
        case finished

        /// The request timed out before receiving all requested resources.
        case timeout

        /// Error occured while waiting for resources from the server.
        case error(Error)

        /// The client is waiting for responses coming back from the server.
        case waiting
    }
}
