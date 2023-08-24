//
//  PingResult.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

public struct PingResult {
    let seqNum: UInt16
    let latency: Double
    let ipAddress: String // TODO: support IPv4 and IPv6
    let timestamp: String
}
