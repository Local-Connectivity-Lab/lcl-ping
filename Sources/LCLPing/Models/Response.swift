//
//  Response.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation

internal enum PingResponse: Equatable {
    static func == (lhs: PingResponse, rhs: PingResponse) -> Bool {
        switch (lhs, rhs) {
        case (PingResponse.ok(let lSequenceNum, let lLatency, let lTime), PingResponse.ok(let rSequenceNum, let rLatency, let rTime)):
            return lSequenceNum == rSequenceNum && lLatency == rLatency && lTime == rTime
        case (PingResponse.duplicated(let lSequenceNum), PingResponse.duplicated(let rSequenceNum)):
            return lSequenceNum == rSequenceNum
        case (PingResponse.timeout(let lSequenceNun), PingResponse.timeout(let rSequenceNum)):
            return lSequenceNun == rSequenceNum
        case (PingResponse.error(.some(let lError)), PingResponse.error(.some(let rError))):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
    
    case ok(UInt16, Double, TimeInterval)
    case duplicated(UInt16)
    case timeout(UInt16)
    case error(Error?)
}
