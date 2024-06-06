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
import NIOCore
@testable import LCLPing

#if INTEGRATION_TEST
final class ICMPIntegrationTests: XCTestCase {

    private func runTest(
        networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected,
        rewriteHeader: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject]? = nil,
        pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0))
    ) throws -> PingSummary {
        let icmp = ICMPPingClient(networkLinkConfig: networkLinkConfig, rewriteHeaders: rewriteHeader, configuration: pingConfig)
        return try icmp.start().wait()
    }

    func testFullyConnectedNetwork() throws {
        let pingSummary = try runTest()
        XCTAssertEqual(pingSummary.totalCount, 10)
        XCTAssertEqual(pingSummary.details.isEmpty, false)
        XCTAssertEqual(pingSummary.duplicates.count, 0)
        XCTAssertEqual(pingSummary.timeout.count, 0)
        for i in 0..<10 {
            XCTAssertEqual(pingSummary.details[i].seqNum, UInt16(i))
        }
    }

    func testFullyDisconnectedNetwork() throws {
        let pingSummary = try runTest(networkLinkConfig: .fullyDisconnected)
        for i in 0..<10 {
            XCTAssertEqual(pingSummary.timeout.contains(UInt16(i)), true)
        }
        XCTAssertEqual(pingSummary.totalCount, 10)
        XCTAssertEqual(pingSummary.details.isEmpty, true)
        XCTAssertEqual(pingSummary.duplicates.count, 0)
        XCTAssertEqual(pingSummary.timeout.count, 10)
    }

    func testUnknownHost() throws {
        let newConfig = ICMPPingClient.Configuration(endpoint: .ipv4("10.10.10.127", 0), count: 10)
        let pingSummary = try runTest(pingConfig: newConfig)
        XCTAssertEqual(pingSummary.timeout.count, 10)
    }

    func testMinorInOutPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.1, outPacketLoss: 0.1)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testMediumInOutPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.4, outPacketLoss: 0.4)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testMinorInPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.2)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testMinorOutPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.2)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testMediumInPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.5)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testMediumOutPacketDrop() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.5)
        let _ = try runTest(networkLinkConfig: networkLink)
    }

    func testFullyDuplicatedNetwork() throws {
        let pingSummary = try runTest(networkLinkConfig: .fullyDuplicated)
        XCTAssertEqual(pingSummary.duplicates.count, 9) // FIXME: before the last duplicate is sent, the channel is already closed.
    }

    func testDuplicatedNetwork() throws {
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.init(inDuplicate: 0.5)
        let pingSummary = try runTest(networkLinkConfig: networkLink)
        XCTAssertEqual(pingSummary.duplicates.isEmpty, false)
    }

    func testInvalidIpHeader() throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 0, byte: 0x55)] as AnyObject
        ]
        let newConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 1)
        let expectedError = PingError.invalidIPVersion
        do {
            let _ = try runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: newConfig)
            XCTFail("Should receive invalid IP protocol error")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidIPProtocol() throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 9, byte: 0x02)] as AnyObject
        ]

        let newConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 1)
        let expectedError = PingError.invalidIPProtocol
        do {
            let _ = try runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: newConfig)
            XCTFail("Should receive invalid IP protocol error")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
        
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidICMPTypeAndCode() throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let testParams: [(Int8, Int8, PingError)] = [
            (0x3, 0x0, PingError.icmpDestinationNetworkUnreachable),
            (0x3, 0x1, PingError.icmpDestinationHostUnreachable),
            (0x3, 0x2, PingError.icmpDestinationProtocoltUnreachable),
            (0x3, 0x3, PingError.icmpDestinationPortUnreachable),
            (0x3, 0x4, PingError.icmpFragmentationRequired),
            (0x3, 0x5, PingError.icmpSourceRouteFailed),
            (0x3, 0x6, PingError.icmpUnknownDestinationNetwork),
            (0x3, 0x7, PingError.icmpUnknownDestinationHost),
            (0x3, 0x8, PingError.icmpSourceHostIsolated),
            (0x3, 0x9, PingError.icmpNetworkAdministrativelyProhibited),
            (0x3, 0xA, PingError.icmpHostAdministrativelyProhibited),
            (0x3, 0xB, PingError.icmpNetworkUnreachableForToS),
            (0x3, 0xC, PingError.icmpHostUnreachableForToS),
            (0x3, 0xD, PingError.icmpCommunicationAdministrativelyProhibited),
            (0x3, 0xE, PingError.icmpHostPrecedenceViolation),
            (0x3, 0xF, PingError.icmpPrecedenceCutoffInEffect),
            (0x5, 0x0, PingError.icmpRedirectDatagramForNetwork),
            (0x5, 0x1, PingError.icmpRedirectDatagramForHost),
            (0x5, 0x2, PingError.icmpRedirectDatagramForTosAndNetwork),
            (0x5, 0x3, PingError.icmpRedirectDatagramForTosAndHost),
            (0x9, 0x0, PingError.icmpRouterAdvertisement),
            (0xA, 0x0, PingError.icmpRouterDiscoverySelectionSolicitation),
            (0xB, 0x0, PingError.icmpTTLExpiredInTransit),
            (0xB, 0x1, PingError.icmpFragmentReassemblyTimeExceeded),
            (0xC, 0x0, PingError.icmpPointerIndicatesError),
            (0xC, 0x1, PingError.icmpMissingARequiredOption),
            (0xC, 0x2, PingError.icmpBadLength),
            (0xD, 0x9, PingError.unknownError("Received unknown ICMP type (13) and ICMP code (9)"))
        ]

        for testParam in testParams {
            let (type, code, expectedError) = testParam
            let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
                \AddressedEnvelope.data: [RewriteData(index: 20, byte: type), RewriteData(index: 21, byte: code)] as AnyObject
            ]

            let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 1)
            do {
                let pingSummary = try runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
                XCTAssertEqual(pingSummary.totalCount, 1)
                XCTAssertEqual(pingSummary.errors, [PingSummary.ErrorSummary(seqNum: 0, reason: expectedError.localizedDescription)])
            } catch {
                XCTFail("Should not throw error: \(error)")
            }
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidSequenceNumber() async throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 27, byte: 0x02)] as AnyObject
        ]

        let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidICMPResponse
        do {
            let _ = try runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTFail("Should receive invalid \(expectedError.localizedDescription)")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidChecksum() async throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 22, byte: 0x56)] as AnyObject
        ]

        let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidICMPChecksum
        do {
            let pingSummary = try runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTAssertEqual(pingSummary.totalCount, 1)
            XCTAssertEqual(pingSummary.errors, [PingSummary.ErrorSummary(seqNum: 0, reason: expectedError.localizedDescription)])
        } catch {
            XCTFail("Should not throw \(error)")
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testCancelBeforeTestStarts() throws {
        let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 3)
        let icmp = ICMPPingClient(networkLinkConfig: .fullyConnected, rewriteHeaders: nil, configuration: pingConfig)
        icmp.cancel()
    }

    func testCancelDuringTest() throws {
        for waitSecond in [2, 4, 5, 6, 7, 9] {
            let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 11)
            let icmpPing = ICMPPingClient(networkLinkConfig: .fullyConnected, rewriteHeaders: nil, configuration: pingConfig)
            
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(waitSecond)) {
                print("will cancel ping")
                icmpPing.cancel()
            }

            let summary = try icmpPing.start().wait()
            XCTAssertLessThanOrEqual(summary.totalCount, waitSecond + 1)
            XCTAssertEqual(summary.details.isEmpty, false)
            XCTAssertEqual(summary.duplicates.count, 0)
            XCTAssertEqual(summary.timeout.count, 0)
        }
    }

    func testCancelAfterTestFinishes() throws {
        let pingConfig: ICMPPingClient.Configuration = .init(endpoint: .ipv4("127.0.0.1", 0), count: 3)
        let icmpPing = ICMPPingClient(networkLinkConfig: .fullyConnected, rewriteHeaders: nil, configuration: pingConfig)
        let summary = try icmpPing.start().wait()
        icmpPing.cancel()
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.details.isEmpty, false)
        XCTAssertEqual(summary.duplicates.count, 0)
        XCTAssertEqual(summary.timeout.count, 0)
    }
}
#endif
