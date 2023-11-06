//
//  PingResult.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

public struct PingResult : Equatable {
    let seqNum: UInt16
    let latency: Double
    let timestamp: TimeInterval
}
