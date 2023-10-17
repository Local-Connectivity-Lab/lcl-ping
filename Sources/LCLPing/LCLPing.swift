public struct LCLPing {
    
    public init() {
        ping = nil
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
        print("START")
        let type = configuration.type
        switch type {
        case .icmp:
            ping = ICMPPing()
        case .http(let options):
            ping = HTTPPing(options: options)
        }
        
        try await ping?.start(with: configuration)
        print("DONE!")
    }
    
    public mutating func stop() {
        print("try to stop ping")
        ping?.stop()
        print("ping stopped")
    }
}
