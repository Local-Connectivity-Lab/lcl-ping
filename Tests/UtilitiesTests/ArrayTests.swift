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

final class ArrayTests: XCTestCase {

    private let empty: [PingResult] = []
    private let single: [PingResult] = [.init(seqNum: 1, latency: 1.0, timestamp: 1)]

    private let basicEvenLength: [PingResult] = [
        .init(seqNum: 0, latency: 1, timestamp: 0),
        .init(seqNum: 1, latency: 2, timestamp: 1),
        .init(seqNum: 2, latency: 3, timestamp: 2),
        .init(seqNum: 3, latency: 4, timestamp: 3),
        .init(seqNum: 4, latency: 5, timestamp: 4),
        .init(seqNum: 5, latency: 6, timestamp: 5)
    ]

    private let basicOddLength: [PingResult] = [
        .init(seqNum: 0, latency: 1, timestamp: 0),
        .init(seqNum: 2, latency: 3, timestamp: 2),
        .init(seqNum: 4, latency: 5, timestamp: 4)
    ]

    private let equalLatencyEvenLength: [PingResult] = [
        .init(seqNum: 0, latency: 2, timestamp: 1),
        .init(seqNum: 1, latency: 2, timestamp: 2),
        .init(seqNum: 2, latency: 2, timestamp: 3),
        .init(seqNum: 3, latency: 2, timestamp: 4)
    ]

    private let equalLatencyOddLength: [PingResult] = [
        .init(seqNum: 1, latency: 1, timestamp: 1),
        .init(seqNum: 2, latency: 1, timestamp: 2),
        .init(seqNum: 3, latency: 1, timestamp: 3)
    ]

    private let reversedEvenLength: [PingResult] = [
        .init(seqNum: 0, latency: 5, timestamp: 1),
        .init(seqNum: 1, latency: 4, timestamp: 1),
        .init(seqNum: 2, latency: 3, timestamp: 2),
        .init(seqNum: 3, latency: 2, timestamp: 3),
        .init(seqNum: 4, latency: 1, timestamp: 4),
        .init(seqNum: 5, latency: 0, timestamp: 5)
    ]

    private let reversedOddLength: [PingResult] = [
        .init(seqNum: 1, latency: 4, timestamp: 1),
        .init(seqNum: 2, latency: 3, timestamp: 2),
        .init(seqNum: 3, latency: 2, timestamp: 3),
        .init(seqNum: 4, latency: 1, timestamp: 4),
        .init(seqNum: 5, latency: 0, timestamp: 5)
    ]

    private let random: [PingResult] = [
        .init(seqNum: 0, latency: 12, timestamp: 1),
        .init(seqNum: 6, latency: 54, timestamp: 1),
        .init(seqNum: 5, latency: 2, timestamp: 5),
        .init(seqNum: 3, latency: 4, timestamp: 2),
        .init(seqNum: 2, latency: 1, timestamp: 3),
        .init(seqNum: 1, latency: 100, timestamp: 4)
    ]

    func testMedianEmptyArray() {
        XCTAssertEqual(empty.median, 0)
    }

    func testAvgEmptyArray() {
        XCTAssertEqual(empty.avg, 0.0)
    }

    func testAvgSingleItem() {
        XCTAssertEqual(single.avg, 1.0)
    }

    func testMedianSingleItem() {
        XCTAssertEqual(single.median, 1.0)
    }

    func testAvgBasic() {
        XCTAssertEqual(basicEvenLength.avg, 3.5)
        XCTAssertEqual(basicOddLength.avg, 3)
    }

    func testMedianBasic() {
        XCTAssertEqual(basicEvenLength.median, 3)
        XCTAssertEqual(basicOddLength.median, 3)
    }

    func testAvgEqualLatency() {
        XCTAssertEqual(equalLatencyEvenLength.avg, 2)
        XCTAssertEqual(equalLatencyOddLength.avg, 1)
    }

    func testMedianEqualLatency() {
        XCTAssertEqual(equalLatencyEvenLength.median, 2)
        XCTAssertEqual(equalLatencyOddLength.median, 1)
    }

    func testAvgReversed() {
        XCTAssertEqual(reversedOddLength.avg, 2)
        XCTAssertEqual(reversedEvenLength.avg, 2.5)
    }

    func testMedianReversed() {
        XCTAssertEqual(reversedOddLength.median, 2)
        XCTAssertEqual(reversedEvenLength.median, 2)
    }

    func testAvgRandom() {
        XCTAssertEqual(random.avg, 28.83, accuracy: 0.01)
    }

    func testMedianRandom() {
        XCTAssertEqual(random.median, 4)
    }

    func testMedianRandom2() {
        let random1: [PingResult] = [
            .init(seqNum: 0, latency: 20, timestamp: 1),
            .init(seqNum: 6, latency: 54, timestamp: 1),
            .init(seqNum: 5, latency: 37, timestamp: 5),
            .init(seqNum: 3, latency: 4, timestamp: 2),
            .init(seqNum: 2, latency: 1, timestamp: 3),
            .init(seqNum: 1, latency: 100, timestamp: 4)
        ]
        XCTAssertEqual(random1.median, 20)

        let random2: [PingResult] = [
            .init(seqNum: 1, latency: 312, timestamp: 1),
            .init(seqNum: 2, latency: 64, timestamp: 2),
            .init(seqNum: 3, latency: 800, timestamp: 3),
            .init(seqNum: 4, latency: 251, timestamp: 4),
            .init(seqNum: 5, latency: 76, timestamp: 5),
            .init(seqNum: 6, latency: 2376, timestamp: 6),
            .init(seqNum: 7, latency: 12, timestamp: 7)
        ]
        XCTAssertEqual(random2.median, 251)
    }
}
