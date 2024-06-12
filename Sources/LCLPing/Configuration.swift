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

/// Type of reachability test that `LCLPing` supports
public enum PingType {
    /// Perform reachability ping test through the ICMP protocol.
    case icmp

    /// Perform reachability ping test through the HTTP protocol.
    case http
}
