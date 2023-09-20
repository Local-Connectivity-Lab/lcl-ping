//
//  Configuration.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation


extension LCLPing {
    
    /// The configuration for running each LCLPing test
    public struct Configuration {
        
        /// Internet Protocol (IP) that LCLPing supports
        public enum IP {
            /// IPv4  address and port(optional)
            case ipv4(String, UInt16?)
            
            /// IPv6 address and port(optional)
            case ipv6(String, UInt16?)
        }
        
        public enum PingType {
            case icmp
            case http(HTTPOptions)
        }
        
        public struct HTTPOptions {
            var useServerTiming: Bool = false
            var enableTLS: Bool = false
        }
        
        public init(type: PingType, endpoint: IP, count: UInt16 = 10, interval: TimeInterval = 1, ttl: UInt16 = 64, timeout: TimeInterval = 1) {
            self.type = type
            self.endpoint = endpoint
            self.count = count
            self.interval = interval
            self.timeToLive = ttl
            self.timeout = timeout
        }
        
        /// The mechanism that LCLPing will use to ping the target host
        let type: PingType
        
        /// The target host that LCLPing will send the Ping request to
        let endpoint: IP
        
        /// Total number of packets sent
        let count: UInt16
        
        /// The wait time, in second, between sending consecutive packet
        let interval: TimeInterval
        
        /// IP Time To Live for outgoing packets
        let timeToLive: UInt16
        
        /// Time, in second, to wait for a reply for each packet sent
        let timeout: TimeInterval
//
//        /// Option to output more information
//        let verboseOutput: Bool
    }
}
