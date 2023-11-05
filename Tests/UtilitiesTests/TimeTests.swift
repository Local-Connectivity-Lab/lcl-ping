//
//  TimeTests.swift
//  
//
//  Created by JOHN ZZN on 11/5/23.
//

import XCTest
@testable import LCLPing

final class TimeTests: XCTestCase {
    
    let utc: TimeZone = TimeZone(abbreviation: "UTC")!
    let zero: TimeInterval = .zero
    let oneThousandSecond: TimeInterval = 1000
    let randomTime: TimeInterval = 1696182591
    let randomTimeWithDigits: TimeInterval = 99999.99
    
    func testDateToString() {
        XCTAssertEqual(Date.toDateString(timeInterval: zero, timeZone: utc), "01/01/1970 00:00:00")
        XCTAssertEqual(Date.toDateString(timeInterval: oneThousandSecond, timeZone: utc), "01/01/1970 00:16:40")
        XCTAssertEqual(Date.toDateString(timeInterval: randomTime, timeZone: utc), "10/01/2023 17:49:51")
        XCTAssertEqual(Date.toDateString(timeInterval: randomTimeWithDigits, timeZone: utc), "01/02/1970 03:46:39")
    }
    
    func testToNanoSecond() {
        XCTAssertEqual(zero.nanosecond, 0)
        XCTAssertEqual(oneThousandSecond.nanosecond, 1000000000000)
        XCTAssertEqual(randomTime.nanosecond, 1696182591000000000)
        XCTAssertEqual(randomTimeWithDigits.nanosecond, 99999990000000)
    }

}
