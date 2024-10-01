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

extension ChannelOption where Self == ChannelOptions.Types.SocketOption {
    public static func ipv6Option(_ name: NIOBSDSocket.Option) -> Self {
        .init(level: .ipv6, name: name)
    }
}
