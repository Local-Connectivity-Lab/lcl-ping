//
//  Configuration.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation
import NIOHTTP1


extension LCLPing {
    
    /// The configuration for running each LCLPing test
    public struct Configuration {
        
        /// Internet Protocol (IP) that LCLPing supports
        public enum IP {
            /// IPv4  address and port(optional)
            case ipv4(String, UInt16?)
            
            /// IPv6 address
            case ipv6(String)
        }
        
        public enum PingType {
            case icmp
            case http(HTTPOptions)
        }
        
        public struct HTTPOptions {
            public var useServerTiming: Bool = false
            public var httpHeaders: [String:String] = [
                "User-Agent": "lclping",
                "Accept": "application/json",
                "Connection": "close"
            ]
            
            public init() {
                
            }
        }
        
        public init(type: PingType, endpoint: IP) {
            self.type = type
            self.endpoint = endpoint
        }
        
        /// The mechanism that LCLPing will use to ping the target host
        public var type: PingType
        
        /// The target host that LCLPing will send the Ping request to
        public var endpoint: IP
        
        /// Total number of packets sent. Default to 10 times.
        public var count: UInt16 = 10
        
        /// The wait time, in second, between sending consecutive packet. Default is 1s.
        public var interval: TimeInterval = 1
        
        /// IP Time To Live for outgoing packets. Default is 64.
        public var timeToLive: UInt16 = 64
        
        /// Time, in second, to wait for a reply for each packet sent. Default is 1s.
        public var timeout: TimeInterval = 1
    }
}
