import Foundation
import RxSwift
import SwiftAtomics

public enum CoFutureError: Error {
    case canceled
}

public class CoFuture<R>: CustomDebugStringConvertible, CustomStringConvertible {

    let _name: String

    let _dispatchQueue: DispatchQueue

    let _task: CoroutineScopeFn<R>

    var _coJob: CoJob? = nil

    var _result: Result<R, Error>? = nil

    let _lock: DispatchSemaphore

    let _disposeBag: DisposeBag = DisposeBag()

    deinit {
        _coJob = nil
        _result = nil
        //print("CoFuture deinit()  - \(self._name)")
    }

    public init(_ name: String, _ dispatchQueue: DispatchQueue = DispatchQueue.global(), _ task: @escaping CoroutineScopeFn<R>) {
        self._name = name
        self._dispatchQueue = dispatchQueue
        self._task = task
        self._lock = DispatchSemaphore(value: 1)
    }

    public func async() -> CoFuture<R> {
        self.launchCo()
        return self
    }

    func launchCo() -> Void {
        self._lock.wait()
        defer {
            self._lock.signal()
        }

        // `self._coJob == nil` means `co` not started
        if self._coJob == nil && self._result == nil {
            self._coJob = CoLauncher.launch(name: "co_\(self._name)", dispatchQueue: self._dispatchQueue) { [unowned self](co: Coroutine) throws -> R in
                if self._result == nil {
                    self._result = Result {
                        try self._task(co)
                    }
                }
                return try self._result!.get()
            }
        }
    }

    @discardableResult
    public func await(_ co: Coroutine) throws -> R {
        self._lock.wait()
        if let result = self._result {
            defer {
                self._lock.signal()
            }
            return try result.get()
        } else {
            self._lock.signal()
        }

        try co.yieldUntil { [unowned self] (resumer: @escaping CoroutineResumer) -> Void in
            self.async()
            self._coJob?.onStateChanged.subscribe(onCompleted: resumer)
        }

        return try self._result!.get()
    }

    public func cancel() -> Bool {
        self._lock.wait()
        defer {
            self._lock.signal()
        }

        // `self._coJob == nil` means `co` not started
        if self._coJob == nil && self._result == nil {
            self._result = .failure(CoFutureError.canceled)
            return true
        } else {
            return false
        }
    }

    public var isCanceled: Bool {
        self._lock.wait()
        defer {
            self._lock.signal()
        }

        if case .failure(let error as CoFutureError)? = self._result {
            return error == .canceled
        }
        return false
    }

    public var debugDescription: String {
        return "CoFuture(_name: \(_name))"
    }

    public var description: String {
        return "CoFuture(_name: \(_name))"
    }
}
