//
//  TimerTests.swift
//  
//
//  Created by JOHN ZZN on 11/15/23.
//

import XCTest
@testable import LCLPing

class TimerTests: XCTestCase {
    
    func testSchedulerSetup() {
        let scheduler = TimerScheduler()
        XCTAssertFalse(scheduler.containsKey(1))
        XCTAssertFalse(scheduler.containsKey(2))
        XCTAssertFalse(scheduler.containsKey(3))
    }
    
    func testSchedulerWithOneTimer() {
        var scheduler = TimerScheduler()
        
        let exp = XCTestExpectation(description: "Timer fired")
        scheduler.schedule(delay: 1.0, key: 1) {
            exp.fulfill()
        }
        
        XCTAssertTrue(scheduler.containsKey(1))
        wait(for: [exp], timeout: 1.5)
    }
    
    func testSchedulerWithTwoTimers() {
        var scheduler = TimerScheduler()
        
        let exp1 = XCTestExpectation(description: "Timer 1 fired")
        scheduler.schedule(delay: 1.0, key: 1) {
            exp1.fulfill()
        }
        XCTAssertTrue(scheduler.containsKey(1))
        wait(for: [exp1], timeout: 1.5)
        
        
        let exp2 = XCTestExpectation(description: "Timer 2 fired")
        scheduler.schedule(delay: 2.0, key: 2) {
            exp2.fulfill()
        }
        XCTAssertTrue(scheduler.containsKey(2))
        wait(for: [exp2], timeout: 2.5)
    }
    
    func testSchedulerWithMultipleTimers() {
        var scheduler = TimerScheduler()
        var totalWaitime: TimeInterval = 0
        var expQueue: [XCTestExpectation] = []
        for i in 1...10 {
            totalWaitime += Double(i)
            let exp = XCTestExpectation(description: "Timer \(i) fired")
            expQueue.append(exp)
            scheduler.schedule(delay: Double(i), key: UInt16(i)) {
                exp.fulfill()
            }
        }
        
        wait(for: expQueue, timeout: totalWaitime + 0.5)
    }
    
    func testSchedulerWithDuplicateScheduling() {
        var scheduler = TimerScheduler()
        let expFired = XCTestExpectation(description: "Timer fired")
        scheduler.schedule(delay: 3.0, key: 1) {
            expFired.fulfill()
        }
        
        scheduler.schedule(delay: 1.0, key: 1) {
            XCTFail("This timer is a duplicate and should not be fired")
        }
        
        wait(for: [expFired], timeout: 3.5)
    }
    
    func testSchedulerWithScheduleAndRemove() {
        var scheduler = TimerScheduler()

        let exp = XCTestExpectation(description: "Timer fired")
        scheduler.schedule(delay: 1.0, key: 1) {
            XCTFail("Timer should have been canceled")
        }

        scheduler.remove(key: 1)
        XCTAssertFalse(scheduler.containsKey(1))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }
    
    func testSchedulerWithSequentialMultipleScheduleAndRemove() {
        var scheduler = TimerScheduler()
        for i in 1...20 {
            let exp = XCTestExpectation(description: "Timer fired")
            scheduler.schedule(delay: Double(i) * 2, key: UInt16(i)) {
                XCTFail("Timer should not get fird")
            }
            
            XCTAssertTrue(scheduler.containsKey(UInt16(i)))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                scheduler.remove(key: UInt16(i))
                XCTAssertFalse(scheduler.containsKey(UInt16(i)))
                exp.fulfill()
            }
            
            wait(for: [exp], timeout: 2)
        }
    }
    
    func testSchedulerWithSchduleAndRandomRemove() {
        var scheduler = TimerScheduler()
        var keptQueue: [XCTestExpectation] = []
        var removedQueue: [XCTestExpectation] = []
        var kept: [UInt16] = []
        var removed: [UInt16] = []
        for i in 1...20 {
            let shouldBeCancelled = Bool.random()
            let exp = shouldBeCancelled ? XCTestExpectation(description: "Timer should be cancelled") : XCTestExpectation(description: "Timer should fire")
            if !shouldBeCancelled {
                kept.append(UInt16(i))
                keptQueue.append(exp)
            } else {
                removed.append(UInt16(i))
                removedQueue.append(exp)
            }
            scheduler.schedule(delay: 0.5 * Double(i), key: UInt16(i)) {
                if shouldBeCancelled {
                    XCTFail("Timer should not fire because it is cancelled")
                } else {
                    exp.fulfill()
                }
            }
            XCTAssertTrue(scheduler.containsKey(UInt16(i)))
            if shouldBeCancelled {
                DispatchQueue.main.async {
                    scheduler.remove(key: UInt16(i))
                    exp.fulfill()
                }
            }
        }
        wait(for: removedQueue, timeout: 5)
        for remove in removed {
            XCTAssertFalse(scheduler.containsKey(remove), "key \(remove) in scheduler: \(scheduler.containsKey(remove))")
        }
        wait(for: keptQueue, timeout: 15)
        for keep in kept {
            XCTAssertTrue(scheduler.containsKey(keep))
        }
    }
    
    func testSchedulerWithRemoveAfterFire() {
        var scheduler = TimerScheduler()
        var expQueue: [XCTestExpectation] = []
        for i in 1...20 {
            let exp = XCTestExpectation(description: "Timer should fire")
            expQueue.append(exp)
            scheduler.schedule(delay: Double(i) * 0.1 + 0.5, key: UInt16(i)) {
                exp.fulfill()
            }
        }
        
        wait(for: expQueue, timeout: 3)
        for i in 1...20 {
            scheduler.remove(key: UInt16(i))
        }
        for i in 1...20 {
            XCTAssertFalse(scheduler.containsKey(UInt16(i)))
        }
    }
    
    func testSchedulerWithRemoveNonExistentKey() {
        var scheduler = TimerScheduler()
        scheduler.remove(key: 1)
        XCTAssertFalse(scheduler.containsKey(1))
    }
    
    func testSchedulerReset() {
        var scheduler = TimerScheduler()
        var expQueue: [XCTestExpectation] = []
        for i in 1...10 {
            let exp = XCTestExpectation(description: "Timer \(i) should not fire")
            expQueue.append(exp)
            scheduler.schedule(delay: Double(i) * 10.0, key: UInt16(i)) {
                XCTFail("Timer \(i) should've been cancelled")
            }
        }
        
        scheduler.reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            expQueue.forEach { exp in
                exp.fulfill()
            }
        }
        
        wait(for: expQueue, timeout: 5.0)
        for i in 1...10 {
            XCTAssertFalse(scheduler.containsKey(UInt16(i)))
        }
    }
}

