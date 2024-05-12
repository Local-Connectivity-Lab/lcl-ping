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

extension Date {

    /// Get the current timestamp, in second, since  00:00:00 UTC on 1 January 1970
    static var currentTimestamp: TimeInterval {
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
            return Date.now.timeIntervalSince1970
        } else {
            // Fallback on earlier versions
            return Date().timeIntervalSince1970
        }
    }

    /// Create a string representation of the given date in "MM/dd/yyyy HH:mm:ss" format, with the given time zone
    /// - Parameters
    ///     - timeInterval: the time interval, in second, since 01/01/1970.
    ///     - timeZone: the time zone at which the string representation will be converted to
    /// - Return: a string representation of the the given time.
    static func toDateString(timeInterval: TimeInterval, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"

        let date = Date(timeIntervalSince1970: timeInterval)
        return formatter.string(from: date)
    }
}
