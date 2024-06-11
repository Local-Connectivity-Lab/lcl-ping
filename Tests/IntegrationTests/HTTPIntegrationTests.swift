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
final class HTTPIntegrationTests: XCTestCase {

    private let endpoint: String = "http://127.0.0.1:8080"

    private func createDefaultConfig() throws -> HTTPPingClient.Configuration {
        return try .init(url: endpoint)
    }

    private func runTest(
        networkLinkConfig: TrafficControllerChannelHandler.NetworkLinkConfiguration = .fullyConnected,
        pingConfig: HTTPPingClient.Configuration
    ) throws -> PingSummary {
        let httpPing = HTTPPingClient(configuration: pingConfig, networkLinkConfig: networkLinkConfig)
        return try httpPing.start().wait()
    }

    func testfullyConnectedNetwork() throws {
        let config = try createDefaultConfig()
        let pingSummary = try runTest(pingConfig: config)
        XCTAssertEqual(pingSummary.totalCount, 10)
        XCTAssertEqual(pingSummary.details.isEmpty, false)
        XCTAssertEqual(pingSummary.duplicates.count, 0)
        XCTAssertEqual(pingSummary.timeout.count, 0)
    }

    func testFullyDisconnectedNetwork() throws {
        let config = try createDefaultConfig()
        let pingSummary = try runTest(networkLinkConfig: .fullyDisconnected, pingConfig: config)
        for i in 0..<10 {
            XCTAssertTrue(pingSummary.timeout.contains(UInt16(i)))
        }
        XCTAssertEqual(pingSummary.totalCount, 10)
        XCTAssertTrue(pingSummary.details.isEmpty)
        XCTAssertEqual(pingSummary.duplicates.count, 0)
        XCTAssertEqual(pingSummary.timeout.count, 10)
    }

    func testUnknownHost() throws {
        let config = try HTTPPingClient.Configuration(url: "http://127.0.0.1:9090", count: 1, connectionTimeout: .milliseconds(10))
        do {
            _ = try runTest(pingConfig: config)
            XCTFail("Expect throwing IO error")
        } catch let error as IOError {
            print("in test error: \(error)")
        } catch {
            XCTFail("Expect throwing IO error, but throw \(error)")
        }
    }

    func testCorrectStatusCode() throws {
        for param in [(statusCode: 200, ok: true), (statusCode: 201, ok: true), (statusCode: 301, ok: false), (statusCode: 404, ok: false), (statusCode: 410, ok: false), (statusCode: 500, ok: false), (statusCode: 505, ok: false)] {
            let config = try HTTPPingClient.Configuration(url: endpoint, count: 3, headers: ["Status-Code": String(param.statusCode)])
            let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
            let pingSummary = try runTest(pingConfig: config)
            XCTAssertEqual(pingSummary.totalCount, 3)
            if param.ok {
                XCTAssertEqual(pingSummary.details.count, 3)
                pingSummary.details.forEach { element in
                    XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
                }
            } else {
                XCTAssertEqual(pingSummary.errors.count, 3)
                pingSummary.errors.forEach { element in
                    XCTAssertNotNil(element.seqNum)
                    XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum!), true)
                    XCTAssertEqual(element.reason, PingError.httpInvalidResponseStatusCode(param.statusCode).localizedDescription)
                }
            }

        }
    }

    func testBasicServerTiming() throws {
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "False",
            "Number-Of-Metrics": "1"
        ]
        let pingConfig: HTTPPingClient.Configuration = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080/server-timing", count: 3, headers: desiredHeaders, useServerTiming: true)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let pingSummary = try runTest(pingConfig: pingConfig)
        XCTAssertEqual(pingSummary.totalCount, 3)
        XCTAssertEqual(pingSummary.details.count, 3)
        pingSummary.details.forEach { element in
            XCTAssertTrue(expectedSequenceNumbers.contains(element.seqNum))
        }
    }

    func testEmptyServerTimingField() throws {
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "True",
            "Number-Of-Metrics": "1"
        ]
        let pingConfig = try  HTTPPingClient.Configuration(url: "http://127.0.0.1:8080/server-timing", count: 3, headers: desiredHeaders, useServerTiming: true)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let pingSummary = try runTest(pingConfig: pingConfig)
        XCTAssertEqual(pingSummary.totalCount, 3)
        XCTAssertEqual(pingSummary.details.count, 3)
        pingSummary.details.forEach { element in
            XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
        }
    }

    func testMultipleServerTimingFields() throws {
        let desiredHeaders = [
            "Status-Code": "200",
            "Use-Empty-Server-Timing": "True",
            "Number-Of-Metrics": "4"
        ]
        let pingConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080/server-timing", count: 3, headers: desiredHeaders, useServerTiming: true)
        let expectedSequenceNumbers: Set<UInt16> = [0, 1, 2]
        let pingSummary = try runTest(pingConfig: pingConfig)
        XCTAssertEqual(pingSummary.totalCount, 3)
        XCTAssertEqual(pingSummary.details.count, 3)
        pingSummary.details.forEach { element in
            XCTAssertEqual(expectedSequenceNumbers.contains(element.seqNum), true)
        }
    }

    func testCancelBeforeTestStarts() throws {
        let pingConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080")
        let httpPing = HTTPPingClient(configuration: pingConfig, networkLinkConfig: .fullyConnected)
        httpPing.cancel()
    }

    func testCancelDuringTest() throws {
        for waitSecond in [2, 4, 5, 6, 7, 9] {
            let pingConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080", count: 3)
            let httpPing = HTTPPingClient(configuration: pingConfig, networkLinkConfig: .fullyConnected)
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(waitSecond)) {
                print("will cancel ping")
                httpPing.cancel()
            }

            let summary = try httpPing.start().wait()
            XCTAssertLessThanOrEqual(summary.totalCount, waitSecond + 1)
            XCTAssertEqual(summary.details.isEmpty, false)
            XCTAssertEqual(summary.duplicates.count, 0)
            XCTAssertEqual(summary.timeout.count, 0)
        }
    }

    func testCancelAfterTestFinishes() throws {
        let pingConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080", count: 3)
        let httpPing = HTTPPingClient(configuration: pingConfig, networkLinkConfig: .fullyConnected)
        let summary = try httpPing.start().wait()
        httpPing.cancel()
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.details.isEmpty, false)
        XCTAssertEqual(summary.duplicates.count, 0)
        XCTAssertEqual(summary.timeout.count, 0)
    }
}
 #endif
