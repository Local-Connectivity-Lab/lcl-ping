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
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
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
//        context.eventLoop.execute {
            let icmpResponse = self.unwrapInboundIn(data)
            
            // TODO: need to handle more response type
            precondition(icmpResponse.type == ICMPType.EchoReply.rawValue, "Not ICMP Reply. Expected \(ICMPType.EchoReply.rawValue). But received \(icmpResponse.type)")
            precondition(icmpResponse.code == 0)
            
            let sequenceNum = icmpResponse.sequenceNum
            let identifier = icmpResponse.idenifier
            
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
//        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // TODO: add logging
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        self.seqToRequest.removeAll()
        self.seqToResponse.removeAll()
        self.timerScheduler.reset()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let pingResponse: PingResponse = .error(error)
        context.fireChannelRead(self.wrapInboundOut(pingResponse))
    }
    
}

internal final class IPDecoder: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        context.eventLoop.execute {
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
//        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}

internal final class ICMPDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ICMPHeader
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        context.eventLoop.execute {
            var buffer = self.unwrapInboundIn(data)
            let icmpResponseHeader: ICMPHeader = decodeByteBuffer(data: &buffer)
            context.fireChannelRead(self.wrapInboundOut(icmpResponseHeader))
//        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}
