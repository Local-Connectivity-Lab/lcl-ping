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

public struct LCLPing {
    
    var ping: Pingable?
    
    public var status: PingState {
        ping?.pingStatus ?? .error
    }
    
    public var summary: PingSummary {
        ping?.summary ?? .empty
    }
    
    private let options: LCLPing.Options
    
    public init(options: LCLPing.Options = .init()) {
        ping = nil
        self.options = options
        logger.logLevel = self.options.verbose ? .debug : .info
        // TODO: think about how to pass configuration to ping instance
    }
    
    public mutating func start(pingConfiguration: LCLPing.PingConfiguration) async throws {
        // TODO: validate configuration
        logger.info("START")
        logger.debug("Using configuration \(pingConfiguration)")
        let type = pingConfiguration.type
        switch type {
        case .icmp:
            logger.debug("start ICMP Ping ...")
            ping = ICMPPing()
        case .http(let httpOptions):
            logger.debug("start HTTP Ping with options \(httpOptions)")
            ping = HTTPPing(httpOptions: httpOptions)
        }
        
        try await ping?.start(with: pingConfiguration)
        logger.info("DONE")
    }
    
    public mutating func stop() {
        logger.debug("try to stop ping")
        ping?.stop()
        logger.debug("ping stopped")
    }
}
