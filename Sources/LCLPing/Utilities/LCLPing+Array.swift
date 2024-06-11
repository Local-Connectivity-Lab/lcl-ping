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

extension Array where Element == PingResult {

    /// Average of the given array of `PingResult`
    var avg: Double {
        if isEmpty {
            return 0.0
        }

        let sum = reduce(0.0) { partialResult, pingResult in
            partialResult + pingResult.latency
        }

        return sum / Double(count)
    }

    /// Median of the given array of `PingResult`
    var median: Double {
        if isEmpty {
            return 0
        }

        let sorted = sorted { $0.latency < $1.latency }
        if count % 2 == 1 {
            // odd
            return sorted[count / 2].latency
        } else {
            // even - lower end will be returned
            return sorted[count / 2 - 1].latency
        }

    }

    /// Standard Deviation of the given array of `PingResult`
    var stdDev: Double {
        if isEmpty || count == 1 {
            return 0.0
        }

        return sqrt(map { ($0.latency - avg) * ($0.latency - avg) }.reduce(0.0, +) / Double(count - 1))
    }
}

extension Array where Element == PingResponse {

    /// Summarize all ping responses after measuring the reachability from the given host.
    /// - Parameters:
    ///     - pingResponses: a list of `PingResponse` generated from the test
    ///     - host: the target host where the ping test is issued
    /// - Returns: a summary of ping test (`PingSummary`).
    func summarize(host: SocketAddress) -> PingSummary {
        var localMin: Double = .greatestFiniteMagnitude
        var localMax: Double = .zero
        var consecutiveDiffSum: Double = .zero
        var errorCount: Int = 0
        var errors: Set<PingSummary.ErrorSummary> = Set()
        var pingResults: [PingResult] = []
        var timeout: Set<UInt16> = Set()
        var duplicates: Set<UInt16> = Set()

        for pingResponse in self {
            switch pingResponse {
            case .ok(let sequenceNum, let latency, let timstamp):
                localMin = Swift.min(localMin, latency)
                localMax = Swift.max(localMax, latency)
                if pingResults.count >= 1 {
                    consecutiveDiffSum += abs(latency - pingResults.last!.latency)
                }
                pingResults.append( PingResult(seqNum: sequenceNum, latency: latency, timestamp: timstamp) )
            case .duplicated(let sequenceNum):
                duplicates.insert(sequenceNum)
            case .timeout(let sequenceNum):
                timeout.insert(sequenceNum)
            case .error(let seqNum, let error):
                errorCount += 1
                if let error = error {
                    errors.insert(PingSummary.ErrorSummary(seqNum: seqNum, reason: error.localizedDescription))
                }
            }
        }

        let pingResultLen = pingResults.count
        let avg = pingResults.avg
        let stdDev = pingResults.stdDev

        let pingSummary = PingSummary(min: localMin == .greatestFiniteMagnitude ? 0.0 : localMin,
                                      max: localMax,
                                      avg: avg,
                                      median: pingResults.median,
                                      stdDev: stdDev,
                                      jitter: pingResultLen == 0 ? 0.0 : consecutiveDiffSum / Double(pingResultLen),
                                      details: pingResults,
                                      totalCount: pingResultLen + errorCount + timeout.count,
                                      timeout: timeout,
                                      duplicates: duplicates,
                                      errors: errors,
                                      ipAddress: host.ipAddress ?? "",
                                      port: host.port ?? 0, protocol: host.protocol.rawValue)

        return pingSummary
    }
}
