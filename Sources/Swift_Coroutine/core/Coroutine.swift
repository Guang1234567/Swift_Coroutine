import Foundation
import Swift_Boost_Context
import SwiftAtomics
import RxSwift
import RxBlocking


public enum CoroutineState: Int {
    case INITED = 0
    case STARTED = 1
    case RESTARTED = 2
    case YIELDED = 3
    case EXITED = 4
}

public typealias CoroutineScopeFn<T> = () throws -> T

public typealias CoroutineResumer = () -> Void

public class CoJob {

    var _isCanceled: AtomicBool
    let _co: Coroutine

    public var onStateChanged: Observable<CoroutineState> {
        _co.onStateChanged
    }

    init(_ co: Coroutine) {
        _isCanceled = AtomicBool()
        _isCanceled.initialize(false)
        _co = co
    }

    @discardableResult
    public func cancel() -> Bool {
        // can not cancel Coroutine
        _isCanceled.CAS(current: false, future: true)
    }

    public func join() throws -> Void {
        _ = try _co.onStateChanged.ignoreElements().toBlocking().first()
    }
}

public protocol Coroutine {

    var currentState: CoroutineState { get }

    var onStateChanged: Observable<CoroutineState> { get }

    func yield() throws -> Void

    static func yield() throws -> Void

    func yieldUntil(cond: () throws -> Bool) throws -> Void

    static func yieldUntil(cond: () throws -> Bool) throws -> Void

    func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void

    static func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void

    func delay(_ timeInterval: DispatchTimeInterval) throws -> Void

    static func delay(_ timeInterval: DispatchTimeInterval) throws -> Void

    func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void

    static func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void

}

enum CoroutineTransfer<T> {
    case YIELD
    case YIELD_UNTIL(Completable)
    case DELAY(DispatchTimeInterval)
    case CONTINUE_ON(DispatchQueue)
    case EXIT(Result<T, Error>)
}

#if canImport(ObjectiveC)
let KEY_SWIFT_COROUTINE_THREAD_LOCAL: NSString = "__key_swift_coroutine_thread_local"
#else
let KEY_SWIFT_COROUTINE_THREAD_LOCAL: String = "__key_swift_coroutine_thread_local"
#endif

public class CoroutineImpl<T>: Coroutine, CustomDebugStringConvertible, CustomStringConvertible {

    let _name: String

    var _originCtx: FN_YIELD<Void, CoroutineTransfer<T>>!

    var _yieldCtx: FN_YIELD<CoroutineTransfer<T>, Void>!

    var _dispatchQueue: DispatchQueue

    let _task: CoroutineScopeFn<T>

    var _currentState: AtomicInt

    let _disposeBag: DisposeBag = DisposeBag()

    let _onStateChanged: AsyncSubject<CoroutineState>

    public var currentState: CoroutineState {
        CoroutineState(rawValue: _currentState.load()) ?? .EXITED
    }

    public var onStateChanged: Observable<CoroutineState> {
        return _onStateChanged.asObserver()
    }

    deinit {
        _yieldCtx = nil
        _originCtx = nil
        //print("CoroutineImpl deinit : _name = \(_name)")
    }

    init(
            _ name: String,
            _ dispatchQueue: DispatchQueue,
            _ task: @escaping CoroutineScopeFn<T>
    ) {
        _name = name
        _onStateChanged = AsyncSubject()
        _dispatchQueue = dispatchQueue
        _task = task
        _currentState = AtomicInt()
        _currentState.initialize(CoroutineState.INITED.rawValue)

        // issue: memory leak!
        //_originCtx = makeBoostContext(self.coScopeFn)

        _originCtx = makeBoostContext { [unowned self] (data: Void, yieldFn: @escaping FN_YIELD<CoroutineTransfer<T>, Void>) -> CoroutineTransfer<T> in
            return self.coScopeFn(data, yieldFn)
        }
    }

    func triggerStateChangedEvent(_ state: CoroutineState) {
        _onStateChanged.on(.next(state))
        if state == CoroutineState.EXITED {
            _onStateChanged.on(.completed)
        }
    }

    @inline(__always)
    func coScopeFn(_ data: Void, _ yieldFn: @escaping FN_YIELD<CoroutineTransfer<T>, Void>) -> CoroutineTransfer<T> {
        self._yieldCtx = yieldFn

        self._currentState.CAS(current: CoroutineState.INITED.rawValue, future: CoroutineState.STARTED.rawValue)
        self.triggerStateChangedEvent(.STARTED)

        let result: Result<T, Error> = Result { [unowned self] in
            try self._task()
        }

        return CoroutineTransfer.EXIT(result)
    }

    func start() -> Void {
        let bctx: FN_YIELD<Void, CoroutineTransfer<T>> = _originCtx
        _dispatchQueue.async(execute: self.makeResumer(bctx))
    }

    func resume(_ yield: @escaping FN_YIELD<Void, CoroutineTransfer<T>>, ctf: CoroutineTransfer<T>) -> Void {
        switch ctf {
        case .YIELD:
            //print("\(self)  --  YIELD")
            triggerStateChangedEvent(.YIELDED)
            //_dispatchQueue.asyncAfter(deadline: .now() + .milliseconds(5), execute: self.makeResumer(bctx))
            _dispatchQueue.async(execute: self.makeResumer(yield))
                //print("\(self)  --  YIELD  -- finish")
        case .YIELD_UNTIL(let onJumpBack):
            //print("\(self)  --  YIELD_UNTIL")
            triggerStateChangedEvent(.YIELDED)
            onJumpBack.subscribe(onCompleted: { [unowned self] in
                        //print("\(self)  --  YIELD_UNTIL2")
                        self._dispatchQueue.async(execute: self.makeResumer(yield))
                    })
                    .disposed(by: _disposeBag)
        case .DELAY(let timeInterval):
            //print("\(self)  --  DELAY  --  \(timeInterval)")
            triggerStateChangedEvent(.YIELDED)
            _dispatchQueue.asyncAfter(deadline: .now() + timeInterval, execute: self.makeResumer(yield))
                //print("\(self)  --  DELAY -- finish")
        case .CONTINUE_ON(let dq):
            triggerStateChangedEvent(.YIELDED)
            //print(" CONTINUE_ON - dispatchQueue - \(dq.label)")
            _dispatchQueue = dq
            dq.async(execute: self.makeResumer(yield))
        case .EXIT(_):
            //print("\(self)  --  EXITED  --  \(result)")
            _currentState.store(CoroutineState.EXITED.rawValue)
            triggerStateChangedEvent(.EXITED)

        }
    }

    func makeResumer(_ yield: @escaping FN_YIELD<Void, CoroutineTransfer<T>>) -> CoroutineResumer {
        return { [self] in
            Thread.setThreadLocalStorageValue(self, forKey: KEY_SWIFT_COROUTINE_THREAD_LOCAL)
            let coTransfer: CoroutineTransfer<T> = yield(())
            Thread.removeThreadLocalStorageValueForKey(forKey: KEY_SWIFT_COROUTINE_THREAD_LOCAL)
            return self.resume(yield, ctf: coTransfer)
        }
    }

    public func yield() throws -> Void {
        return try _yield(CoroutineTransfer.YIELD)
    }

    public static func yield() throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalStorageValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try co.yield()
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func yield() throws -> Void` !")
        }
    }

    public func yieldUntil(cond: () throws -> Bool) throws -> Void {
        while !(try cond()) {
            try self.yield()
        }
    }

    public static func yieldUntil(cond: () throws -> Bool) throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalStorageValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try co.yieldUntil(cond: cond)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func yieldUntil(cond: () throws -> Bool) throws -> Void` !")
        }
    }

    public func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void {
        let resumeNotifier: AsyncSubject<Never> = AsyncSubject()
        beforeYield({ resumeNotifier.on(.completed) })
        try _yield(CoroutineTransfer.YIELD_UNTIL(resumeNotifier.asCompletable()))
    }

    public static func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalStorageValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try co.yieldUntil(beforeYield)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void` !")
        }
    }

    public func delay(_ timeInterval: DispatchTimeInterval) throws -> Void {
        try _yield(CoroutineTransfer.DELAY(timeInterval))
    }

    public static func delay(_ timeInterval: DispatchTimeInterval) throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalStorageValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try co.delay(timeInterval)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func delay(_ timeInterval: DispatchTimeInterval) throws -> Void` !")
        }
    }

    public func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void {
        guard dispatchQueue !== _dispatchQueue else {
            return
        }
        try _yield(CoroutineTransfer.CONTINUE_ON(dispatchQueue))
    }

    public static func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void {
        let co: Coroutine? = Thread.getThreadLocalStorageValueForKey(KEY_SWIFT_COROUTINE_THREAD_LOCAL)
        if let co = co {
            return try co.continueOn(dispatchQueue)
        } else {
            throw CoroutineError.getCoroutineFromThreadLocalFail(reason: "get coroutine from thread-local fail when call `func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void` !")
        }
    }

    func _yield(_ ctf: CoroutineTransfer<T>) throws -> Void {
        // not in current coroutine scope
        // equals `func isInsideCoroutine() -> Bool`
        // ---------------
        if _yieldCtx == nil {
            throw CoroutineError.calledOutsideCoroutine(reason: "Call `yield()` outside Coroutine")
        }

        // jump back
        // ---------------
        _currentState.store(CoroutineState.YIELDED.rawValue)
        //print("\(self)  _yield  :  \(fromCtx)  <----  \(Thread.current)")
        let _: Void = _yieldCtx(ctf)
        _currentState.store(CoroutineState.RESTARTED.rawValue)
        triggerStateChangedEvent(.RESTARTED)
        //print("\(self)  _yield  :  \(btf.fromContext)  ---->  \(Thread.current)")
    }

    func isInsideCoroutine() -> Bool {
        return _yieldCtx != nil
    }

    public var debugDescription: String {
        return "CoroutineImpl(_name: \(_name))"
    }
    public var description: String {
        return "CoroutineImpl(_name: \(_name))"
    }

}


public class CoLauncher {
    public static func launch<T>(
            name: String = "",
            dispatchQueue: DispatchQueue,
            _ task: @escaping CoroutineScopeFn<T>
    ) -> CoJob {
        let co: CoroutineImpl = CoroutineImpl<T>(name, dispatchQueue, task)
        co.start()
        return CoJob(co)
    }
}


extension CoroutineImpl: ReactiveCompatible {

}


extension Reactive where Base: CoroutineImpl<Any> {

}