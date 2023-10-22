//
//  ICMPChannelHandlers.swift
//  
//
//  Created by JOHN ZZN on 8/26/23.
//

import Foundation
import NIO
import NIOCore


// TODO: add logging
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
    
    private var configuration: LCLPing.Configuration
    
    /// sequence number to ICMP request
    private var seqToRequest: Dictionary<UInt16, ICMPHeader>
    
    /// sequence number to an optional ICMP response
    private var seqToResponse: Dictionary<UInt16, ICMPHeader?>
    
    private var timerScheduler: TimerScheduler
    
    init(configuration: LCLPing.Configuration) {
        self.configuration = configuration
        self.seqToRequest = [:]
        self.seqToResponse = [:]
        self.timerScheduler = TimerScheduler()
        self.state = .inactive
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.isOperational else {
            let pingResponse: PingResponse = .error(ChannelError.ioOnClosedChannel)
            context.fireChannelRead(self.wrapInboundOut(pingResponse))
            return
        }
        
        let (identifier, sequenceNum) = self.unwrapOutboundIn(data)
        var icmpRequest = ICMPHeader(idenifier: identifier, sequenceNum: sequenceNum)
        icmpRequest.setChecksum()
        
        let buffer = context.channel.allocator.buffer(bytes: icmpRequest.toData())
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: promise)
        self.seqToRequest[sequenceNum] = icmpRequest
        
        self.timerScheduler.schedule(delay: self.configuration.timeout, key: sequenceNum) { [weak self] in
            if let self = self, !self.seqToResponse.keys.contains(sequenceNum) {
                self.seqToResponse[sequenceNum] = nil
                let pingResponse: PingResponse = .timeout(sequenceNum)
                context.fireChannelRead(self.wrapInboundOut(pingResponse))
            }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            print("drop data: \(data) because channel is not in operational state")
            return
        }
        
        let icmpResponse = self.unwrapInboundIn(data)
        
        // TODO: need to handle more response type
        precondition(icmpResponse.type == ICMPType.EchoReply.rawValue, "Not ICMP Reply. Expected \(ICMPType.EchoReply.rawValue). But received \(icmpResponse.type)")
        precondition(icmpResponse.code == 0)
        
        let sequenceNum = icmpResponse.sequenceNum
        let identifier = icmpResponse.idenifier
        
        self.timerScheduler.cancel(key: sequenceNum)
        
        if self.seqToResponse.keys.contains(sequenceNum) {
            let pingResponse: PingResponse = self.seqToResponse[sequenceNum] == nil ? .timeout(sequenceNum) : .duplicated(sequenceNum)
            context.fireChannelRead(self.wrapInboundOut(pingResponse))
            return
        }
        
        guard let icmpRequest = self.seqToRequest[sequenceNum] else {
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
            context.close(mode: .all, promise: nil)
        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            print("[\(self)]: Channel already active")
            break
        case .error:
            assertionFailure("[\(self)] in an incorrect state: \(state)")
        case .inactive:
            print("[\(self)]: Channel active")
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
            print("[\(self)]: Channel inactive")
        case .error:
            break
        case .inactive:
            assertionFailure("[\(self)] received inactive signal when channel is already in inactive state.")
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            print("already in error state. ignore error \(error)")
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
            print("[\(self)]: Channel already active")
            break
        case .error:
            assertionFailure("[\(self)] in an incorrect state: \(state)")
        case .inactive:
            print("[\(self)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            print("[\(self)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            assertionFailure("[\(self)]: received inactive signal when channel is already in inactive state.")
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            print("drop data: \(data) because channel is not in operational state")
            return
        }
        
        let addressedBuffer = self.unwrapInboundIn(data)
        var buffer = addressedBuffer.data
        let ipv4Header: IPv4Header = decodeByteBuffer(data: &buffer)
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
            print("already in error state. ignore error \(error)")
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
            print("[\(self)]: Channel already active")
            break
        case .error:
            assertionFailure("[\(self)] in an incorrect state: \(state)")
        case .inactive:
            print("[\(self)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            print("[\(self)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            assertionFailure("[\(self)] received inactive signal when channel is already in inactive state.")
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            print("drop data: \(data) because channel is not in operational state")
            return
        }
        
        var buffer = self.unwrapInboundIn(data)
        let icmpResponseHeader: ICMPHeader = decodeByteBuffer(data: &buffer)
        context.fireChannelRead(self.wrapInboundOut(icmpResponseHeader))
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            print("already in error state. ignore error \(error)")
            return
        }
        
        self.state = .error
        context.fireErrorCaught(error)
    }
}
