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

#if INTEGRATION_TEST && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || swift(>=5.7))
final class ICMPIntegrationTests: XCTestCase {

    private func runTest(
        networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected,
        rewriteHeader: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject]? = nil,
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

    func testMinorInOutPacketDrop() async throws {
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

    func testInvalidIpHeader() async throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 0, byte: 0x55)] as AnyObject
        ]

        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidIPVersion
        do {
            let (pingState, pingSummary) = try await runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTAssertEqual(pingState, .finished)
            XCTAssertNotNil(pingSummary)
            XCTAssertEqual(pingSummary!.totalCount, 1)
            XCTAssertEqual(pingSummary!.errors, [PingSummary.PingErrorSummary(seqNum: nil, reason: expectedError.localizedDescription)])

        } catch {
            XCTFail("Should not throw \(error)")
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidIPProtocol() async throws {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let addressedEnvelopRewriteHeaders: [PartialKeyPath<AddressedEnvelope<ByteBuffer>>: AnyObject] = [
            \AddressedEnvelope.data: [RewriteData(index: 9, byte: 0x02)] as AnyObject
        ]

        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidIPProtocol
        do {
            let (pingState, pingSummary) = try await runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTAssertEqual(pingState, .finished)
            XCTAssertNotNil(pingSummary)
            XCTAssertEqual(pingSummary!.totalCount, 1)
            XCTAssertEqual(pingSummary!.errors, [PingSummary.PingErrorSummary(seqNum: nil, reason: expectedError.localizedDescription)])

        } catch {
            XCTFail("Should not throw \(error)")
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testInvalidICMPTypeAndCode() async throws {
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

            let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 1)
            do {
                let (pingState, pingSummary) = try await runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
                XCTAssertEqual(pingState, .finished)
                XCTAssertNotNil(pingSummary)
                XCTAssertEqual(pingSummary!.totalCount, 1)
                XCTAssertEqual(pingSummary!.errors, [PingSummary.PingErrorSummary(seqNum: 0, reason: expectedError.localizedDescription)])

            } catch {
                XCTFail("Should not throw \(error)")
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

        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidICMPResponse
        do {
            let (pingState, pingSummary) = try await runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTAssertEqual(pingState, .finished)
            XCTAssertNotNil(pingSummary)
            XCTAssertEqual(pingSummary!.totalCount, 2) // since sequence number is invalid, no match request can be found in the history. Thus there will be two error reported
            XCTAssertEqual(pingSummary!.errors, [PingSummary.PingErrorSummary(seqNum: 512, reason: expectedError.localizedDescription)]) // os will convert from big endian to little endian (0x002 -> 0x200)
            XCTAssertEqual(pingSummary!.timeout, Set([UInt16(0)]))

        } catch {
            XCTFail("Should not throw \(error)")
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

        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 1)

        let expectedError = PingError.invalidICMPChecksum
        do {
            let (pingState, pingSummary) = try await runTest(rewriteHeader: addressedEnvelopRewriteHeaders, pingConfig: pingConfig)
            XCTAssertEqual(pingState, .finished)
            XCTAssertNotNil(pingSummary)
            XCTAssertEqual(pingSummary!.totalCount, 1)
            XCTAssertEqual(pingSummary!.errors, [PingSummary.PingErrorSummary(seqNum: 0, reason: expectedError.localizedDescription)])

        } catch {
            XCTFail("Should not throw \(error)")
        }
        #else
        XCTSkip("Skipped on Linux Platform")
        #endif
    }

    func testCancelBeforeTestStarts() async throws {
        let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 3)
        switch pingConfig.type {
        case .icmp:
            var icmpPing = ICMPPing(networkLinkConfig: networkLinkConfig, rewriteHeaders: nil)
            icmpPing.stop()
            try await icmpPing.start(with: pingConfig)
            switch icmpPing.pingStatus {
            case .cancelled:
                XCTAssertNil(icmpPing.summary)
            default:
                XCTFail("Invalid ICMP Ping state. Should be .cancelled, but is \(icmpPing.pingStatus)")
            }
        default:
            XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
        }
    }

    @MainActor
    func testCancelDuringTest() async throws {
//        throw XCTSkip("Skipped: the following test after https://github.com/apple/swift-nio/issues/2612 is fixed")
        for waitSecond in [2, 4, 5, 6, 7, 9] {
            let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
            let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 10)
            switch pingConfig.type {
            case .icmp:
                var icmpPing = ICMPPing(networkLinkConfig: networkLinkConfig, rewriteHeaders: nil)

                Task {
                    try await Task.sleep(nanoseconds: UInt64(waitSecond) * 1_000_000_000)
                    icmpPing.stop()
                }

                try await icmpPing.start(with: pingConfig)

                switch icmpPing.pingStatus {
                case .cancelled:
                    XCTAssertNotNil(icmpPing.summary?.totalCount)
                    XCTAssertLessThanOrEqual(icmpPing.summary!.totalCount, waitSecond + 1)
                    XCTAssertEqual(icmpPing.summary?.details.isEmpty, false)
                    XCTAssertEqual(icmpPing.summary?.duplicates.count, 0)
                    XCTAssertEqual(icmpPing.summary?.timeout.count, 0)
                default:
                    XCTFail("Invalid ICMP Ping state. Should be .finished, but is \(icmpPing.pingStatus)")
                }
            default:
                XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
            }
        }
    }

    func testCancelAfterTestFinishes() async throws {
        let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
        let pingConfig: LCLPing.PingConfiguration = .init(type: .icmp, endpoint: .ipv4("127.0.0.1", 0), count: 3)
        switch pingConfig.type {
        case .icmp:
            var icmpPing = ICMPPing(networkLinkConfig: networkLinkConfig, rewriteHeaders: nil)
            try await icmpPing.start(with: pingConfig)
            icmpPing.stop()
            switch icmpPing.pingStatus {
            case .finished:
                XCTAssertEqual(icmpPing.summary?.totalCount, 3)
                XCTAssertEqual(icmpPing.summary?.details.isEmpty, false)
                XCTAssertEqual(icmpPing.summary?.duplicates.count, 0)
                XCTAssertEqual(icmpPing.summary?.timeout.count, 0)
            default:
                XCTFail("Invalid ICMP Ping state. Should be .finished, but is \(icmpPing.pingStatus)")
            }
        default:
            XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
        }
    }
}
#endif
