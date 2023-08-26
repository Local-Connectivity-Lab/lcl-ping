//
//  ByteOrder.swift
//  
//
//  Created by JOHN ZZN on 8/25/23.
//

import Foundation

/// Converts a 16-bit integer from the little-endian to big-endian format.
internal func int16LittleToBig(_ arg: UInt16) -> UInt16 {
    return arg.bigEndian
}

/// Converts a 16-bit integer from the big-endian to little-endian format.
internal func int16BigToLittle(_ arg: UInt16) -> UInt16 {
    return arg.littleEndian
}
