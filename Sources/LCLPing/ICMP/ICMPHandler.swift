//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOCore

final class ICMPHandler {

    private let totalCount: UInt16
    /// sequence number to ICMP request
    private var seqToRequest: [UInt16: ICMPHeader]

    /// sequence number to an optional ICMP response
    private var seqToResponse: [UInt16: ICMPHeader?]
    private var responseSeqNumSet: Set<UInt16>
    private var result: [PingResponse]
    
    private var icmpPingPromise: EventLoopPromise<[PingResponse]>

    init(totalCount: UInt16, promise: EventLoopPromise<[PingResponse]>) {
        self.totalCount = totalCount
        self.seqToRequest = [:]
        self.seqToResponse = [:]
        self.responseSeqNumSet = Set()
        self.result = []
        self.icmpPingPromise = promise
    }
    
    public var futureResult: EventLoopFuture<[PingResponse]> {
        return self.icmpPingPromise.futureResult
    }

    func handleRead(response: ICMPHeader) {
        let type = response.type
        let code = response.code
        let sequenceNum = response.sequenceNum
        let identifier = response.idenifier
        
        print("[ICMPDuplexer][\(#function)]: received icmp response with type: \(type), code: \(code), sequence number: \(sequenceNum), identifier: \(identifier)")
        
        let currentTimestamp = Date.currentTimestamp

        if self.responseSeqNumSet.contains(sequenceNum) {
            let pingResponse: PingResponse = self.seqToResponse[sequenceNum] == nil ? .timeout(sequenceNum) : .duplicated(sequenceNum)
            print("[ICMPDuplexer][\(#function)]: response for #\(sequenceNum) is \(self.seqToResponse[sequenceNum] == nil ? "timeout" : "duplicate")")
            result.append(pingResponse)
            checkIfComplete()
            return
        }

        guard let icmpRequest = self.seqToRequest[sequenceNum] else {
            logger.error("[ICMPDuplexer][\(#function)]: Unable to find matching request with sequence number \(sequenceNum)")
            self.handleError(sequenceNum: sequenceNum, error: PingError.invalidICMPResponse)
            checkIfComplete()
            return
        }

        self.seqToResponse[sequenceNum] = response
        self.responseSeqNumSet.insert(sequenceNum)

        switch (type, code) {
        case (ICMPType.echoReply.rawValue, 0):
            break
        case (3, 0):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationNetworkUnreachable))
            checkIfComplete()
            return
        case (3, 1):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationHostUnreachable))
            checkIfComplete()
            return
        case (3, 2):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationProtocoltUnreachable))
            checkIfComplete()
            return
        case (3, 3):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationPortUnreachable))
            checkIfComplete()
            return
        case (3, 4):
            self.result.append(.error(sequenceNum, PingError.icmpFragmentationRequired))
            checkIfComplete()
            return
        case (3, 5):
            self.result.append(.error(sequenceNum, PingError.icmpSourceRouteFailed))
            checkIfComplete()
            return
        case (3, 6):
            self.result.append(.error(sequenceNum, PingError.icmpUnknownDestinationNetwork))
            checkIfComplete()
            return
        case (3, 7):
            self.result.append(.error(sequenceNum, PingError.icmpUnknownDestinationHost))
            checkIfComplete()
            return
        case (3, 8):
            self.result.append(.error(sequenceNum, PingError.icmpSourceHostIsolated))
            checkIfComplete()
            return
        case (3, 9):
            self.result.append(.error(sequenceNum, PingError.icmpNetworkAdministrativelyProhibited))
            checkIfComplete()
            return
        case (3, 10):
            self.result.append(.error(sequenceNum, PingError.icmpHostAdministrativelyProhibited))
            checkIfComplete()
            return
        case (3, 11):
            self.result.append(.error(sequenceNum, PingError.icmpNetworkUnreachableForToS))
            checkIfComplete()
            return
        case (3, 12):
            self.result.append(.error(sequenceNum, PingError.icmpHostUnreachableForToS))
            checkIfComplete()
            return
        case (3, 13):
            self.result.append(.error(sequenceNum, PingError.icmpCommunicationAdministrativelyProhibited))
            checkIfComplete()
            return
        case (3, 14):
            self.result.append(.error(sequenceNum, PingError.icmpHostPrecedenceViolation))
            checkIfComplete()
            return
        case (3, 15):
            self.result.append(.error(sequenceNum, PingError.icmpPrecedenceCutoffInEffect))
            checkIfComplete()
            return
        case (5, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForNetwork))
            checkIfComplete()
            return
        case (5, 1):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForHost))
            checkIfComplete()
            return
        case (5, 2):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForTosAndNetwork))
            checkIfComplete()
            return
        case (5, 3):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForTosAndHost))
            checkIfComplete()
            return
        case (9, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRouterAdvertisement))
            checkIfComplete()
            return
        case (10, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRouterDiscoverySelectionSolicitation))
            checkIfComplete()
            return
        case (11, 0):
            self.result.append(.error(sequenceNum, PingError.icmpTTLExpiredInTransit))
            checkIfComplete()
            return
        case (11, 1):
            self.result.append(.error(sequenceNum, PingError.icmpFragmentReassemblyTimeExceeded))
            checkIfComplete()
            return
        case (12, 0):
            self.result.append(.error(sequenceNum, PingError.icmpPointerIndicatesError))
            checkIfComplete()
            return
        case (12, 1):
            self.result.append(.error(sequenceNum, PingError.icmpMissingARequiredOption))
            checkIfComplete()
            return
        case (12, 2):
            self.result.append(.error(sequenceNum, PingError.icmpBadLength))
            checkIfComplete()
            return
        default:
            self.result.append(.error(sequenceNum, PingError.unknownError("Received unknown ICMP type (\(type)) and ICMP code (\(code))")))
            return
        }

        if response.checkSum != response.calcChecksum() {
            self.handleError(sequenceNum: sequenceNum, error: PingError.invalidICMPChecksum)
            checkIfComplete()
            return
        }

        #if canImport(Darwin)
        if identifier != icmpRequest.idenifier {
            self.handleError(sequenceNum: sequenceNum, error: PingError.invalidICMPIdentifier)
            checkIfComplete()
            return
        }
        #endif

        let latency = (currentTimestamp - icmpRequest.payload.timestamp) * 1000

        let pingResponse: PingResponse = .ok(sequenceNum, latency, currentTimestamp)
        self.result.append(pingResponse)
        checkIfComplete()
    }

    func handleWrite(request: ICMPHeader) {
        self.seqToRequest[request.sequenceNum] = request
    }
    
    func handleTimeout(sequenceNum: UInt16) {
        if !self.responseSeqNumSet.contains(sequenceNum) {
            self.responseSeqNumSet.insert(sequenceNum)
            self.result.append(.timeout(sequenceNum))
        }
    }

    func handleError(error: Error) {
        self.handleError(sequenceNum: nil, error: error)
        self.icmpPingPromise.fail(error)
    }
    
    func handleError(sequenceNum: UInt16?, error: Error) {
        self.result.append(.error(sequenceNum, error))
    }

    func reset() {
        self.seqToRequest.removeAll()
        self.seqToResponse.removeAll()
        self.result.removeAll()
    }
    
    func shouldCloseHandler() {
        checkIfComplete(shouldForceClose: true)
    }
    
    private func checkIfComplete(shouldForceClose: Bool = false) {
        if self.responseSeqNumSet.count == self.totalCount && self.seqToResponse.count == self.totalCount || shouldForceClose {
            self.icmpPingPromise.succeed(self.result)
        }
    }
}
