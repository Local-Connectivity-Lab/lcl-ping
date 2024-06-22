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
import NIO
import NIOCore

internal final class ICMPDuplexer: ChannelDuplexHandler {
    typealias InboundIn = ICMPPingClient.ICMPHeader
    typealias InboundOut = PingResponse
    typealias OutboundIn = ICMPPingClient.Request
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

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
    private let configuration: ICMPPingClient.Configuration
    private let resolvedAddress: SocketAddress
    private var handler: ICMPHandler
    private var timer: [UInt16: Scheduled<Void>]

    init(configuration: ICMPPingClient.Configuration, promise: EventLoopPromise<[PingResponse]>) {
        self.state = .inactive
        self.configuration = configuration
        self.resolvedAddress = self.configuration.resolvedAddress
        self.timer = [:]
        self.handler = ICMPHandler(totalCount: self.configuration.count, promise: promise)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            logger.error("[\(#fileID)][\(#line)][\(#function)]:: Error: IO on closed channel")
            self.handler.handleError(error: ChannelError.ioOnClosedChannel)
            return
        }

        var icmpRequest = ICMPPingClient.ICMPHeader(idenifier: request.identifier, sequenceNum: request.sequenceNum)
        icmpRequest.setChecksum()

        let buffer = context.channel.allocator.buffer(bytes: icmpRequest.data)
        let evelope = AddressedEnvelope(remoteAddress: resolvedAddress, data: buffer)

        context.writeAndFlush(self.wrapOutboundOut(evelope), promise: promise)
        self.handler.handleWrite(request: icmpRequest)

        let scheduledTimer = context.eventLoop.scheduleTask(in: self.configuration.timeout) {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: timer for \(request.sequenceNum) is invoked => time out!")
            self.timer.removeValue(forKey: request.sequenceNum)
            self.handler.handleTimeout(sequenceNumber: Int(request.sequenceNum))
        }

        timer[request.sequenceNum] = scheduledTimer
        logger.debug("[\(#fileID)][\(#line)][\(#function)]: schedule timer [\(configuration.timeout)s] for # \(request.sequenceNum)")
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        let icmpResponse = self.unwrapInboundIn(data)
        let sequenceNum = icmpResponse.sequenceNum
        self.timer[sequenceNum]?.cancel()
        self.timer.removeValue(forKey: sequenceNum)
        self.handler.handleRead(response: icmpResponse)
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel already active")
        case .error:
            assertionFailure("[\(#function)]: in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            context.fireChannelInactive()
            self.state = .inactive
            self.timer.forEach { (_, timer) in
                timer.cancel()
            }
            self.timer.removeAll()
            self.handler.shouldCloseHandler(shouldForceClose: true)
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel inactive")
        case .error:
            break
        case .inactive:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }
    func channelUnregistered(context: ChannelHandlerContext) {
        self.handler.reset()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDuplexer]: already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        self.handler.handleError(error: error)
    }

}

internal final class IPDecoder: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer

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

    private var state: State = .inactive

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[IPDecoder][\(#function)]: Channel already active")
        case .error:
            assertionFailure("[IPDecoder][\(#function)] in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[IPDecoder][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[IPDecoder][\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            assertionFailure("[IPDecoder][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[IPDecoder][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        let addressedBuffer = self.unwrapInboundIn(data)
        var buffer = addressedBuffer.data
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let ipv4Header: ICMPPingClient.IPv4Header
        do {
            ipv4Header = try decodeByteBuffer(of: ICMPPingClient.IPv4Header.self, data: &buffer)
        } catch {
            context.fireErrorCaught(error)
            return
        }
        let version = ipv4Header.versionAndHeaderLength & 0xF0
        if version != 0x40 {
            logger.debug("received version: \(version)")
            context.fireErrorCaught(PingError.invalidIPVersion)
            return
        }

        let proto = ipv4Header.protocol
        if proto != IPPROTO_ICMP {
            logger.debug("received protocol: \(proto)")
            context.fireErrorCaught(PingError.invalidIPProtocol)
            return
        }
        let headerLength = (Int(ipv4Header.versionAndHeaderLength) & 0x0F) * sizeof(UInt32.self)
        buffer.moveReaderIndex(to: headerLength)
        #endif // Linux
        context.fireChannelRead(self.wrapInboundOut(buffer.slice()))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[IPDecoder]: already in error state. ignore error \(error)")
            return
        }

        self.state = .error
        context.fireErrorCaught(error)
    }
}

internal final class ICMPDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ICMPPingClient.ICMPHeader

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

    private var state: State = .inactive

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel already active")
        case .error:
            assertionFailure("[\(#function)] in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)] received inactive signal when channel is already in inactive state.")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        var buffer = self.unwrapInboundIn(data)
        let icmpResponseHeader: ICMPPingClient.ICMPHeader
        do {
            icmpResponseHeader = try decodeByteBuffer(of: ICMPPingClient.ICMPHeader.self, data: &buffer)
        } catch {
            context.fireErrorCaught(error)
            return
        }
        context.fireChannelRead(self.wrapInboundOut(icmpResponseHeader))
        logger.debug("[\(#fileID)][\(#line)][\(#function)]: finish decoding icmp header: \(icmpResponseHeader)")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: already in error state. ignore error \(error)")
            return
        }

        self.state = .error
        context.fireErrorCaught(error)
    }
}
