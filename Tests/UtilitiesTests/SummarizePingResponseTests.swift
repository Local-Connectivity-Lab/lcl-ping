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

final class SummarizePingResponseTests: XCTestCase {

    private let empty: [PingResponse] = []
    private let singleValueOk: [PingResponse] = [.ok(1, 1.1, 100)]
    private let singleValueError: [PingResponse] = [.error(1, PingError.forTestingPurposeOnly)]
    private let multipleOk: [PingResponse] = [.ok(1, 1.3, 100), .ok(2, 2.3, 101), .ok(3, 3.1, 102)]
    private let multipleOkAndError: [PingResponse] = [.ok(1, 1.3, 100), .error(2, PingError.forTestingPurposeOnly), .ok(3, 3.1, 102), .ok(4, 4.2, 103)]
    private let multpleOkAndDuplicates: [PingResponse] = [
        .ok(1, 1.3, 100),
        .duplicated(1),
        .duplicated(1),
        .duplicated(1),
        .ok(3, 3.1, 103)
    ]
    private let multipleOkAndTimeouts: [PingResponse] = [
        .ok(1, 1.3, 100),
        .timeout(2),
        .ok(3, 3.1, 103),
        .timeout(4),
        .timeout(5),
        .ok(6, 5.8, 105),
        .timeout(7)
    ]
    private let mixed: [PingResponse] = [
        .timeout(1),
        .duplicated(1),
        .ok(2, 2.2, 102),
        .duplicated(2),
        .error(3, PingError.forTestingPurposeOnly),
        .ok(4, 1.4, 104),
        .duplicated(3),
        .timeout(5),
        .ok(6, 4.2, 106),
        .ok(7, 3.6, 107),
        .duplicated(7),
        .timeout(8),
        .timeout(9),
        .ok(10, 5.9, 110)
    ]
    private let allTimeouts: [PingResponse] = [
        .timeout(1),
        .timeout(2),
        .timeout(3),
        .timeout(4),
        .timeout(5),
        .timeout(6),
        .timeout(7),
        .timeout(8)
    ]
    private let timeoutsDuplicates: [PingResponse] = [
        .timeout(1),
        .timeout(2),
        .timeout(3),
        .timeout(4),
        .timeout(1),
        .timeout(2),
        .timeout(3),
        .timeout(4),
        .timeout(1),
        .timeout(2),
        .timeout(3),
        .timeout(4)
    ]
    private let allErrors: [PingResponse] = [
        .error(1, PingError.forTestingPurposeOnly),
        .error(2, PingError.forTestingPurposeOnly),
        .error(3, PingError.forTestingPurposeOnly),
        .error(4, PingError.forTestingPurposeOnly),
        .error(5, PingError.forTestingPurposeOnly),
        .error(6, PingError.forTestingPurposeOnly)
    ]

    private let host = try! SocketAddress(ipAddress: "127.0.0.1", port: 80)

    func testEmpty() {
        let result = empty.summarize(host: host)
        let target = PingSummary(min: .zero, max: .zero, avg: .zero, median: .zero, stdDev: .zero, jitter: 0.0, details: [], totalCount: 0, timeout: Set(), duplicates: Set(), errors: Set(), ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(result, target)
    }

    func testOneValue() {
        let resultOk = singleValueOk.summarize(host: host)
        let targetOk = PingSummary(min: 1.1, max: 1.1, avg: 1.1, median: 1.1, stdDev: 0.0, jitter: 0.0, details: [.init(seqNum: 1, latency: 1.1, timestamp: 100)], totalCount: 1, timeout: Set(), duplicates: Set(), errors: [], ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)
        XCTAssertEqual(resultOk, targetOk)

        let resultError = singleValueError.summarize(host: host)
        let targetError = PingSummary(min: .zero, max: .zero, avg: .zero, median: .zero, stdDev: .zero, jitter: .zero, details: [], totalCount: 1, timeout: Set(), duplicates: Set(), errors: [.init(seqNum: 1, reason: PingError.forTestingPurposeOnly.localizedDescription)], ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)
        XCTAssertEqual(resultError, targetError)
    }

    func testMultipleOk() {
        let resultMultipleOk = multipleOk.summarize(host: host)
        let multipleOkPingResults: [PingResult] = [.init(seqNum: 1, latency: 1.3, timestamp: 100), .init(seqNum: 2, latency: 2.3, timestamp: 101), .init(seqNum: 3, latency: 3.1, timestamp: 102)]
        let targetMultipleOk = PingSummary(min: 1.3,
                                           max: 3.1,
                                           avg: multipleOkPingResults.avg,
                                           median: 2.3,
                                           stdDev: multipleOkPingResults.stdDev,
                                           jitter: computeJitter(multipleOkPingResults),
                                           details: multipleOkPingResults,
                                           totalCount: 3,
                                           timeout: Set(),
                                           duplicates: Set(),
                                           errors: Set(),
                                           ipAddress: host.ipAddress!,
                                           port: 80,
                                           protocol: host.protocol.rawValue
        )
        XCTAssertEqual(resultMultipleOk, targetMultipleOk)

        let resultMultipleOkAndError = multipleOkAndError.summarize(host: host)
        let multipleOkAndErrorPingResults: [PingResult] = [.init(seqNum: 1, latency: 1.3, timestamp: 100), .init(seqNum: 3, latency: 3.1, timestamp: 102), .init(seqNum: 4, latency: 4.2, timestamp: 103)]
        let multipleOkAndErrorErrors: Set<PingSummary.ErrorSummary> = [
            .init(seqNum: 2, reason: PingError.forTestingPurposeOnly.localizedDescription)
        ]
        let targetMultipleOkAndError = PingSummary(min: 1.3,
                                                   max: 4.2,
                                                   avg: multipleOkAndErrorPingResults.avg,
                                                   median: 3.1,
                                                   stdDev: multipleOkAndErrorPingResults.stdDev,
                                                   jitter: computeJitter(multipleOkAndErrorPingResults),
                                                   details: multipleOkAndErrorPingResults,
                                                   totalCount: 4,
                                                   timeout: Set(), duplicates: Set(),
                                                   errors: multipleOkAndErrorErrors,
                                                   ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)
        XCTAssertEqual(resultMultipleOkAndError, targetMultipleOkAndError)
    }

    func testMultipleOkAndDuplicates() {
        let resultMultipleOkAndDuplicates = multpleOkAndDuplicates.summarize(host: host)
        let multipleOkAndDuplicates = [
            PingResult(seqNum: 1, latency: 1.3, timestamp: 100),
            PingResult(seqNum: 3, latency: 3.1, timestamp: 103)
        ]
        let targetMultipleOkAndDuplicates = PingSummary(min: 1.3,
                                                        max: 3.1,
                                                        avg: multipleOkAndDuplicates.avg,
                                                        median: 1.3,
                                                        stdDev: multipleOkAndDuplicates.stdDev,
                                                        jitter: computeJitter(multipleOkAndDuplicates),
                                                        details: multipleOkAndDuplicates, totalCount: 2, timeout: Set(),
                                                        duplicates: Set([1]), errors: Set(),
                                                        ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultMultipleOkAndDuplicates, targetMultipleOkAndDuplicates)
    }

    func testMultipleOkAndTimeouts() {
        let resultMultipleOkAndTimeouts = multipleOkAndTimeouts.summarize(host: host)
        let multipleOkAndTimeouts = [
            PingResult(seqNum: 1, latency: 1.3, timestamp: 100),
            PingResult(seqNum: 3, latency: 3.1, timestamp: 103),
            PingResult(seqNum: 6, latency: 5.8, timestamp: 105)
        ]
        let targetMultipleOkAndTimeouts = PingSummary(min: 1.3,
                                                        max: 5.8,
                                                        avg: multipleOkAndTimeouts.avg,
                                                        median: 3.1,
                                                        stdDev: multipleOkAndTimeouts.stdDev,
                                                        jitter: computeJitter(multipleOkAndTimeouts),
                                                        details: multipleOkAndTimeouts, totalCount: 7, timeout: Set([2, 4, 5, 7]),
                                                      duplicates: Set(), errors: Set(),
                                                        ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultMultipleOkAndTimeouts, targetMultipleOkAndTimeouts)
    }

    func testAllTimeouts() {
        let resultAllTimeouts = allTimeouts.summarize(host: host)
        let allTimeouts = [PingResult]()
        let targetAllTimeouts = PingSummary(min: .zero,
                                            max: .zero,
                                            avg: .zero,
                                            median: .zero,
                                            stdDev: .zero,
                                            jitter: .zero,
                                            details: allTimeouts,
                                            totalCount: 8,
                                            timeout: Set([1, 2, 3, 4, 5, 6, 7, 8]),
                                            duplicates: Set(), errors: Set(),
                                                        ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultAllTimeouts, targetAllTimeouts)
    }

    func testTimeoutDuplicates() {
        let resultTimeoutsDuplicates = timeoutsDuplicates.summarize(host: host)
        let timeoutsDuplicates = [PingResult]()
        let targetTimeoutsDuplicates = PingSummary(min: .zero,
                                            max: .zero,
                                            avg: .zero,
                                            median: .zero,
                                            stdDev: .zero,
                                            jitter: .zero,
                                            details: timeoutsDuplicates,
                                            totalCount: 4,
                                            timeout: Set([1, 2, 3, 4]),
                                                   duplicates: Set(), errors: Set(),
                                                        ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultTimeoutsDuplicates, targetTimeoutsDuplicates)
    }

    func testAllErrors() {
        let resultAllErrors = allErrors.summarize(host: host)
        let allErrorsPingResult = [PingResult]()
        let allErrorsErrorSummaries: Set<PingSummary.ErrorSummary> = [
            .init(seqNum: 1, reason: PingError.forTestingPurposeOnly.localizedDescription),
            .init(seqNum: 2, reason: PingError.forTestingPurposeOnly.localizedDescription),
            .init(seqNum: 3, reason: PingError.forTestingPurposeOnly.localizedDescription),
            .init(seqNum: 4, reason: PingError.forTestingPurposeOnly.localizedDescription),
            .init(seqNum: 5, reason: PingError.forTestingPurposeOnly.localizedDescription),
            .init(seqNum: 6, reason: PingError.forTestingPurposeOnly.localizedDescription)
        ]
        let targetAllErrors = PingSummary(min: .zero,
                                            max: .zero,
                                            avg: .zero,
                                            median: .zero,
                                            stdDev: .zero,
                                            jitter: .zero,
                                            details: allErrorsPingResult,
                                            totalCount: 6,
                                            timeout: Set(),
                                          duplicates: Set(), errors: allErrorsErrorSummaries,
                                                        ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultAllErrors, targetAllErrors)
    }

    func testMixedResults() {
        let resultMixed = mixed.summarize(host: host)
        let mixedPingResults: [PingResult] = [
            PingResult(seqNum: 2, latency: 2.2, timestamp: 102),
            PingResult(seqNum: 4, latency: 1.4, timestamp: 104),
            PingResult(seqNum: 6, latency: 4.2, timestamp: 106),
            PingResult(seqNum: 7, latency: 3.6, timestamp: 107),
            PingResult(seqNum: 10, latency: 5.9, timestamp: 110)
        ]
        let mixedErrorSummaries: Set<PingSummary.ErrorSummary> = [
            .init(seqNum: 3, reason: PingError.forTestingPurposeOnly.localizedDescription)
        ]
        let targetMixed = PingSummary(min: 1.4,
                                      max: 5.9,
                                      avg: mixedPingResults.avg,
                                      median: mixedPingResults.median,
                                      stdDev: mixedPingResults.stdDev,
                                      jitter: computeJitter(mixedPingResults),
                                      details: mixedPingResults,
                                      totalCount: 10,
                                      timeout: Set([1, 5, 8, 9]),
                                      duplicates: Set([1, 2, 3, 7]), errors: mixedErrorSummaries,
                                      ipAddress: host.ipAddress!, port: 80, protocol: host.protocol.rawValue)

        XCTAssertEqual(resultMixed, targetMixed)
    }

    private func computeJitter(_ pingResponse: [PingResult]) -> Double {
        if pingResponse.count == 1 || pingResponse.isEmpty {
            return 0.0
        }

        var result: Double = 0.0
        for i in 1..<pingResponse.count {
            result += abs(pingResponse[i].latency - pingResponse[i-1].latency)
        }
        return result / Double(pingResponse.count)
    }
}
