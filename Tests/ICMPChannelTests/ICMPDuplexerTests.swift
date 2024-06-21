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

import XCTest
import NIOEmbedded
import NIOCore
import NIOTestUtils
@testable import LCLPing

final class ICMPDuplexerTests: XCTestCase {

    private var channel: EmbeddedChannel!
    private var loop: EmbeddedEventLoop {
        return self.channel.embeddedEventLoop
    }

    private let icmpConfiguration = ICMPPingClient.Configuration(
        endpoint: .ipv4("127.0.0.1", 0),
        count: 1,
        timeout: .seconds(2)
    )

    private var resolvedAddress: SocketAddress? {
        return try? SocketAddress(ipAddress: "127.0.0.1", port: 0)
    }

    override func setUp() {
        channel = EmbeddedChannel()
        XCTAssertNotNil(resolvedAddress)
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.channel?.finish(acceptAlreadyClosed: true))
        channel = nil
    }

    func testAddDuplexerChannelHandler() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now and but is nil")
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)

        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()
    }

    func testBasicOutboundWrite() throws {
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()

        let outboundInData: ICMPPingClient.Request = ICMPPingClient.Request(sequenceNum: 2, identifier: 1)
        try channel.writeOutbound(outboundInData)
        self.loop.run()
        let outboundOutData = try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self)
        XCTAssertNotNil(outboundOutData)
        var data = outboundOutData!.data
        let remoteAddr = outboundOutData!.remoteAddress
        let sent = try decodeByteBuffer(of: ICMPPingClient.ICMPHeader.self, data: &data)
        XCTAssertEqual(remoteAddr, try! SocketAddress(ipAddress: "127.0.0.1", port: 0))
        XCTAssertEqual(sent.type, ICMPPingClient.ICMPType.echoRequest.rawValue)
        XCTAssertEqual(sent.code, 0)
        XCTAssertEqual(sent.idenifier, 1)
        XCTAssertEqual(sent.sequenceNum, 2)
        XCTAssertEqual(sent.payload.identifier, 1)
    }

    func testBasicInboundRead() throws {
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()

        let outboundInData: ICMPPingClient.Request = ICMPPingClient.Request(sequenceNum: 2, identifier: 0xbeef)
        var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()

        let inboundInResult = try promise.futureResult.wait()
        XCTAssertEqual(inboundInResult.count, 1)
        switch inboundInResult[0] {
        case .ok(let sequenceNum, _, _):
            XCTAssertEqual(sequenceNum, 2)
        default:
            XCTFail("Should receive a PingResponse.ok, but received \(String(describing: inboundInResult))")
        }
    }

    func testReadFireCorrectError() {
        let inputs = [
            (3, 0, PingError.icmpDestinationNetworkUnreachable),
            (3, 1, PingError.icmpDestinationHostUnreachable),
            (3, 2, PingError.icmpDestinationProtocoltUnreachable),
            (3, 3, PingError.icmpDestinationPortUnreachable),
            (3, 4, PingError.icmpFragmentationRequired),
            (3, 5, PingError.icmpSourceRouteFailed),
            (3, 6, PingError.icmpUnknownDestinationNetwork),
            (3, 7, PingError.icmpUnknownDestinationHost),
            (3, 8, PingError.icmpSourceHostIsolated),
            (3, 9, PingError.icmpNetworkAdministrativelyProhibited),
            (3, 10, PingError.icmpHostAdministrativelyProhibited),
            (3, 11, PingError.icmpNetworkUnreachableForToS),
            (3, 12, PingError.icmpHostUnreachableForToS),
            (3, 13, PingError.icmpCommunicationAdministrativelyProhibited),
            (3, 14, PingError.icmpHostPrecedenceViolation),
            (3, 15, PingError.icmpPrecedenceCutoffInEffect),
            (5, 0, PingError.icmpRedirectDatagramForNetwork),
            (5, 1, PingError.icmpRedirectDatagramForHost),
            (5, 2, PingError.icmpRedirectDatagramForTosAndNetwork),
            (5, 3, PingError.icmpRedirectDatagramForTosAndHost),
            (9, 0, PingError.icmpRouterAdvertisement),
            (10, 0, PingError.icmpRouterDiscoverySelectionSolicitation),
            (11, 0, PingError.icmpTTLExpiredInTransit),
            (11, 1, PingError.icmpFragmentReassemblyTimeExceeded),
            (12, 0, PingError.icmpPointerIndicatesError),
            (12, 1, PingError.icmpMissingARequiredOption),
            (12, 2, PingError.icmpBadLength),
            (13, 3, PingError.unknownError("Received unknown ICMP type (13) and ICMP code (3)"))
        ]

        for input in inputs {
            let (type, code, expectedError) = input
            var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: UInt8(type), code: UInt8(code), idenifier: 0xbeef, sequenceNum: 2)
            let outboundInData: ICMPPingClient.Request = ICMPPingClient.Request(sequenceNum: 2, identifier: 0xbeef)
            inboundInData.setChecksum()
            let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
            do {
                let channel = EmbeddedChannel()
                let loop = channel.embeddedEventLoop
                XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
                channel.pipeline.fireChannelActive()

                try channel.writeOutbound(outboundInData)
                try channel.writeInbound(inboundInData)
                loop.run()
                let inboundInResult = try promise.futureResult.wait()
                XCTAssertEqual(inboundInResult.count, 1)
                switch inboundInResult[0] {
                case .error(.some(let seqNum), .some(let error)):
                    XCTAssertEqual(seqNum, 2)
                    XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
                default:
                    XCTFail("Should receive a PingResponse.error, but received \(String(describing: inboundInResult))")
                }
            } catch {
                XCTFail("Test failed unexpectedly: \(error)")
            }
        }
    }

    func testICMPResponseWithNoMatchingRequest() throws {
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        try channel.writeInbound(inboundInData)
        let expectedError = PingError.invalidICMPResponse
        self.loop.run()
        do {
            let shouldNotReceive = try promise.futureResult.wait()
            XCTFail("Should receive a PingResponse.error, but received \(shouldNotReceive)")
        } catch {
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        }
    }

    func testInvalidICMPChecksum() throws {
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()
        let inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        let outboundInData: ICMPPingClient.Request = .init(sequenceNum: 2, identifier: 0xbeef)
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()
        try channel.close(mode: .all).wait()
        let inboundInResult = try promise.futureResult.wait()
        let expectedError = PingError.invalidICMPChecksum
        XCTAssertEqual(inboundInResult.count, 1)
        switch inboundInResult[0] {
        case .error(.some(let seqNum), .some(let error)):
            XCTAssertEqual(seqNum, 2)
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        default:
            XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
        }
    }

    // On Linux platform, idenfier is unpredictable, we skip if test is run on Linux platform
    func testInvalidICMPIdentifier() throws {
        #if canImport(Darwin)
        let resultPromise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: resultPromise)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        let outboundInData: ICMPPingClient.Request = ICMPPingClient.Request(sequenceNum: 2, identifier: 0xdead)
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()
        let inboundInResult = try resultPromise.futureResult.wait()
        let expectedError = PingError.invalidICMPIdentifier
        XCTAssertEqual(inboundInResult.count, 1)
        switch inboundInResult[0] {
        case .error(.some(let seqNum), .some(let error)):
            XCTAssertEqual(seqNum, 2)
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        default:
            XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
        }
        #endif // canImport(Darwin)
    }

    func testICMPResponseTimeout() throws {
        let promise = channel.eventLoop.makePromise(of: [PingResponse].self)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        let outboundInData: ICMPPingClient.Request = .init(sequenceNum: 2, identifier: 0xbeef)
        try channel.writeOutbound(outboundInData)
        loop.scheduleTask(in: .seconds(2)) {
            try self.channel.writeInbound(inboundInData)
        }
        loop.advanceTime(by: .seconds(4))
        let inboundInResult = try promise.futureResult.wait()
        XCTAssertEqual(inboundInResult.count, 1)
        switch inboundInResult[0] {
        case .timeout(let seqNum):
            XCTAssertEqual(UInt16(seqNum), inboundInData.sequenceNum)
        default:
            XCTFail("Should receive a PingResponse timeout, but received \(inboundInResult)")
        }
    }

    func testICMPResponseDuplicate() throws {
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        let config = ICMPPingClient.Configuration(endpoint: .ipv4("127.0.0.1", 0), count: 2)
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: config, resolvedAddress: resolvedAddress!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        var inboundInData2: ICMPPingClient.ICMPHeader = .init(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 3)
        inboundInData.setChecksum()
        inboundInData2.setChecksum()
        let outboundInData: ICMPPingClient.Request = .init(sequenceNum: 2, identifier: 0xbeef)
        let outboundInData2: ICMPPingClient.Request = .init(sequenceNum: 3, identifier: 0xbeef)
        try channel.writeOutbound(outboundInData)
        try channel.writeOutbound(outboundInData2)
        for _ in 0..<5 {
            try channel.writeInbound(inboundInData)
        }
        try channel.writeInbound(inboundInData2)
        self.loop.run()
        let inboundInResult = try promise.futureResult.wait()
        XCTAssertEqual(inboundInResult.count, 6)
        switch inboundInResult[0] {
        case .ok(let seqNum, _, _):
            XCTAssertEqual(UInt16(seqNum), inboundInData.sequenceNum)
        default:
            XCTFail("Should receive a PingResponse ok, but received \(inboundInResult[0])")
        }

        for i in 1..<5 {
            switch inboundInResult[i] {
            case .duplicated(let seqNum):
                XCTAssertEqual(UInt16(seqNum), inboundInData.sequenceNum)
            default:
                XCTFail("Should receive a PingResponse duplicated, but received \(inboundInResult[i])")
            }
        }
    }

    func testDuplexerClosedAfterFinish() throws {
        let config = ICMPPingClient.Configuration(
            endpoint: .ipv4("127.0.0.1", 0),
            count: 2
        )
        let promise = channel!.eventLoop.makePromise(of: [PingResponse].self)
        let resolvedAddr = try? SocketAddress(ipAddress: "127.0.0.1", port: 0)
        XCTAssertNotNil(resolvedAddr)
        let eventCounter = EventCounterHandler()
        XCTAssertNoThrow(try channel.pipeline.addHandler(eventCounter).wait())
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: config, resolvedAddress: resolvedAddr!, promise: promise)).wait())
        channel.pipeline.fireChannelActive()

        for i in 0..<2 {
            let outboundInData = ICMPPingClient.Request(sequenceNum: UInt16(i), identifier: 0xbeef)
            try channel.writeOutbound(outboundInData)
        }
        for i in 0..<2 {
            var inboundInData: ICMPPingClient.ICMPHeader = ICMPPingClient.ICMPHeader(type: ICMPPingClient.ICMPType.echoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: UInt16(i))
            inboundInData.setChecksum()
            try channel.writeInbound(inboundInData)
        }
        self.loop.run()
        let inboundInResult = try promise.futureResult.wait()
        try channel.close(mode: .all).wait()
        XCTAssertEqual(inboundInResult.count, 2)
        for i in 0..<2 {
            let inboundIn = inboundInResult[i]
            switch inboundIn {
            case .ok(let seqNum, _, _):
                XCTAssertEqual(UInt16(seqNum), UInt16(i))
            default:
                XCTFail("Should receive a PingResponse ok, but received \(inboundInResult)")
            }
        }
        XCTAssertFalse(channel.isActive)
        XCTAssertEqual(2, eventCounter.writeCalls)
        XCTAssertEqual(2, eventCounter.channelReadCalls)
        XCTAssertEqual(1, eventCounter.channelUnregisteredCalls)
        XCTAssertEqual(1, eventCounter.channelActiveCalls)
        XCTAssertEqual(1, eventCounter.channelInactiveCalls)
        XCTAssertEqual(["channelUnregistered", "channelReadComplete", "channelRead", "write", "flush", "channelActive", "channelInactive", "close"], eventCounter.allTriggeredEvents())
    }
}
