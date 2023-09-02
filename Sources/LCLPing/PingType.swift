//
//  PingType.swift
//  
//
//  Created by JOHN ZZN on 9/2/23.
//

import Foundation

extension LCLPing {
    
    /// Supported ping methods
    public enum PingType {
        
        /// Use Internet Control Message Protocol (ICMP) to ping host
        case icmp
        
        /// Use Hypertext Transfer Protocol (HTTP) to ping host with an option to use server-timing header
        case http(HTTPPingType)
        
        /// HTTPPing options
        public enum HTTPPingType {
            
            /// Use server-timing attribute in the HTTP header to measure network performance
            case useServerTiming
            
            /// Measure the performance using round-trip time (RTT)
            case normal
        }
    }
}
