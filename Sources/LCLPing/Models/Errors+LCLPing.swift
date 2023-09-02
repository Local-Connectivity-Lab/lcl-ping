//
//  Errors+LCLPing.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation

public enum PingError: Error {
    
    case operationNotSupported
    
    case invalidConfiguration(String)
    case hostConnectionError(Error)
    case sendPingFailed(Error)
    
    case failedToInitialzeChannel
}
