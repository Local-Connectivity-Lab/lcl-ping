//
// This source file is part of the LCLPing open source project
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

    // ICMP message type (ECHO_REQUEST)
    let type: UInt8
    let code: UInt8
    var checkSum: UInt16

    // the packet identifier
    let idenifier: UInt16

    // the packet sequence number
    let sequenceNum: UInt16

    var payload: ICMPRequestPayload

    init(type: UInt8 = ICMPType.echoRequest.rawValue, code: UInt8 = 0, idenifier: UInt16, sequenceNum: UInt16) {
        self.type = type
        self.code = code
        self.checkSum = 0
        self.idenifier = idenifier
        self.sequenceNum = sequenceNum
        self.payload = ICMPRequestPayload(timestamp: Date.currentTimestamp, identifier: self.idenifier)
    }

    /// Calculate and then set the checksum of the request header
    mutating func setChecksum() {
        self.checkSum = calcChecksum()
    }

    /// Calculate the checksum of the given ICMP header
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

extension ICMPHeader {
    mutating func toData() -> Data {
        return Data(bytes: &self, count: sizeof(ICMPHeader.self))
    }
}

/// The payload in the ICMP message
struct ICMPRequestPayload: Hashable {
    let timestamp: TimeInterval
    let identifier: UInt16
}

extension ICMPRequestPayload {

    /// Convert ICMP request payload in the header to byte array
    var data: Data {
        var payload = self
        return Data(bytes: &payload, count: MemoryLayout<ICMPRequestPayload>.size)
    }
}

/// ICMP message type
internal enum ICMPType: UInt8 {

    /// ICMP Request to host
    case echoRequest = 8

    /// ICMP Reply from host
    case echoReply = 0
}
