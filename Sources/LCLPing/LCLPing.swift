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
        case .http:
            ping = HTTPPing()
        }
        
        try await ping?.start(with: configuration)
        print("DONE!")
    }
    
//    private func validateConfiguration(type: LCLPing.PingType, configuration: LCLPing.Configuration) -> Bool {
//        switch configuration.host {
//        case .icmp(_):
//            return type == .icmp
//        case .ipv4(_, _):
//            <#code#>
//        case .ipv6(_, _):
//            <#code#>
//        }
//    }
}
