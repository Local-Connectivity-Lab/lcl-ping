//
//  Common.swift
//  
//
//  Created by JOHN ZZN on 11/25/23.
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
