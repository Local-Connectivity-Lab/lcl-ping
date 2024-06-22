//
// This source file is part of the LCL open source project
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
import Collections
import NIO
import NIOCore
import NIOHTTP1

internal final class HTTPTracingHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = PingResponse
    typealias OutboundIn = HTTPPingClient.Request
    typealias OutboundOut = HTTPClientRequestPart

    private var state: State
    private let configuration: HTTPPingClient.Configuration
    private let handler: HTTPHandler
    private var timer: Scheduled<Void>?

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

    init(configuration: HTTPPingClient.Configuration, promise: EventLoopPromise<PingResponse>) {
        self.state = .inactive
        self.configuration = configuration
        self.handler = HTTPHandler(useServerTiming: self.configuration.useServerTiming, promise: promise)
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel already active")
        case .error:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)]: in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel active")
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            self.state = .inactive
            logger.debug("[\(#fileID)][\(#line)][\(#function)] Channel inactive")
        case .error:
            break
        case .inactive:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            self.handler.handleError(sequenceNum: request.sequenceNumber, error: ChannelError.ioOnClosedChannel)
            return
        }

        context.write(self.wrapOutboundOut(.head(request.requestHead)), promise: promise)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        self.handler.handleWrite(request: request)
        self.timer = context.eventLoop.scheduleTask(in: self.configuration.readTimeout) {
            self.timer = nil
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: \(request.sequenceNumber) timeout!")
            self.handler.handleTimeout(sequenceNumber: request.sequenceNumber)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        let httpResponse: HTTPClientResponsePart = self.unwrapInboundIn(data)
        if case .some(let timer) = self.timer {
            timer.cancel()
            self.handler.handleRead(response: httpResponse)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        self.handler.handleError(error: error)
    }
}
