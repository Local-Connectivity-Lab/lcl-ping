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
@testable import LCLPing

final class ICMPChecksumTests: XCTestCase {
    func testExample() throws {
        var header1 = ICMPPingClient.ICMPHeader(idenifier: 123, sequenceNum: 456)
        header1.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 987654321.0, identifier: header1.idenifier)
        header1.setChecksum()
        XCTAssertEqual(header1.data.computeIPChecksum(), 0)

        var header2 = ICMPPingClient.ICMPHeader(idenifier: 789, sequenceNum: 321)
        header2.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 123456789.0, identifier: header2.idenifier)
        header2.setChecksum()
        XCTAssertEqual(header2.data.computeIPChecksum(), 0)

        var header3 = ICMPPingClient.ICMPHeader(idenifier: 1, sequenceNum: 2)
        header3.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 987654321.0, identifier: header3.idenifier)
        header3.setChecksum()
        XCTAssertEqual(header3.data.computeIPChecksum(), 0)

        var header4 = ICMPPingClient.ICMPHeader(idenifier: 5, sequenceNum: 777)
        header4.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 123456789.0, identifier: header4.idenifier)
        header4.setChecksum()
        XCTAssertEqual(header4.data.computeIPChecksum(), 0)

        var header5 = ICMPPingClient.ICMPHeader(idenifier: 999, sequenceNum: 88)
        header5.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 987654321.0, identifier: header5.idenifier)
        header5.setChecksum()
        XCTAssertEqual(header5.data.computeIPChecksum(), 0)

        var header6 = ICMPPingClient.ICMPHeader(idenifier: 777, sequenceNum: 666)
        header6.payload = ICMPPingClient.ICMPRequestPayload(timestamp: 123456789.0, identifier: header6.idenifier)
        header6.setChecksum()
        XCTAssertEqual(header6.data.computeIPChecksum(), 0)
    }
}

// Taken directly from swift-nio(Tests/NIOPosixTests/IPv4Header.swift)
extension Sequence where Element == UInt8 {
    func computeIPChecksum() -> UInt16 {
        var sum = UInt16(0)

        var iterator = self.makeIterator()

        while let nextHigh = iterator.next() {
            let nextLow = iterator.next() ?? 0
            let next = (UInt16(nextHigh) << 8) | UInt16(nextLow)
            sum = onesComplementAdd(lhs: sum, rhs: next)
        }

        return ~sum
    }

    private func onesComplementAdd<Integer: FixedWidthInteger>(lhs: Integer, rhs: Integer) -> Integer {
        var (sum, overflowed) = lhs.addingReportingOverflow(rhs)
        if overflowed {
            sum &+= 1
        }
        return sum
    }
}
