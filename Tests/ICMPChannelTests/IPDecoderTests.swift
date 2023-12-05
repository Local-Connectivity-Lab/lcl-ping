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
@testable import LCLPing


final class IPDecoderTests: XCTestCase {
    
    private var channel: EmbeddedChannel!
    private var loop: EmbeddedEventLoop {
        return self.channel.embeddedEventLoop
    }

    override func setUp() {
        channel = EmbeddedChannel()
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.channel?.finish(acceptAlreadyClosed: true))
        channel = nil
    }
    
    func testAddIPDecoderChannelHandler() {
        XCTAssertNotNil(channel, "Channel should be initialized by now and but is nil")
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(IPDecoder()).wait())
        channel.pipeline.fireChannelActive()
    }
    
    private func sendIPPacket(byteString ipString: String) throws {
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(IPDecoder()).wait())
        let socketAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        var buffer = channel.allocator.buffer(capacity: ipString.count)
        channel.pipeline.fireChannelActive()
        buffer.writeBytes(ipString.toBytes)
        let ae = AddressedEnvelope(remoteAddress: socketAddress, data: buffer)
        try channel.writeInbound(ae)
        self.loop.run()
    }
    
    func testDecodeValidIPHeader() throws {
        XCTAssertNoThrow(try sendIPPacket(byteString: "45000054000000003a0157518efad94ec0a80067"))
        let remaining = try channel.readInbound(as: ByteBuffer.self)
        XCTAssertEqual(remaining?.readableBytes, 0)
    }
    
    
    func testDecodeCorrectSliceAfterDecode() throws {
        XCTAssertNoThrow(try sendIPPacket(byteString: "45000054000000003a0157518efad94ec0a800671122334455667788"))
        let remaining = try channel.readInbound(as: ByteBuffer.self)
        XCTAssertEqual(remaining?.readableBytes, 8)
    }
    
    func testDecodeInvalidIPVersion() throws {
        let expectedError: PingError = .invalidIPVersion
        XCTAssertThrowsError(try sendIPPacket(byteString: "15000054000000003a0157518efad94ec0a80067")) { error in
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        }
    }
    
    func testDecodeInvalidIPProtocol() throws {
        let expectedError: PingError = .invalidIPProtocol
        XCTAssertThrowsError(try sendIPPacket(byteString: "45000054000000003a0257518efad94ec0a80067")) { error in
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        }
    }
    
    func testDecodeInsufficientByteLength() throws {
        let expectedError: RuntimeError = .insufficientBytes("Not enough bytes in the reponse message. Need 20 bytes. But received 8")
        XCTAssertThrowsError(try sendIPPacket(byteString: "4500005400000000")) { error in
            XCTAssertEqual(error as? RuntimeError, expectedError)
        }
    }
    
    func testDecodeEmptyPacket() throws {
        let expectedError: RuntimeError = .insufficientBytes("Not enough bytes in the reponse message. Need 20 bytes. But received 0")
        XCTAssertThrowsError(try sendIPPacket(byteString: "")) { error in
            XCTAssertEqual(error as? RuntimeError, expectedError)
        }
    }
}
