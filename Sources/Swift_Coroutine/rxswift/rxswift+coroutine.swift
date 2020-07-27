import Foundation
import RxSwift

public struct RxCoEventProducer<E> {
    private let _co: Coroutine
    private let _coChannel: CoChannel<Event<E>>

    fileprivate init(_ co: Coroutine, _ coChannel: CoChannel<Event<E>>) {
        self._co = co
        self._coChannel = coChannel
    }

    public func send(_ e: E) throws -> Void {
        try _coChannel.send(_co, .next(e))
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

            let coConsumer = CoLauncher.launch(name: "", dispatchQueue: dispatchQueue) { (co: Coroutine) throws -> Void in
                for event in try channel.receive(co) {
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

            let coProducer: CoJob = CoLauncher.launch(name: "", dispatchQueue: dispatchQueue) { (co: Coroutine) throws -> Void in
                do {
                    try produceScope(RxCoEventProducer(co, channel))
                    try channel.send(co, .completed)
                } catch {
                    try channel.send(co, .error(error))
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