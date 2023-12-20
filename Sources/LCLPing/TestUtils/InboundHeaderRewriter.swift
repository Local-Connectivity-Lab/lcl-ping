//
// This source file is part of the LCLPing open source project
//
// Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOCore
import NIO

class InboundHeaderRewriter<In: Rewritable>: ChannelInboundHandler {
    typealias InboundIn = In
    typealias InboundOut = In

    private enum State {
        case operational
        case error
        case inactive
        
        var isOperational: Bool {
            switch self {
            case .operational:
                return true
            case .error, .inactive:
                return false
            }
        }
    }

    private var state: State
    private var rewriteHeaders: [PartialKeyPath<In>:AnyObject]?

    init(rewriteHeaders: [PartialKeyPath<In>:AnyObject]?) {
        self.rewriteHeaders = rewriteHeaders
        self.state = .inactive
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            break
        case .error:
            logger.error("[\(#function)]: in an incorrect state: \(self.state)")
            assertionFailure("[\(#function)]: in an incorrect state: \(self.state)")
        case .inactive:
            logger.debug("[\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            logger.error("[\(#function)]: received inactive signal when channel is already in inactive state.")
            assertionFailure("[\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        guard let rewriteHeaders = self.rewriteHeaders else {
            context.fireChannelRead(data)
            return
        }

        let unwrapped = self.unwrapInboundIn(data)
        let newValue = unwrapped.rewrite(newValues: rewriteHeaders)
        context.fireChannelRead(self.wrapInboundOut(newValue))
    }

}
