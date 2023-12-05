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

final class MatchServerTimingTests: XCTestCase {
    // Single metric without value
    private let noValue = "Server-Timing: missedCache"

    // Single metric with value
    private let singleValue = "Server-Timing: cpu;dur=2.4"

    // Single metric with description and value
    private let singleValueWithDescription = "Server-Timing: cache;desc='Cache Read';dur=23.2"

    // Two metrics with value
    private let twoValues = "Server-Timing: db;dur=36.4, app;dur=47.2"
    
    // Multiple metrics with value
    private let multipleValues1 = "Server-Timing: db;dur=53, app;dur=47.2; cpu;dur=10.2, cache;desc='Cache';dur=5.3"
    private let multipleValues2 = "Server-Timing: a;dur=1.1, b;dur=2.2; c;dur=3.3, d;dur=4.4, e;dur=5.5, f;dur=6.6, g;dur=7.7, h;dur=8.8, i;dur=9.9"

    // missing value
    private let missingValue = "Server-Timing: total;dur="
    
    // typo
    private let typo = "Server-Timing: app;due=123.56"
    
    // garbage
    private let invalid = "Some random string"
    
    func testNoValue() {
        XCTAssertEqual(matchServerTiming(field: noValue), 0.0)
    }
    
    func testSingleValue() {
        XCTAssertEqual(matchServerTiming(field: singleValue), 2.4)
    }
    
    func testSingleMetricWithDescription() {
        XCTAssertEqual(matchServerTiming(field: singleValueWithDescription), 23.2)
    }
    
    func testTwoValues() {
        XCTAssertEqual(matchServerTiming(field: twoValues), 83.6)
    }
    
    func testMultipleValues() {
        XCTAssertEqual(matchServerTiming(field: multipleValues1), 115.7)
        XCTAssertEqual(matchServerTiming(field: multipleValues2), 49.5)
    }
    
    
    func testInvalidInput() {
        XCTAssertEqual(matchServerTiming(field: missingValue), 0.0)
        XCTAssertEqual(matchServerTiming(field: typo), 0.0)
        XCTAssertEqual(matchServerTiming(field: invalid), 0.0)
    }

}
