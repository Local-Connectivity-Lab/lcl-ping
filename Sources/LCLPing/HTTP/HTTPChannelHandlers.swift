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
    
    // TODO: add state management
    
    init(useServerTiming: Bool) {
        self.useServerTiming = useServerTiming
        super.init()
    }
    
    private let useServerTiming: Bool
    
    private var task: Task<(), Never>?
    
    private var session: URLSession?
    private var taskToSeqNum: Dictionary<Int, UInt16> = [:]
//    private var taskToHeader: Dictionary<Int, HTTPURLResponse> = [:]
    private var taskToLatency: Dictionary<Int, Double?> = [:]
    private static let estimatedServerTiming: Double = 15
    private var userConfiguration: LCLPing.Configuration?
    
    private var continuation: AsyncStream<PingResponse>.Continuation?
    
    func execute(configuration: LCLPing.Configuration) async throws -> AsyncStream<PingResponse>  {
        self.userConfiguration = configuration
        let config: URLSessionConfiguration = .ephemeral
        config.timeoutIntervalForRequest = configuration.timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        print(6)
        
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
            print(7)
            
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
            print("request is \(request)")
        case .ipv6(let url, let port):
            guard let url = prepareURL(url: url, port: port) else {
                cancel()
                throw PingError.invalidIPv6URL
            }
            
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
        
        for cnt in 0..<configuration.count {
            let dataTask = session.dataTask(with: request)
            let taskIdentifier = dataTask.taskIdentifier
            taskToSeqNum[taskIdentifier] = cnt
            dataTask.resume()
            try await Task.sleep(nanoseconds: configuration.interval.nanosecond)
        }

        return stream
    }
    
    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }
}

extension HTTPHandler {
    private func probe(url: URL) async -> Result<Void, PingError> {
        if let session = session {
            do {
                let (_, response) = try await session.data(from: url)
                let httpResponse = response as! HTTPURLResponse
                switch httpResponse.statusCode {
                case 200...299:
                    if let serverTimingField = httpResponse.value(forHTTPHeaderField: "Server-Timing") {
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
    
    private func prepareRequest(url: URL) -> URLRequest {
        print(7.1)
        var host: String = url.host ?? ""
        print("host is \(host)")
        
        var request: URLRequest = URLRequest(url: url)
        print(8.1)
        request.httpMethod = "GET"
        request.allowsCellularAccess = true
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        print(9)
        return request
    }
}

extension HTTPHandler: URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskIdentifier = task.taskIdentifier
        print("task \(taskIdentifier) completes")
    
        
        if let error = error {
            let urlError = error as! URLError
            switch urlError.code {
            case .timedOut:
                print("task \(taskIdentifier) times out")
                self.continuation?.yield(.timeout(taskToSeqNum[taskIdentifier]!))
            default:
                print("task \(taskIdentifier) has error \(urlError.code)")
                self.continuation?.yield(.error)
                break
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
                    fatalError("Unknown URLSession Datatask")
                }
                
                if let latency = taskToLatency[taskIdentifier]!, let seqNum = taskToSeqNum[taskIdentifier] {
                    self.continuation?.yield(.ok(seqNum, latency, Date.currentTimestamp))
                }
            default:
                self.continuation?.yield(.error)
            }
            
            if let userConfiguration = self.userConfiguration, taskToSeqNum.count == userConfiguration.count {
                continuation?.finish()
            }
        }
        
    }
    
//    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
//        let taskIdentifier = dataTask.taskIdentifier
//        taskToHeader[taskIdentifier] = (response as! HTTPURLResponse)
//        print("task \(taskIdentifier) receives http response")
//        completionHandler(.allow)
//    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let metric = metrics.transactionMetrics.last else {
            return
        }
        
        let taskIdentifier = task.taskIdentifier
        print("task \(taskIdentifier) finishes collecting metrics")
        
        
        let requestStart = metric.requestStartDate?.timeIntervalSince1970 ?? 0
        let responseEnd = metric.responseEndDate?.timeIntervalSince1970 ?? 0
        
        if !useServerTiming {
//            self.continuation?.yield(.ok(taskToSeqNum[taskIdentifier]!, (responseEnd - requestStart) * 1000.0, Date.currentTimestamp))
            self.taskToLatency[taskIdentifier] = (responseEnd - requestStart) * 1000.0
            print("latency is: \((responseEnd - requestStart) * 1000.0) ms")
            
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
                    }
                }
            } else {
                // TODO: use estimated timing
                taskToLatency[taskIdentifier] = HTTPHandler.estimatedServerTiming
            }
        } else {
            taskToLatency[taskIdentifier] = nil
        }
    }
}
#endif


