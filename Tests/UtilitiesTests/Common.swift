//
//  Common.swift
//  
//
//  Created by JOHN ZZN on 11/5/23.
//

import Foundation
import NIOCore

func createByteBuffer<T>( _ original:  inout T) -> ByteBuffer {
    return withUnsafeBytes(of: &original) {
        return ByteBuffer(bytes: $0)
    }
}
