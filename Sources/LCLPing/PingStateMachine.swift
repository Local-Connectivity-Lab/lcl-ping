//
//  PingStateMachine.swift
//  
//
//  Created by JOHN ZZN on 9/1/23.
//

import Foundation


/// Possible states of an instance of LCLPing
public enum PingState {
    
    /// LCLPing is ready to initiate ping requests
    case ready
    
    /// LCLPing is in progress of sending and receiving ping requests and responses
    case running
    
    /// LCLPing failed
    case failed
    
    /// LCLPing is stopped by explicit `stop()` and ping summary is ready
    case stopped
    
    /// LCLPing finishes and ping summary is ready
    case finished
}
