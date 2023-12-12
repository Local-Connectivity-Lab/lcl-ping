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

class TrafficControllerChannelHandler: ChannelDuplexHandler {

    class NetworkLinkConfiguration {

        public static let fullyDisconnected: NetworkLinkConfiguration = .init(inPacketLoss: 1.0, outPacketLoss: 1.0, inDelay: .zero, outDelay: .zero)
        public static let fullyConnected: NetworkLinkConfiguration = .init()

        private static func ensureInRange<T: Comparable>(from: T, to: T, val: T) -> T {
            return min(max(from, val), to)
        }


        private(set) var inPacketLoss: Double {
            didSet {
                inPacketLoss = NetworkLinkConfiguration.ensureInRange(from: 0.0, to: 1.0, val: inPacketLoss)
            }
        }
        private(set) var outPacketLoss: Double {
            didSet {
                outPacketLoss = NetworkLinkConfiguration.ensureInRange(from: 0.0, to: 1.0, val: outPacketLoss)
            }
        }
        private(set) var inDelay: Int64 {
            didSet {
                inDelay = NetworkLinkConfiguration.ensureInRange(from: 0, to: .max, val: inDelay)
            }
        }
        private(set) var outDelay: Int64 {
            didSet {
                inDelay = NetworkLinkConfiguration.ensureInRange(from: 0, to: .max, val: inDelay)
            }
        }

        init(inPacketLoss: Double = .zero, outPacketLoss: Double = .zero, inDelay: Int64 = .zero, outDelay: Int64 = .zero) {
            self.inPacketLoss = inPacketLoss
            self.outPacketLoss = outPacketLoss
            self.inDelay = inDelay
            self.outDelay = outDelay
        }
    }


    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboudOut = ByteBuffer

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
    private let networkLinkConfig: NetworkLinkConfiguration

    init(networkLinkConfig: NetworkLinkConfiguration) {
        self.state = .inactive
        self.networkLinkConfig = networkLinkConfig
    }
    
    private func shouldDropPacket(for possibility: Double) -> Bool {
        let num = Double.random(in: 0.0...1.0)
        return num < possibility
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
        
        // check if packet should be dropped
        if shouldDropPacket(for: self.networkLinkConfig.inPacketLoss) {
            logger.debug("[\(#function)]: drop data \(data)")
            return
        }
        
        logger.debug("[\(#function)]: schedule to read data in \(self.networkLinkConfig.inDelay) ms")
        context.eventLoop.scheduleTask(in: .milliseconds(self.networkLinkConfig.inDelay)) {
            logger.debug("[\(#function)] fireChannelRead after delaying \(self.networkLinkConfig.inDelay) ms")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.isOperational else {
            logger.error("[\(#function)]: Error: IO on closed channel")
            return
        }

        // check if packet should be dropped
        if shouldDropPacket(for: self.networkLinkConfig.outPacketLoss) {
            logger.debug("[\(#function)]: drop data \(data)")
            return
        }
        
        logger.debug("[\(#function)]: schedule to send data in \(self.networkLinkConfig.outDelay) ms")
        context.eventLoop.scheduleTask(in: .milliseconds(self.networkLinkConfig.outDelay)) {
            _ = context.writeAndFlush(data)
            logger.debug("[\(#function)] writeAndFlush after delaying \(self.networkLinkConfig.outDelay) ms")
        }
    }
}
