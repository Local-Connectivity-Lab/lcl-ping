//
//  Pingable.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

protocol Pingable {
    mutating func start(with configuration: LCLPing.Configuration) async throws
    
    // TODO: need to handle fallback of start(callback)
    
    mutating func stop()
    
    var summary: PingSummary? { get }
    
    var pingStatus: PingState { get }
}
