import Foundation
import RxSwift

// https://github.com/Kotlin/kotlinx.coroutines/blob/1.3.1/reactive/coroutines-guide-reactive.md#backpressure

public struct RxCoEventProducer<E> {
    private let _coChannel: CoChannel<Event<E>>

    fileprivate init(_ coChannel: CoChannel<Event<E>>) {
        self._coChannel = coChannel
    }

    public func send(_ e: E) throws -> Void {
        try _coChannel.send(.next(e))
    }
}

extension ObservableType {

    public static func coroutineCreate(
            capacity: Int = 1,
            dispatchQueue: DispatchQueue,
            produceScope: @escaping (RxCoEventProducer<Element>) throws -> Void
    ) -> Observable<Element> {

        return Observable<Element>.create { (observer) -> Disposable in
            let channel = CoChannel<Event<Element>>(name: "", capacity: capacity)

            let coConsumer = CoLauncher.launch(name: "", dispatchQueue: dispatchQueue) { () throws -> Void in
                for event in try channel.receive() {
                    switch event {
                    case .next:
                        observer.on(event)
                        break
                    case .error:
                        observer.on(event)
                        return
                    case .completed:
                        observer.on(event)
                        return
                    }
                }
            }

            let coProducer: CoJob = CoLauncher.launch(name: "", dispatchQueue: dispatchQueue) { () throws -> Void in
                do {
                    try produceScope(RxCoEventProducer(channel))
                    try channel.send(.completed)
                } catch {
                    try channel.send(.error(error))
                }
            }

            return Disposables.create {
                if !channel.isClosed() {
                    channel.close()
                }
            }
        }
    }
}