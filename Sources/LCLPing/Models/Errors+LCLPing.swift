//
//  Errors+LCLPing.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation

public enum PingError: Error {
    
    case operationNotSupported(String)
    
    case invalidConfiguration(String)
    case hostConnectionError(Error)
    case sendPingFailed(Error)
    
    case failedToInitialzeChannel
    case invalidICMPResponse
    case invalidIPv4URL
    case invalidIPv6URL
    
    case invalidHTTPSession
    case httpRequestFailed(Int)
    
    case httpNoMatchingRequest
    case httpNoResponse
    case httpRedirect
    case httpClientError
    case httpServerError
    case httpUnknownStatus(UInt)
}
