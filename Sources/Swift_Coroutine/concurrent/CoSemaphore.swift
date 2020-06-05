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
        try co.yieldUntil(cond: { [unowned self] in
            let result = self._count.load() > 0
            //print("\(self._name) self._count.load() > 0  == \(result)")
            return result
        })
        self._count.decrement()
    }

    public func signal() -> Void {
        self._count.increment()
    }

    public var description: String {
        return "CoSemaphore(_count: \(_count.load()))"
    }

    public var debugDescription: String {
        return "CoSemaphore(_count: \(_count.load()))"
    }
}
