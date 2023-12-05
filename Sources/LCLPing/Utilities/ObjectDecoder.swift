//
// This source file is part of the LCLPing open source project
//
// Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
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
func decodeByteBuffer<Out>(of: Out.Type, data: inout ByteBuffer) throws -> Out {
    let readLength = sizeof(Out.self)
    guard let buffer = data.readBytes(length: readLength) else {
        throw RuntimeError.insufficientBytes("Not enough bytes in the reponse message. Need \(readLength) bytes. But received \(data.readableBytes)")
    }
    
    let ret = buffer.withUnsafeBytes { $0.load(as: Out.self) }
    return ret
}
