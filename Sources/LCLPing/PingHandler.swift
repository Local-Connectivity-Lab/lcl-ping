//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

/**
 The pingHandler protocol allows the implementation to handle various events from the eventloop.
 
 PingHandler should be part of the ChannelHandler to help handle event or data when they occur.
 */
protocol PingHandler {
    associatedtype Request
    associatedtype Response

    /// Handle reading the inbound response.
    func handleRead(response: Response)

    /// Handle writing outbound request.
    func handleWrite(request: Request)

    /// Handle the timeout event associated with the certain request identified by its sequence number.
    func handleTimeout(sequenceNumber: UInt16)

    /// Handle error.
    func handleError(error: Error)

    /// Close the handler, and maybe the associated channel, if certain condition is met.
    /// if `shouldForceClose` is true, then the handler is closed unconditionally.
    func shouldCloseHandler(shouldForceClose: Bool)
}
