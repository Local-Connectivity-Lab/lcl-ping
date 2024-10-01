//
// This source file is part of the LCL open source project
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

public enum PingError: Error {

    case unknownError(String)
    case invalidLatencyResponseState
    case taskIsCancelled

    case invalidICMPResponse
    case invalidURL(String)
    case invalidIPVersion
    case invalidIPProtocol
    case invalidICMPChecksum
    case invalidICMPIdentifier

    case icmpDestinationNetworkUnreachable
    case icmpDestinationHostUnreachable
    case icmpDestinationProtocoltUnreachable
    case icmpDestinationPortUnreachable
    case icmpFragmentationRequired
    case icmpSourceRouteFailed
    case icmpUnknownDestinationNetwork
    case icmpUnknownDestinationHost
    case icmpSourceHostIsolated
    case icmpNetworkAdministrativelyProhibited
    case icmpHostAdministrativelyProhibited
    case icmpNetworkUnreachableForToS
    case icmpHostUnreachableForToS
    case icmpCommunicationAdministrativelyProhibited
    case icmpHostPrecedenceViolation
    case icmpPrecedenceCutoffInEffect
    case icmpRedirectDatagramForNetwork
    case icmpRedirectDatagramForHost
    case icmpRedirectDatagramForTosAndNetwork
    case icmpRedirectDatagramForTosAndHost
    case icmpRouterAdvertisement
    case icmpRouterDiscoverySelectionSolicitation
    case icmpTTLExpiredInTransit
    case icmpFragmentReassemblyTimeExceeded
    case icmpPointerIndicatesError
    case icmpMissingARequiredOption
    case icmpBadLength
    case icmpDestinationNotMulticast
    case icmpBindToUnixDomainSocket

    case httpMissingHost
    case httpMissingSchema
    case httpInvalidResponseStatusCode(Int)
    case httpInvalidHandlerState
    case httpMissingResponse
    case httpInvalidURLSessionTask(Int)
    case httpBindToUnixDomainSocket

    case invalidHexFormat

    case insufficientBytes(String)
    
    case missingConfiguration

    case forTestingPurposeOnly
}

extension PingError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .unknownError(let string):
            return "Unknown Error: \(string)."
        case .invalidLatencyResponseState:
            return "Latency response is in invalid state."
        case .taskIsCancelled:
            return "Task is canceled."
        case .invalidICMPResponse:
            return "ICMP response is invalid."
        case .invalidURL(let url):
            return "URL (\(url)) is invalid."
        case .invalidIPVersion:
            return "IP version in the ICMP header is invalid."
        case .invalidIPProtocol:
            return "IP protocol in the ICMP header is invalid."
        case .invalidICMPChecksum:
            return "Checksum in the ICMP header is invalid."
        case .invalidICMPIdentifier:
            return "Identifier in the ICMP header is invalid."
        case .icmpDestinationNetworkUnreachable:
            return "Destination network is unreachable."
        case .icmpDestinationHostUnreachable:
            return "Destination host is unreachable."
        case .icmpDestinationProtocoltUnreachable:
            return "Destination protocol is unreachable."
        case .icmpDestinationPortUnreachable:
            return "Destination port is unreachable."
        case .icmpFragmentationRequired:
            return "Fragmentation is needed and Don't Fragment was set"
        case .icmpSourceRouteFailed:
            return "Source route failed."
        case .icmpUnknownDestinationNetwork:
            return "Destination network is unknown."
        case .icmpUnknownDestinationHost:
            return "Destination host is unknown."
        case .icmpSourceHostIsolated:
            return "Source host is isolated"
        case .icmpNetworkAdministrativelyProhibited:
            return "Communication with destination network is administratively prohibited."
        case .icmpHostAdministrativelyProhibited:
            return "Communication with destination host is adminstratively prohibited."
        case .icmpNetworkUnreachableForToS:
            return "Destination network is unreachable for type of service."
        case .icmpHostUnreachableForToS:
            return "Destination host is unreachable for type of service."
        case .icmpCommunicationAdministrativelyProhibited:
            return "Communication is administratively prohibited."
        case .icmpHostPrecedenceViolation:
            return "Host precedence violation."
        case .icmpPrecedenceCutoffInEffect:
            return "Precedence cutoff is in effect."
        case .icmpRedirectDatagramForNetwork:
            return "Redirect datagram for network (or subnet)."
        case .icmpRedirectDatagramForHost:
            return "Redirect datagram for the host."
        case .icmpRedirectDatagramForTosAndNetwork:
            return "Redirect datagram for the type of service and network."
        case .icmpRedirectDatagramForTosAndHost:
            return "Redirect datagram for the type of service and host."
        case .icmpRouterAdvertisement:
            return "Router advertisement."
        case .icmpRouterDiscoverySelectionSolicitation:
            return "Router discovery/selection/solicitation."
        case .icmpTTLExpiredInTransit:
            return "Time to Live exceeded in transit."
        case .icmpFragmentReassemblyTimeExceeded:
            return "Fragment reassembly time exceeded."
        case .icmpPointerIndicatesError:
            return "Pointer indicates the error."
        case .icmpMissingARequiredOption:
            return "Missing a required option."
        case .icmpBadLength:
            return "Bad length."
        case .httpMissingHost:
            return "Host is missing in the HTTP request."
        case .httpMissingSchema:
            return "Schema is missing in the HTTP request."
        case .httpInvalidResponseStatusCode(let code):
            return "Received invalid response status code (\(code))."
        case .httpInvalidHandlerState:
            return "HTTP Handler is not in a valid state."
        case .invalidHexFormat:
            return "Invalid hex format."
        case .insufficientBytes(let string):
            return "Insufficient bytes: \(string)"
        case .forTestingPurposeOnly:
            return "For testing purpose ONLY."
        case .missingConfiguration:
            return "Please provide a valid configuration."
        case .httpMissingResponse:
            return "Missing HTTP response."
        case .httpInvalidURLSessionTask(let id):
            return "URLSession Task \(id) is invalid."
        case .icmpDestinationNotMulticast:
            return "Destination address is not a multicast address."
        case .icmpBindToUnixDomainSocket:
            return "Cannot bind to a unix domain socket device."
        case .httpBindToUnixDomainSocket:
            return "Cannot bind to a unix domain socket device."
        }
    }

}
