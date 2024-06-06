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

/// Possible states of an instance of LCLPing
enum PingState: Equatable {

    /// LCLPing is ready to initiate ping requests
    case ready

    /// LCLPing is in progress of sending and receiving ping requests and responses
    case running

    /// LCLPing encountered error(s)
    case error

    /// LCLPing is stopped by explicit `cancel()` and ping summary is ready
    case cancelled

    /// LCLPing finishes and ping summary is ready
    case finished
}
