//
// This source file is part of the LCLPing open source project
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


internal func sizeof<T>(_ type: T.Type) -> Int {
    return MemoryLayout<T>.size
}

internal func summarizePingResponse(_ pingResponses: [PingResponse], host: SocketAddress) -> PingSummary {
    var localMin: Double = .greatestFiniteMagnitude
    var localMax: Double = .zero
    var consecutiveDiffSum: Double = .zero
    var errorCount: Int = 0
    var pingResults: [PingResult] = []
    var timeout: Set<UInt16> = Set()
    var duplicates: Set<UInt16> = Set()
    
    for pingResponse in pingResponses {
        switch pingResponse {
        case .ok(let sequenceNum, let latency, let timstamp):
            localMin = min(localMin, latency)
            localMax = max(localMax, latency)
            if pingResults.count >= 1 {
                consecutiveDiffSum += abs(latency - pingResults.last!.latency)
            }
            pingResults.append( PingResult(seqNum: sequenceNum, latency: latency, timestamp: timstamp) )
        case .duplicated(let sequenceNum):
            duplicates.insert(sequenceNum)
        case .timeout(let sequenceNum):
            timeout.insert(sequenceNum)
        case .error:
            errorCount += 1
        }
    }
    
    let pingResultLen = pingResults.count
    let avg = pingResults.avg
    let stdDev = pingResults.stdDev
    
    let pingSummary = PingSummary(min: localMin,
                                  max: localMax,
                                  avg: avg,
                                  median: pingResults.median,
                                  stdDev: stdDev,
                                  jitter: pingResultLen == 0 ? 0.0 : consecutiveDiffSum / Double(pingResultLen),
                                  details: pingResults,
                                  totalCount: pingResultLen + errorCount + timeout.count,
                                  timeout: timeout,
                                  duplicates: duplicates,
                                  ipAddress: host.ipAddress ?? "",
                                  port: host.port ?? 0, protocol: host.protocol.rawValue)
    
    return pingSummary
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
