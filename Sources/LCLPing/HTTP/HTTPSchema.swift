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

/// The HTTP schema supported by the `HTTPPingClient`
public enum Schema: String {

    /// The HTTP schema
    case http

    /// The HTTPS schema
    case https

    /// Indicate whether the schema should enable TLS
    ///
    /// - Returns: true if the schema is set to HTTPS; false otherwise.
    var enableTLS: Bool {
        switch self {
        case .http:
            return false
        case .https:
            return true
        }
    }

    /// The default port that will be used when connecting to the host if not specified.
    ///
    /// - Returns: 443 if the HTTPS schema is used; otherwise, fall back to 80.
    var defaultPort: Int {
        return self.enableTLS ? 443 : 80
    }
}
