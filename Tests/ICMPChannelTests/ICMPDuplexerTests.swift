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
    
    private let icmpConfiguration = LCLPing.PingConfiguration(
        type: .icmp,
        endpoint: .ipv4("127.0.0.1", 0),
        timeout: 2
    )

    override func setUp() {
        channel = EmbeddedChannel()
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.channel?.finish(acceptAlreadyClosed: true))
        channel = nil
    }

    func testAddDuplexerChannelHandler() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now and but is nil")
        
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
    }
    
    func testBasicOutboundWrite() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        
        let outboundInData: ICMPOutboundIn = (1,2)
        try channel.writeOutbound(outboundInData)
        self.loop.run()
        var outboundOutData = try channel.readOutbound(as: ByteBuffer.self)
        XCTAssertNotNil(outboundOutData)
        let sent = try decodeByteBuffer(of: ICMPHeader.self, data: &outboundOutData!)
        XCTAssertEqual(sent.type, ICMPType.EchoRequest.rawValue)
        XCTAssertEqual(sent.code, 0)
        XCTAssertEqual(sent.idenifier, 1)
        XCTAssertEqual(sent.sequenceNum, 2)
        XCTAssertEqual(sent.payload.identifier, 1)
    }
    
    
    func testBasicInboundRead() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        
        let outboundInData: ICMPOutboundIn = (0xbeef, 2)
        var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()
        let inboundInResult = try channel.readInbound(as: PingResponse.self)!
        switch inboundInResult {
        case .ok(let sequenceNum, _, _):
            XCTAssertEqual(sequenceNum, 2)
        default:
            XCTFail("Should receive a PingResponse.ok, but received \(inboundInResult)")
        }
    }
    
    func testReadFireCorrectError() {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        
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
            (10, 0 , PingError.icmpRouterDiscoverySelectionSolicitation),
            (11, 0 , PingError.icmpTTLExpiredInTransit),
            (11, 1 , PingError.icmpFragmentReassemblyTimeExceeded),
            (12, 0,  PingError.icmpPointerIndicatesError),
            (12, 1 , PingError.icmpMissingARequiredOption),
            (12, 2 , PingError.icmpBadLength),
            (13, 3, PingError.unknownError("Received unknown ICMP type (13) and ICMP code (3)"))
        ]
        
        for input in inputs {
            let (type, code, expectedError) = input
            var inboundInData: ICMPHeader = ICMPHeader(type: UInt8(type), code: UInt8(code), idenifier: 0xbeef, sequenceNum: 2)
            inboundInData.setChecksum()
            do {
                try channel.writeInbound(inboundInData)
                self.loop.run()
                let inboundInResult = try channel.readInbound(as: PingResponse.self)!
                switch inboundInResult {
                case .error(.some(let error)):
                    XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
                default:
                    XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
                }
            } catch {
                XCTFail("Test failed unexpectedly: \(error)")
            }
        }
    }
    
    func testICMPResponseWithNoMatchingRequest() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        try channel.writeInbound(inboundInData)
        self.loop.run()
        let inboundInResult = try channel.readInbound(as: PingResponse.self)!
        let expectedError = PingError.invalidICMPResponse
        switch inboundInResult {
        case .error(.some(let error)):
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        default:
            XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
        }
    }
    
    func testInvalidICMPChecksum() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        let inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        let outboundInData: ICMPOutboundIn = (0xbeef, 2)
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()
        let inboundInResult = try channel.readInbound(as: PingResponse.self)!
        let expectedError = PingError.invalidICMPChecksum
        switch inboundInResult {
        case .error(.some(let error)):
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        default:
            XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
        }
    }
    
    func testInvalidICMPIdentifier() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        let outboundInData: ICMPOutboundIn = (0xdead, 2)
        try channel.writeOutbound(outboundInData)
        try channel.writeInbound(inboundInData)
        self.loop.run()
        let inboundInResult = try channel.readInbound(as: PingResponse.self)!
        let expectedError = PingError.invalidICMPIdentifier
        switch inboundInResult {
        case .error(.some(let error)):
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        default:
            XCTFail("Should receive a PingResponse.error, but received \(inboundInResult)")
        }
    }
    
    func testICMPResponseTimeout() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        let outboundInData: ICMPOutboundIn = (0xbeef, 2)
        try channel.writeOutbound(outboundInData)
        let expectation = XCTestExpectation(description: "Expect PingResponse Timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            do {
                try self.channel.writeInbound(inboundInData)
                expectation.fulfill()
            } catch {
                XCTFail("Should not throw any error: \(error)")
            }
        }
        self.loop.run()
        
        wait(for: [expectation], timeout: 2.5)
        let inboundInResult = try channel.readInbound(as: PingResponse.self)!
        switch inboundInResult {
        case .timeout(let seqNum):
            XCTAssertEqual(seqNum, inboundInData.sequenceNum)
        default:
            XCTFail("Should receive a PingResponse timeout, but received \(inboundInResult)")
        }
    }
    
    func testICMPResponseDuplicate() throws {
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: self.icmpConfiguration)).wait())
        channel.pipeline.fireChannelActive()
        var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: 2)
        inboundInData.setChecksum()
        let outboundInData: ICMPOutboundIn = (0xbeef, 2)
        try channel.writeOutbound(outboundInData)
        for _ in 0..<5 {
            try channel.writeInbound(inboundInData)
        }
        self.loop.run()
        let firstInboundInResult = try channel.readInbound(as: PingResponse.self)!
        switch firstInboundInResult {
        case .ok(let seqNum, _, _):
            XCTAssertEqual(seqNum, inboundInData.sequenceNum)
        default:
            XCTFail("Should receive a PingResponse ok, but received \(firstInboundInResult)")
        }
        
        for _ in 1..<5 {
            let duplicatedInboundInResult = try channel.readInbound(as: PingResponse.self)!
            switch duplicatedInboundInResult {
            case .duplicated(let seqNum):
                XCTAssertEqual(seqNum, inboundInData.sequenceNum)
            default:
                XCTFail("Should receive a PingResponse duplicated, but received \(duplicatedInboundInResult)")
            }
        }
    }
    
    func testDuplexerClosedAfterFinish() throws {
        let config = LCLPing.PingConfiguration(
            type: .icmp,
            endpoint: .ipv4("127.0.0.1", 0),
            count: 2
        )
        let eventCounter = EventCounterHandler()
        XCTAssertNoThrow(try channel.pipeline.addHandler(eventCounter).wait())
        XCTAssertNoThrow(try channel.pipeline.addHandler(ICMPDuplexer(configuration: config)).wait())
        channel.pipeline.fireChannelActive()

        for i in 0..<2 {
            let outboundInData: ICMPOutboundIn = (0xbeef, UInt16(i))
            try channel.writeOutbound(outboundInData)
        }
        for i in 0..<2 {
            var inboundInData: ICMPHeader = ICMPHeader(type: ICMPType.EchoReply.rawValue, code: 0, idenifier: 0xbeef, sequenceNum: UInt16(i))
            inboundInData.setChecksum()
            try channel.writeInbound(inboundInData)
        }
        self.loop.run()
        
        for i in 0..<2 {
            let inboundInResult = try channel.readInbound(as: PingResponse.self)!
            switch inboundInResult {
            case .ok(let seqNum, _, _):
                XCTAssertEqual(seqNum, UInt16(i))
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
