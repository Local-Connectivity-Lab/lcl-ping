//
//  File.swift
//  
//
//  Created by Zhennan Zhou on 5/26/24.
//

import Foundation

public protocol PingHandler {
    associatedtype Request
    associatedtype Response

    func handleRead(response: Response)
    func handleWrite(request: Request)
    func handleTimeout(sequenceNumber: UInt16)
    func handleError(error: Error)
    func shouldCloseHandler(shouldForceClose: Bool)
}
