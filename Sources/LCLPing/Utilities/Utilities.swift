//
//  Utilities.swift
//  
//
//  Created by JOHN ZZN on 8/25/23.
//

import Foundation

internal func calcChecksum(header: inout ICMPHeader) -> UInt16 {
    let typecode = Data([header.type, header.code]).withUnsafeBytes { $0.load(as: UInt16.self) }
    var sum = UInt64(typecode) + UInt64(header.idenifier) + UInt64(header.sequenceNum)
    let payload = header.payload.toData()
    
    for idx in stride(from: 0, to: payload.count, by: 2) {
        sum += Data([payload[idx], payload[idx + 1]]).withUnsafeBytes { UInt64($0.load(as: UInt16.self)) }
    }
    
    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }
    
    return ~UInt16(sum)
}

internal func sizeof<T>(_ type: T.Type) -> Int {
    return MemoryLayout<T>.size
}

