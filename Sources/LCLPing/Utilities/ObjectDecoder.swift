//
//  ObjectDecoder.swift
//  
//
//  Created by JOHN ZZN on 8/27/23.
//

import Foundation
import NIOCore


/// Decode the given byte buffer into object of user-defined type
///
/// Input `data` will be passed in as reference
///
/// - Parameters:
///     - data: input byte buffer that will be decoded
/// - Returns: decoded object of type `Out`
func decodeByteBuffer<Out>(of: Out.Type, data: inout ByteBuffer) -> Out {
    let readLength = sizeof(Out.self)
    guard let buffer = data.readBytes(length: readLength) else {
        fatalError("Not enough bytes in the reponse message. Need \(readLength) bytes. But received \(data.readableBytes)")
    }
    
    let ret = buffer.withUnsafeBytes { $0.load(as: Out.self) }
    return ret
}
