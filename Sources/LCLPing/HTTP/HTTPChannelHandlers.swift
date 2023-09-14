//
//  HTTPChannelHandlers.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation
import NIO
import NIOCore


#if os(Linux)
#else
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
    private static let estimatedServerTiming: Double = 15
    private var userConfiguration: LCLPing.Configuration?
    
    private var continuation: AsyncStream<PingResponse>.Continuation?
    
    func execute(configuration: LCLPing.Configuration) async throws -> AsyncStream<PingResponse>  {
        self.userConfiguration = configuration
        let urlsessionConfig: URLSessionConfiguration = .ephemeral
        urlsessionConfig.timeoutIntervalForRequest = configuration.timeout
        urlsessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: urlsessionConfig, delegate: self, delegateQueue: nil)
        
        let request: URLRequest
        switch configuration.host {
        case .icmp(_):
            cancel()
            throw PingError.invalidConfiguration("Cannot execute HTTP Ping with ICMP Configuration")
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
        case .ipv6(let url, let port):
            guard let url = prepareURL(url: url, port: port) else {
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
                self.continuation?.yield(.error)
            }
            
        } else {
            // no error, let's check the data received
            guard let response = task.response else {
                self.continuation?.yield(.error)
                print("request #\(taskIdentifier) doesnt have response")
                return
            }
            
            switch (response as! HTTPURLResponse).statusCode {
            case 200...299:
                guard taskToLatency.keys.contains(taskIdentifier) && taskToSeqNum.keys.contains(taskIdentifier) else {
                    fatalError("Unknown URLSession Datatask \(taskIdentifier)")
                }
                
                if let latency = taskToLatency[taskIdentifier]!, let seqNum = taskToSeqNum[taskIdentifier] {
                    self.continuation?.yield(.ok(seqNum, latency, Date.currentTimestamp))
                }
            default:
                self.continuation?.yield(.error)
            }
            
            // completes the async stream
            if let userConfiguration = self.userConfiguration, taskToSeqNum.count == userConfiguration.count {
                continuation?.finish()
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
                var totalTiming: Double = .zero

                if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                    let pattern = #/dur=([\d.]+)/#
                    let matches = serverTimingField.matches(of: pattern)
                    for match in matches {
                        totalTiming += Double(match.output.1) ?? 0.0
                    }
                } else {
                    do {
                        let pattern = try NSRegularExpression(pattern: #"dur=([\d.]+)"#)
                        let matchingResult = pattern.matches(in: serverTimingField, range: NSRange(location: .zero, length: serverTimingField.count))
                        matchingResult.forEach { result in
                            let nsRange = result.range(at: 1)
                            if let range = Range(nsRange, in: serverTimingField) {
                                totalTiming += Double(serverTimingField[range]) ?? 0.0
                            }
                        }
                    } catch {
                        // TODO: handle error
                        fatalError("Invalid Regular Expression: \(error)")
                    }
                }
            } else {
                // use estimated timing
                taskToLatency[taskIdentifier] = HTTPHandler.estimatedServerTiming
            }
        } else {
            // error status code
            taskToLatency[taskIdentifier] = nil
        }
    }
}
#endif


