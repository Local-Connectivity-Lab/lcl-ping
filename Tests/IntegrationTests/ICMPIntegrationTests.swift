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
import NIOCore
@testable import LCLPing

#if INTEGRATION_TEST
final class ICMPIntegrationTests: XCTestCase {
    
    private func runTest(
        networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected,
        rewriteHeader: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>:AnyObject]? = nil,
        pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0))
    ) async throws -> (PingState, PingSummary?) {
        var icmpPing = ICMPPing(networkLinkConfig: networkLinkConfig, rewriteHeaders: rewriteHeader)
        try await icmpPing.start(with: pingConfig)
        return (icmpPing.pingStatus, icmpPing.summary)
    }

    func testFullyConnectedNetwork() async throws {
        let (pingStatus, pingSummary) = try await runTest()
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
        let fullyDisconnected = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDisconnected
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyDisconnected)
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
        let pingConfig = LCLPing.PingConfiguration(type: .icmp, endpoint: .ipv4("10.10.10.127", 0), count: 10)
        let (pingStatus, pingSummary) = try await runTest(pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.timeout.count, 10)
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorInOutPacketDrop() async throws  {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.1, outPacketLoss: 0.1)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumInOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.4, outPacketLoss: 0.4)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorInPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.2)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMinorOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.2)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumInPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.5)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testMediumOutPacketDrop() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.5)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }
    
    func testFullyDuplicatedNetwork() async throws {
        let fullyDuplicated = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDuplicated
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyDuplicated)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.duplicates.count, 9) // before the last duplicate is sent, the channel is already closed.
        default:
            XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }

    func testDuplicatedNetwork() async throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.init(inDuplicate: 0.5)
        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
            case .finished:
                XCTAssertEqual(pingSummary?.duplicates.isEmpty, false)
            default:
                XCTFail("ICMP Test failed with status \(pingStatus)")
        }
    }

    // TODO: more tests with header rewrite
    
//    func testInvalidIpHeader() async throws {
//        let ipRewriteHeaders: [PartialKeyPath<IPv4Header> : AnyObject] = [
//            \.versionAndHeaderLength: 0x55 as AnyObject,
//            \.protocol: 1 as AnyObject
//        ]
//        let expectedError = PingError.sendPingFailed(PingError.invalidIPVersion)
//        do {
//            let _ = try await runTest(ipRewriteHeader: ipRewriteHeaders)
//        } catch {
//            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
//        }
//    }
    
    // TODO: more tests on cancellation
}

#endif
