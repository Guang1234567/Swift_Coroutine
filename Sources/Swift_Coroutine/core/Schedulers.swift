import Foundation

public protocol CoroutineScheduler {

    func scheduleTask(_ task: @escaping () -> Void) -> Void

}

public class ImmediateScheduler: CoroutineScheduler {

    public init() {
    }

    @inlinable
    public func scheduleTask(_ task: @escaping () -> Void) -> Void {
        task()
    }
}
