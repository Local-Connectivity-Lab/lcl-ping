//
//  Pingable.swift
//  
//
//  Created by JOHN ZZN on 8/22/23.
//

import Foundation

protocol Pingable {
    func start()
    
    // TODO: need to handle fallback of start(callback)
    
    func stop()
    
    var summary: PingSummary { get }
}
