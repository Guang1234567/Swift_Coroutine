import Foundation
import Swift_Coroutine

enum TestError: Error {
    case SomeError(reason: String)
}

func main() throws {

    // Example-01
    // ===================
    print("Example-01 =============================")

    //let queue = DispatchQueue(label: "TestCoroutine")
    let queue = DispatchQueue.global()

    print("co1 =============================")

    let co1 = launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 01 - end \(Thread.current)")
        }
        print("co 01 - start \(Thread.current)")
        try co.yield()
        return "co1 's result"
    }

    print("co2 =============================")

    let co2 = launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 02 - end \(Thread.current)")
        }
        print("co 02 - start \(Thread.current)")
        try co.yield()
        throw TestError.SomeError(reason: "Occupy some error in co2")
        return "co2 's result"
    }

    print("co3 =============================")

    let co3 = launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 03 - end \(Thread.current)")
        }
        print("co 03 - start \(Thread.current)")
        try co.yield()
        return "co3 's result"
    }

    print("while =============================")

    while !(co1.currentState == .EXITED
            && co2.currentState == .EXITED
            && co3.currentState == .EXITED
    ) {
        //print("while ing ...")
    }

    print("co1.currentState = \(co1.currentState)")
    print("co2.currentState = \(co2.currentState)")
    print("co3.currentState = \(co3.currentState)")


    // Example-02
    // ===================
    print("Example-02 =============================")

    let producerQueue = DispatchQueue(label: "producerQueue", attributes: .concurrent)
    let consumerQueue = DispatchQueue(label: "consumerQueue", attributes: .concurrent)
    let semFull = CoSemaphore(value: 8, "full")
    let semEmpty = CoSemaphore(value: 0, "empty")
    let semMutex = DispatchSemaphore(value: 1)
    var buffer: [Int] = []

    let coConsumer = launch(dispatchQueue: consumerQueue) { (co: Coroutine) throws -> Void in
        for time in (1...32) {
            try semEmpty.wait(co)
            semMutex.wait()
            if buffer.isEmpty {
                fatalError()
            }
            let consumedItem = buffer.removeFirst()
            print("consume : \(consumedItem)  -- at \(time)   \(Thread.current)")
            semMutex.signal()
            semFull.signal()
        }
    }

    let coProducer = launch(dispatchQueue: producerQueue) { (co: Coroutine) throws -> Void in
        for time in (1...32).reversed() {
            try semFull.wait(co)
            semMutex.wait()
            buffer.append(time)
            print("produced : \(time)   \(Thread.current)")
            semMutex.signal()
            semEmpty.signal()
        }
    }

    while !(coProducer.currentState == .EXITED
            && coConsumer.currentState == .EXITED
    ) {
        //print("while ing ...")
    }

    print("finally, buffer = \(buffer)")
    print("semFull = \(semFull)")
    print("semEmpty = \(semEmpty)")
    print("coProducer.currentState = \(coProducer.currentState)")
    print("coConsumer.currentState = \(coConsumer.currentState)")
}

do {
    try main()
} catch {
    print("main : \(error)")
}