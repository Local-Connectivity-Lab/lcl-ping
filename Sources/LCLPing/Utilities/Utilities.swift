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
import NIOCore

/// Find and sum up the server timing fields in the HTTP header string
/// - Parameters:
///     - field: the http header field, in String, from which the `Server-Timing` field is queried.
/// - Returns: the sum of all attributes in the `Server-Timing` field in the given field string.
internal func matchServerTiming(field: String) -> Double {
    var totalTiming: Double = 0.0
    if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
        let pattern = #/dur=([\d.]+)/#
        let matches = field.matches(of: pattern)
        for match in matches {
            totalTiming += Double(match.output.1) ?? 0.0
        }
    } else {
        do {
            let pattern = try NSRegularExpression(pattern: #"dur=([\d.]+)"#)
            let matchingResult = pattern.matches(in: field, range: NSRange(location: .zero, length: field.count))
            matchingResult.forEach { result in
                let nsRange = result.range(at: 1)
                if let range = Range(nsRange, in: field) {
                    totalTiming += Double(field[range]) ?? 0.0
                }
            }
        } catch {
            // do nothing
            // TODO: log
        }
    }
    return totalTiming
}

/// Calculate the size of a given type considering it memory layout
/// - Parameters:
///     - type: the type on which the size will be calculated
/// - Returns: the size of the given type, in Int.
internal func sizeof<T>(_ type: T.Type) -> Int {
    return MemoryLayout<T>.size
}

internal func printSummary(_ pingSummary: PingSummary) {
    print("====== Ping Result ======")
    print("Host: \(pingSummary.ipAddress)")
    print("Total Count: \(pingSummary.totalCount)")

    print("====== Details ======")

    for detail in pingSummary.details {
        print("#\(detail.seqNum): \(detail.latency.round(to: 2)) ms.  [\(Date.toDateString(timeInterval: detail.timestamp))]")
    }

    print("Duplicate: \(pingSummary.duplicates.sorted())")
    print("Timeout: \(pingSummary.timeout.sorted())")

    print("======= Statistics =======")
    print("Jitter: \(pingSummary.jitter.round(to: 2)) ms")
    print("Average: \(pingSummary.avg.round(to: 2)) ms")
    print("Medium: \(pingSummary.median.round(to: 2)) ms")
    print("Min: \(pingSummary.min.round(to: 2)) ms")
    print("Max: \(pingSummary.max.round(to: 2)) ms")
    print("Standard Deviation: \(pingSummary.stdDev.round(to: 2)) ms")

}
