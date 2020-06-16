import Foundation
import SwiftAtomics

public class CoSemaphore: CustomStringConvertible, CustomDebugStringConvertible {

    var _count: AtomicInt

    let _name: String

    public init(value: Int, _ name: String = "") {
        self._count = AtomicInt()
        self._count.initialize(value)
        self._name = name
    }

    public func wait(_ co: Coroutine) throws -> Void {
        try co.yieldUntil { [unowned self] () -> Bool in
            self.count() > 0
        }
        self._count.decrement()
    }

    public func waitUntil(_ co: Coroutine, _ cond: @escaping (Int) throws -> Bool) throws -> Void {
        try co.yieldUntil { [unowned self] () throws -> Bool in
            return try cond(self.count())
        }
        self._count.decrement()
    }

    public func signal() -> Void {
        self._count.increment()
    }

    public func count() -> Int {
        return self._count.load()
    }

    public var description: String {
        return "CoSemaphore(_count: \(count()))"
    }

    public var debugDescription: String {
        return "CoSemaphore(_count: \(count()))"
    }
}
