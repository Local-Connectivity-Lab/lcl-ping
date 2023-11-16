//
//  PingResult.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

public struct PingResult : Equatable, Encodable {
    public let seqNum: UInt16
    public let latency: Double
    public let timestamp: TimeInterval
}
