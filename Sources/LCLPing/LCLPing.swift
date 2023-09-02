public struct LCLPing {
    
    public static func start(type: LCLPing.PingType, configuration: LCLPing.Configuration) async throws {
        // TODO: validate configuration
        var ping: Pingable?
        switch type {
        case .icmp:
            ping = ICMPPing()
        case .http:
            throw PingError.operationNotSupported
        }
        
        try await ping?.start(with: configuration)
    }

}
