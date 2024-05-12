//
// This source file is part of the LCL open source project
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

extension String {
    
    var toBytes: [UInt8] {
        guard self.count % 2 == 0 else {
            return []
        }

        var bytes: [UInt8] = []

        var index = self.startIndex
        while index < self.endIndex {
            let byteString = self[index ..< self.index(after: self.index(after: index))]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            } else {
                return []
            }
            index = self.index(after: self.index(after: index))
        }

        return bytes
    }
}
