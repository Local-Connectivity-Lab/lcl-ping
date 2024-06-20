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
import LCLPing

// create ping configuration for each run
let icmpConfig = ICMPPingClient.Configuration(endpoint: .ipv4("127.0.0.1", 0), count: 1)
let httpConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080", count: 1)

// initialize test client
let icmpClient = ICMPPingClient(configuration: icmpConfig)
let httpClient = HTTPPingClient(configuration: httpConfig)

do {
    // run the test using SwiftNIO EventLoopFuture
    let result = try icmpClient.start().wait()
    print(result)
} catch {
    print("received: \(error)")
}

do {
    let result = try httpClient.start().wait()
    print(result)
} catch {
    print("received: \(error)")
}
