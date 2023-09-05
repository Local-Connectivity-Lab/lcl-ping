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
        
        public init(count: UInt16 = 10, interval: TimeInterval = 1, ttl: UInt16 = 64, timeout: TimeInterval = 1, host: IP) {
            self.count = count
            self.interval = interval
            self.timeToLive = ttl
            self.timeout = timeout
            self.host = host
        }
        
        // TODO: need to add default value
        
        /// Total number of packets sent
        let count: UInt16
        
        /// The wait time, in second, between sending consecutive packet
        let interval: TimeInterval
        
        /// IP Time To Live for outgoing packets
        let timeToLive: UInt16
        
        /// Time, in second, to wait for a reply for each packet sent
        let timeout: TimeInterval
        
        /// The destination IP address the packet will be sent to
        let host: IP
    }
    
    public enum IP {
        
        /// ICMP address
        case icmp(String)
        
        /// IPv4  address and port
        case ipv4(String, UInt16)
        
        /// IPv6 address and port
        case ipv6(String, UInt16)
    }
}
