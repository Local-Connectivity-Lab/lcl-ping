//
//  PerformanceEntry.swift
//  
//
//  Created by JOHN ZZN on 9/19/23.
//

import Foundation


struct PerformanceEntry {
    var requestStart: TimeInterval = .zero
    var responseStart: TimeInterval = .zero
    var responseEnd: TimeInterval = .zero
    
    let seqNum: UInt16
    
    init(seqNum: UInt16) {
        self.seqNum = seqNum
    }
}
