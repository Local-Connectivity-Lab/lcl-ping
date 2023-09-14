//
//  HTTPPing.swift
//  
//
//  Created by JOHN ZZN on 9/6/23.
//

import Foundation


internal struct HTTPPing: Pingable {
    
    var summary: PingSummary? {
        get {
            // return empty if ping is still running
            switch pingStatus {
            case .ready, .running, .failed:
                return .empty
            case .stopped, .finished:
                return pingSummary
            }
        }
        
        set {
            
        }
    }
    
    var status: PingState {
        get {
            pingStatus
        }
    }
    
    
//    private var timeout: Set<UInt16> = Set()
//    private var duplicates: Set<UInt16> = Set()
//    private var pingResults: [PingResult] = []
    private var pingStatus: PingState = .ready
    private var pingSummary: PingSummary?
    
//    mutating func start(with configuration: LCLPing.Configuration) throws {
//
//    }
    
    mutating func start(with configuration: LCLPing.Configuration) async throws {
        pingStatus = .running
        
        let host: String
        switch configuration.host {
        case .ipv4(let h, _):
            host = h
        case .ipv6(let h, _):
            host = h
        default:
            pingStatus = .failed
            throw PingError.invalidConfiguration("Expect IP.IPv4 or IP.IPv6 host. But received \(configuration.host)")
        }
        
        let httpExecutor = HTTPHandler(useServerTiming: false)
        
        var pingResponses: [PingResponse] = []
        do {
            for try await pingResponse in try await httpExecutor.execute(configuration: configuration) {
                print("received ping response: \(pingResponse)")
                pingResponses.append(pingResponse)
            }
            
            if pingStatus == .running {
                pingStatus = .finished
            }
            
            pingSummary = summarizePingResponse(pingResponses, host: host)
            print("summary is \(String(describing: pingSummary))")
        } catch {
            pingStatus = .failed
            print("Error \(error)")
        }
        
    }
    
    mutating func stop() {
        if pingStatus != .failed {
            pingStatus = .stopped
        }
    }
    

    
    
}
