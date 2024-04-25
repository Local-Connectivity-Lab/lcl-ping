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
@testable import LCLPing

final class TimeTests: XCTestCase {

    let utc: TimeZone = TimeZone(abbreviation: "UTC")!
    let zero: TimeInterval = .zero
    let oneThousandSecond: TimeInterval = 1000
    let randomTime: TimeInterval = 1696182591
    let randomTimeWithDigits: TimeInterval = 99999.99

    func testZeroSecondToDateString() {
        XCTAssertEqual(Date.toDateString(timeInterval: zero, timeZone: utc), "01/01/1970 00:00:00")
    }

    func testOneThousandSecondToDateString() {
        XCTAssertEqual(Date.toDateString(timeInterval: oneThousandSecond, timeZone: utc), "01/01/1970 00:16:40")
    }

    func testRandomTimeToDateString() {
        XCTAssertEqual(Date.toDateString(timeInterval: randomTime, timeZone: utc), "10/01/2023 17:49:51")
        XCTAssertEqual(Date.toDateString(timeInterval: randomTimeWithDigits, timeZone: utc), "01/02/1970 03:46:39")
    }

    func testZeroSecondToNanoSecond() {
        XCTAssertEqual(zero.nanosecond, 0)
    }

    func testOneThousandSecondToNanoSecond() {
        XCTAssertEqual(oneThousandSecond.nanosecond, 1000000000000)
    }

    func testRandomTimeToNanoSecond() {
        XCTAssertEqual(randomTime.nanosecond, 1696182591000000000)
        XCTAssertEqual(randomTimeWithDigits.nanosecond, 99999990000000)
    }
}
