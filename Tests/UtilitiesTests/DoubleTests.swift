//
//  DoubleTests.swift
//  
//
//  Created by JOHN ZZN on 11/4/23.
//

import XCTest
@testable import LCLPing

final class DoubleTests: XCTestCase {
    
    let zero: Double = .zero
    let pi: Double = .pi
    let basicDouble: Double = 1.23456789
    let doubleWithDecimalGreaterThan5: Double = 3.56789
    let doubleWithNines: Double = 0.99999
    let doubleWithZeroDecimal: Double = 1
    
    func testRoundToZeroDecimal() {
        XCTAssertEqual(zero.round(to: 0), 0.0)
        XCTAssertEqual(pi.round(to: 0), 3.0)
        XCTAssertEqual(basicDouble.round(to: 0), 1.0)
        XCTAssertEqual(doubleWithDecimalGreaterThan5.round(to: 0), 4.0)
        XCTAssertEqual(doubleWithNines.round(to: 0), 1.0)
        XCTAssertEqual(doubleWithZeroDecimal.round(to: 0), 1.0)
    }
    
    func testRoundToOneDecimal() {
        XCTAssertEqual(zero.round(to: 1), 0.0)
        XCTAssertEqual(pi.round(to: 1), 3.1)
        XCTAssertEqual(basicDouble.round(to: 1), 1.2)
        XCTAssertEqual(doubleWithDecimalGreaterThan5.round(to: 1), 3.6)
        XCTAssertEqual(doubleWithNines.round(to: 1), 1.0)
        XCTAssertEqual(doubleWithZeroDecimal.round(to: 1), 1.0)
    }
    
    func testRoundToTwoDecimal() {
        XCTAssertEqual(zero.round(to: 2), 0.0)
        XCTAssertEqual(pi.round(to: 2), 3.14)
        XCTAssertEqual(basicDouble.round(to: 2), 1.23)
        XCTAssertEqual(doubleWithDecimalGreaterThan5.round(to: 2), 3.57)
        XCTAssertEqual(doubleWithNines.round(to: 2), 1.00)
        XCTAssertEqual(doubleWithZeroDecimal.round(to: 2), 1.00)
    }
    
    func testRoundToThreeDecimal() {
        XCTAssertEqual(zero.round(to: 3), 0.0)
        XCTAssertEqual(pi.round(to: 3), 3.142)
        XCTAssertEqual(basicDouble.round(to: 3), 1.235)
        XCTAssertEqual(doubleWithDecimalGreaterThan5.round(to: 3), 3.568)
        XCTAssertEqual(doubleWithNines.round(to: 3), 1.000)
        XCTAssertEqual(doubleWithZeroDecimal.round(to: 3), 1.000)
    }
}
