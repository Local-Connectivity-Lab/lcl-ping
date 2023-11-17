//
//  ICMPChannelHandlers.swift
//  
//
//  Created by JOHN ZZN on 8/26/23.
//

import Foundation
import NIO
import NIOCore



// TODO: support version without swift concurrency
internal final class ICMPDuplexer: ChannelDuplexHandler {
    typealias InboundIn = ICMPHeader
    typealias InboundOut = PingResponse
    typealias OutboundIn = ICMPOutboundIn
    typealias OutboundOut = ByteBuffer
    
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
    
    /// sequence number to ICMP request
    private var seqToRequest: Dictionary<UInt16, ICMPHeader>
    
    /// sequence number to an optional ICMP response
    private var seqToResponse: Dictionary<UInt16, ICMPHeader?>
    
    private var timerScheduler: TimerScheduler<UInt16>
    
    init(configuration: LCLPing.PingConfiguration) {
        self.configuration = configuration
        self.seqToRequest = [:]
        self.seqToResponse = [:]
        self.timerScheduler = TimerScheduler()
        self.state = .inactive
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.isOperational else {
            logger.error("[\(#function)]: Error: IO on closed channel")
            context.fireChannelRead(self.wrapInboundOut(.error(ChannelError.ioOnClosedChannel)))
            return
        }
        
        let (identifier, sequenceNum) = self.unwrapOutboundIn(data)
        var icmpRequest = ICMPHeader(idenifier: identifier, sequenceNum: sequenceNum)
        icmpRequest.setChecksum()
        
        let buffer = context.channel.allocator.buffer(bytes: icmpRequest.toData())
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: promise)
        self.seqToRequest[sequenceNum] = icmpRequest
        
        self.timerScheduler.schedule(delay: self.configuration.timeout, key: sequenceNum) { [weak self, context] in
            if let self = self, !self.seqToResponse.keys.contains(sequenceNum) {
                logger.debug("[\(#function)]: packet #\(sequenceNum) timed out")
                self.seqToResponse[sequenceNum] = nil
                context.fireChannelRead(self.wrapInboundOut(.timeout(sequenceNum)))
            }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }
        
        let icmpResponse = self.unwrapInboundIn(data)
        
        let type = icmpResponse.type
        let code = icmpResponse.code
        switch (type, code) {
        case (ICMPType.EchoReply.rawValue, 0):
            break
        case (3,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpDestinationNetworkUnreachable)))
            return
        case (3,1):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpDestinationHostUnreachable)))
            return
        case (3,2):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpDestinationProtocoltUnreachable)))
            return
        case (3,3):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpDestinationPortUnreachable)))
            return
        case (3,4):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpFragmentationRequired)))
            return
        case (3,5):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpSourceRouteFailed)))
            return
        case (3,6):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpUnknownDestinationNetwork)))
            return
        case (3,7):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpUnknownDestinationHost)))
            return
        case (3,8):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpSourceHostIsolated)))
            return
        case (3,9):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpNetworkAdministrativelyProhibited)))
            return
        case (3,10):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpHostAdministrativelyProhibited)))
            return
        case (3,11):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpNetworkUnreachableForToS)))
            return
        case (3,12):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpHostUnreachableForToS)))
            return
        case (3,13):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpCommunicationAdministrativelyProhibited)))
            return
        case (3,14):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpHostPrecedenceViolation)))
            return
        case (3,15):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpPrecedenceCutoffInEffect)))
            return
        case (5,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRedirectDatagramForNetwork)))
            return
        case (5,1):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRedirectDatagramForHost)))
            return
        case (5,2):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRedirectDatagramForTosAndNetwork)))
            return
        case (5,3):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRedirectDatagramForTosAndHost)))
            return
        case (9,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRouterAdvertisement)))
            return
        case (10,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpRouterDiscoverySelectionSolicitation)))
            return
        case (11,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpTTLExpiredInTransit)))
            return
        case (11,1):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpFragmentReassemblyTimeExceeded)))
            return
        case (12,0):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpPointerIndicatesError)))
            return
        case (12,1):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpMissingARequiredOption)))
            return
        case (12,2):
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.icmpBadLength)))
            return
        default:
            context.fireChannelRead(self.wrapInboundOut(.error(PingError.unknownError("Received unknown ICMP type (\(type) and ICMP code (\(code)"))))
            return
        }
        
        let sequenceNum = icmpResponse.sequenceNum
        let identifier = icmpResponse.idenifier
        
        self.timerScheduler.remove(key: sequenceNum)
        
        if self.seqToResponse.keys.contains(sequenceNum) {
            let pingResponse: PingResponse = self.seqToResponse[sequenceNum] == nil ? .timeout(sequenceNum) : .duplicated(sequenceNum)
            context.fireChannelRead(self.wrapInboundOut(pingResponse))
            return
        }
        
        guard let icmpRequest = self.seqToRequest[sequenceNum] else {
            logger.error("[\(#function)]: Unable to find matching request with sequence number \(sequenceNum)")
            fatalError("Unable to find matching request with sequence number \(sequenceNum)")
        }
        
        precondition(icmpResponse.checkSum == icmpResponse.calcChecksum())
        precondition(identifier == icmpRequest.idenifier)
        
        self.seqToResponse[sequenceNum] = icmpResponse
        let currentTimestamp = Date.currentTimestamp
        let latency = (currentTimestamp - icmpRequest.payload.timestamp) * 1000

        let pingResponse: PingResponse = .ok(sequenceNum, latency, currentTimestamp)
        context.fireChannelRead(self.wrapInboundOut(pingResponse))

        if self.seqToRequest.count == self.configuration.count && self.seqToResponse.count == self.configuration.count {
            logger.debug("Ping finished. Closing all channels")
            context.close(mode: .all, promise: nil)
        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#function)]: Channel already active")
            break
        case .error:
            logger.error("[\(#function)]: in an incorrect state: \(state)")
            assertionFailure("[\(#function)]: in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[\(#function)]: Channel active")
            self.state = .operational
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            self.state = .inactive
            self.seqToRequest.removeAll()
            self.seqToResponse.removeAll()
            self.timerScheduler.reset()
            logger.debug("[\(#function)]: Channel inactive")
        case .error:
            break
        case .inactive:
            logger.error("[\(#function)] received inactive signal when channel is already in inactive state.")
            assertionFailure("[\(#function)] received inactive signal when channel is already in inactive state.")
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        let pingResponse: PingResponse = .error(error)
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
            logger.debug("[\(#function)]: Channel already active")
            break
        case .error:
            logger.error("[\(#function)] in an incorrect state: \(state)")
            assertionFailure("[\(#function)] in an incorrect state: \(state)")
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
            logger.debug("[\(#function)]: received inactive signal when channel is already in inactive state.")
            assertionFailure("[\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }
        
        let addressedBuffer = self.unwrapInboundIn(data)
        var buffer = addressedBuffer.data
        let ipv4Header: IPv4Header
        do {
            ipv4Header = try decodeByteBuffer(of: IPv4Header.self, data: &buffer)
        } catch {
            context.fireErrorCaught(error)
            return
        }
        let version = ipv4Header.versionAndHeaderLength & 0xF0
        precondition(version == 0x40, "Not valid IP Header. Need 0x40. But received \(version)")
        
        let proto = ipv4Header.protocol
        precondition(proto == IPPROTO_ICMP, "Not ICMP Message. Need \(IPPROTO_ICMP). But received \(proto)")
        
        let headerLength = (Int(ipv4Header.versionAndHeaderLength) & 0x0F) * sizeof(UInt32.self)
        buffer.moveReaderIndex(to: headerLength)
        context.fireChannelRead(self.wrapInboundOut(buffer.slice()))
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("already in error state. ignore error \(error)")
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
            logger.debug("[\(#function)]: Channel already active")
            break
        case .error:
            logger.error("[\(#function)] in an incorrect state: \(state)")
            assertionFailure("[\(#function)] in an incorrect state: \(state)")
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
            logger.error("[\(#function)] received inactive signal when channel is already in inactive state.")
            assertionFailure("[\(#function)] received inactive signal when channel is already in inactive state.")
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("drop data: \(data) because channel is not in operational state")
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
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("already in error state. ignore error \(error)")
            return
        }
        
        self.state = .error
        context.fireErrorCaught(error)
    }
}
