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

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Foundation
import NIOCore

final class URLSessionClient: NSObject, Pingable {
    private let promise: EventLoopPromise<PingSummary>
    private let config: HTTPPingClient.Configuration
    private let resolvedAddress: SocketAddress
    private var results: [Int: PingResponse] = [:]
    private var taskToSeqNum: [Int: Int] = [:]
    private var taskToLatency: [Int: Double] = [:]

    private lazy var session: URLSession? = {
        let urlSessionConfig = URLSessionConfiguration.ephemeral
        urlSessionConfig.timeoutIntervalForRequest = config.connectionTimeout.second
        urlSessionConfig.timeoutIntervalForResource = config.readTimeout.second
        urlSessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: urlSessionConfig, delegate: self, delegateQueue: nil)
    }()

    init(config: HTTPPingClient.Configuration, socketAddress: SocketAddress, promise: EventLoopPromise<PingSummary>) {
        self.config = config
        self.promise = promise
        self.resolvedAddress = socketAddress
        super.init()
    }

    func start() -> EventLoopFuture<PingSummary> {
        let request = makeRequest(using: config)

        let now = Date()
        for cnt in 0..<self.config.count {
            logger.debug("Scheduled #\(cnt) request")
            self.session?.delegateQueue.schedule(after: .init(now + config.readTimeout.second * Double(cnt))) {
                guard let session = self.session else {
                    logger.debug("Session has been invalidated.")
                    return
                }
                let dataTask = session.dataTask(with: request)
                let id = dataTask.taskIdentifier
                self.taskToSeqNum[id] = cnt
                dataTask.resume()
            }
        }

        return self.promise.futureResult
    }

    func cancel() {
        self.session?.invalidateAndCancel()
        self.session = nil
        shouldCloseHandler(shouldForceClose: true)
    }

    private func makeRequest(using config: HTTPPingClient.Configuration) -> URLRequest {
        var request = URLRequest(url: config.url)
        request.httpMethod = "GET"
        config.httpHeaders.forEach { header in
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    private func shouldCloseHandler(shouldForceClose: Bool = false) {
        logger.debug("should close handelr: \(self.config.count), \(self.results.count) shouldForceclose = \(shouldForceClose)")
        if self.config.count == self.results.count || shouldForceClose {
            let summary = self.results.sorted { $0.key < $1.key }.map { $0.value }.summarize(host: self.resolvedAddress)
            self.promise.succeed(summary)
        }
    }
}

extension URLSessionClient: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        guard let seqNum = taskToSeqNum[id] else {
            self.promise.fail(PingError.httpInvalidURLSessionTask(task.taskIdentifier))
            return
        }

        if let error = error {
            let urlError = error as! URLError
            switch urlError.code {
            case .timedOut:
                self.results[id] = .timeout(id)
            default:
                self.promise.fail(urlError)
            }
        } else {
            // no error
            guard let response = task.response else {
                self.promise.fail(PingError.httpMissingResponse)
                return
            }

            guard let latency = taskToLatency[id] else {
                self.promise.fail(PingError.httpInvalidURLSessionTask(task.taskIdentifier))
                return
            }

            let statusCode = (response as! HTTPURLResponse).statusCode

            switch statusCode {
            case 200...299:
                // ok
                self.results[seqNum] = .ok(seqNum, latency, Date.currentTimestamp)
            default:
                // should report as error
                self.results[seqNum] = .error(seqNum, PingError.httpInvalidResponseStatusCode(statusCode))
            }
        }

        // close if necessary
        shouldCloseHandler()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let metric = metrics.transactionMetrics.last else {
            logger.debug("No metric collected. Exit")
            return
        }

        let id = task.taskIdentifier

        let responseStart = metric.responseStartDate?.timeIntervalSince1970 ?? 0
        let requestStart = metric.requestStartDate?.timeIntervalSince1970 ?? 0
        var latency = (responseStart - requestStart) * 1000

        if !self.config.useServerTiming {
            self.taskToLatency[id] = latency
            return
        }

        guard let response = metric.response else {
            logger.debug("No response received. Exit")
            return
        }

        let httpResponse = response as! HTTPURLResponse

        var serverTiming: Double {
            if case .some(let field) = httpResponse.value(forHTTPHeaderField: "Server-Timing") {
                return matchServerTiming(field: field)
            }

            return estimatedServerTiming
        }

        latency -= serverTiming
        self.taskToLatency[id] = latency
    }
}
#endif

extension TimeAmount {
    var second: Double {
        Double(self.nanoseconds) / 1_000_000_000.0
    }
}
