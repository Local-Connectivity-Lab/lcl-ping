//
//  PingSummary.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

public struct PingSummary {
    let min: Double
    let max: Double
    let avg: Double
    let median: Double
    let stdDev: Double
    let jitter: Double
    let details: [PingResult]
    let totalCount: UInt16
    let timeOutCount: UInt16
    let duplicateCount: UInt16
    let ipAddress: String // TODO: support IPv4 and IPv6
}
