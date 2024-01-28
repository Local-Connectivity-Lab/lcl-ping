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
    func rewrite(newValues: [PartialKeyPath<Self> : AnyObject]) -> Self
}

extension ICMPRequestPayload: Rewritable {
    func rewrite(newValues: [PartialKeyPath<ICMPRequestPayload> : AnyObject]) -> ICMPRequestPayload {
        return ICMPRequestPayload(timestamp: newValues[\.timestamp] as? TimeInterval ?? self.timestamp, identifier: newValues[\.identifier] as? UInt16 ?? self.identifier)
    }
}

extension IPv4Header: Rewritable {
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

extension AddressedEnvelope: Rewritable where DataType == ByteBuffer {
    func rewrite(newValues: [PartialKeyPath<NIOCore.AddressedEnvelope<DataType>> : AnyObject]) -> NIOCore.AddressedEnvelope<DataType> {
        return AddressedEnvelope(
            remoteAddress: newValues[\.remoteAddress] as? SocketAddress ?? self.remoteAddress,
            data: data.rewrite(newValues: newValues[\AddressedEnvelope.data] as? [RewriteData] ?? [RewriteData(index: 0, byte: 0x55)])
        )
    }
}


extension ByteBuffer {
    func rewrite(newValues: ByteBuffer) -> NIOCore.ByteBuffer {
        print("[ByteBuffer Rewrite]: received new value: \(newValues.readableBytesView)")
        return ByteBuffer(buffer: newValues)
    }
    
    func rewrite(newValues: [RewriteData]) -> ByteBuffer {
        print("[ByteBuffer Rewrite]: received new value: \(newValues)")
        var newBuffer = ByteBuffer(buffer: self)
        for newValue in newValues {
            newBuffer.setBytes(newValue.byte.data, at: newValue.index)
        }
        print("ByteBuffer Rewrite: rewritten as \(newBuffer.readableBytesView)")
        return newBuffer
    }
}

extension Int8 {
    var data: Data {
        var int = self
        return Data(bytes: &int, count: MemoryLayout<Int8>.size)
    }
}

struct RewriteData {
    let index: Int
    let byte: Int8
}
