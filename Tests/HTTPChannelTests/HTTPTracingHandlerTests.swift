//
//  HTTPTracingHandlerTests.swift
//  
//
//  Created by JOHN ZZN on 11/27/23.
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
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 10
        )
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
        channel.pipeline.fireChannelActive()
    }
    
    func testBasicWrite() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 10
        )
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
        channel.pipeline.fireChannelActive()
        let httpRequest = HTTPRequestHead(version: .http1_1, method: .GET, uri: "127.0.0.1:8080/")
        try channel.writeOutbound((UInt16(2), httpRequest))
        self.loop.run()
        let head = try channel.readOutbound(as: HTTPClientRequestPart.self)
        XCTAssertNotNil(head)
        let end = try channel.readOutbound(as: HTTPClientRequestPart.self)
        XCTAssertNotNil(end)
        
        switch (head!, end!) {
        case (.head(let request), .end(_)):
            XCTAssertEqual(request.version, HTTPVersion.http1_1)
            XCTAssertEqual(request.method, HTTPMethod.GET)
            XCTAssertEqual(request.uri, "127.0.0.1:8080/")
            XCTAssertEqual(request.headers, HTTPHeaders())
        default:
            XCTFail("Should receive a head and end. But received head = \(String(describing: head)), end = \(String(describing: end))")
        }
    }
    
    func testBasicRead() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 10
        )
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
        channel.pipeline.fireChannelActive()
        let httpRequest = HTTPRequestHead(version: .http1_1, method: .GET, uri: "127.0.0.1:8080/")
        try channel.writeOutbound((UInt16(2), httpRequest))
        
        
        let httpResponse = HTTPClientResponsePart.head(HTTPResponseHead(version: .http1_1, status: .ok))
        try channel.writeInbound(httpResponse)
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        self.loop.run()
        let latencyEntry = try channel.readInbound(as: LatencyEntry.self)
        XCTAssertNotNil(latencyEntry)
        XCTAssertEqual(latencyEntry!.latencyStatus, .finished)
        XCTAssertEqual(latencyEntry!.seqNum, 2)
    }
    
    
//    func testWriteOnClosedChannel() throws {
//        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
//        let config = LCLPing.PingConfiguration(
//            type: .http(httpOptions),
//            endpoint: .ipv4("127.0.0.1", 8080),
//            timeout: 10
//        )
//        XCTAssertNoThrow(try channel.pipeline.addHandler(EventCounterHandler()).wait())
//        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
//
//        let httpRequest = HTTPRequestHead(version: .http1_1, method: .GET, uri: "127.0.0.1:8080/")
//        XCTAssertThrowsError(try channel.writeOutbound((UInt16(2), httpRequest)))
//        self.loop.run()
////        channel.pipeline.fireChannelActive()
//    }
    
    func testReadWithoutWrite() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 2
        )
        let expectedError: PingError = .httpNoMatchingRequest
        let eventCounter = EventCounterHandler()
        XCTAssertNoThrow(try channel.pipeline.addHandler(eventCounter).wait())
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
        channel.pipeline.fireChannelActive()
        let head = HTTPClientResponsePart.head(HTTPResponseHead(version: .http1_1, status: .ok))
        let end = HTTPClientResponsePart.end(nil)
        XCTAssertThrowsError(try channel.writeInbound(head)) { error in
            XCTAssertEqual(error.localizedDescription, expectedError.localizedDescription)
        }
        XCTAssertNoThrow(try channel.writeInbound(end))
        XCTAssertEqual(2, eventCounter.channelReadCalls)
        self.loop.run()
    }
    
    func testReadCorrectStatusCode() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 2
        )
        
        
        let pairs: [(UInt16, HTTPResponseStatus, LatencyEntry.Status)] = [
            (1, .ok, .finished),
            (2, .movedPermanently, .error(301)),
            (3, .badRequest, .error(400)),
            (4, .unauthorized, .error(401)),
            (5, .forbidden, .error(403)),
            (6, .notFound,.error(404)),
            (7, .requestTimeout, .error(408)),
            (8, .internalServerError, .error(500)),
            (9, .badGateway, .error(502)),
            (10, .serviceUnavailable, .error(503)),
            (11, .gatewayTimeout, .error(504)),
            (12, .httpVersionNotSupported, .error(505)),
            (13, .networkAuthenticationRequired, .error(511))
        ]
        
        for pair in pairs {
            channel = EmbeddedChannel()
            let (seqNum, responseStatus, latencyStatus) = pair
            XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: config, httpOptions: httpOptions)).wait())
            channel.pipeline.fireChannelActive()
            let httpRequest = HTTPRequestHead(version: .http1_1, method: .GET, uri: "127.0.0.1:8080/")
            let httpResponseHead = HTTPClientResponsePart.head(.init(version: .http1_1, status: responseStatus))
            let httpResponseEnd = HTTPClientResponsePart.end(nil)
            try channel.writeOutbound((seqNum, httpRequest))
            try channel.writeInbound(httpResponseHead)
            try channel.writeInbound(httpResponseEnd)
            
            self.loop.run()
            let latency = try channel.readInbound(as: LatencyEntry.self)
            XCTAssertNotNil(latency, "#\(seqNum) failed")
            XCTAssertEqual(latency!.latencyStatus, latencyStatus, "#\(seqNum) failed")
            XCTAssertEqual(latency!.seqNum, seqNum, "#\(seqNum) failed")
            XCTAssertEqual(latency!.serverTiming, 0.0, "#\(seqNum) failed")
            XCTAssertLessThan(latency!.responseEnd - latency!.requestStart, 0.1, "#\(seqNum) failed")
            let _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
        }
    }
    
    func testReadWithServerTimingEnabled() throws {
        var httpOptionsUseServerTiming = LCLPing.PingConfiguration.HTTPOptions()
        httpOptionsUseServerTiming.useServerTiming = true
        
        let configUseServerTiming = LCLPing.PingConfiguration(
            type: .http(httpOptionsUseServerTiming),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 2
        )
        
        let parameters: [(UInt16, HTTPHeaders, Double)] = [
            (1, [:], estimatedServerTiming),
            (2, ["Server-Timing": "cpu;dur=2.4"], 2.4),
            (3, ["Server-Timing": "db;dur=36.4, app;dur=47.2"], 83.6),
            (4, ["Server-Timing": "total;dur="], 0.0),
            (5, ["Server-Timing": "a;dur=1.1, b;dur=2.2; c;dur=3.3, d;dur=4.4, e;dur=5.5, f;dur=6.6, g;dur=7.7, h;dur=8.8, i;dur=9.9"], 49.5)
        ]
        
        let httpRequest = HTTPRequestHead(version: .http1_1, method: .GET, uri: "127.0.0.1:8080/")
        let httpResponseEnd = HTTPClientResponsePart.end(nil)
        for parameter in parameters {
            channel = EmbeddedChannel()
            let (seqNum, httpHeader, totalTime) = parameter
            XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPTracingHandler(configuration: configUseServerTiming, httpOptions: httpOptionsUseServerTiming)).wait())
            channel.pipeline.fireChannelActive()
            let httpResponseHead = HTTPClientResponsePart.head(.init(version: .http1_1, status: .ok, headers: httpHeader))
            try channel.writeOutbound((seqNum, httpRequest))
            try channel.writeInbound(httpResponseHead)
            try channel.writeInbound(httpResponseEnd)
            
            self.loop.run()
            let latency = try channel.readInbound(as: LatencyEntry.self)
            XCTAssertNotNil(latency, "#\(seqNum) failed")
            XCTAssertEqual(latency!.latencyStatus, .finished, "#\(seqNum) failed")
            XCTAssertEqual(latency!.seqNum, seqNum, "#\(seqNum) failed")
            XCTAssertEqual(latency!.serverTiming, totalTime, "#\(seqNum) failed")
            let _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
        }
    }
}
