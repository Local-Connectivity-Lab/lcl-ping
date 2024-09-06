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
import Collections

extension ICMPPingClient {

    /// The identifier used by the ICMP Header
    var identifier: UInt16 { return 0xbeef }

    /// The request that the ICMP Ping Client expects
    ///
    /// The information in this data will be used to construct the corresponding ICMP header.
    internal struct Request {
        /// The sequence number of the ICMP test. This number should be monotonically increasing.
        let sequenceNum: UInt16

        /// The identifier that will be used in the ICMP header (by default, it is `identifier (0xbeef)`.
        let identifier: UInt16
    }

    /// The IPv4 Header
    internal struct IPv4Header {
        let versionAndHeaderLength: UInt8
        let differentiatedServicesAndECN: UInt8
        let totalLength: UInt16
        let identification: UInt16
        let flagsAndFragmentOffset: UInt16
        let timeToLive: UInt8
        let `protocol`: UInt8
        let headerChecksum: UInt16
        let sourceAddress: (UInt8, UInt8, UInt8, UInt8)
        let destinationAddress: (UInt8, UInt8, UInt8, UInt8)
    }

    /// The ICMP request message header
    internal struct ICMPHeader {

        /// ICMP message type (ECHO_REQUEST)
        let type: UInt8
        let code: UInt8
        var checkSum: UInt16

        /// the packet identifier
        let idenifier: UInt16

        /// the packet sequence number
        let sequenceNum: UInt16

        /// the ICMP header payload
        var payload: ICMPRequestPayload

        init(type: UInt8 = ICMPType.echoRequest.rawValue, code: UInt8 = 0, idenifier: UInt16, sequenceNum: UInt16) {
            self.type = type
            self.code = code
            self.checkSum = 0
            self.idenifier = idenifier
            self.sequenceNum = sequenceNum
            self.payload = ICMPRequestPayload(timestamp: Date.currentTimestamp, identifier: self.idenifier)
        }

        /// Calculate and then set the checksum of the request header.
        mutating func setChecksum() {
            self.checkSum = calcChecksum()
        }

        /// Calculate the checksum of the given ICMP header
        ///
        /// - Returns: the checksum value of this ICMP header.
        func calcChecksum() -> UInt16 {
            let typecode = Data([self.type, self.code]).withUnsafeBytes { $0.load(as: UInt16.self) }
            var sum = UInt64(typecode) + UInt64(self.idenifier) + UInt64(self.sequenceNum)
            let payload = self.payload.data

            for idx in stride(from: 0, to: payload.count, by: 2) {
                sum += Data([payload[idx], payload[idx + 1]]).withUnsafeBytes { UInt64($0.load(as: UInt16.self)) }
            }

            while sum >> 16 != 0 {
                sum = (sum & 0xFFFF) + (sum >> 16)
            }

            return ~UInt16(sum)
        }
    }

    /// The payload in the ICMP message
    struct ICMPRequestPayload: Hashable {
        let timestamp: TimeInterval
        let identifier: UInt16
    }

    /// ICMP message type
    internal enum ICMPType: UInt8 {

        /// ICMP Request to host
        case echoRequest = 8

        /// ICMP Reply from host
        case echoReply = 0
    }
}

extension ICMPPingClient.ICMPHeader {

    /// The ICMP header in byte array form.
    var data: Data {
        var payload = self
        return Data(bytes: &payload, count: sizeof(ICMPPingClient.ICMPHeader.self))
    }
}

extension ICMPPingClient.ICMPRequestPayload {

    /// ICMP request payload in the header in byte array form.
    var data: Data {
        var payload = self
        return Data(bytes: &payload, count: sizeof(ICMPPingClient.ICMPRequestPayload.self))
    }
}

final class ICMPHandler: PingHandler {

    typealias Request = ICMPPingClient.ICMPHeader
    typealias Response = ICMPPingClient.ICMPHeader

    private let totalCount: Int

    // sequence number to ICMP request
    private var seqToRequest: [Int: ICMPPingClient.ICMPHeader]

    // a bit set that contains the response sequence number seen so far
    private var seen: BitSet

    // a bit set that contains the response sequence number received by the handler
    private var hasResponses: BitSet

    // a list of `PingResponse`
    private var result: [PingResponse]

    // the promise that will be resolved when the ping test is done.
    private var icmpPingPromise: EventLoopPromise<[PingResponse]>

    init(totalCount: Int, promise: EventLoopPromise<[PingResponse]>) {
        self.totalCount = totalCount
        self.seqToRequest = [:]
        self.result = []
        self.icmpPingPromise = promise
        self.seen = BitSet(reservingCapacity: self.totalCount)
        self.hasResponses = BitSet(reservingCapacity: self.totalCount)
    }

    func handleRead(response: ICMPPingClient.ICMPHeader) {
        let type = response.type
        let code = response.code
        let sequenceNum = Int(response.sequenceNum)
        let identifier = response.idenifier

        logger.debug("[[\(#fileID)][\(#line)][\(#function)]: received icmp response with type: \(type), code: \(code), sequence number: \(sequenceNum), identifier: \(identifier)")

        let currentTimestamp = Date.currentTimestamp

        guard let icmpRequest = self.seqToRequest[sequenceNum] else {
            logger.error("[\(#fileID)][\(#line)][\(#function)]: Unable to find matching request with sequence number \(sequenceNum)")
            self.handleError(error: PingError.invalidICMPResponse)
            return
        }

        if self.seen.contains(sequenceNum) {
            let pingResponse: PingResponse = self.hasResponses.contains(sequenceNum) ? .duplicated(sequenceNum) : .timeout(sequenceNum)
            logger.debug("[\(#fileID)][\(#line)][\(#function)]:: response for #\(sequenceNum) is \(self.hasResponses.contains(sequenceNum) ? "timeout" : "duplicate")")
            result.append(pingResponse)
            shouldCloseHandler()
            return
        }

        self.hasResponses.insert(sequenceNum)
        self.seen.insert(sequenceNum)

        switch (type, code) {
        case (ICMPPingClient.ICMPType.echoReply.rawValue, 0):
            break
        case (3, 0):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationNetworkUnreachable))
            shouldCloseHandler()
            return
        case (3, 1):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationHostUnreachable))
            shouldCloseHandler()
            return
        case (3, 2):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationProtocoltUnreachable))
            shouldCloseHandler()
            return
        case (3, 3):
            self.result.append(.error(sequenceNum, PingError.icmpDestinationPortUnreachable))
            shouldCloseHandler()
            return
        case (3, 4):
            self.result.append(.error(sequenceNum, PingError.icmpFragmentationRequired))
            shouldCloseHandler()
            return
        case (3, 5):
            self.result.append(.error(sequenceNum, PingError.icmpSourceRouteFailed))
            shouldCloseHandler()
            return
        case (3, 6):
            self.result.append(.error(sequenceNum, PingError.icmpUnknownDestinationNetwork))
            shouldCloseHandler()
            return
        case (3, 7):
            self.result.append(.error(sequenceNum, PingError.icmpUnknownDestinationHost))
            shouldCloseHandler()
            return
        case (3, 8):
            self.result.append(.error(sequenceNum, PingError.icmpSourceHostIsolated))
            shouldCloseHandler()
            return
        case (3, 9):
            self.result.append(.error(sequenceNum, PingError.icmpNetworkAdministrativelyProhibited))
            shouldCloseHandler()
            return
        case (3, 10):
            self.result.append(.error(sequenceNum, PingError.icmpHostAdministrativelyProhibited))
            shouldCloseHandler()
            return
        case (3, 11):
            self.result.append(.error(sequenceNum, PingError.icmpNetworkUnreachableForToS))
            shouldCloseHandler()
            return
        case (3, 12):
            self.result.append(.error(sequenceNum, PingError.icmpHostUnreachableForToS))
            shouldCloseHandler()
            return
        case (3, 13):
            self.result.append(.error(sequenceNum, PingError.icmpCommunicationAdministrativelyProhibited))
            shouldCloseHandler()
            return
        case (3, 14):
            self.result.append(.error(sequenceNum, PingError.icmpHostPrecedenceViolation))
            shouldCloseHandler()
            return
        case (3, 15):
            self.result.append(.error(sequenceNum, PingError.icmpPrecedenceCutoffInEffect))
            shouldCloseHandler()
            return
        case (5, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForNetwork))
            shouldCloseHandler()
            return
        case (5, 1):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForHost))
            shouldCloseHandler()
            return
        case (5, 2):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForTosAndNetwork))
            shouldCloseHandler()
            return
        case (5, 3):
            self.result.append(.error(sequenceNum, PingError.icmpRedirectDatagramForTosAndHost))
            shouldCloseHandler()
            return
        case (9, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRouterAdvertisement))
            shouldCloseHandler()
            return
        case (10, 0):
            self.result.append(.error(sequenceNum, PingError.icmpRouterDiscoverySelectionSolicitation))
            shouldCloseHandler()
            return
        case (11, 0):
            self.result.append(.error(sequenceNum, PingError.icmpTTLExpiredInTransit))
            shouldCloseHandler()
            return
        case (11, 1):
            self.result.append(.error(sequenceNum, PingError.icmpFragmentReassemblyTimeExceeded))
            shouldCloseHandler()
            return
        case (12, 0):
            self.result.append(.error(sequenceNum, PingError.icmpPointerIndicatesError))
            shouldCloseHandler()
            return
        case (12, 1):
            self.result.append(.error(sequenceNum, PingError.icmpMissingARequiredOption))
            shouldCloseHandler()
            return
        case (12, 2):
            self.result.append(.error(sequenceNum, PingError.icmpBadLength))
            shouldCloseHandler()
            return
        default:
            self.result.append(.error(
                                sequenceNum,
                                PingError.unknownError("Received unknown ICMP type (\(type)) and ICMP code (\(code))"))
                            )
            shouldCloseHandler()
            return
        }

        if response.checkSum != response.calcChecksum() {
            self.handleError(sequenceNum: sequenceNum, error: PingError.invalidICMPChecksum)
            shouldCloseHandler()
            return
        }

        #if canImport(Darwin)
        if identifier != icmpRequest.idenifier {
            self.handleError(sequenceNum: sequenceNum, error: PingError.invalidICMPIdentifier)
            shouldCloseHandler()
            return
        }
        #endif

        let latency = (currentTimestamp - icmpRequest.payload.timestamp) * 1000

        let pingResponse: PingResponse = .ok(sequenceNum, latency, currentTimestamp)
        self.result.append(pingResponse)
        shouldCloseHandler()
    }

    func handleWrite(request: ICMPPingClient.ICMPHeader) {
        self.seqToRequest[Int(request.sequenceNum)] = request
    }

    func handleTimeout(sequenceNumber: Int) {
        if !self.seen.contains(sequenceNumber) {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: #\(sequenceNumber) timed out")
            self.seen.insert(sequenceNumber)
            self.result.append(.timeout(sequenceNumber))
            shouldCloseHandler()
        }
    }

    func handleError(error: Error) {
        self.handleError(sequenceNum: nil, error: error)
        self.icmpPingPromise.fail(error)
    }

    func handleError(sequenceNum: Int?, error: Error) {
        self.result.append(.error(sequenceNum, error))
    }

    func reset() {
        self.seqToRequest.removeAll()
        self.result.removeAll()
    }

    func shouldCloseHandler(shouldForceClose: Bool = false) {
        if self.seen.count == self.totalCount || shouldForceClose {
            logger.debug("[\(#fileID)][\(#line)][\(#function)]: should close icmp handler")
            self.icmpPingPromise.succeed(self.result)
        }
    }
}
