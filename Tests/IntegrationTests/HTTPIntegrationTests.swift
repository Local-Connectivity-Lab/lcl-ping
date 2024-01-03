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
final class HTTPIntegrationTests: XCTestCase {
    
    private func runTest(
        networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected,
        pingConfig: LCLPing.PingConfiguration = .init(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("http://127.0.0.1", 8080))
    ) async throws -> (PingState, PingSummary?) {
        switch pingConfig.type {
        case .http(let httpOptions):
            var httpPing = HTTPPing(httpOptions: httpOptions, networkLinkConfig: networkLinkConfig)
            try await httpPing.start(with: pingConfig)
            return (httpPing.pingStatus, httpPing.summary)
        default:
            XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
        }
        return (PingState.error, nil)
    }
    
    func testfullyConnectedNetwork() async throws {
        let (pingStatus, pingSummary) = try await runTest()
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.totalCount, 10)
            XCTAssertEqual(pingSummary?.details.isEmpty, false)
            XCTAssertEqual(pingSummary?.duplicates.count, 0)
            XCTAssertEqual(pingSummary?.timeout.count, 0)
        default:
            XCTFail("HTTP Test failed with status \(pingStatus)")
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
            XCTFail("HTTP Test failed with status \(pingStatus)")
        }
    }

    func testInvalidIPURL() async throws {
        let expectedError = PingError.invalidIPv4URL
        do {
            let pingConfig = LCLPing.PingConfiguration(type: .http(.init()), endpoint: .ipv4("ww.invalid-url.^&*", 8080))
            let _ = try await runTest(pingConfig: pingConfig)
            XCTFail("Expect throwing PingError.invalidIPv4URL")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }

    func testMissingHostInURL() async throws {
        let expectedError = PingError.httpMissingHost
        do {
            let pingConfig: LCLPing.PingConfiguration = .init(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("127.0.0.1", 8080))
            let _ = try await runTest(pingConfig: pingConfig)
            XCTFail("Expect throwing PingError.httpMissingHost")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }

    func testMissingHTTPSchemaInURL() async throws {
        let expectedError = PingError.httpMissingSchema
        do {
            let pingConfig = LCLPing.PingConfiguration(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("someOtherSchema://127.0.0.1", 8080))
            let _ = try await runTest(pingConfig: pingConfig)
            XCTFail("Expect throwing PingError.httpMissingSchema")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }

    func testUnknownHost() async throws {
        let expectedError = PingError.sendPingFailed(IOError(errnoCode: 61, reason: "connection reset (error set)"))
        let pingConfig = LCLPing.PingConfiguration(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("http://127.0.0.1", 9090))
        do {
            let _ = try await runTest(pingConfig: pingConfig)
            XCTFail("Expect throwing ")
        } catch {
            print("error: \(error)")
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }

    func testMinorInOutPacketDrop() async throws  {
        throw XCTSkip("Skipped: re-enable test after https://github.com/apple/swift-nio/issues/2612 is fixed")
        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.1, outPacketLoss: 0.1)
        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
        switch pingStatus {
        case .finished:
            ()
        default:
            XCTFail("HTTP Test failed with status \(pingStatus)")
        }
    }
    
    func testCorrectStatusCode() async throws {
        for param in [(statusCode: 200, ok: true), (statusCode: 201, ok: true), (statusCode: 301, ok: false), (statusCode: 404, ok: false), (statusCode: 410, ok: false), (statusCode: 500, ok: false), (statusCode: 505, ok: false)] {
            var httpOptions = LCLPing.PingConfiguration.HTTPOptions()
            let desiredHeaders = [
                "Status-Code": String(param.statusCode)
            ]
            httpOptions.httpHeaders = desiredHeaders
            let pingConfig: LCLPing.PingConfiguration = .init(type: .http(httpOptions), endpoint: .ipv4("http://127.0.0.1", 8080), count: 3)
            let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
            let (pingStatus, pingSummary) = try await runTest(pingConfig: pingConfig)
            switch pingStatus {
            case .finished:
                XCTAssertEqual(pingSummary?.totalCount, 3)
                if param.ok {
                    XCTAssertEqual(pingSummary?.details.count, 3)
                    pingSummary?.details.forEach { element in
                        XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
                    }
                } else {
                    XCTAssertEqual(pingSummary?.errors.count, 3)
                    switch param.statusCode {
                    case 300...399:
                        pingSummary?.errors.forEach { element in
                            XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
                            XCTAssertEqual(element.reason, PingError.httpRedirect.localizedDescription)
                        }
                    case 400...499:
                        pingSummary?.errors.forEach { element in
                            XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
                            XCTAssertEqual(element.reason, PingError.httpClientError.localizedDescription)
                        }
                    case 500...599:
                        pingSummary?.errors.forEach { element in
                            XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
                            XCTAssertEqual(element.reason, PingError.httpServerError.localizedDescription)
                        }
                    default:
                        XCTFail("HTTP Test failed with unknown status code \(param.statusCode)")
                    }
                }

            default:
                XCTFail("HTTP Test failed with status \(pingStatus)")
            }
        }
    }
    
    func testBasicServerTiming() async throws {
        var httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "False",
            "Number-Of-Metrics": "1"
        ]
        httpOptions.useServerTiming = true
        httpOptions.httpHeaders = desiredHeaders
        let pingConfig: LCLPing.PingConfiguration = .init(type: .http(httpOptions), endpoint: .ipv4("http://127.0.0.1/server-timing", 8080), count: 3)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let (pingStatus, pingSummary) = try await runTest(pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.totalCount, 3)
            XCTAssertEqual(pingSummary?.details.count, 3)
            pingSummary?.details.forEach { element in
                XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
            }
        default:
            XCTFail("HTTP Test failed with status \(pingStatus)")
        }
    }
    
    func testEmptyServerTimingField() async throws {
        var httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "True",
            "Number-Of-Metrics": "1"
        ]
        httpOptions.useServerTiming = true
        httpOptions.httpHeaders = desiredHeaders
        let pingConfig: LCLPing.PingConfiguration = .init(type: .http(httpOptions), endpoint: .ipv4("http://127.0.0.1/server-timing", 8080), count: 3)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let (pingStatus, pingSummary) = try await runTest(pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.totalCount, 3)
            XCTAssertEqual(pingSummary?.details.count, 3)
            pingSummary?.details.forEach { element in
                XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
            }
        default:
            XCTFail("HTTP Test failed with status \(pingStatus)")
        }
    }
    
    func testMultipleServerTimingFields() async throws {
        var httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "True",
            "Number-Of-Metrics": "4"
        ]
        httpOptions.useServerTiming = true
        httpOptions.httpHeaders = desiredHeaders
        let pingConfig: LCLPing.PingConfiguration = .init(type: .http(httpOptions), endpoint: .ipv4("http://127.0.0.1/server-timing", 8080), count: 3)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let (pingStatus, pingSummary) = try await runTest(pingConfig: pingConfig)
        switch pingStatus {
        case .finished:
            XCTAssertEqual(pingSummary?.totalCount, 3)
            XCTAssertEqual(pingSummary?.details.count, 3)
            pingSummary?.details.forEach { element in
                XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
            }
        default:
            XCTFail("HTTP Test failed with status \(pingStatus)")
        }
    }
    
    func testCancelBeforeTestStarts() async throws {
        let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
        let pingConfig: LCLPing.PingConfiguration = .init(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("http://127.0.0.1", 8080))
        switch pingConfig.type {
        case .http(let httpOptions):
            var httpPing = HTTPPing(httpOptions: httpOptions, networkLinkConfig: networkLinkConfig)
            httpPing.stop()
            try await httpPing.start(with: pingConfig)
            switch httpPing.pingStatus {
            case .stopped:
                XCTAssertNil(httpPing.summary)
            default:
                XCTFail("Invalid HTTP Ping state. Should be .stopped, but is \(httpPing.pingStatus)")
            }
        default:
            XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
        }
    }
    
//    @MainActor
//    func testCancelDuringTest() async throws {
//        throw XCTSkip("Skipped: the following test after https://github.com/apple/swift-nio/issues/2612 is fixed")
//        for waitSecond in [2, 4, 5, 6, 7, 9] {
//            let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
//            let pingConfig: LCLPing.PingConfiguration = .init(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("http://127.0.0.1", 8080))
//            switch pingConfig.type {
//            case .http(let httpOptions):
//                var httpPing = HTTPPing(httpOptions: httpOptions, networkLinkConfig: networkLinkConfig)
//
//                Task {
//                    try await Task.sleep(nanoseconds: UInt64(waitSecond) * 1_000_000_000)
//                    httpPing.stop()
//                }
//
//                try await httpPing.start(with: pingConfig)
//
//                switch httpPing.pingStatus {
//                case .stopped:
//                    XCTAssertNotNil(httpPing.summary?.totalCount)
//                    XCTAssertLessThanOrEqual(httpPing.summary!.totalCount, waitSecond + 1)
//                    XCTAssertEqual(httpPing.summary?.details.isEmpty, false)
//                    XCTAssertEqual(httpPing.summary?.duplicates.count, 0)
//                    XCTAssertEqual(httpPing.summary?.timeout.count, 0)
//                default:
//                    XCTFail("Invalid HTTP Ping state. Should be .finished, but is \(httpPing.pingStatus)")
//                }
//            default:
//                XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
//            }
//        }
//    }
    
    func testCancelAfterTestFinishes() async throws {
        let networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected
        let pingConfig: LCLPing.PingConfiguration = .init(type: .http(LCLPing.PingConfiguration.HTTPOptions()), endpoint: .ipv4("http://127.0.0.1", 8080), count: 3)
        switch pingConfig.type {
        case .http(let httpOptions):
            var httpPing = HTTPPing(httpOptions: httpOptions, networkLinkConfig: networkLinkConfig)
            try await httpPing.start(with: pingConfig)
            httpPing.stop()
            switch httpPing.pingStatus {
            case .finished:
                XCTAssertEqual(httpPing.summary?.totalCount, 3)
                XCTAssertEqual(httpPing.summary?.details.isEmpty, false)
                XCTAssertEqual(httpPing.summary?.duplicates.count, 0)
                XCTAssertEqual(httpPing.summary?.timeout.count, 0)
            default:
                XCTFail("Invalid HTTP Ping state. Should be .finished, but is \(httpPing.pingStatus)")
            }
        default:
            XCTFail("Invalid PingConfig. Need HTTP, but received \(pingConfig.type)")
        }
    }
    
    
    
        // FIXME: re-enable the following test after https://github.com/apple/swift-nio/issues/2612 is fixed

//    func testMediumInOutPacketDrop() async throws {
//        XCTSkip("temporarily skip the test because Deinited NIOAsyncWriter without calling finish()")
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.4, outPacketLoss: 0.4)
//        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//        case .finished:
//            ()
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testMinorInPacketDrop() async throws {
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.2)
//        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//        case .finished:
//            ()
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testMinorOutPacketDrop() async throws {
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.2)
//        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//        case .finished:
//            ()
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testMediumInPacketDrop() async throws {
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(inPacketLoss: 0.5)
//        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//        case .finished:
//            ()
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testMediumOutPacketDrop() async throws {
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration(outPacketLoss: 0.5)
//        let (pingStatus, _) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//        case .finished:
//            ()
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testFullyDuplicatedNetwork() async throws {
//        let fullyDuplicated = TrafficControllerChannelHandler.NetworkLinkConfiguration.fullyDuplicated
//        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: fullyDuplicated)
//        switch pingStatus {
//        case .finished:
//            XCTAssertEqual(pingSummary?.duplicates.count, 9) // before the last duplicate is sent, the channel is already closed.
//        default:
//            XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
//
//    func testDuplicatedNetwork() async throws {
//        let networkLink = TrafficControllerChannelHandler.NetworkLinkConfiguration.init(inDuplicate: 0.5)
//        let (pingStatus, pingSummary) = try await runTest(networkLinkConfig: networkLink)
//        switch pingStatus {
//            case .finished:
//                XCTAssertEqual(pingSummary?.duplicates.isEmpty, false)
//            default:
//                XCTFail("HTTP Test failed with status \(pingStatus)")
//        }
//    }
    
}
#endif
