import Foundation
import SwiftAtomics

public enum CoChannelError: Error {
    case closed
}

public class CoChannel<E>: CustomDebugStringConvertible, CustomStringConvertible {

    let _semFull: CoSemaphore

    let _semEmpty: CoSemaphore

    let _lock: DispatchSemaphore

    var _buffer: [E]

    var _isClosed: AtomicBool

    var _name: String!

    public init(name: String? = nil, capacity: Int = 7) {
        self._semFull = CoSemaphore(value: capacity, "CoChannel_Full")
        self._semEmpty = CoSemaphore(value: 0, "CoChannel_Empty")
        self._lock = DispatchSemaphore(value: 1)
        self._buffer = []
        self._isClosed = AtomicBool()
        self._isClosed.initialize(false)
        self._name = name ?? "\(ObjectIdentifier(self))"
    }

    public func send(_ co: Coroutine, _ e: E) throws -> Void {
        try self._semFull.waitUntil(co) { [unowned self]  count in
            if self.isClosed() {
                throw CoChannelError.closed
            }
            return count > 0
        }
        defer {
            self._semEmpty.signal()
        }

        self._lock.wait()
        defer {
            self._lock.signal()
        }
        self._buffer.append(e)
    }

    func _receive(_ co: Coroutine) throws -> E {
        try self._semEmpty.waitUntil(co) { [unowned self] count in
            if self.isClosed() && count <= 0 {
                throw CoChannelError.closed
            }
            return count > 0
        }
        defer {
            self._semFull.signal()
        }

        self._lock.wait()
        defer {
            self._lock.signal()
        }
        return self._buffer.removeFirst()
    }

    public func receive(_ co: Coroutine) throws -> AnyIterator<E> {
        return AnyIterator { [unowned self] in
            return try? self._receive(co)
        }
    }

    public func close() -> Void {
        if _isClosed.CAS(current: false, future: true) {
        }
    }

    public func isClosed() -> Bool {
        self._isClosed.load()
    }

    public var debugDescription: String {
        return "CoChannel(_name: \(String(describing: _name)), _isClosed: \(isClosed()), _semFull: \(_semFull), _semEmpty: \(_semEmpty))"
    }

    public var description: String {
        return "CoChannel(_name: \(String(describing: _name)), _isClosed: \(isClosed()), _semFull: \(_semFull), _semEmpty: \(_semEmpty))"
    }

}
