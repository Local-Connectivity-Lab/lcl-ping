//
//  File.swift
//  
//
//  Created by JOHN ZZN on 9/1/23.
//

import Foundation


extension Array where Element == PingResult {
    var avg: Double {
        if isEmpty {
            return 0.0
        }

        let sum = reduce(0.0) { partialResult, pingResult in
            partialResult + pingResult.latency
        }
        
        return sum / Double(count)
    }
    
    var median: Double {
        if isEmpty {
            return 0
        }
        
        let sorted = sorted { $0.latency < $1.latency }
        if count % 2 == 1 {
            // odd
            return sorted[count / 2].latency
        } else {
            // even - lower end will be returned
            return sorted[count / 2 - 1].latency
        }
        
    }
}
