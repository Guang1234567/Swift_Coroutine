import Foundation
import Swift_Boost_Context
import SwiftAtomics
import RxSwift
import RxCocoa
import RxBlocking

public enum CoroutineState: Int {
    case INITED = 0
    case STARTED = 1
    case RESTARTED = 2
    case YIELDED = 3
    case EXITED = 4
}

public typealias CoroutineScopeFn<T> = (Coroutine) throws -> T

public typealias CoroutineResumer = () -> Void

public class CoJob {

    var _isCanceled: AtomicBool
    let _co: Coroutine

    public var onStateChanged: Observable<CoroutineState> {
        self._co.onStateChanged
    }

    init(_ co: Coroutine) {
        self._isCanceled = AtomicBool()
        self._isCanceled.initialize(false)
        self._co = co
    }

    @discardableResult
    public func cancel() -> Bool {
        // can not cancel Coroutine
        _isCanceled.CAS(current: false, future: true)
    }

    public func join() throws -> Void {
        try _co.onStateChanged.ignoreElements().toBlocking().first()
    }
}

public protocol Coroutine {

    var currentState: CoroutineState { get }

    var onStateChanged: Observable<CoroutineState> { get }

    func yield() throws -> Void

    func yieldUntil(cond: () throws -> Bool) throws -> Void

    func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void

    func delay(_ timeInterval: DispatchTimeInterval) throws -> Void

    func continueOn(_ dispatchQueue: DispatchQueue) throws -> Void

}

enum CoroutineTransfer<T> {
    case YIELD
    case YIELD_UNTIL(Completable)
    case DELAY(DispatchTimeInterval)
    case CONTINUE_ON(DispatchQueue)
    case EXIT(Result<T, Error>)
}

class CoroutineImpl<T>: Coroutine, CustomDebugStringConvertible, CustomStringConvertible {

    let _name: String

    var _originCtx: BoostContext!

    var _yieldCtx: BoostContext?

    var _dispatchQueue: DispatchQueue

    let _task: CoroutineScopeFn<T>

    var _currentState: AtomicInt

    let _disposeBag: DisposeBag = DisposeBag()

    let _onStateChanged: AsyncSubject<CoroutineState>

    var currentState: CoroutineState {
        CoroutineState(rawValue: _currentState.load()) ?? .EXITED
    }

    var onStateChanged: Observable<CoroutineState> {
        return _onStateChanged.asObserver()
    }

    deinit {
        self._originCtx = nil
        self._yieldCtx = nil
        //print("CoroutineImpl deinit : _name = \(self._name)")
    }

    init(
            _ name: String,
            _ dispatchQueue: DispatchQueue,
            _ task: @escaping CoroutineScopeFn<T>
    ) {
        self._name = name
        self._onStateChanged = AsyncSubject()
        self._yieldCtx = nil
        self._dispatchQueue = dispatchQueue
        self._task = task
        self._currentState = AtomicInt()
        self._currentState.initialize(CoroutineState.INITED.rawValue)

        // issue: memory leak!
        //self.originCtx = makeBoostContext(self.coScopeFn)

        self._originCtx = makeBoostContext { [unowned self] (fromCtx: BoostContext, data: Void) -> Void in
            //print("\(self)  coScopeFn  :  \(fromCtx)  ---->  \(_bctx!)")
            self._currentState.CAS(current: CoroutineState.INITED.rawValue, future: CoroutineState.STARTED.rawValue)
            self.triggerStateChangedEvent(.STARTED)

            self._yieldCtx = fromCtx
            let result: Result<T, Error> = Result { [unowned self] in
                try self._task(self)
            }

            //print("\(self)  coScopeFn  :  \(self._fromCtx ?? fromCtx)  <----  ")
            let _: BoostTransfer<Void> = (self._yieldCtx ?? fromCtx).jump(data: CoroutineTransfer.EXIT(result))
            //print("Never jump back to here !!!")
        }
    }

    func triggerStateChangedEvent(_ state: CoroutineState) {
        self._onStateChanged.on(.next(state))
        if state == CoroutineState.EXITED {
            self._onStateChanged.on(.completed)
        }
    }

    /*
    func coScopeFn(_ fromCtx: BoostContext, _ data: Void) -> Void {
        //print("\(self)  coScopeFn  :  \(fromCtx)  ---->  \(_bctx!)")
        self._currentState.CAS(current: CoroutineState.INITED.rawValue, future: CoroutineState.STARTED.rawValue)
        self.triggerStateChangedEvent(.STARTED)

        self._yieldCtx = fromCtx
        let result: Result<T, Error> = Result { [unowned self] in
            try self._task(self)
        }

        //print("\(self)  coScopeFn  :  \(self._fromCtx ?? fromCtx)  <----  ")
        let _: BoostTransfer<Void> = (self._yieldCtx ?? fromCtx).jump(data: CoroutineTransfer.EXIT(result))
        //print("Never jump back to here !!!")
    }
    */

    func start() -> Void {
        let bctx: BoostContext = self._originCtx
        self._dispatchQueue.async(execute: self.makeResumer(bctx))
    }

    func resume(_ bctx: BoostContext, ctf: CoroutineTransfer<T>) -> Void {
        switch ctf {
            case .YIELD:
                //print("\(self)  --  YIELD")
                triggerStateChangedEvent(.YIELDED)
                //self._dispatchQueue.asyncAfter(deadline: .now() + .milliseconds(5), execute: self.makeResumer(bctx))
                self._dispatchQueue.async(execute: self.makeResumer(bctx))
                //print("\(self)  --  YIELD  -- finish")
            case .YIELD_UNTIL(let onJumpBack):
                //print("\(self)  --  YIELD_UNTIL")
                triggerStateChangedEvent(.YIELDED)
                onJumpBack.subscribe(onCompleted: {
                              //print("\(self)  --  YIELD_UNTIL2")
                              self._dispatchQueue.async(execute: self.makeResumer(bctx))
                          })
                          .disposed(by: self._disposeBag)
            case .DELAY(let timeInterval):
                //print("\(self)  --  DELAY  --  \(timeInterval)")
                triggerStateChangedEvent(.YIELDED)
                self._dispatchQueue.asyncAfter(deadline: .now() + timeInterval, execute: self.makeResumer(bctx))
                //print("\(self)  --  DELAY -- finish")
            case .CONTINUE_ON(let dq):
                triggerStateChangedEvent(.YIELDED)
                //print(" CONTINUE_ON - dispatchQueue - \(dq.label)")
                self._dispatchQueue = dq
                dq.async(execute: self.makeResumer(bctx))
            case .EXIT(let result):
                //print("\(self)  --  EXITED  --  \(result)")
                self._currentState.store(CoroutineState.EXITED.rawValue)
                triggerStateChangedEvent(.EXITED)

        }
    }

    func makeResumer(_ bctx: BoostContext) -> CoroutineResumer {
        return { [unowned self] in
            let btf: BoostTransfer<CoroutineTransfer<T>> = bctx.jump(data: ())
            let coTransfer: CoroutineTransfer<T> = btf.data
            return self.resume(btf.fromContext, ctf: coTransfer)
        }
    }

    func yield() throws -> Void {
        return try self._yield(CoroutineTransfer.YIELD)
    }

    func yieldUntil(cond: () throws -> Bool) throws -> Void {
        while !(try cond()) {
            try self.yield()
        }
    }

    func yieldUntil(_ beforeYield: (@escaping CoroutineResumer) -> Void) throws -> Void {
        let resumeNotifier: AsyncSubject<Never> = AsyncSubject()
        beforeYield({ resumeNotifier.on(.completed) })
        try self._yield(CoroutineTransfer.YIELD_UNTIL(resumeNotifier.asCompletable()))
    }

    func delay(_ timeInterval: DispatchTimeInterval) throws -> Void {
        try self._yield(CoroutineTransfer.DELAY(timeInterval))
    }

    func continueOn(_ dispatchQueue: DispatchQueue) throws {
        guard dispatchQueue != self._dispatchQueue else {
            return
        }
        try self._yield(CoroutineTransfer.CONTINUE_ON(dispatchQueue))
    }

    func _yield(_ ctf: CoroutineTransfer<T>) throws -> Void {
        // not in current coroutine scope
        // equals `func isInsideCoroutine() -> Bool`
        // ---------------
        guard let yieldCtx = self._yieldCtx else {
            throw CoroutineError.calledOutsideCoroutine(reason: "Call `yield()` outside Coroutine")
        }

        // jump back
        // ---------------
        _currentState.store(CoroutineState.YIELDED.rawValue)
        //print("\(self)  _yield  :  \(fromCtx)  <----  \(Thread.current)")
        let btf: BoostTransfer<Void> = yieldCtx.jump(data: ctf)
        // update `self._fromCtx` when restart
        self._yieldCtx = btf.fromContext
        _currentState.store(CoroutineState.RESTARTED.rawValue)
        triggerStateChangedEvent(.RESTARTED)
        //print("\(self)  _yield  :  \(btf.fromContext)  ---->  \(Thread.current)")
    }

    func isInsideCoroutine() -> Bool {
        return self._yieldCtx != nil
    }

    var debugDescription: String {
        return "CoroutineImpl(_name: \(_name))"
    }
    var description: String {
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