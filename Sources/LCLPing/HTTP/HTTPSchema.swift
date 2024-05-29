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

public enum Schema: String {
    case http
    case https

    var enableTLS: Bool {
        switch self {
        case .http:
            return false
        case .https:
            return true
        }
    }

    var defaultPort: Int {
        return self.enableTLS ? 443 : 80
    }
}
