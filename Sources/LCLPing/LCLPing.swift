public struct LCLPing {
    
    public init() {
        ping = nil
    }
    
    var ping: Pingable?
    
    var status: PingState? {
        ping?.status
    }
    
    var summary: PingSummary? {
        ping?.summary
    }
    
    public mutating func start(type: LCLPing.PingType, configuration: LCLPing.Configuration) async throws {
        // TODO: validate configuration
        print("START")
        switch type {
        case .icmp:
            ping = ICMPPing()
            print("1")
        case .http:
            ping = HTTPPing()
//            throw PingError.operationNotSupported("Ping through HTTP is currently not supported")
        }
        
        print("2")
        try await ping?.start(with: configuration)
        print("DONE!")
    }
}
