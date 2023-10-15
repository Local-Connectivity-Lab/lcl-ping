//
//  HTTPChannelHandlers.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation
import Collections
import NIO
import NIOCore
import NIOHTTP1


internal final class HTTPDuplexer: ChannelDuplexHandler {
    typealias InboundIn = LatencyEntry // latency entry
    typealias InboundOut = PingResponse
    typealias OutboundIn = HTTPOutboundIn
    typealias OutboundOut = (UInt16, HTTPRequestHead) // seqNum, HTTP Request
    
    private let url: URL
    private let configuration: LCLPing.Configuration
    private let httpOptions: LCLPing.Configuration.HTTPOptions
    
    init(url: URL, httpOptions: LCLPing.Configuration.HTTPOptions, configuration: LCLPing.Configuration) {
        self.url = url
        self.httpOptions = httpOptions
        self.configuration = configuration
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        print("[write] enter")
        let sequenceNumber = self.unwrapOutboundIn(data)
        print("seq number = \(sequenceNumber)")
        var header = HTTPHeaders(self.httpOptions.httpHeaders.map { ($0.key, $0.value) })
        if !self.httpOptions.httpHeaders.keys.contains("Host"), let host = self.url.host {
            header.add(name: "Host", value: host)
        }
        
        print("Header is \(header)")
        print("url is \(self.url.absoluteString)")
        print("path is \(url.path)")
        
        let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: url.path.isEmpty ? "/" : url.path, headers: header)
        context.write(self.wrapOutboundOut((sequenceNumber, requestHead)), promise: promise)
        print("[write] content written")
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("[HTTPDuplexer] read")
        let latencyEntry = self.unwrapInboundIn(data)
        print("[HTTPDuplexer] decode done")
        
        switch latencyEntry.latencyStatus {
            
        case .finished:
            let latency = (latencyEntry.responseEnd - latencyEntry.requestStart) * 1000.0
            context.fireChannelRead(self.wrapInboundOut(.ok(latencyEntry.seqNum, latency, Date.currentTimestamp)))
        case .timeout:
            context.fireChannelRead(self.wrapInboundOut(.timeout(latencyEntry.seqNum)))
        case .error(let statusCode):
            switch statusCode {
            case 200...299:
                let latency = (latencyEntry.responseEnd - latencyEntry.requestStart) * 1000.0
                context.fireChannelRead(self.wrapInboundOut(.ok(latencyEntry.seqNum, latency, Date.currentTimestamp)))
            case 300...399:
                context.fireChannelRead(self.wrapInboundOut(.error(PingError.httpRedirect)))
            case 400...499:
                context.fireChannelRead(self.wrapInboundOut(.error(PingError.httpClientError)))
            case 500...599:
                context.fireChannelRead(self.wrapInboundOut(.error(PingError.httpServerError)))
            default:
                context.fireChannelRead(self.wrapInboundOut(.error(PingError.httpUnknownStatus(statusCode))))
            }
        case .waiting:
            fatalError("Latency Entry should not be in waiting state.")
        }
        
        context.channel.close(mode: .all, promise: nil)
    }
    
//    func channelInactive(context: ChannelHandlerContext) {
//    }
}

internal final class HTTPTracingHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = LatencyEntry // latency
    typealias OutboundIn = (UInt16, HTTPRequestHead) // seqNum, HTTP Request
    typealias OutboundOut = HTTPClientRequestPart
    
    private let configuration: LCLPing.Configuration
    private let httpOptions: LCLPing.Configuration.HTTPOptions
    private var latencyEntry: LatencyEntry?
    private var timerScheduler: TimerScheduler
    
    init(configuration: LCLPing.Configuration, httpOptions: LCLPing.Configuration.HTTPOptions) {
        self.configuration = configuration
        self.httpOptions = httpOptions
        self.timerScheduler = TimerScheduler()
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (sequenceNum, httpRequest) = self.unwrapOutboundIn(data)
        var le = LatencyEntry(seqNum: sequenceNum)
        le.requestStart = Date.currentTimestamp
        self.latencyEntry = le
        context.write(self.wrapOutboundOut(.head(httpRequest)), promise: promise)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        
        timerScheduler.schedule(delay: self.configuration.timeout, key: sequenceNum) { [weak self] in
            if let self = self, var le = self.latencyEntry {
                le.latencyStatus = .timeout
                context.fireChannelRead(self.wrapInboundOut(le))
                return
            }
        }
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("[HTTPTracingHandler] read")
        let httpResponse: HTTPClientResponsePart = self.unwrapInboundIn(data)
        guard var le = self.latencyEntry else {
            fatalError("No corresponding latency entry found")
        }

        switch httpResponse {
        case .head(let responseHead):
            print("Received status: \(responseHead)")
            let statusCode = responseHead.status.code
            switch statusCode {
            case 200...299:
                le.responseStart = Date.currentTimestamp
                if httpOptions.useServerTiming {
                    le.serverTiming = responseHead.headers.contains(name: "Server-Timing") ? matchServerTiming(field: responseHead.headers.first(name: "Server-Timing")!) : estimatedServerTiming
                }
            case 300...399,
                400...499,
                500...599:
                le.latencyStatus = .error(statusCode)
            default:
                le.latencyStatus = .error(statusCode)
            }
        case .body(_):
            break
        case .end:
            print("finish reading response")
            
            guard var le = self.latencyEntry else {
                fatalError("Latency Entry should not be empty")
            }
            le.responseEnd = Date.currentTimestamp
            le.latencyStatus = .finished
            context.fireChannelRead(self.wrapInboundOut(le))
            self.latencyEntry = nil
        }
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
    private var taskToSeqNum: Dictionary<Int, UInt16> = [:]
    private var taskToLatency: Dictionary<Int, Double?> = [:]
    private var userConfiguration: LCLPing.Configuration?
    
    private var continuation: AsyncStream<PingResponse>.Continuation?
    
    func execute(configuration: LCLPing.Configuration) async throws -> AsyncStream<PingResponse>  {
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
                print("Unable to connect to host: \(error)")
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
                print("task \(taskIdentifier) times out")
                self.continuation?.yield(.timeout(taskToSeqNum[taskIdentifier]!))
            default:
                print("task \(taskIdentifier) has error: \(urlError.localizedDescription)")
                self.continuation?.yield(.error(urlError))
            }
            
        } else {
            // no error, let's check the data received
            guard let response = task.response else {
                self.continuation?.yield(.error(PingError.httpNoResponse))
                print("request #\(taskIdentifier) doesnt have response")
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
                self.continuation?.yield(.error(PingError.httpRequestFailed(statusCode)))
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
            print("no response. maybe timeout")
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


