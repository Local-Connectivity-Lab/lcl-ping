//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOCore
import NIOHTTP1

final class HTTPHandler: PingHandler {

    private var latency: HTTPLatency
    private let promise: EventLoopPromise<PingResponse>
    private let useServerTiming: Bool

    init(useServerTiming: Bool = false, promise: EventLoopPromise<PingResponse>) {
        self.promise = promise
        self.latency = HTTPLatency()
        self.useServerTiming = useServerTiming
    }

    func handleRead(response: HTTPClientResponsePart) {
        switch self.latency.state {
        case .waiting:
            switch response {
            case .head(let head):
                self.latency.responseStart = Date.currentTimestamp
                let statusCode = head.status.code
                switch statusCode {
                case 200...299:
                    if self.useServerTiming {
                        self.latency.serverTiming = head.headers.contains(name: "Server-Timing")
                        ? matchServerTiming(field: head.headers.first(name: "Server-Timing")!) : estimatedServerTiming
                    }
                default:
                    print("received invalid response code: \(statusCode)")
                    self.latency.state = .error(PingError.httpInvalidResponseStatusCode(Int(statusCode)))
                }
            case .body:
                break
            case .end:
                logger.debug("[\(#fileID)][\(#line)][\(#function)]: we finish waiting all http response")
                self.latency.state = .finished
                self.latency.responseEnd = Date.currentTimestamp
                shouldCloseHandler()
            }
        case .error:
            switch response {
            case .body:
                break
            case .end:
                self.latency.responseEnd = Date.currentTimestamp
                shouldCloseHandler()
            default:
                logger.error("[\(#fileID)][\(#line)][\(#function)]: Invalid HTTP handler state: \(self.latency.state)")
                logger.error("[\(#fileID)][\(#line)][\(#function)]: current response type: \(response)")
                self.promise.fail(PingError.httpInvalidHandlerState)
            }
        default:
            logger.error("[\(#fileID)][\(#line)][\(#function)]: Invalid state: \(self.latency.state)")
            self.promise.fail(PingError.httpInvalidHandlerState)
        }
    }

    func handleWrite(request: HTTPPingClient.Request) {
        self.latency.seqNum = request.sequenceNumber
        self.latency.requestStart = Date.currentTimestamp
    }

    func handleTimeout(sequenceNumber: UInt16) {
        if sequenceNumber == self.latency.seqNum {
            self.latency.state = .timeout
            self.shouldCloseHandler()
        }
    }

    func handleError(sequenceNum: UInt16?, error: Error) {
        if let seqNum = sequenceNum, seqNum == self.latency.seqNum {
            self.latency.state = .error(error)
            self.promise.fail(error)
        } else {
            handleError(error: error)
        }
    }

    func handleError(error: Error) {
        self.latency.state = .error(error)
        self.promise.fail(error)
    }

    func handleError() {
        self.latency.state = .error(PingError.unknownError("Unknown Error"))
        self.promise.fail(PingError.unknownError("Unknown Error"))
    }

    func shouldCloseHandler(shouldForceClose: Bool = false) {
        if shouldForceClose {
            self.promise.succeed(self.makePingResponse())
            return
        }

        switch self.latency.state {
        case .finished, .timeout, .error:
            self.promise.succeed(self.makePingResponse())
        case .waiting:
            ()
        }
    }

    private func makePingResponse() -> PingResponse {
        switch self.latency.state {
        case .finished:
            let result = (self.latency.responseEnd - self.latency.requestStart) * 1000.0 - self.latency.serverTiming
            return .ok(self.latency.seqNum, result, Date.currentTimestamp)
        case .timeout:
            return .timeout(self.latency.seqNum)
        case .error(let error):
            print("ping response error: \(error as! PingError)")
            return .error(self.latency.seqNum, error)
        case .waiting:
            return .error(self.latency.seqNum, PingError.invalidLatencyResponseState)
        }
    }
}
