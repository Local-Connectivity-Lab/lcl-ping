//
//  ICMPIPDecoderTests.swift
//  
//
//  Created by JOHN ZZN on 11/24/23.
//

import XCTest
import NIOEmbedded
import NIOCore
@testable import LCLPing


final class ICMPIPDecoderTests: XCTestCase {
    
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
    
    func testAddIPDecoderChannel() {
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

private extension String {
    
    var toBytes: [UInt8] {
        guard self.count % 2 == 0 else {
            return []
        }

        var bytes: [UInt8] = []

        var index = self.startIndex
        while index < self.endIndex {
            let byteString = self[index ..< self.index(after: self.index(after: index))]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            } else {
                return []
            }
            index = self.index(after: self.index(after: index))
        }

        return bytes
    }
}



//final class ICMPIPDecoderTests: XCTestCase {
//
//    private var channel: EmbeddedChannel!
//
//    override func setUp() {
//        self.channel = EmbeddedChannel()
//    }
//
//    override func tearDown() {
//        XCTAssertNoThrow(try self.channel.finish(acceptAlreadyClosed: true))
//    }
//
//    func testAddingIPDecoderHandler() {
//        XCTAssertNoThrow(try channel.pipeline.addHandler(IPDecoder()).wait())
//    }
//
//    func testDecodeBasicIPHeader() {
//        XCTAssertNoThrow(try channel.pipeline.addHandler(IPDecoder()).wait())
//
////        let header = IPv4Header(versionAndHeaderLength: UInt8, differentiatedServicesAndECN: UInt8, totalLength: UInt16, identification: UInt16, flagsAndFragmentOffset: UInt16, timeToLive: UInt8, protocol: UInt8, headerChecksum: UInt16, sourceAddress: (UInt8, UInt8, UInt8, UInt8), destinationAddress: (UInt8, UInt8, UInt8, UInt8))
//    }
//
//    // we can test the following test cases
//    // 1. valid header
//    // 2. invalid IP version
//    // 3. invalid protocol
//    // 4. insufficient byte length
//    // 5. empty incoming data
//}

//private extension IPv4Header {
//
//    // from https://github.com/apple/swift-nio/blob/main/Tests/NIOPosixTests/IPv4Header.swift
//    func computeChecksum() -> UInt16 {
//        let sourceIpAddress = UInt32(sourceAddress.0) << 24 | UInt32(sourceAddress.1) << 16 | UInt32(sourceAddress.2) << 8 | UInt32(sourceAddress.3)
//        let destinationIpAddress = UInt32(destinationAddress.0) << 24 | UInt32(destinationAddress.1) << 16 | UInt32(destinationAddress.2) << 8 | UInt32(destinationAddress.3)
//        let checksum = ~[
//            UInt16(versionAndHeaderLength) << 8 | UInt16(differentiatedServicesAndECN),
//            totalLength,
//            identification,
//            flagsAndFragmentOffset,
//            UInt16(timeToLive) << 8 | UInt16(`protocol`.rawValue),
//            UInt16(sourceIpAddress >> 16),
//            UInt16(sourceIpAddress & 0b0000_0000_0000_0000_1111_1111_1111_1111),
//            UInt16(destinationIpAddress >> 16),
//            UInt16(destinationIpAddress & 0b0000_0000_0000_0000_1111_1111_1111_1111),
//        ].reduce(UInt16(0), onesComplementAdd)
//        assert(isValidChecksum(checksum))
//        return checksum
//    }
//
//    mutating func setChecksum() {
//        self.headerChecksum = computeChecksum()
//    }
//
//    private func onesComplementAdd<Integer: FixedWidthInteger>(lhs: Integer, rhs: Integer) -> Integer {
//        var (sum, overflowed) = lhs.addingReportingOverflow(rhs)
//        if overflowed {
//            sum &+= 1
//        }
//        return sum
//    }
//}
