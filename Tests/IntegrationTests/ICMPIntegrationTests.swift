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
    
    private func runTest(networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration, pingConfig: LCLPing.PingConfiguration) async throws -> (PingState, PingSummary?) {
        var icmpPing = ICMPPing(networkLinkConfig: networkLinkConfig)
        try await icmpPing.start(with: pingConfig)
        return (icmpPing.pingStatus, icmpPing.summary)
    }

    func testFullyConnectedNetwork() async throws {
        let fullyConnectedLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyConnected
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyConnectedLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.totalCount, 10)
            XCTAssertEqual(pingSummary?.details.isEmpty, false)
            XCTAssertEqual(pingSummary?.duplicates.count, 0)
            XCTAssertEqual(pingSummary?.timeout.count, 0)
            for i in 0..<10 {
                XCTAssertEqual(pingSummary?.details[i].seqNum, UInt16(i))
            }
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testFullyDisconnectedNetwork() async throws {
        let fullyConnectedLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDisconnected
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyConnectedLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            for i in 0..<10 {
                XCTAssertEqual(pingSummary?.timeout.contains(UInt16(i)), true)
            }
            XCTAssertEqual(pingSummary?.totalCount, 10)
            XCTAssertEqual(pingSummary?.details.isEmpty, true)
            XCTAssertEqual(pingSummary?.duplicates.count, 0)
            XCTAssertEqual(pingSummary?.timeout.count, 10)
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testUnknownHost() async throws {
        let fullyConnectedLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDisconnected
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("10.10.10.127", 0), count: 10)
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyConnectedLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.timeout.count, 10)
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorInOutPacketDrop() async throws  {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.1, outPacketLoss: 0.1)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumInOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.4, outPacketLoss: 0.4)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorInPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.2)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.2)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumInPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.5)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.5)
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testFullyDuplicatedNetwork() async throws {
        logger.logLevel = .debug
        let fullyDuplicated = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDuplicated
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyDuplicated, pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.duplicates.count, 9) // before the last duplicate is sent, the channel is already closed.
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
}

#endif
