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

//extension LCLPing {
//
//    /// The options that controls the overall behaviors of the LCLPing instance.
//    public struct Options {
//        /// Whether or not to output more information when the test is running. Default is false.
//        public var verbose = false
//        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
//        /// Whether or not to use native URLSession implementation on Apple Platform if HTTP Ping test is selected.
//        /// If ICMP Ping test is selected, then setting this variable results in an no-op.
//        public var useURLSession = false
//        #endif
//
//        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
//        /// Initialize the `Options` with given verbose level and 
//        /// given selections on HTTP implementation for HTTP Ping test.
//        /// - Parameters:
//        ///     - verbose: a boolean value indicating whether to output verbosely or not.
//        ///     - useNative: a boolean value indicating whether to use native URLSession on Apple Platform or not.
//        public init(verbose: Bool = false, useURLSession: Bool = false) {
//            self.verbose = verbose
//            self.useURLSession = useURLSession
//        }
//        #else // !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
//        /// Initialize the `Options` with given verbose level.
//        /// - Parameters:
//        ///     - verbose: a boolean value indicating whether to output verbosely or not.
//        public init(verbose: Bool = false) {
//            self.verbose = verbose
//        }
//        #endif // !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
//    }
//}
//
//extension LCLPing {
//    public enum PingType {
//        case icmp
//        case http
//    }
//}
