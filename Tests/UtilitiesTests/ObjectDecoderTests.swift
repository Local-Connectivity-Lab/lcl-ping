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

import XCTest
@testable import LCLPing
import NIOCore

final class ObjectDecoderTests: XCTestCase {

    private struct A: Equatable {
        let a: Int32 = 1
    }

    private struct B: Equatable {
        let b1: Int8 = 2
        let b2: Bool = true
    }

    private struct C1: Equatable {
        let c1: Double = 1.0
        let c2: Int16 = 2
        let c3: Bool = false
        let c4: Int64 = 3
    }

    private struct C2: Equatable {
        let c3: Bool = false
        let c1: Double = 1.0
        let c2: Int16 = 2
        let c4: Int64 = 3
    }

    private struct AB: Equatable {
        let a: A = A()
        let b: B = B()
    }

    private struct AC1: Equatable {
        let a: A = A()
        let c: C1 = C1()
    }

    private struct AC2: Equatable {
        let a: A = A()
        let c: C2 = C2()
    }

    private struct BC1: Equatable {
        let b: B = B()
        let c: C1 = C1()
    }

    private struct BC2: Equatable {
        let b: B = B()
        let c: C2 = C2()
    }

    private struct ABC1: Equatable {
        let a: A = A()
        let b: B = B()
        let c: C1 = C1()
    }

    private struct ABC2: Equatable {
        let a: A = A()
        let b: B = B()
        let c: C2 = C2()
    }

    private var arrA: [A] = [A(), A(), A()]
    private var arrB: [B] = [B(), B()]
    private var arrC1: [C1] = [C1(), C1(), C1(), C1()]
    private var arrAB: [AB] = [AB(), AB()]
    private var arrAC1: [AC1] = [AC1(), AC1()]
    private var arrBC2: [BC2] = [BC2(), BC2()]

    func testSizeofPrimitiveTypes() {
        // Int
        XCTAssertEqual(sizeof(Int8.self), 1)
        XCTAssertEqual(sizeof(Int16.self), 2)
        XCTAssertEqual(sizeof(Int32.self), 4)
        XCTAssertEqual(sizeof(Int64.self), 8)

        // Double
        XCTAssertEqual(sizeof(Double.self), 8)

        // Float
        XCTAssertEqual(sizeof(Float.self), 4)

        // Boolean
        XCTAssertEqual(sizeof(Bool.self), 1)
    }

    func testSizeofStruct() {
        XCTAssertEqual(sizeof(A.self), 4) // 4
        XCTAssertEqual(sizeof(B.self), 2) // 1 + 1
        XCTAssertEqual(sizeof(C1.self), 24) // 8 + 2 + 1 + 8 + 5(padding)
        XCTAssertEqual(sizeof(C2.self), 32) // 1 + 7(alignment) + 8 + 2 + 8 + 6(padding)
    }

    func testSizeofNestedStructs() {
        XCTAssertEqual(sizeof(AB.self), 6)
        XCTAssertEqual(sizeof(BC1.self), 32)
        XCTAssertEqual(sizeof(BC2.self), 40)
        XCTAssertEqual(sizeof(AC1.self), 32)
        XCTAssertEqual(sizeof(AC2.self), 40)
        XCTAssertEqual(sizeof(ABC1.self), 32)
        XCTAssertEqual(sizeof(ABC2.self), 40)
    }

    func testDecodePrimitiveObjects() {
        // Int8
        let int8: Int8 = 1
        var int8BB = ByteBuffer(integer: int8, endianness: .little)
        XCTAssertEqual(try decodeByteBuffer(of: Int8.self, data: &int8BB), int8)

        // Int16
        let int16: Int16 = 2
        var int16BB = ByteBuffer(integer: int16, endianness: .little)
        XCTAssertEqual(try decodeByteBuffer(of: Int16.self, data: &int16BB), int16)

        // Int32
        let int32: Int32 = 3
        var int32BB = ByteBuffer(integer: int32, endianness: .little)
        XCTAssertEqual(try decodeByteBuffer(of: Int32.self, data: &int32BB), int32)

        // Int64
        let int64: Int64 = 4
        var int64BB = ByteBuffer(integer: int64, endianness: .little)
        XCTAssertEqual(try decodeByteBuffer(of: Int64.self, data: &int64BB), int64)

        // Double
        var double: Double = 1.0
        var doubleBB: ByteBuffer = createByteBuffer(&double)
        XCTAssertEqual(try decodeByteBuffer(of: Double.self, data: &doubleBB), double)

        // Float
        var float: Float = 2.0
        var floatBB: ByteBuffer = createByteBuffer(&float)
        XCTAssertEqual(try decodeByteBuffer(of: Float.self, data: &floatBB), float)

        // Boolean
        var boolean: Bool = true
        var booleanBB: ByteBuffer = createByteBuffer(&boolean)
        XCTAssertEqual(try decodeByteBuffer(of: Bool.self, data: &booleanBB), boolean)
    }

    func testDecodeSimpleStruct() {
        var structA: A = A()
        var structABB = createByteBuffer(&structA)
        XCTAssertEqual(try decodeByteBuffer(of: A.self, data: &structABB), structA)

        var structB: B = B()
        var structBBB = createByteBuffer(&structB)
        XCTAssertEqual(try decodeByteBuffer(of: B.self, data: &structBBB), structB)

        var structC1: C1 = C1()
        var structC1BB = createByteBuffer(&structC1)
        XCTAssertEqual(try decodeByteBuffer(of: C1.self, data: &structC1BB), structC1)

        var structC2: C2 = C2()
        var structC2BB = createByteBuffer(&structC2)
        XCTAssertEqual(try decodeByteBuffer(of: C2.self, data: &structC2BB), structC2)
    }

    func testDecodeNestedStruct() {
        var structAB: AB = AB()
        var structABBB = createByteBuffer(&structAB)
        XCTAssertEqual(try decodeByteBuffer(of: AB.self, data: &structABBB), structAB)

        var structBC1: BC1 = BC1()
        var structBC1BB = createByteBuffer(&structBC1)
        XCTAssertEqual(try decodeByteBuffer(of: BC1.self, data: &structBC1BB), structBC1)

        var structAC2: AC2 = AC2()
        var structAC2BB = createByteBuffer(&structAC2)
        XCTAssertEqual(try decodeByteBuffer(of: AC2.self, data: &structAC2BB), structAC2)

        var structABC1: ABC1 = ABC1()
        var structABC1BB = createByteBuffer(&structABC1)
        XCTAssertEqual(try decodeByteBuffer(of: ABC1.self, data: &structABC1BB), structABC1)

        var structABC2: ABC2 = ABC2()
        var structABC2BB = createByteBuffer(&structABC2)
        XCTAssertEqual(try decodeByteBuffer(of: ABC2.self, data: &structABC2BB), structABC2)
    }

    func testDecodeArray() throws {
        var arrABB = createByteBuffer(&arrA)
        XCTAssertEqual(try decodeByteBuffer(of: [A].self, data: &arrABB), arrA)

        var arrBBB = createByteBuffer(&arrB)
        XCTAssertEqual(try decodeByteBuffer(of: [B].self, data: &arrBBB), arrB)

        var arrC1BB = createByteBuffer(&arrC1)
        XCTAssertEqual(try decodeByteBuffer(of: [C1].self, data: &arrC1BB), arrC1)

        var arrABBB = createByteBuffer(&arrAB)
        XCTAssertEqual(try decodeByteBuffer(of: [AB].self, data: &arrABBB), arrAB)

        var arrAC1BB = createByteBuffer(&arrAC1)
        XCTAssertEqual(try decodeByteBuffer(of: [AC1].self, data: &arrAC1BB), arrAC1)

        var arrBC2BB = createByteBuffer(&arrBC2)
        XCTAssertEqual(try decodeByteBuffer(of: [BC2].self, data: &arrBC2BB), arrBC2)
    }

    func testInsufficientByteBuffer() {
        var structSmall: A = A()
        var smallByteBuffer = createByteBuffer(&structSmall)
        var emptyByteBuffer = ByteBuffer()
        XCTAssertThrowsError(try decodeByteBuffer(of: B.self, data: &emptyByteBuffer))
        XCTAssertThrowsError(try decodeByteBuffer(of: C1.self, data: &smallByteBuffer))
    }

}
