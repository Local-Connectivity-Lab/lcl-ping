//
//  TimerScheduler.swift
//  
//
//  Created by JOHN ZZN on 8/24/23.
//

import Foundation

/// Internal timer to keep track of the time elapsed for each packet sent.
///
/// A timer will be fired when the deadline is reached and the caller need to handle it.
/// Timer can be canceled at any time before it is fired.
internal struct TimerScheduler {
    private static let LABEL = "com.lcl.lclping"

    private var tracker: Dictionary<UInt16, DispatchWorkItem>
    private let queue: DispatchQueue
    
    init() {
        self.queue = DispatchQueue(label: TimerScheduler.LABEL, qos: .utility)
        self.tracker = [:]
    }
    
    /// Schedule a timer for the given key with the given operation when the timer is fired
    ///
    /// If there is already a timer associated with the key, then the new operation will be ignored. Calling this function will result in a no-op.
    ///
    /// - Parameters:
    ///     - key: the key for which the timer will be scheduled
    ///     - operation: the operation that will be invoked when the timer is fired
    mutating func schedule(delay: Double, key: UInt16, operation: @escaping () -> Void) {
        if containsKey(key) {
            return
        }
        
        let timer = DispatchWorkItem(block: operation)
        
        self.tracker.updateValue(timer, forKey: key)
        self.queue.asyncAfter(deadline: .now() + delay, execute: timer)
    }
    
    /// Check whether the key has already associated with an existing timer
    ///
    /// - Returns: true if the key is associated with a timer; false otherwise
    func containsKey(_ key: UInt16) -> Bool {
        return self.tracker.keys.contains(key)
    }
    
    /// Cancel the timer associated with the given key
    ///
    /// If the key doesn't have any associated timer, then calling this function will result in a no-op
    ///
    /// - Parameters:
    ///     - key: the key whose associated timer will be cancelled
    mutating func cancel(key: UInt16) {
        if let timer = self.tracker.removeValue(forKey: key) {
            timer.cancel()
        }
    }
    
    /// Reset and cancel all timers that are currently scheduled
    ///
    /// The capacity will be kept
    mutating func reset() {
        self.tracker.forEach { (_, timer) in
            timer.cancel()
        }
        self.tracker.removeAll(keepingCapacity: true)
    }
}
