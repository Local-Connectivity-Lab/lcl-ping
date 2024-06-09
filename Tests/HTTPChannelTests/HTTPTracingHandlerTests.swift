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
import NIOEmbedded
import NIOCore
import NIOHTTP1
import NIOTestUtils
@testable import LCLPing

final class HTTPTracingHandlerTests: XCTestCase {

    private var channel: EmbeddedChannel!
    private var loop: EmbeddedEventLoop {
        return self.channel.embeddedEventLoop
    }

    override func setUp() {
        self.channel = EmbeddedChannel()
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.channel?.finish(acceptAlreadyClosed: true))
        channel = nil
    }

    func testAddHTTPTracingChannelHandler() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(10)
        )
        let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
        let handler = HTTPHandler(promise: promise)
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
        channel.pipeline.fireChannelActive()
        promise.fail(PingError.forTestingPurposeOnly)
    }

    func testBasicWrite() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(10)
        )
        let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
        let handler = HTTPHandler(promise: promise)
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
        channel.pipeline.fireChannelActive()
        let request = config.makeHTTPRequest(for: 2)
        try channel.writeOutbound(request)
        self.loop.run()
        let head = try channel.readOutbound(as: HTTPClientRequestPart.self)
        XCTAssertNotNil(head)
        let end = try channel.readOutbound(as: HTTPClientRequestPart.self)
        XCTAssertNotNil(end)

        switch (head!, end!) {
        case (.head(let request), .end(_)):
            XCTAssertEqual(request.version, HTTPVersion.http1_1)
            XCTAssertEqual(request.method, HTTPMethod.GET)
            XCTAssertEqual(request.uri, config.url.uri)
            XCTAssertEqual(request.headers, config.httpHeaders)
        default:
            XCTFail("Should receive a head and end. But received head = \(String(describing: head)), end = \(String(describing: end))")
        }
    }

    func testBasicRead() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(10)
        )
        let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
        let handler = HTTPHandler(promise: promise)
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
        channel.pipeline.fireChannelActive()
        let httpRequest = config.makeHTTPRequest(for: 2)
        try channel.writeOutbound(httpRequest)

        let httpResponse = HTTPClientResponsePart.head(HTTPResponseHead(version: .http1_1, status: .ok))
        try channel.writeInbound(httpResponse)
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        self.loop.run()
        let result = try promise.futureResult.wait()
        switch result {
        case .ok(let seqNum, _, _):
            XCTAssertEqual(seqNum, 2)
        default:
            XCTFail("Invalid result: \(result)")
        }
    }

    func testReadWithoutWrite() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(2)
        )
        let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
        let eventCounter = EventCounterHandler()
        XCTAssertNoThrow(try channel.pipeline.addHandler(eventCounter).wait())
        let handler = HTTPHandler(promise: promise)
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())

        channel.pipeline.fireChannelActive()
        let head = HTTPClientResponsePart.head(HTTPResponseHead(version: .http1_1, status: .ok))
        let end = HTTPClientResponsePart.end(nil)
        try channel.writeInbound(head)
        XCTAssertNoThrow(try channel.writeInbound(end))
        XCTAssertEqual(2, eventCounter.channelReadCalls)
        self.loop.run()
        promise.futureResult.whenComplete { result in
            switch result {
            case .success:
                XCTFail("Promise should not return successful result")
            case .failure(let failure):
                let expectedError = PingError.httpInvalidHandlerState
                XCTAssertEqual(expectedError.localizedDescription, failure.localizedDescription)
            }
        }
    }

    func testReadCorrectStatusCode() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(2)
        )

        let pairs: [(UInt16, HTTPResponseStatus, Int)] = [
            (1, .ok, 200),
            (2, .movedPermanently, 301),
            (3, .badRequest, 400),
            (4, .unauthorized, 401),
            (5, .forbidden, 403),
            (6, .notFound, 404),
            (7, .requestTimeout, 408),
            (8, .internalServerError, 500),
            (9, .badGateway, 502),
            (10, .serviceUnavailable, 503),
            (11, .gatewayTimeout, 504),
            (12, .httpVersionNotSupported, 505),
            (13, .networkAuthenticationRequired, 511)
        ]

        for pair in pairs {
            channel = EmbeddedChannel()
            let (seqNum, responseStatus, responseCode) = pair
            let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
            let handler = HTTPHandler(promise: promise)
            XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
            channel.pipeline.fireChannelActive()
            let httpRequest = config.makeHTTPRequest(for: seqNum)
            let httpResponseHead = HTTPClientResponsePart.head(.init(version: .http1_1, status: responseStatus))
            let httpResponseEnd = HTTPClientResponsePart.end(nil)
            try channel.writeOutbound(httpRequest)
            try channel.writeInbound(httpResponseHead)
            try channel.writeInbound(httpResponseEnd)

            self.loop.run()
            do {
                let result = try promise.futureResult.wait()
                switch result {
                case .ok(let seq, let latency, _):
                    if seq == 1 {
                        XCTAssertEqual(seq, seqNum)
                        XCTAssertLessThan(latency, 1, "#\(seqNum) failed")
                    } else {
                        XCTFail("# \(seq) failed due to incorrect result state. Should receive error")
                    }
                case .error(.some(let seq), .some(let error)):
                    if seqNum == 1 {
                        XCTFail("# \(seqNum) failed due to incorrect result state. Should receive ok")
                    } else {
                        XCTAssertEqual(seq, seqNum)
                        let expectedError = PingError.httpInvalidResponseStatusCode(responseCode)
                        print("error as ping error: \(error as! PingError)")
                        XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription, "#\(seqNum) failed")
                    }
                default:
                    XCTFail("Incorrect result state: \(result)")
                }
            } catch {
                XCTFail("Should not throw error: \(error)")
            }
            _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
        }
    }

    func testReadWithServerTimingEnabled() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(2),
            useServerTiming: true
        )

        let parameters: [(UInt16, HTTPHeaders, Double)] = [
            (1, [:], estimatedServerTiming),
            (2, ["Server-Timing": "cpu;dur=2.4"], 2.4),
            (3, ["Server-Timing": "db;dur=36.4, app;dur=47.2"], 83.6),
            (4, ["Server-Timing": "total;dur="], estimatedServerTiming),
            (5, ["Server-Timing": "a;dur=1.1, b;dur=2.2; c;dur=3.3, d;dur=4.4, e;dur=5.5, f;dur=6.6, g;dur=7.7, h;dur=8.8, i;dur=9.9"], 49.5)
        ]

        let httpResponseEnd = HTTPClientResponsePart.end(nil)
        for parameter in parameters {
            channel = EmbeddedChannel()
            let (seqNum, httpHeader, serverTiming) = parameter
            let httpRequest = config.makeHTTPRequest(for: seqNum)
            let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
            let handler = HTTPHandler(useServerTiming: config.useServerTiming, promise: promise)
            XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
            channel.pipeline.fireChannelActive()
            let httpResponseHead = HTTPClientResponsePart.head(.init(version: .http1_1, status: .ok, headers: httpHeader))
            try channel.writeOutbound(httpRequest)
            try channel.writeInbound(httpResponseHead)
            try channel.writeInbound(httpResponseEnd)

            self.loop.run()
            let result = try promise.futureResult.wait()
            switch result {

            case .ok(let seq, let latency, _):
                XCTAssertEqual(seq, seqNum)
                XCTAssertLessThanOrEqual(abs(latency), serverTiming)
            default:
                XCTFail("Invalid result state for sequence number \(seqNum)")
            }
            _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
        }
    }

    func testReadTimeout() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let config = try HTTPPingClient.Configuration(
            url: "http://127.0.0.1:8080",
            readTimeout: .seconds(1)
        )
        let promise = self.channel.eventLoop.makePromise(of: PingResponse.self)
        let handler = HTTPHandler(promise: promise)
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, handler: handler)).wait())
        channel.pipeline.fireChannelActive()
        let httpRequest = config.makeHTTPRequest(for: 1)
        let exp = XCTestExpectation(description: "Read Tiemout")
        try channel.writeOutbound(httpRequest)
        self.loop.run()
        channel.eventLoop.scheduleTask(in: .milliseconds(1500)) {
            self.loop.run()
            exp.fulfill()
        }
        self.loop.advanceTime(by: .seconds(2))
        wait(for: [exp], timeout: 2)
        let result = try promise.futureResult.wait()
        switch result {
        case .timeout(let seq):
            XCTAssertEqual(seq, 1)
        default:
            XCTFail("Invalid result state. Should receive timeout, but received \(result)")
        }
    }
}
