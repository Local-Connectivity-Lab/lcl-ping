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

/// Internal timer to keep track of the time elapsed for each packet sent.
///
/// A timer will be fired when the deadline is reached and the caller need to handle it.
/// Timer can be canceled at any time before it is fired.
internal struct TimerScheduler<Key: Hashable> {
    private let LABEL = "com.lcl.lclping"

    private var tracker: [Key: DispatchWorkItem]
    private let queue: DispatchQueue

    init() {
        self.queue = DispatchQueue(label: LABEL, qos: .utility)
        self.tracker = [:]
    }

    /// Schedule a timer for the given key with the given operation when the timer is fired
    ///
    /// If there is already a timer associated with the key, then the new operation will be ignored. Calling this function will result in a no-op.
    ///
    /// - Parameters:
    ///     - key: the key for which the timer will be scheduled
    ///     - operation: the operation that will be invoked when the timer is fired
    mutating func schedule(delay: Double, key: Key, operation: @escaping () -> Void) {
        if containsKey(key) {
            logger.debug("[\(#function)]: already scheduled a timer for packet #\(key). Ignore scheduling request")
            return
        }

        let timer = DispatchWorkItem(block: operation)

        self.tracker.updateValue(timer, forKey: key)
        self.queue.asyncAfter(deadline: .now() + delay, execute: timer)
    }

    /// Check whether the key has already associated with an existing timer
    ///
    /// - Returns: true if the key is associated with a timer; false otherwise
    func containsKey(_ key: Key) -> Bool {
        return self.tracker.keys.contains(key)
    }

    /// Remove and cancel the timer associated with the given key if the timer is not cancelled.
    ///
    /// If the key doesn't have any associated timer or the timer has already been cancelled, then calling this function will result in a no-op
    ///
    /// - Parameters:
    ///     - key: the key whose associated timer will be cancelled
    mutating func remove(key: Key) {
        if let timer = self.tracker.removeValue(forKey: key), !timer.isCancelled {
            logger.debug("[\(#function)]: removed timer for packet #\(key)")
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
        self.tracker.removeAll()
    }
}
