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
    typealias InboundIn = ICMPHeader
    typealias InboundOut = PingResponse
    typealias OutboundIn = ICMPOutboundIn
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

    private var configuration: LCLPing.PingConfiguration
    private let resolvedAddress: SocketAddress

    /// sequence number to ICMP request
    private var seqToRequest: [UInt16: ICMPHeader]

    /// sequence number to an optional ICMP response
    private var seqToResponse: [UInt16: ICMPHeader?]
    private var responseSeqNumSet: Set<UInt16>
    private var handler: ICMPHandler
    private var timer: [UInt16: Scheduled<Void>]

    init(configuration: LCLPing.PingConfiguration, resolvedAddress: SocketAddress, handler: ICMPHandler) {
        self.configuration = configuration
        self.seqToRequest = [:]
        self.seqToResponse = [:]
        self.responseSeqNumSet = Set()
        self.state = .inactive
        self.resolvedAddress = resolvedAddress
        self.timer = [:]
        self.handler = handler
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (identifier, sequenceNum) = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            logger.error("[ICMPDuplexer][\(#function)]: Error: IO on closed channel")
            self.handler.handleError(sequenceNum: sequenceNum, error: ChannelError.ioOnClosedChannel)
            return
        }

        var icmpRequest = ICMPHeader(idenifier: identifier, sequenceNum: sequenceNum)
        icmpRequest.setChecksum()

        let buffer = context.channel.allocator.buffer(bytes: icmpRequest.toData())
        let evelope = AddressedEnvelope(remoteAddress: resolvedAddress, data: buffer)

        context.writeAndFlush(self.wrapOutboundOut(evelope), promise: promise)
        self.handler.handleWrite(request: icmpRequest)
        
        let scheduledTimer = context.eventLoop.scheduleTask(deadline: .now() + .seconds(1)) {
            self.timer.removeValue(forKey: sequenceNum)
            self.handler.handleTimeout(sequenceNum: sequenceNum)
        }

        timer[sequenceNum] = scheduledTimer
        logger.debug("[ICMPDuplexer][\(#function)]: schedule timer for # \(sequenceNum) for \(self.configuration.timeout) second")
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDuplexer][\(#function)]: drop data: \(data) because channel is not in operational state")
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
            logger.debug("[ICMPDuplexer][\(#function)]: Channel already active")
        case .error:
            logger.error("[ICMPDuplexer][\(#function)]: in an incorrect state: \(state)")
            assertionFailure("[\(#function)]: in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[ICMPDuplexer][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            context.fireChannelInactive()
            self.state = .inactive
            self.handler.reset()
            self.timer.forEach { (_, timer) in
                timer.cancel()
            }
            self.timer.removeAll()
            logger.debug("[ICMPDuplexer][\(#function)]: Channel inactive")
        case .error:
            break
        case .inactive:
            logger.error("[ICMPDuplexer][\(#function)] received inactive signal when channel is already in inactive state.")
            assertionFailure("[ICMPDuplexer][\(#function)] received inactive signal when channel is already in inactive state.")
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDuplexer]: already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        self.handler.handleError(error: error)
        context.close(mode: .all, promise: nil)
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
            logger.error("[IPDecoder][\(#function)] in an incorrect state: \(state)")
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
            logger.debug("[IPDecoder][\(#function)]: received inactive signal when channel is already in inactive state.")
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
        let ipv4Header: IPv4Header
        do {
            ipv4Header = try decodeByteBuffer(of: IPv4Header.self, data: &buffer)
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
    typealias InboundOut = ICMPHeader

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
            logger.debug("[ICMPDecoder][\(#function)]: Channel already active")
        case .error:
            logger.error("[ICMPDecoder][\(#function)] in an incorrect state: \(state)")
            assertionFailure("[\(#function)] in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[ICMPDecoder][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[ICMPDecoder][\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            logger.error("[ICMPDecoder][\(#function)] received inactive signal when channel is already in inactive state.")
            assertionFailure("[ICMPDecoder][\(#function)] received inactive signal when channel is already in inactive state.")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDecoder]: drop data: \(data) because channel is not in operational state")
            return
        }

        var buffer = self.unwrapInboundIn(data)
        let icmpResponseHeader: ICMPHeader
        do {
            icmpResponseHeader = try decodeByteBuffer(of: ICMPHeader.self, data: &buffer)
        } catch {
            context.fireErrorCaught(error)
            return
        }
        context.fireChannelRead(self.wrapInboundOut(icmpResponseHeader))
        logger.debug("[ICMPDecoder][\(#function)] finish decoding icmp header: \(icmpResponseHeader)")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDecoder]: already in error state. ignore error \(error)")
            return
        }

        self.state = .error
        context.fireErrorCaught(error)
    }
}
