//
//  Platform.Darwin.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import Darwin
import Foundation

extension Thread {
    static func setThreadLocalValue<T: AnyObject>(_ value: T?, forKey key: NSCopying) {
        let currentThread = Thread.current
        let threadDictionary = currentThread.threadDictionary

        if let newValue = value {
            threadDictionary[key] = newValue
        } else {
            threadDictionary[key] = nil
        }
    }

    static func getThreadLocalValueForKey<T>(_ key: NSCopying) -> T? {
        let currentThread = Thread.current
        let threadDictionary = currentThread.threadDictionary

        return threadDictionary[key] as? T
    }

    static func removeThreadLocalValueForKey(forKey key: NSCopying) {
        let currentThread = Thread.current
        let threadDictionary = currentThread.threadDictionary

        threadDictionary.removeObject(forKey: key)
    }
}

#endif
