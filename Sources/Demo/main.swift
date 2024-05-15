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

#if swift(>=5.9)
import Foundation
import LCLPing

// create ping configuration for each run
let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("google.com", 0))

// create ping options
#if os(macOS) || os(iOS)
let options = LCLPing.Options(verbose: false, useNative: false)
#else
let options = LCLPing.Options(verbose: false)
#endif

// initialize ping object with the options
var ping = LCLPing(options: options)

try await ping.start(pingConfiguration: pingConfig)
switch ping.status {
case .error, .ready, .running:
    print("LCLPing is in invalid state. Abort")
case .stopped, .finished:
    print(ping.summary)
}
#else
fatalError("Requires at least Swift 5.9")
#endif
