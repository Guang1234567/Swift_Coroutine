//
//  Platform.Linux.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(Linux) || os(Android)

import Foundation

extension Thread {
    static func setThreadLocalValue<T>(_ value: T?, forKey key: String) {
        if let newValue = value {
            Thread.current.threadDictionary[key] = newValue
        } else {
            Thread.current.threadDictionary[key] = nil
        }
    }

    static func getThreadLocalValueForKey<T>(_ key: String) -> T? {
        let currentThread = Thread.current
        let threadDictionary = currentThread.threadDictionary

        return threadDictionary[key] as? T
    }

    static func removeThreadLocalValueForKey(forKey key: String) {
        let currentThread = Thread.current
        let threadDictionary = currentThread.threadDictionary

        threadDictionary.removeObject(forKey: key)
    }
}

#endif
