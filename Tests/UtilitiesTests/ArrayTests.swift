//
//  ArrayTests.swift
//  
//
//  Created by JOHN ZZN on 11/4/23.
//

import XCTest
@testable import LCLPing

final class ArrayTests: XCTestCase {
    
    func testMedianEmptyArray() {
        let a: [PingResult] = []
        XCTAssertEqual(a.median, 0)
    }
    
    func testAvgEmptyArray() {
        let a: [PingResult] = []
        XCTAssertEqual(a.avg, 0.0)
    }
    
    func testAvgSingleItemArray() {
        let a: [PingResult] = [.init(seqNum: 1, latency: 1.0, timestamp: 1)]
        XCTAssertEqual(a.avg, 1.0)
    }
    
    func testAvg() {
        let basicEvenLength: [PingResult] = [
            .init(seqNum: 0, latency: 1, timestamp: 0),
            .init(seqNum: 1, latency: 2, timestamp: 1),
            .init(seqNum: 2, latency: 3, timestamp: 2),
            .init(seqNum: 3, latency: 4, timestamp: 3),
            .init(seqNum: 4, latency: 5, timestamp: 4),
            .init(seqNum: 5, latency: 6, timestamp: 5)
        ]
        
        let basicOddLength: [PingResult] = [
            .init(seqNum: 0, latency: 1, timestamp: 0),
            .init(seqNum: 2, latency: 3, timestamp: 2),
            .init(seqNum: 4, latency: 5, timestamp: 4),
        ]
        
        let equalLatency: [PingResult] = [
            .init(seqNum: 0, latency: 2, timestamp: 1),
            .init(seqNum: 1, latency: 2, timestamp: 1),
            .init(seqNum: 2, latency: 2, timestamp: 2),
            .init(seqNum: 3, latency: 2, timestamp: 3)
        ]
        
        let random: [PingResult] = [
            .init(seqNum: 0, latency: 12, timestamp: 1),
            .init(seqNum: 6, latency: 54, timestamp: 1),
            .init(seqNum: 5, latency: 2, timestamp: 5),
            .init(seqNum: 3, latency: 4, timestamp: 2),
            .init(seqNum: 2, latency: 1, timestamp: 3),
            .init(seqNum: 1, latency: 100, timestamp: 4)
        ]
        
        XCTAssertEqual(basicEvenLength.avg, 3.5)
        XCTAssertEqual(basicOddLength.avg, 3)
        XCTAssertEqual(equalLatency.avg, 2)
        XCTAssertEqual(random.avg, 28.83, accuracy: 0.01)
    }

    func testMedianEvenLength() {
        let basic: [PingResult] = [
            .init(seqNum: 0, latency: 1, timestamp: 0),
            .init(seqNum: 1, latency: 2, timestamp: 1),
            .init(seqNum: 2, latency: 3, timestamp: 2),
            .init(seqNum: 3, latency: 4, timestamp: 3),
            .init(seqNum: 4, latency: 5, timestamp: 4),
            .init(seqNum: 5, latency: 6, timestamp: 5)
        ]
        
        let equalLatency: [PingResult] = [
            .init(seqNum: 0, latency: 2, timestamp: 1),
            .init(seqNum: 1, latency: 2, timestamp: 1),
            .init(seqNum: 2, latency: 2, timestamp: 2),
            .init(seqNum: 3, latency: 2, timestamp: 3)
        ]
        
        let reversed: [PingResult] = [
            .init(seqNum: 0, latency: 5, timestamp: 1),
            .init(seqNum: 1, latency: 4, timestamp: 1),
            .init(seqNum: 2, latency: 3, timestamp: 2),
            .init(seqNum: 3, latency: 2, timestamp: 3),
            .init(seqNum: 4, latency: 1, timestamp: 4),
            .init(seqNum: 5, latency: 0, timestamp: 5)
        ]
        
        let random: [PingResult] = [
            .init(seqNum: 0, latency: 12, timestamp: 1),
            .init(seqNum: 6, latency: 54, timestamp: 1),
            .init(seqNum: 5, latency: 2, timestamp: 5),
            .init(seqNum: 3, latency: 4, timestamp: 2),
            .init(seqNum: 2, latency: 1, timestamp: 3),
            .init(seqNum: 1, latency: 100, timestamp: 4)
        ]
        
        let short: [PingResult] = [
            .init(seqNum: 1, latency: 100, timestamp: 1),
            .init(seqNum: 2, latency: 5, timestamp: 2)
        ]
        
        XCTAssertEqual(basic.median, 3)
        XCTAssertEqual(equalLatency.median, 2)
        XCTAssertEqual(reversed.median, 2)
        XCTAssertEqual(random.median, 4)
        XCTAssertEqual(short.median, 5)
    }
    
    func testMedianOddLength() {
        let basic: [PingResult] = [
            .init(seqNum: 1, latency: 1, timestamp: 1)
        ]
        
        let equalLatency: [PingResult] = [
            .init(seqNum: 1, latency: 1, timestamp: 1),
            .init(seqNum: 2, latency: 1, timestamp: 2),
            .init(seqNum: 3, latency: 1, timestamp: 3)
        ]
        
        let ordered: [PingResult] = [
            .init(seqNum: 1, latency: 1, timestamp: 1),
            .init(seqNum: 2, latency: 2, timestamp: 2),
            .init(seqNum: 3, latency: 3, timestamp: 3),
            .init(seqNum: 4, latency: 4, timestamp: 4),
            .init(seqNum: 5, latency: 5, timestamp: 5)
            
        ]
        
        let reversed: [PingResult] = [
            .init(seqNum: 5, latency: 50, timestamp: 5),
            .init(seqNum: 4, latency: 40, timestamp: 4),
            .init(seqNum: 3, latency: 30, timestamp: 3),
            .init(seqNum: 2, latency: 20, timestamp: 2),
            .init(seqNum: 1, latency: 10, timestamp: 1)
        ]
        
        let random: [PingResult] = [
            .init(seqNum: 1, latency: 312, timestamp: 1),
            .init(seqNum: 2, latency: 64, timestamp: 2),
            .init(seqNum: 3, latency: 800, timestamp: 3),
            .init(seqNum: 4, latency: 251, timestamp: 4),
            .init(seqNum: 5, latency: 76, timestamp: 5),
            .init(seqNum: 6, latency: 2376, timestamp: 6),
            .init(seqNum: 7, latency: 12, timestamp: 7)
        ]
        
        XCTAssertEqual(basic.median, 1)
        XCTAssertEqual(equalLatency.median, 1)
        XCTAssertEqual(ordered.median, 3)
        XCTAssertEqual(reversed.median, 30)
        XCTAssertEqual(random.median, 251)
    }
    
    
}
