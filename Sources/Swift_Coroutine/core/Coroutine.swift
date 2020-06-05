import Foundation
import Swift_Boost_Context

public enum CoroutineState: Int {
    case INITED = 0
    case STARTED = 1
    case RESTARTED = 2
    case YIELDED = 3
    case EXITED = 4
}

public typealias CoroutineTASK<T> = (Coroutine) throws -> T

public protocol Coroutine {

    var currentState: CoroutineState { get }

    func yield() throws -> Void

    func yieldUntil(cond: () -> Bool) throws -> Void

    func yieldWhile(cond: () -> Bool) throws -> Void
}

class CoroutineTransfer<T> {
    let state: CoroutineState
    let result: T

    init(_ state: CoroutineState, _ result: T) {
        self.state = state
        self.result = result
    }
}

extension Coroutine {
}

class CoroutineImpl<T>: Coroutine {

    var _fromCtx: BoostContext?

    let _dispatchQueue: DispatchQueue

    let _task: CoroutineTASK<T>

    var _bctx: BoostContext!

    var _currentState: CoroutineState!

    var currentState: CoroutineState {
        self._currentState
    }

    deinit {
        self._fromCtx = nil
    }

    init(
            _ dispatchQueue: DispatchQueue,
            _ task: @escaping CoroutineTASK<T>
    ) {
        self._fromCtx = nil
        self._dispatchQueue = dispatchQueue
        self._task = task
        self._bctx = makeBoostContext(self.coScopeFn)
        self._currentState = .INITED
    }

    func coScopeFn(_ fromCtx: BoostContext, data: Void) -> Void {
        _currentState = .STARTED

        self._fromCtx = fromCtx
        let result: Result<T, Error> = Result {
            try self._task(self)
        }

        let _: BoostTransfer<Void> = (self._fromCtx ?? fromCtx).jump(data: CoroutineTransfer(.EXITED, result))
    }

    func resume() -> Void {
        return resume(self._bctx)
    }

    func resume(_ bctx: BoostContext) -> Void {
        self._dispatchQueue.async { [unowned self] in
            do {
                let btf: BoostTransfer<CoroutineTransfer<Result<T, Error>>> = bctx.jump(data: ())
                let coState: CoroutineState = btf.data.state
                switch coState {
                    case .YIELDED:
                        let yieldedFromCtx: BoostContext = btf.fromContext
                        return self.resume(yieldedFromCtx)
                    case .EXITED:
                        //let coTransfer: CoroutineTransfer<Result<T, Error>> = btf.data
                        //let result: Result<T, Error> = coTransfer.result
                        //print("EXITED : \(result)")
                        self._currentState = .EXITED
                        return
                    default:
                        return
                }
            } catch {
                print("CoroutineImpl start fail : \(error)")
            }
        }
    }

    func yield() throws -> Void {
        // not in current coroutine scope
        // equals `func isInsideCoroutine() -> Bool`
        // ---------------
        guard let fromCtx = self._fromCtx else {
            throw CoroutineError.calledOutsideCoroutine(reason: "Call `yield()` outside Coroutine")
        }

        // jump back
        // ---------------
        self._currentState = .YIELDED
        let btf: BoostTransfer<Void> = fromCtx.jump(data: CoroutineTransfer(.YIELDED, ()))
        // update `self._fromCtx` when restart
        self._fromCtx = btf.fromContext
        self._currentState = .RESTARTED
    }

    func yieldUntil(cond: () -> Bool) throws -> Void {
        while !cond() {
            try self.yield()
        }
    }

    @inlinable
    func yieldWhile(cond: () -> Bool) throws -> Void {
        try yieldUntil(cond: { !cond() })
    }

    func isInsideCoroutine() -> Bool {
        return self._fromCtx != nil
    }
}


public func launch<T>(
        dispatchQueue: DispatchQueue,
        _ task: @escaping CoroutineTASK<T>
) -> Coroutine {
    let co: CoroutineImpl = CoroutineImpl<T>(dispatchQueue, task)
    co.resume()
    return co
}