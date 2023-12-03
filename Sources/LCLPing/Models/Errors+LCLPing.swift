//
//  Errors+LCLPing.swift
//  
//
//  Created by JOHN ZZN on 8/23/23.
//

import Foundation

public enum PingError: Error {    
    case operationNotSupported(String)
    case unknownError(String)
    case invalidConfiguration(String)
    case hostConnectionError(Error)
    case sendPingFailed(Error)
    case invalidLatencyResponseState
    
    case failedToInitialzeChannel
    case invalidICMPResponse
    case invalidIPv4URL
    case invalidIPv6URL
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
    
    case invalidHTTPSession
    case httpRequestFailed(Int)
    
    case httpNoMatchingRequest
    case httpNoResponse
    case httpRedirect
    case httpClientError
    case httpServerError
    case httpUnknownStatus(UInt)
    case httpMissingHost
    case httpMissingSchema
    case httpUnableToEstablishTLSConnection
    case httpMissingResult
}

public enum RuntimeError: Error, Equatable {
    case insufficientBytes(String)
}
