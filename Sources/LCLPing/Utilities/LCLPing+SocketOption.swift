//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOCore

extension NIOBSDSocket.Option {
    #if canImport(Darwin)
    public static let ip_bound_if: NIOBSDSocket.Option = Self(rawValue: IP_BOUND_IF)
    public static let ipv6_bound_if: NIOBSDSocket.Option = Self(rawValue: IPV6_BOUND_IF)
    #elseif canImport(Glibc)
    public static let so_bindtodevice = Self(rawValue: SO_BINDTODEVICE)
    #endif
}

extension SocketOptionProvider {
    #if canImport(Glibc)
    /// Sets the socket option SO_BINDTODEVICE to `value`.
    ///
    /// - parameters:
    ///     - value: The value to set SO_BINDTODEVICE to.
    /// - returns: An `EventLoopFuture` that fires when the option has been set,
    ///     or if an error has occurred.
    public func setBindToDevice(_ value: String) -> EventLoopFuture<Void> {
        self.unsafeSetSocketOption(level: .socket, name: .so_bindtodevice, value: value)
    }
    #endif
}
