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
import NIO
import NIOCore



// TODO: support version without swift concurrency
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
    private var seqToRequest: Dictionary<UInt16, ICMPHeader>
    
    /// sequence number to an optional ICMP response
    private var seqToResponse: Dictionary<UInt16, ICMPHeader?>
    private var responseSeqNumSet: Set<UInt16>
    
    private var timerScheduler: TimerScheduler<UInt16>
    
    init(configuration: LCLPing.PingConfiguration, resolvedAddress: SocketAddress) {
        self.configuration = configuration
        self.seqToRequest = [:]
        self.seqToResponse = [:]
        self.responseSeqNumSet = Set()
        self.timerScheduler = TimerScheduler()
        self.state = .inactive
        self.resolvedAddress = resolvedAddress
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (identifier, sequenceNum) = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            logger.error("[ICMPDuplexer][\(#function)]: Error: IO on closed channel")
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum, ChannelError.ioOnClosedChannel)))
            return
        }
        
        var icmpRequest = ICMPHeader(idenifier: identifier, sequenceNum: sequenceNum)
        icmpRequest.setChecksum()
        
        let buffer = context.channel.allocator.buffer(bytes: icmpRequest.toData())
        let evelope = AddressedEnvelope(remoteAddress: resolvedAddress, data: buffer)
        
        context.writeAndFlush(self.wrapOutboundOut(evelope), promise: promise)
        self.seqToRequest[sequenceNum] = icmpRequest
        
        self.timerScheduler.schedule(delay: self.configuration.timeout, key: sequenceNum) { [weak self, context] in
            if let self = self, !self.seqToResponse.keys.contains(sequenceNum) {
                logger.debug("[ICMPDuplexer][\(#function)]: packet #\(sequenceNum) timed out")
                self.responseSeqNumSet.insert(sequenceNum)
                context.eventLoop.execute {
                    context.fireChannelRead(self.wrapInboundOut(.timeout(sequenceNum)))
                    self.closeWhenComplete(context: context)
                }
            }
        }
        logger.debug("[ICMPDuplexer][\(#function)]: schedule timer for # \(sequenceNum) for \(self.configuration.timeout) second")
    }
    
    private func closeWhenComplete(context: ChannelHandlerContext) {
        if self.seqToRequest.count == self.configuration.count && self.responseSeqNumSet.count == self.configuration.count {
            logger.debug("[ICMPDuplexer]: Ping finished. Closing all channels")
            context.close(mode: .all, promise: nil)
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[ICMPDuplexer][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }
        
        let icmpResponse = self.unwrapInboundIn(data)
        
        let type = icmpResponse.type
        let code = icmpResponse.code
        let sequenceNum = icmpResponse.sequenceNum
        let identifier = icmpResponse.idenifier
        logger.debug("[ICMPDuplexer][\(#function)]: received icmp response with type: \(type), code: \(code), sequence number: \(sequenceNum), identifier: \(identifier)")
        
        if self.responseSeqNumSet.contains(sequenceNum) {
            let pingResponse: PingResponse = self.seqToResponse[sequenceNum] == nil ? .timeout(sequenceNum) : .duplicated(sequenceNum)
            logger.debug("[ICMPDuplexer][\(#function)]: response for #\(sequenceNum) is \(self.seqToResponse[sequenceNum] == nil ? "timeout" : "duplicate")")
            context.fireChannelRead(self.wrapInboundOut(pingResponse))
            closeWhenComplete(context: context)
            return
        }
        
        guard let icmpRequest = self.seqToRequest[sequenceNum] else {
            logger.error("[ICMPDuplexer][\(#function)]: Unable to find matching request with sequence number \(sequenceNum)")
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum, PingError.invalidICMPResponse)))
            closeWhenComplete(context: context)
            return
        }
        
        self.timerScheduler.remove(key: sequenceNum)
        self.seqToResponse[sequenceNum] = icmpResponse
        self.responseSeqNumSet.insert(sequenceNum)

        switch (type, code) {
        case (ICMPType.EchoReply.rawValue, 0):
            break
        case (3,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum, PingError.icmpDestinationNetworkUnreachable)))
            self.closeWhenComplete(context: context)
            return
        case (3,1):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpDestinationHostUnreachable)))
            self.closeWhenComplete(context: context)
            return
        case (3,2):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpDestinationProtocoltUnreachable)))
            self.closeWhenComplete(context: context)
            return
        case (3,3):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpDestinationPortUnreachable)))
            self.closeWhenComplete(context: context)
            return
        case (3,4):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpFragmentationRequired)))
            self.closeWhenComplete(context: context)
            return
        case (3,5):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpSourceRouteFailed)))
            self.closeWhenComplete(context: context)
            return
        case (3,6):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpUnknownDestinationNetwork)))
            self.closeWhenComplete(context: context)
            return
        case (3,7):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpUnknownDestinationHost)))
            self.closeWhenComplete(context: context)
            return
        case (3,8):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpSourceHostIsolated)))
            self.closeWhenComplete(context: context)
            return
        case (3,9):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpNetworkAdministrativelyProhibited)))
            self.closeWhenComplete(context: context)
            return
        case (3,10):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpHostAdministrativelyProhibited)))
            self.closeWhenComplete(context: context)
            return
        case (3,11):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpNetworkUnreachableForToS)))
            self.closeWhenComplete(context: context)
            return
        case (3,12):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpHostUnreachableForToS)))
            self.closeWhenComplete(context: context)
            return
        case (3,13):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpCommunicationAdministrativelyProhibited)))
            self.closeWhenComplete(context: context)
            return
        case (3,14):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpHostPrecedenceViolation)))
            self.closeWhenComplete(context: context)
            return
        case (3,15):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpPrecedenceCutoffInEffect)))
            self.closeWhenComplete(context: context)
            return
        case (5,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRedirectDatagramForNetwork)))
            self.closeWhenComplete(context: context)
            return
        case (5,1):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRedirectDatagramForHost)))
            self.closeWhenComplete(context: context)
            return
        case (5,2):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRedirectDatagramForTosAndNetwork)))
            self.closeWhenComplete(context: context)
            return
        case (5,3):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRedirectDatagramForTosAndHost)))
            self.closeWhenComplete(context: context)
            return
        case (9,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRouterAdvertisement)))
            self.closeWhenComplete(context: context)
            return
        case (10,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpRouterDiscoverySelectionSolicitation)))
            self.closeWhenComplete(context: context)
            return
        case (11,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpTTLExpiredInTransit)))
            self.closeWhenComplete(context: context)
            return
        case (11,1):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpFragmentReassemblyTimeExceeded)))
            self.closeWhenComplete(context: context)
            return
        case (12,0):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpPointerIndicatesError)))
            self.closeWhenComplete(context: context)
            return
        case (12,1):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpMissingARequiredOption)))
            self.closeWhenComplete(context: context)
            return
        case (12,2):
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.icmpBadLength)))
            self.closeWhenComplete(context: context)
            return
        default:
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum,PingError.unknownError("Received unknown ICMP type (\(type)) and ICMP code (\(code))"))))
            self.closeWhenComplete(context: context)
            return
        }
        
        if icmpResponse.checkSum != icmpResponse.calcChecksum() {
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum, PingError.invalidICMPChecksum)))
            closeWhenComplete(context: context)
            return
        }
        
        #if canImport(Darwin)
        if identifier != icmpRequest.idenifier {
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNum, PingError.invalidICMPIdentifier)))
            closeWhenComplete(context: context)
            return
        }
        #endif
        
        let currentTimestamp = Date.currentTimestamp
        let latency = (currentTimestamp - icmpRequest.payload.timestamp) * 1000

        let pingResponse: PingResponse = .ok(sequenceNum, latency, currentTimestamp)
        context.fireChannelRead(self.wrapInboundOut(pingResponse))

        closeWhenComplete(context: context)
    }
    
    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[ICMPDuplexer][\(#function)]: Channel already active")
            break
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
            self.seqToRequest.removeAll()
            self.seqToResponse.removeAll()
            self.timerScheduler.reset()
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
        let pingResponse: PingResponse = .error(nil, error)
        context.fireChannelRead(self.wrapInboundOut(pingResponse))
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
            break
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
            break
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
