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

/// This channel handler emulates different network conditions, according to the `NetworkLinkConfiguration`.
/// This channel handler _should not_ be used in normal testing.
///
/// - Note: This channel handler should usually be placed at the first position in the channel handlers pipeline.
final class TrafficControllerChannelHandler: ChannelDuplexHandler {

    /// The configuration to simulate different network conditions.
    struct NetworkLinkConfiguration {

        /// A fully disconnected network. Using this configuration, all inbound and outbound packets will be dropped.
        public static let fullyDisconnected: NetworkLinkConfiguration = .init(inPacketLoss: 1.0,
                                                                              outPacketLoss: 1.0,
                                                                              inDelay: .zero,
                                                                              outDelay: .zero,
                                                                              inDuplicate: .zero)

        /// A fully connected network. Using this configuration, all packets flows normally without any interferences.
        public static let fullyConnected: NetworkLinkConfiguration = .init()

        /// A fully duplicated network. Using this configuration, each inbound packet will be duplicated, which means inbound handlers that followed `TrafficControllerChannelHandler`
        /// will receive two identical packets.
        public static let fullyDuplicated: NetworkLinkConfiguration = .init(inDuplicate: 1.0)

        private static func ensureInRange<T: Comparable>(from: T, to: T, val: T) -> T {
            return min(max(from, val), to)
        }

        /// The possibility, in double, that the inbound packet will be dropped. Value should be between `0.0` and `1.0`.
        private(set) var inPacketLoss: Double {
            didSet {
                inPacketLoss = NetworkLinkConfiguration.ensureInRange(from: 0.0, to: 1.0, val: inPacketLoss)
            }
        }

        /// The possibility, in double, that the outbound packet will be dropped. Value should be between `0.0` and `1.0`.
        private(set) var outPacketLoss: Double {
            didSet {
                outPacketLoss = NetworkLinkConfiguration.ensureInRange(from: 0.0, to: 1.0, val: outPacketLoss)
            }
        }

        /// The number of seconds that the inbound packet will be delayed before delivering to inbound handlers that followed. Value should be between `0` and `Int64.max`.
        private(set) var inDelay: Int64 {
            didSet {
                inDelay = NetworkLinkConfiguration.ensureInRange(from: 0, to: .max, val: inDelay)
            }
        }

        /// The number of seconds that the outbound packet will be delayed before delivering to the next outbound handlers. Value should be between `0` and `Int64.max`.
        private(set) var outDelay: Int64 {
            didSet {
                inDelay = NetworkLinkConfiguration.ensureInRange(from: 0, to: .max, val: inDelay)
            }
        }

        /// The possibility, in double, that the inbound packet will be duplicated. Value should be between `0.0` and `1.0`.
        private(set) var inDuplicate: Double {
            didSet {
                inDuplicate = NetworkLinkConfiguration.ensureInRange(from: 0.0, to: 1.0, val: inDuplicate)
            }
        }

        init(inPacketLoss: Double = .zero,
             outPacketLoss: Double = .zero,
             inDelay: Int64 = .zero,
             outDelay: Int64 = .zero,
             inDuplicate: Double = .zero) {
            self.inPacketLoss = inPacketLoss
            self.outPacketLoss = outPacketLoss
            self.inDelay = inDelay
            self.outDelay = outDelay
            self.inDuplicate = inDuplicate
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
        let num = Double.random(in: 0.0..<1.0)
        return num < possibility
    }

    private func shouldDuplicatePacket(for possibility: Double) -> Bool {
        let num = Double.random(in: 0.0..<1.0)
        return num < possibility
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            break
        case .error:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)]: in an incorrect state: \(self.state)")
        case .inactive:
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[\(#fileID)][\(#line)][\(#fileID)][\(#line)][\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            assertionFailure("[\(#fileID)][\(#line)][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        // check if packet should be dropped
        if shouldDropPacket(for: self.networkLinkConfig.inPacketLoss) {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data \(data)")
            return
        }

        let shouldDuplicatePacket = shouldDuplicatePacket(for: self.networkLinkConfig.inDuplicate)

        logger.debug("[\(#fileID)][\(#line)][\(#function)]: schedule to read data in \(self.networkLinkConfig.inDelay) ms. Should duplicate: \(shouldDuplicatePacket)")
        context.eventLoop.scheduleTask(in: .milliseconds(self.networkLinkConfig.inDelay)) {
            context.fireChannelRead(data)
            if shouldDuplicatePacket {
                context.fireChannelRead(data)
            }
            logger.debug("[\(#fileID)][\(#line)][\(#function)] fireChannelRead after delaying \(self.networkLinkConfig.inDelay) ms")
        }

    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.isOperational else {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: Error: IO on closed channel")
            return
        }

        // check if packet should be dropped
        if shouldDropPacket(for: self.networkLinkConfig.outPacketLoss) {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: drop data \(data)")
            return
        }

        logger.debug("[\(#fileID)][\(#line)][\(#function)]: schedule to send data in \(self.networkLinkConfig.outDelay) ms")
        context.eventLoop.scheduleTask(in: .milliseconds(self.networkLinkConfig.outDelay)) {
            _ = context.writeAndFlush(data)
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: writeAndFlush after delaying \(self.networkLinkConfig.outDelay) ms")
        }
    }
}
