//
//  Response.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation

internal enum PingResponse {
    case ok(UInt16, Double, TimeInterval)
    case duplicated(UInt16)
    case timeout(UInt16)
    case error
}
