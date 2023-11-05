//
//  LCLPing+Time.swift
//  
//
//  Created by JOHN ZZN on 8/25/23.
//

import Foundation

extension Date {

    /// Get the current timestamp, in second, since  00:00:00 UTC on 1 January 1970
    static var currentTimestamp: TimeInterval {
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
            return Date.now.timeIntervalSince1970
        } else {
            // Fallback on earlier versions
            return Date().timeIntervalSince1970
        }
    }
    
    static func toDateString(timeInterval: TimeInterval, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        
        let date = Date(timeIntervalSince1970: timeInterval)
        return formatter.string(from: date)
    }
}
