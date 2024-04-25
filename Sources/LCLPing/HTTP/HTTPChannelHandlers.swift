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

import Foundation
import Collections
import NIO
import NIOCore
import NIOHTTP1

internal final class HTTPDuplexer: ChannelDuplexHandler {
    typealias InboundIn = LatencyEntry
    typealias InboundOut = PingResponse
    typealias OutboundIn = HTTPOutboundIn
    typealias OutboundOut = (UInt16, HTTPRequestHead) // sequence number, HTTP Request

    private enum State {
        case operational
        case error
        case inactive

        var isOperational: Bool {
            switch self {
            case .operational:
                return true
            case .error, .inactive:
                return false
            }
        }
    }

    private var state: State

    private let url: URL
    private let configuration: LCLPing.PingConfiguration
    private let httpOptions: LCLPing.PingConfiguration.HTTPOptions

    init(url: URL, httpOptions: LCLPing.PingConfiguration.HTTPOptions, configuration: LCLPing.PingConfiguration) {
        self.url = url
        self.httpOptions = httpOptions
        self.configuration = configuration
        self.state = .inactive
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[HTTPDuplexer][\(#function)]: Channel already active")
            break
        case .error:
            assertionFailure("[HTTPDuplexer][\(#function)] in an incorrect state: \(state)")
        case .inactive:
            logger.debug("[HTTPDuplexer][\(#function)]: Channel active")
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            self.state = .inactive
            logger.debug("[HTTPDuplexer][\(#function)]: Channel inactive")
        case .error:
            break
        case .inactive:
            logger.error("[HTTPDuplexer][\(#function)]: received inactive signal when channel is already in inactive state.")
            assertionFailure("[HTTPDuplexer][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let sequenceNumber = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            context.fireChannelRead(self.wrapInboundOut(.error(sequenceNumber, ChannelError.ioOnClosedChannel)))
            return
        }

        var header = HTTPHeaders(self.httpOptions.httpHeaders.map { ($0.key, $0.value) })
        if !self.httpOptions.httpHeaders.keys.contains("Host"), let host = self.url.host {
            header.add(name: "Host", value: host)
        }

        logger.debug("[HTTPDuplexer]: Header is \(header)")
        logger.debug("[HTTPDuplexer]: url is \(self.url.absoluteString)")

        let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: url.path.isEmpty ? "/" : url.path, headers: header)
        context.write(self.wrapOutboundOut((sequenceNumber, requestHead)), promise: promise)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let latencyEntry = self.unwrapInboundIn(data)
        guard self.state.isOperational else {
            logger.debug("[HTTPDuplexer][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        switch latencyEntry.latencyStatus {
        case .finished:
            let latency = (latencyEntry.responseEnd - latencyEntry.requestStart) * 1000.0 - latencyEntry.serverTiming
            context.fireChannelRead(self.wrapInboundOut(.ok(latencyEntry.seqNum, latency, Date.currentTimestamp)))
        case .timeout:
            context.fireChannelRead(self.wrapInboundOut(.timeout(latencyEntry.seqNum)))
        case .error(let statusCode):
            switch statusCode {
            case 200...299:
                self.state = .error
                fatalError("[HTTPDuplexer]: HTTP Handler in some error state while the status code is \(statusCode). Please report this to the developer")
            case 300...399:
                context.fireChannelRead(self.wrapInboundOut(.error(latencyEntry.seqNum, PingError.httpRedirect)))
            case 400...499:
                context.fireChannelRead(self.wrapInboundOut(.error(latencyEntry.seqNum, PingError.httpClientError)))
            case 500...599:
                context.fireChannelRead(self.wrapInboundOut(.error(latencyEntry.seqNum, PingError.httpServerError)))
            default:
                context.fireChannelRead(self.wrapInboundOut(.error(latencyEntry.seqNum, PingError.httpUnknownStatus(statusCode))))
            }
        case .waiting:
            self.state = .error
            context.fireChannelRead(self.wrapInboundOut(.error(latencyEntry.seqNum, PingError.invalidLatencyResponseState)))
        }

        context.channel.close(mode: .all, promise: nil)
        logger.debug("[HTTPDuplexer][\(#function)]: Closing all channels ... because packet #\(latencyEntry.seqNum) done")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[HTTPDuplexer]: already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        let pingResponse: PingResponse = .error(nil, error)
        context.fireChannelRead(self.wrapInboundOut(pingResponse))
        context.channel.close(mode: .all, promise: nil)
    }
}

internal final class HTTPTracingHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = LatencyEntry // latency
    typealias OutboundIn = (UInt16, HTTPRequestHead) // seqNum, HTTP Request
    typealias OutboundOut = HTTPClientRequestPart

    private enum State {
        case operational
        case error
        case inactive

        var isOperational: Bool {
            switch self {
            case .operational:
                return true
            case .error, .inactive:
                return false
            }
        }
    }

    private var state: State

    private let configuration: LCLPing.PingConfiguration
    private let httpOptions: LCLPing.PingConfiguration.HTTPOptions
    private var latencyEntry: LatencyEntry?
    private var timerScheduler: TimerScheduler<UInt16>

    init(configuration: LCLPing.PingConfiguration, httpOptions: LCLPing.PingConfiguration.HTTPOptions) {
        self.configuration = configuration
        self.httpOptions = httpOptions
        self.timerScheduler = TimerScheduler()
        self.state = .inactive
    }

    func channelActive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            break
        case .error:
            logger.error("[HTTPTracingHandler][\(#function)]: in an incorrect state: \(self.state)")
            assertionFailure("[\(#function)]: in an incorrect state: \(self.state)")
        case .inactive:
            logger.debug("[HTTPTracingHandler][\(#function)]: Channel active")
            context.fireChannelActive()
            self.state = .operational
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .operational:
            logger.debug("[HTTPTracingHandler][\(#function)]: Channel inactive")
            context.fireChannelInactive()
            self.state = .inactive
        case .error:
            break
        case .inactive:
            logger.error("[HTTPTracingHandler][\(#function)]: received inactive signal when channel is already in inactive state.")
            assertionFailure("[HTTPTracingHandler][\(#function)]: received inactive signal when channel is already in inactive state.")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (sequenceNum, httpRequest) = self.unwrapOutboundIn(data)
        guard self.state.isOperational else {
            logger.error("[HTTPTracingHandler][\(#function)]: error: IO on closed channel")
            context.fireErrorCaught(ChannelError.ioOnClosedChannel)
            return
        }

        var le = LatencyEntry(seqNum: sequenceNum)
        le.requestStart = Date.currentTimestamp
        self.latencyEntry = le
        context.write(self.wrapOutboundOut(.head(httpRequest)), promise: promise)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)

        timerScheduler.schedule(delay: self.configuration.timeout, key: sequenceNum) { [weak self, context] in
            if let self = self, var le = self.latencyEntry {
                context.eventLoop.execute {
                    logger.debug("[HTTPTracingHandler][\(#function)]: packet #\(le.seqNum) timed out")
                    le.latencyStatus = .timeout
                    context.fireChannelRead(self.wrapInboundOut(le))
                    return
                }
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            logger.debug("[HTTPTracingHandler][\(#function)]: drop data: \(data) because channel is not in operational state")
            return
        }

        let httpResponse: HTTPClientResponsePart = self.unwrapInboundIn(data)
        if self.latencyEntry == nil {
            self.state = .error
            context.fireErrorCaught(PingError.httpNoMatchingRequest)
            return
        }

        switch httpResponse {
        case .head(let responseHead):
            let statusCode = responseHead.status.code
            switch statusCode {
            case 200...299:
                self.latencyEntry!.responseStart = Date.currentTimestamp
                if httpOptions.useServerTiming {
                    self.latencyEntry!.serverTiming = responseHead.headers.contains(name: "Server-Timing") ? matchServerTiming(field: responseHead.headers.first(name: "Server-Timing")!) : estimatedServerTiming
                }
            case 300...599:
                self.latencyEntry!.latencyStatus = .error(statusCode)
            default:
                self.latencyEntry!.latencyStatus = .error(statusCode)
            }
        case .body:
            break
        case .end:
            if self.latencyEntry == nil {
                self.state = .error
                context.fireErrorCaught(PingError.httpNoMatchingRequest)
                return
            }

            self.timerScheduler.remove(key: self.latencyEntry!.seqNum)
            self.latencyEntry!.responseEnd = Date.currentTimestamp
            if self.latencyEntry!.latencyStatus == .waiting {
                self.latencyEntry!.latencyStatus = .finished
            }
            context.fireChannelRead(self.wrapInboundOut(self.latencyEntry!))
            self.latencyEntry = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            logger.debug("[HTTPTracingHandler]: already in error state. ignore error \(error)")
            return
        }
        self.state = .error
        context.fireErrorCaught(error)
    }
}

#if os(macOS) || os(iOS)
internal final class HTTPHandler: NSObject {
    init(useServerTiming: Bool) {
        self.useServerTiming = useServerTiming
        super.init()
    }

    private let useServerTiming: Bool

    private var task: Task<(), Never>?

    private var session: URLSession?
    private var taskToSeqNum: [Int: UInt16] = [:]
    private var taskToLatency: [Int: Double?] = [:]
    private var userConfiguration: LCLPing.PingConfiguration?

    private var continuation: AsyncStream<PingResponse>.Continuation?

    func execute(configuration: LCLPing.PingConfiguration) async throws -> AsyncStream<PingResponse> {
        self.userConfiguration = configuration
        let urlsessionConfig: URLSessionConfiguration = .ephemeral
        urlsessionConfig.timeoutIntervalForRequest = configuration.timeout
        urlsessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: urlsessionConfig, delegate: self, delegateQueue: nil)

        let request: URLRequest
        switch configuration.endpoint {
        case .ipv4(let url, let port):
            guard let url = prepareURL(url: url, port: port) else {
                cancel()
                throw PingError.invalidIPv4URL
            }

            // probe the server to see if it supports `Server-Timing`
            if useServerTiming {
                switch await probe(url: url) {
                case .failure(let error):
                    cancel()
                    throw error
                default:
                    break
                }
            }

            request = prepareRequest(url: url)
        case .ipv6(let url):
            guard let url = prepareURL(url: url, port: nil) else {
                cancel()
                throw PingError.invalidIPv6URL
            }

            // probe the server to see if it supports `Server-Timing`
            if useServerTiming {
                switch await probe(url: url) {
                case .failure(let error):
                    cancel()
                    throw error
                default:
                    break
                }
            }

            request = prepareRequest(url: url)
        }

        let stream = AsyncStream<PingResponse> { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in
                self.cancel()
            }
        }

        guard let session else {
            // TODO: change fatalError to some other error message
            fatalError("Unable to create URLSession")
        }

        let now = Date()
        for cnt in 0..<configuration.count {
            session.delegateQueue.schedule(after: .init(now + configuration.interval * Double(cnt)), tolerance: .microseconds(100), options: nil) {
                let dataTask = session.dataTask(with: request)
                let taskIdentifier = dataTask.taskIdentifier
                self.taskToSeqNum[taskIdentifier] = cnt
                dataTask.resume()
            }
        }

        return stream
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }
}

extension HTTPHandler {

    /// Probe the given URL to check if the remote server supports `Server-Timing` attribute
    ///
    /// - Parameters:
    ///     - url: the URL of the server to probe
    /// - Returns: success if the remote server supports Server-Timing attribute; failure otherwise
    private func probe(url: URL) async -> Result<Void, PingError> {
        if let session = session {
            do {
                let (_, response) = try await session.data(from: url)
                let httpResponse = response as! HTTPURLResponse
                switch httpResponse.statusCode {
                case 200...299:
                    if let _ = httpResponse.value(forHTTPHeaderField: "Server-Timing") {
                        return .success(())
                    } else {
                        return .failure(.operationNotSupported("ServerTiming not support on server at host \(url.absoluteString)"))
                    }
                default:
                    return .failure(.httpRequestFailed(httpResponse.statusCode))
                }
            } catch {
                logger.debug("Unable to connect to host: \(error)")
                return .failure(.hostConnectionError(error))
            }
        } else {
            return .failure(.invalidHTTPSession)
        }
    }

    /// Create an URL object from the given URL string and optional port number
    ///
    /// - Parameters:
    ///     - url: the URL string that will be converted to an URL object
    ///     - port: the port number that the client should connect to
    /// - Returns: an URL object id `url` string and `port` are valid; `nil` otherwise
    private func prepareURL(url: String, port: UInt16?) -> URL? {
        var urlString = url
        if let port = port {
            urlString += ":\(port)"
        }
        guard let requestURL: URL = URL(string: urlString) else {
            return nil
        }
        return requestURL
    }

    /// Create URLRequest object given the `url`
    ///
    /// - Parameters:
    ///     - url: the `URL` object that will be used to create the `URLRequest` object
    /// - Returns: `URLRequest` object that can be used to send request using `URLSession`
    private func prepareRequest(url: URL) -> URLRequest {
        let host: String = url.host ?? ""
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allowsCellularAccess = true
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        return request
    }
}

extension HTTPHandler: URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskIdentifier = task.taskIdentifier
        if let error = error {
            let urlError = error as! URLError
            switch urlError.code {
            case .timedOut:
                logger.debug("task \(taskIdentifier) times out")
                self.continuation?.yield(.timeout(taskToSeqNum[taskIdentifier]!))
            default:
                logger.debug("task \(taskIdentifier) has error: \(urlError.localizedDescription)")
                self.continuation?.yield(.error(UInt16(taskIdentifier), urlError))
            }

        } else {
            // no error, let's check the data received
            guard let response = task.response else {
                self.continuation?.yield(.error(UInt16(taskIdentifier), PingError.httpNoResponse))
                logger.debug("request #\(taskIdentifier) doesnt have response")
                return
            }

            let statusCode = (response as! HTTPURLResponse).statusCode
            switch statusCode {
            case 200...299:
                guard taskToLatency.keys.contains(taskIdentifier) && taskToSeqNum.keys.contains(taskIdentifier) else {
                    fatalError("Unknown URLSession Datatask \(taskIdentifier)")
                }

                if let latency = taskToLatency[taskIdentifier]!, let seqNum = taskToSeqNum[taskIdentifier] {
                    self.continuation?.yield(.ok(seqNum, latency, Date.currentTimestamp))
                }
            default:
                self.continuation?.yield(.error(UInt16(taskIdentifier), PingError.httpRequestFailed(statusCode)))
            }

            // completes the async stream
            if let userConfiguration = self.userConfiguration, taskToSeqNum.count == userConfiguration.count {
                continuation?.finish()
                session.finishTasksAndInvalidate()
            }
        }

    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let metric = metrics.transactionMetrics.last else {
            return
        }

        let taskIdentifier = task.taskIdentifier

        let requestStart = metric.requestStartDate?.timeIntervalSince1970 ?? 0
        let responseEnd = metric.responseEndDate?.timeIntervalSince1970 ?? 0

        if !useServerTiming {
            self.taskToLatency[taskIdentifier] = (responseEnd - requestStart) * 1000.0
            return
        }

        guard let response = metric.response else {
            logger.debug("no response. maybe timeout")
            return
        }

        let httpResponse = (response as! HTTPURLResponse)

        if (200...299).contains(httpResponse.statusCode) {
            if let serverTimingField = httpResponse.value(forHTTPHeaderField: "Server-Timing") {
                let totalTiming: Double = matchServerTiming(field: serverTimingField)
                taskToLatency[taskIdentifier] = (responseEnd - requestStart) * 1000.0 - totalTiming
            } else {
                // use estimated timing
                taskToLatency[taskIdentifier] = (responseEnd - requestStart) * 1000.0 - estimatedServerTiming
            }
        } else {
            // error status code
            taskToLatency[taskIdentifier] = nil
        }
    }
}
#endif
