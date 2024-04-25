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

/// The top-level entrypoint for Ping test
///
/// An LCLPing instance allows the caller to initialize the ping test with 
/// either ICMP or HTTP method and read the result once the test finishes.
/// It also gives caller the opportunity to cancel the test.
/// The caller can reuse the same ping configuration and rerun the test multiple times
public struct LCLPing {

    /// A instance that implements Pingable protocol.
    var ping: Pingable?

    /// The status of the ping test. If the pingable instance is nil, then `status` is set to `error`.
    public var status: PingState {
        ping?.pingStatus ?? .error
    }

    /// The test result the ping test. If the pingable instance is nil, then `summary` is set to empty.
    public var summary: PingSummary {
        ping?.summary ?? .empty
    }

    /// The options to configure the behavior of the LCLPing instance.
    private let options: LCLPing.Options

    /// Initialize the LCLPing instance with the given options
    /// - Parameters:
    ///     - options: the LCLPing options that defines the overall behavior of LCLPing. 
    ///                 `options` is set with default values by default.
    public init(options: LCLPing.Options = .init()) {
        ping = nil
        self.options = options
        logger.logLevel = self.options.verbose ? .debug : .info
        // TODO: think about how to pass configuration to ping instance
    }

    /// Start the ping test with the given `pingConfiguration` asynchronously.
    /// - Parameters
    ///     - pingConfiguration: the configuration that defines the behavior of the ping test 
    public mutating func start(pingConfiguration: LCLPing.PingConfiguration) async throws {
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

    /// Stop the current ping test.
    public mutating func stop() {
        logger.debug("try to stop ping")
        ping?.stop()
        logger.debug("ping stopped")
    }
}
