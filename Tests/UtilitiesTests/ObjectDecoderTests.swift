//
//  ObjectDecoderTests.swift
//  
//
//  Created by JOHN ZZN on 11/5/23.
//

import XCTest
@testable import LCLPing
import NIOCore

final class ObjectDecoderTests: XCTestCase {
    
    fileprivate struct A {
        let a: Int32 = 1
    }
    
    fileprivate struct B {
        let b1: Int8 = 2
        let b2: Bool = true
    }
    
    fileprivate struct C1 {
        let c1: Double = 1.0
        let c2: Int16 = 2
        let c3: Bool = false
        let c4: Int64 = 3
    }
    
    fileprivate struct C2 {
        let c3: Bool = false
        let c1: Double = 1.0
        let c2: Int16 = 2
        let c4: Int64 = 3
    }
    
    fileprivate struct AB {
        let a: A = A()
        let b: B = B()
    }
    
    fileprivate struct AC1 {
        let a: A = A()
        let c: C1 = C1()
    }
    
    fileprivate struct AC2 {
        let a: A = A()
        let c: C2 = C2()
    }
    
    fileprivate struct BC1 {
        let b: B = B()
        let c: C1 = C1()
    }
    
    fileprivate struct BC2 {
        let b: B = B()
        let c: C2 = C2()
    }
    
    fileprivate struct ABC1 {
        let a: A = A()
        let b: B = B()
        let c: C1 = C1()
    }
    
    fileprivate struct ABC2 {
        let a: A = A()
        let b: B = B()
        let c: C2 = C2()
    }
    
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
        XCTAssertEqual(decodeByteBuffer(of: Int8.self, data: &int8BB), int8)
        
        // Int16
        let int16: Int16 = 2
        var int16BB = ByteBuffer(integer: int16, endianness: .little)
        XCTAssertEqual(decodeByteBuffer(of: Int16.self, data: &int16BB), int16)
        
        // Int32
        let int32: Int32 = 3
        var int32BB = ByteBuffer(integer: int32, endianness: .little)
        XCTAssertEqual(decodeByteBuffer(of: Int32.self, data: &int32BB), int32)
        
        // Int64
        let int64: Int64 = 4
        var int64BB = ByteBuffer(integer: int64, endianness: .little)
        XCTAssertEqual(decodeByteBuffer(of: Int64.self, data: &int64BB), int64)
        
        // Double
        var double: Double = 1.0
        var doubleBB: ByteBuffer = createByteBuffer(&double)
        XCTAssertEqual(decodeByteBuffer(of: Double.self, data: &doubleBB), double)
        
        // Float
        var float: Float = 2.0
        var floatBB: ByteBuffer = createByteBuffer(&float)
        XCTAssertEqual(decodeByteBuffer(of: Float.self, data: &floatBB), float)
        
        // Boolean
        var boolean: Bool = true
        var booleanBB: ByteBuffer = createByteBuffer(&boolean)
        XCTAssertEqual(decodeByteBuffer(of: Bool.self, data: &booleanBB), boolean)
    }

}
