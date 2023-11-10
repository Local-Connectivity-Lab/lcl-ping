//
//  PingSummary.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation
import NIOCore

public struct PingSummary: Equatable {    
    public let min: Double
    public let max: Double
    public let avg: Double
    public let median: Double
    public let stdDev: Double
    public let jitter: Double
    public let details: [PingResult]
    public let totalCount: Int
    public let timeout: Set<UInt16>
    public let duplicates: Set<UInt16>
    public let ipAddress: String
    public let port: Int
    public let `protocol`: CInt
}

extension PingSummary {
    static let empty: PingSummary = .init(min: .zero, max: .zero, avg: .zero, median: .zero, stdDev: .zero, jitter: .zero, details: [], totalCount: .zero, timeout: .init(), duplicates: .init(), ipAddress: "", port: 0, protocol: 0)
}
