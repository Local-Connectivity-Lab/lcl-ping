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
import Logging

/// Estimated server timing if no data is present
let estimatedServerTiming: Double = 15

let LOGGER_LABEL = "org.seattlecommunitynetwork.lclping"
var logger: Logger {
    get {
        var logger = Logger(label: LOGGER_LABEL)
    #if LOG
        logger.logLevel = .debug
    #else // !LOG
        logger.logLevel = .info
    #endif
        return logger
    }

    set {

    }
}
