//
//  PingSummary.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation
import NIOCore

public struct PingSummary: Equatable {    
    let min: Double
    let max: Double
    let avg: Double
    let median: Double
    let stdDev: Double
    let jitter: Double
    let details: [PingResult]
    let totalCount: Int
    let timeout: Set<UInt16>
    let duplicates: Set<UInt16>
    let ipAddress: String
    let port: Int
    let `protocol`: CInt
}

extension PingSummary {
    static let empty: PingSummary = .init(min: .zero, max: .zero, avg: .zero, median: .zero, stdDev: .zero, jitter: .zero, details: [], totalCount: .zero, timeout: .init(), duplicates: .init(), ipAddress: "", port: 0, protocol: 0)
}
