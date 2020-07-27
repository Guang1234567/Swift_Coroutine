import Foundation
import SwiftAtomics

open class CoScope {

    var _coJobs: [CoJob]

    var _isCanceled: AtomicBool

    deinit {
        // auto
        cancel()
    }

    init() {
        _coJobs = []
        _isCanceled = AtomicBool()
        _isCanceled.initialize(false)
    }

    @discardableResult
    public final func cancel() -> Bool {
        let r = _isCanceled.CAS(current: false, future: true)
        if r {
            for job in _coJobs {
                job.cancel()
            }
        }
        return r
    }
}

extension CoScope {
    public func launch<T>(
            name: String = "",
            dispatchQueue: DispatchQueue,
            _ task: @escaping CoroutineScopeFn<T>
    ) -> CoJob {
        let coJob = CoLauncher.launch(name: name, dispatchQueue: dispatchQueue, task)
        _coJobs.append(coJob)
        return coJob
    }
}
