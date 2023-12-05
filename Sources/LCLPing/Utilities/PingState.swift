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


/// Possible states of an instance of LCLPing
public enum PingState {
    
    /// LCLPing is ready to initiate ping requests
    case ready
    
    /// LCLPing is in progress of sending and receiving ping requests and responses
    case running
    
    /// LCLPing encountered error(s)
    case error
    
    /// LCLPing is stopped by explicit `stop()` and ping summary is ready
    case stopped
    
    /// LCLPing finishes and ping summary is ready
    case finished
}
