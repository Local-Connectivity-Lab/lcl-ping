import Logging

fileprivate var logger: Logger = Logger(label: LOGGER_LABEL)

public struct LCLPing {
    
    public init() {
        ping = nil
        logger.logLevel = .debug
    }
    
    var ping: Pingable?
    
    var status: PingState? {
        ping?.pingStatus
    }
    
    var summary: PingSummary? {
        ping?.summary
    }
    
    public mutating func start(configuration: LCLPing.Configuration) async throws {
        // TODO: validate configuration
        logger.info("START")
        logger.debug("Using configuration \(configuration)")
        let type = configuration.type
        switch type {
        case .icmp:
            logger.debug("start ICMP Ping ...")
            ping = ICMPPing()
        case .http(let options):
            logger.debug("start HTTP Ping with options \(options)")
            ping = HTTPPing(options: options)
        }
        
        try await ping?.start(with: configuration)
        logger.info("DONE")
    }
    
    public mutating func stop() {
        logger.debug("try to stop ping")
        ping?.stop()
        logger.debug("ping stopped")
    }
}
