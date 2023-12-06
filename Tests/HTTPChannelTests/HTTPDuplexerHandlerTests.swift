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
import NIOEmbedded
import NIOCore
import NIOHTTP1
import NIOTestUtils
@testable import LCLPing

final class HTTPDuplexerHandlerTests: XCTestCase {
    
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

    func testAddHandler() throws {
        XCTAssertNotNil(channel, "Channel should be initialized by now but is still nil")
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4("127.0.0.1", 8080),
            timeout: 10
        )
        let url = URL(string: "http://127.0.0.1")
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(HTTPDuplexer(url: url!, httpOptions: httpOptions, configuration: config)).wait())
        channel.pipeline.fireChannelActive()
    }
    
    func testBasicWrite() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let urlString = "http://127.0.0.1"
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4(urlString, 8080),
            timeout: 10
        )
        let url = URL(string: urlString)!
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: config)).wait())
        channel.pipeline.fireChannelActive()
        let sequenceNumber: UInt16 = 2
        try channel.writeOutbound(sequenceNumber)
        self.loop.run()
        
        let outbound = try channel.readOutbound(as: (UInt16, HTTPRequestHead).self)
        XCTAssertNotNil(outbound)
        let (seqNum, httpRequestHead) = outbound!
        XCTAssertEqual(seqNum, sequenceNumber)
        XCTAssertEqual(httpRequestHead.method, .GET)
        XCTAssertEqual(httpRequestHead.version, .http1_1)
        XCTAssertEqual(httpRequestHead.uri, "/")
        XCTAssertTrue(httpRequestHead.headers.contains(name: "Host"))
        XCTAssertTrue(!httpRequestHead.headers.isEmpty)
        XCTAssertEqual(httpRequestHead.headers.first(name: "Host"), "127.0.0.1")
        XCTAssertEqual(httpRequestHead.headers.first(name: "Accept"), "application/json")
        XCTAssertEqual(httpRequestHead.headers.first(name: "User-Agent"), "lclping")
        XCTAssertEqual(httpRequestHead.headers.first(name: "Connection"), "close")
    }
    
    func testBasicRead() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let urlString = "http://127.0.0.1"
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4(urlString, 8080),
            timeout: 10
        )
        let url = URL(string: urlString)!
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: config)).wait())
        channel.pipeline.fireChannelActive()
        
        var inbound = LatencyEntry(seqNum: 2)
        inbound.latencyStatus = .finished
        inbound.requestStart = 1
        inbound.responseStart = 2
        inbound.responseEnd = 3
        try channel.writeInbound(inbound)
        self.loop.run()
        let inboundRead = try channel.readInbound(as: PingResponse.self)
        XCTAssertNotNil(inboundRead)
        switch inboundRead! {
            
        case .ok(let seqNumber, let latency, _):
            XCTAssertEqual(seqNumber, 2)
            XCTAssertEqual(latency, 2000.0)
        default:
            XCTFail("Should receive PingResponse.ok")
        }
    }
    
    func testReadCorrectPingResponseTimeout() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let urlString = "http://127.0.0.1"
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4(urlString, 8080),
            timeout: 10
        )
        let url = URL(string: urlString)!
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: config)).wait())
        channel.pipeline.fireChannelActive()
        
        var inbound = LatencyEntry(seqNum: 2)
        inbound.latencyStatus = .timeout
        try channel.writeInbound(inbound)
        self.loop.run()
        let inboundRead = try channel.readInbound(as: PingResponse.self)
        XCTAssertNotNil(inboundRead)
        switch inboundRead! {
        case .timeout(let seqNum):
            XCTAssertEqual(seqNum, 2)
        default:
            XCTFail("Should receive PingResponse.timeout")
        }
    }
    
    
    func testReadCorrectPingResponseError() throws {
        let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
        let urlString = "http://127.0.0.1"
        let config = LCLPing.PingConfiguration(
            type: .http(httpOptions),
            endpoint: .ipv4(urlString, 8080),
            timeout: 10
        )
        let url = URL(string: urlString)!
        
        let params: [(UInt, PingError)] = [
            (301, .httpRedirect),
            (404, .httpClientError),
            (500, .httpServerError),
            (601, .httpUnknownStatus(601))
        ]
        
        for param in params {
            channel = EmbeddedChannel()
            let (statusCode, expectedError) = param
            XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: httpOptions, configuration: config)).wait())
            channel.pipeline.fireChannelActive()
            var inbound = LatencyEntry(seqNum: 2)
            inbound.latencyStatus = .error(statusCode)
            try channel.writeInbound(inbound)
            self.loop.run()
            let inboundRead = try channel.readInbound(as: PingResponse.self)
            XCTAssertNotNil(inboundRead)
            switch inboundRead! {
            case .error(let error):
                XCTAssertEqual(error?.localizedDescription, expectedError.localizedDescription)
            default:
                XCTFail("Should receive PingResponse.timeout")
            }
            _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
        }
    }
    
   func testSetupHTTPHeaders() throws {
       let httpOptions = LCLPing.PingConfiguration.HTTPOptions()
       let urlString = "http://127.0.0.1"
       let config = LCLPing.PingConfiguration(
           type: .http(httpOptions),
           endpoint: .ipv4(urlString, 8080),
           timeout: 10
       )
       let url = URL(string: urlString)!
       let params: [[String:String]] = [
           [
               "A": "a",
               "B": "b",
               "C": "c"
           ],
           [:],
       ]
       for param in params {
           channel = EmbeddedChannel()
            var newHttpOptions = httpOptions
            newHttpOptions.httpHeaders = param
            XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPDuplexer(url: url, httpOptions: newHttpOptions, configuration: config)).wait())
            channel.pipeline.fireChannelActive()
            try channel.writeOutbound(UInt16(2))
            self.loop.run()
            let outboundRead = try channel.readOutbound(as: (UInt16, HTTPRequestHead).self)
            XCTAssertNotNil(outboundRead)
            let (_, httpHeader) = outboundRead!
            let target = param.isEmpty ? LCLPing.PingConfiguration.HTTPOptions.DEFAULT_HEADER : param
            for (key, val) in target {
                XCTAssertTrue(httpHeader.headers.contains(name: key))
                XCTAssertEqual(httpHeader.headers.first(name: key), val)
            }
            
            _ = try channel.finish(acceptAlreadyClosed: true)
            channel = nil
       }
   }
}
