import Foundation
import SwiftAtomics

public class CoSemaphore: CustomStringConvertible, CustomDebugStringConvertible {

    let _value: Int

    var _count: AtomicInt

    let _name: String

    let _lock: DispatchSemaphore

    var _resumers: [CoroutineResumer]

    deinit {
    }

    public init(value: Int, _ name: String = "") {
        _value = value
        _count = AtomicInt()
        _count.initialize(value)
        _name = name
        _lock = DispatchSemaphore(value: 1)
        _resumers = []
    }

    public func wait(_ co: Coroutine) throws -> Void {
        try self.waitUntil(co) {
            return $0 > 0
        }
    }

    public func wait() throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try self.wait(co)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func wait() throws -> Void` !")
        }
    }

    public func waitUntil(_ co: Coroutine, _ cond: @escaping (Int) throws -> Bool) throws -> Void {
        _lock.wait()
        if try cond(self._count.load()) {
            defer {
                _lock.signal()
            }
            _count.decrement()
        } else {
            try co.yieldUntil { [unowned self] (resumer: @escaping CoroutineResumer) -> Void in
                defer {
                    _lock.signal()
                }
                _resumers.append(resumer)
                _count.decrement()
            }
        }
    }

    public func waitUntil(_ cond: @escaping (Int) throws -> Bool) throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try self.waitUntil(cond)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func waitUntil(_ cond: @escaping (Int) throws -> Bool) throws -> Void` !")
        }
    }

    public func signal() -> Void {
        _lock.wait()
        defer {
            _lock.signal()
        }

        _count.increment()
        if !_resumers.isEmpty {
            let resumer = _resumers.removeFirst()
            resumer()
        }
    }

    public func count() -> Int {
        let count = _count.load()
        return count < 0 ? 0 : count
    }

    public var debugDescription: String {
        return description
    }

    public var description: String {
        return "CoSemaphore(initValue: \(_value), count: \(count()), waiting: \(_resumers.count))"
    }
}
