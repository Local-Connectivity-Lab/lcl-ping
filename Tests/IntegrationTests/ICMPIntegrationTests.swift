//
//  ICMPIntegrationTests.swift
//  
//
//  Created by JOHN ZZN on 12/12/23.
//

import XCTest
@testable import LCLPing

#if INTEGRATION_TEST
final class ICMPIntegrationTests: XCTestCase {

    func testFullyConnectedNetwork() async throws {
//        logger.logLevel = .debug
        let fullyConnectedLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyConnected
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        var icmpPing = ICMPPing(networkLinkConfig: fullyConnectedLink)
        try await icmpPing.start(with: pingConfig)
        switch icmpPing.pingStatus {
        case .finished:
            let summary = icmpPing.summary
            XCTAssertEqual(summary?.totalCount, 10)
            XCTAssertEqual(summary?.details.isEmpty, false)
            XCTAssertEqual(summary?.duplicates.count, 0)
            XCTAssertEqual(summary?.timeout.count, 0)
            for i in 0..<10 {
                XCTAssertEqual(summary?.details[i].seqNum, UInt16(i))
            }
        default:
            XCTFail("ICMP Test failed with status \(icmpPing.pingStatus)")
        }
    }
    
    func testFullyDisconnectedNetwork() async throws {
//        logger.logLevel = .debug
        let fullyConnectedLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDisconnected
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        var icmpPing = ICMPPing(networkLinkConfig: fullyConnectedLink)
        try await icmpPing.start(with: pingConfig)
        switch icmpPing.pingStatus {
        case .finished:
            let summary = icmpPing.summary
            for i in 0..<10 {
                XCTAssertEqual(summary?.timeout.contains(UInt16(i)), true)
            }
            XCTAssertEqual(summary?.totalCount, 10)
            XCTAssertEqual(summary?.details.isEmpty, true)
            XCTAssertEqual(summary?.duplicates.count, 0)
            XCTAssertEqual(summary?.timeout.count, 10)
        default:
            XCTFail("ICMP Test failed with status \(icmpPing.pingStatus)")
        }
    }
}

#endif
