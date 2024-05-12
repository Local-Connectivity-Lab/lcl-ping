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
    case operationNotSupported(String)
    case unknownError(String)
    case invalidConfiguration(String)
    case hostConnectionError(Error)
    case sendPingFailed(Error)
    case invalidLatencyResponseState
    case taskIsCancelled

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

    case invalidHexFormat

    case forTestingPurposeOnly
}

public enum RuntimeError: Error, Equatable {
    case insufficientBytes(String)
}
