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
import NIOCore

protocol Rewritable {
//    var allKeyPaths: [PartialKeyPath<Self>] { get }
    func rewrite(newValues: [PartialKeyPath<Self> : AnyObject]) -> Self
}

extension ICMPRequestPayload: Rewritable {
//    var allKeyPaths: [PartialKeyPath<ICMPRequestPayload>] {
//        return [\.identifier, \.timestamp]
//    }

    func rewrite(newValues: [PartialKeyPath<ICMPRequestPayload> : AnyObject]) -> ICMPRequestPayload {
        return ICMPRequestPayload(timestamp: newValues[\.timestamp] as? TimeInterval ?? self.timestamp, identifier: newValues[\.identifier] as? UInt16 ?? self.identifier)
    }
}

extension IPv4Header: Rewritable {
//    var allKeyPaths: [PartialKeyPath<IPv4Header>] {
//        return [
//            \.versionAndHeaderLength,
//            \.differentiatedServicesAndECN,
//            \.totalLength,
//            \.identification,
//            \.flagsAndFragmentOffset,
//            \.timeToLive,
//            \.protocol,
//            \.headerChecksum,
//            \.sourceAddress,
//            \.destinationAddress
//        ]
//    }

    func rewrite(newValues: [PartialKeyPath<IPv4Header> : AnyObject]) -> IPv4Header {
        return IPv4Header(
            versionAndHeaderLength: newValues[\.versionAndHeaderLength] as? UInt8 ?? self.versionAndHeaderLength, 
            differentiatedServicesAndECN: newValues[\.differentiatedServicesAndECN] as? UInt8 ?? self.differentiatedServicesAndECN, 
            totalLength: newValues[\.totalLength] as? UInt16 ?? self.totalLength, 
            identification: newValues[\.identification] as? UInt16 ?? self.identification,
            flagsAndFragmentOffset: newValues[\.flagsAndFragmentOffset] as? UInt16 ?? self.flagsAndFragmentOffset, 
            timeToLive: newValues[\.timeToLive] as? UInt8 ?? self.timeToLive, 
            protocol: newValues[\.protocol] as? UInt8 ?? self.protocol, 
            headerChecksum: newValues[\.headerChecksum] as? UInt16 ?? self.headerChecksum, 
            sourceAddress: newValues[\.sourceAddress] as? (UInt8, UInt8, UInt8, UInt8) ?? self.sourceAddress, 
            destinationAddress: newValues[\.destinationAddress] as? (UInt8, UInt8, UInt8, UInt8) ?? self.destinationAddress
        )
    }
}

extension ICMPHeader: Rewritable {
//    var allKeyPaths: [PartialKeyPath<ICMPHeader>] {
//        return [
//            \.type,
//            \.code,
//            \.checkSum,
//            \.idenifier,
//            \.sequenceNum,
//            \.payload
//        ]
//    }

    func rewrite(newValues: [PartialKeyPath<ICMPHeader> : AnyObject]) -> ICMPHeader {
        var newHeader = ICMPHeader(
            type: newValues[\.type] as? UInt8 ?? self.type, 
            code: newValues[\.code] as? UInt8 ?? self.code, 
            idenifier: newValues[\.idenifier] as? UInt16 ?? self.idenifier, 
            sequenceNum: newValues[\.sequenceNum] as? UInt16 ?? self.sequenceNum
        )

        newHeader.payload = self.payload.rewrite(newValues: newValues[\.payload] as! [PartialKeyPath<ICMPRequestPayload> : AnyObject])
        return newHeader
    }
}

extension AddressedEnvelope: Rewritable where DataType: Rewritable {
//    var allKeyPaths: [PartialKeyPath<NIOCore.AddressedEnvelope<DataType>>] {
//        return [
//            \.remoteAddress,
//            \.data
//        ]
//    }
    
    func rewrite(newValues: [PartialKeyPath<NIOCore.AddressedEnvelope<DataType>> : AnyObject]) -> NIOCore.AddressedEnvelope<DataType> {
        return AddressedEnvelope(
            remoteAddress: newValues[\.remoteAddress] as? SocketAddress ?? self.remoteAddress,
            data: data.rewrite(newValues: newValues[\.data] as! [PartialKeyPath<DataType> : AnyObject])
        )
    }
}

// TODO: implement Bytebuffer
extension ByteBuffer: Rewritable {
    func rewrite(newValues: [PartialKeyPath<NIOCore.ByteBuffer> : AnyObject]) -> NIOCore.ByteBuffer {
        return ByteBuffer(buffer: self)
    }
}
