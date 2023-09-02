//
//  File.swift
//  
//
//  Created by JOHN ZZN on 8/31/23.
//

import Foundation

extension TimeInterval {
    
    /// The time interval in unsigned Int64
    var nanosecond: UInt64 {
        return UInt64(self * 1_000_000_000)
    }
}
