// //
// // This source file is part of the LCL open source project
// //
// // Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// // Licensed under Apache License v2.0
// //
// // See LICENSE for license information
// // See CONTRIBUTORS for the list of project authors
// //
// // SPDX-License-Identifier: Apache-2.0
// //

import Foundation
import NIOCore
import NIOPosix

 /// The top-level entrypoint for Ping test
 ///
 /// An LCLPing instance allows the caller to initialize the ping test with 
 /// either ICMP or HTTP method and read the result once the test finishes.
 /// It also gives caller the opportunity to cancel the test.
 public struct LCLPing {

     /// A instance that implements Pingable protocol.
     private var ping: Pingable

     /// Type of test (ICMP or HTTP) that the caller wants to perform
     private let pingType: PingType

     /// Initialize the LCLPing instance with the given options
     public init(pingType: PingType) {
         self.pingType = pingType
         switch pingType {
         case .icmp(let config):
             ping = ICMPPingClient(configuration: config)
         case .http(let config):
             ping = HTTPPingClient(configuration: config)
         }
     }

     /// Start the ping test with the `pingType` and associated configuration
     ///
     /// - Returns: An future, when resolved, contains the result `PingSummary`
     public func start() throws -> EventLoopFuture<PingSummary> {
         return try ping.start()
     }

     /// Cancel the current ping test.
     /// All outstanding tests will be canceled and results will be ignored.
     public func cancel() {
         logger.debug("try to stop ping")
         ping.cancel()
         logger.debug("ping stopped")
     }
 }
