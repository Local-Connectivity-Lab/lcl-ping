<div align="center">
<img src="images/logo.png" alt="Logo" width="250px" />
</div>

---

LCLPing is a cross-platform Ping library written in Swift, and for Swift. It is designed to help streamline testing, measuring, and monitoring network reachability and latency for both the client side and server side applications and services.

# LCLPing

![Apple platform CI](https://github.com/Local-Connectivity-Lab/lcl-ping/actions/workflows/macos.yaml/badge.svg?branch=main)
![Ubuntu CI](https://github.com/Local-Connectivity-Lab/lcl-ping/actions/workflows/ubuntu.yaml/badge.svg?branch=main)


## Requirements
- Swift 5.7+
- macOS 10.15+, iOS 14+, Linux

## Getting Started


### Swift Package Manager (SPM)

Add the following to your `Package.swift` file:
```code
.package(url: "https://github.com/Local-Connectivity-Lab/lcl-ping.git", from: "1.0.0")
```

Then import the module to your project
```code
.target(
    name: "YourAppName",
    .dependencies: [
        .product(name: "LCLPing", package: "lcl-ping")
    ]
)
```

### Basic Usage
```swift
// Reachability Test
let isReachable = LCLPing.reachable(via: .icmp, strategy: .multiple, host: "google.com")
print("is reachable: \(isReachable)")
```

```swift
// Run Ping Test

// create ping configuration for each run
let icmpConfig = ICMPPingClient.Configuration(endpoint: .ipv4("127.0.0.1", 0), count: 1)
let httpConfig = try HTTPPingClient.Configuration(url: "http://127.0.0.1:8080", count: 1)

// initialize test client
let icmpClient = ICMPPingClient(configuration: icmpConfig)
let httpClient = HTTPPingClient(configuration: httpConfig)

do {
    // run the test using SwiftNIO EventLoopFuture
    let result = try icmpClient.start().wait()
    print(result)
} catch {
    print("received: \(error)")
}

do {
    let result = try httpClient.start().wait()
    print(result)
} catch {
    print("received: \(error)")
}
```

You can also run the [demo](/Sources/Demo/README.md) using `make demo` or `swift run Demo` if you do not have make installed.

### Features
- Ping via ICMP and HTTP(S)
- Support IPv4 ICMP and IPv4 and IPv6 for HTTP
- Flexible and configurable wait time, time-to-live, count, and duration
- Supports parsing Server-Timing in the HTTP header to account for time taken by server processing


## Contributing
Any contribution and pull requests are welcome! However, before you plan to implement some features or try to fix an uncertain issue, it is recommended to open a discussion first. You can also join our [Discord channel](https://discord.com/invite/gn4DKF83bP), or visit our [website](https://seattlecommunitynetwork.org/).

## License
LCLPing is released under Apache License. See [LICENSE](/LICENSE) for more details.
