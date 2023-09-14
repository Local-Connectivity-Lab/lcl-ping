//
//  Utilities.swift
//  
//
//  Created by JOHN ZZN on 8/25/23.
//

import Foundation


internal func sizeof<T>(_ type: T.Type) -> Int {
    return MemoryLayout<T>.size
}

internal func summarizePingResponse(_ pingResponses: [PingResponse], host: String) -> PingSummary {
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
            if pingResults.count > 1 {
                consecutiveDiffSum += abs(latency - pingResults.last!.latency)
            }
            pingResults.append( PingResult(seqNum: sequenceNum, latency: latency, timestamp: timstamp) )
        case .duplicated(let sequenceNum):
            duplicates.insert(sequenceNum)
        case .timeout(let sequenceNum):
            timeout.insert(sequenceNum)
        case .error:
            errorCount += 1
            print("Error occurred during ping")
        }
    }
    
    let pingResultLen = pingResults.count
    let avg = pingResults.avg
    let stdDev = sqrt( pingResults.map { ($0.latency - avg) * ($0.latency - avg) }.reduce(0.0, +) / Double(pingResultLen - 1))

    let pingSummary = PingSummary(min: localMin,
                               max: localMax,
                               avg: avg,
                               median: pingResults.median,
                               stdDev: stdDev,
                               jitter: consecutiveDiffSum / Double(pingResultLen),
                               details: pingResults,
                               totalCount: pingResultLen + errorCount + timeout.count,
                               timeout: timeout,
                               duplicates: duplicates,
                               ipAddress: host)
    
    return pingSummary
}
