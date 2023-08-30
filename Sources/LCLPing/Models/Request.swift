//
//  Request.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

/// The IPv4 Header
internal struct IPv4Header {
    let versionAndHeaderLength: UInt8
    let differentiatedServicesAndECN: UInt8
    let totalLength: UInt16
    let identification: UInt16
    let flagsAndFragmentOffset: UInt16
    let timeToLive: UInt8
    let `protocol`: UInt8
    let headerChecksum: UInt16
    let sourceAddress: (UInt8,UInt8,UInt8,UInt8)
    let destinationAddress: (UInt8,UInt8,UInt8,UInt8)
}

/// The ICMP request message header
internal struct ICMPHeader {
    
    // ICMP message type (ECHO_REQUEST)
    let type: UInt8
    let code: UInt8
    var checkSum: UInt16
    
    // the packet identifier, in network order
    let idenifier: UInt16
    
    // the packet sequence number,  in network order
    let sequenceNum: UInt16
    
    var payload: ICMPRequestPayload
    
    init(idenifier: UInt16, sequenceNum: UInt16) {
        self.type = ICMPType.EchoRequest.rawValue
        self.code = 0
        self.checkSum = 0
        self.idenifier = int16LittleToBig(idenifier)
        self.sequenceNum = int16LittleToBig(sequenceNum)
        self.payload = ICMPRequestPayload(timestamp: Date.currentTimestamp, identifier: self.idenifier)
    }
    
    /// Calculate and then set the checksum of the request header
    mutating func setChecksum() {
        self.checkSum = calcChecksum(header: &self)
    }
}

extension ICMPHeader {
    mutating func toData() -> Data {
        return Data(bytes: &self, count: sizeof(ICMPHeader.self))
    }
}

/// The payload in the ICMP message
struct ICMPRequestPayload: Hashable {
    let timestamp: TimeInterval
    let identifier: UInt16
}

extension ICMPRequestPayload {
    
    /// Convert ICMP request payload in the header to byte array
    mutating func toData() -> Data {
        return Data(bytes: &self, count: MemoryLayout<ICMPRequestPayload>.size)
    }
}

/// ICMP message type
internal enum ICMPType: UInt8 {
    
    /// ICMP Request to host
    case EchoRequest = 8
    
    /// ICMP Reply from host
    case EchoReply = 0
}

internal struct HTTPRequest {
    
}
