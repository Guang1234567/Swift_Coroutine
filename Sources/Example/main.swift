import Foundation
import Swift_Coroutine
import Swift_Boost_Context
import RxSwift

enum TestError: Error {
    case SomeError(reason: String)
}

func example_01() throws {
    // Example-01
    // ===================
    print("Example-01 =============================")

    //let queue = DispatchQueue(label: "TestCoroutine")
    let queue = DispatchQueue.global()

    let coJob1 = CoLauncher.launch(name: "co1", dispatchQueue: queue) { () throws -> String in
        defer {
            print("co 01 - end \(Thread.current)")
        }
        print("co 01 - start \(Thread.current)")
        try CoroutineImpl<Any>.yield()
        return "co1 's result"
    }

    let coJob2 = CoLauncher.launch(name: "co2", dispatchQueue: queue) { () throws -> String in
        defer {
            print("co 02 - end \(Thread.current)")
        }
        print("co 02 - start \(Thread.current)")
        try CoroutineImpl<Any>.yield()
        throw TestError.SomeError(reason: "Occupy some error in co2")
        return "co2 's result"
    }

    let coJob3 = CoLauncher.launch(name: "co3", dispatchQueue: queue) { () throws -> String in
        defer {
            print("co 03 - end \(Thread.current)")
        }
        print("co 03 - start \(Thread.current)")
        try CoroutineImpl<Any>.yield()
        return "co3 's result"
    }

    try coJob1.join()
    try coJob2.join()
    try coJob3.join()

    print("Example-01 =============  end  ===============")
}

func example_02() throws {
    // Example-02
    // ===================
    print("Example-02 =============================")

    let producerQueue = DispatchQueue(label: "producerQueue", attributes: .concurrent)
    let consumerQueue = DispatchQueue(label: "consumerQueue", attributes: .concurrent)
    let semFull = CoSemaphore(value: 8, "full")
    let semEmpty = CoSemaphore(value: 0, "empty")
    let semMutex = CoSemaphore(value: 1, "mutex")
    //let semMutex = DispatchSemaphore(value: 1)
    var buffer: [Int] = []

    let coConsumer = CoLauncher.launch(dispatchQueue: consumerQueue) { () throws -> Void in
        for time in (1...32) {
            try semEmpty.wait()
            try semMutex.wait()
            if buffer.isEmpty {
                fatalError()
            }
            let consumedItem = buffer.removeFirst()
            print("consume : \(consumedItem)  -- at \(time)   \(Thread.current)")
            semMutex.signal()
            semFull.signal()
        }
    }

    let coProducer = CoLauncher.launch(dispatchQueue: producerQueue) { () throws -> Void in
        for time in (1...32).reversed() {
            try semFull.wait()
            try semMutex.wait()
            buffer.append(time)
            print("produced : \(time)   \(Thread.current)")
            semMutex.signal()
            semEmpty.signal()
        }
    }

    try coConsumer.join()
    try coProducer.join()

    print("finally, buffer = \(buffer)")
    print("semFull  = \(semFull)")
    print("semEmpty = \(semEmpty)")
    print("semMutex = \(semMutex)")
}

func example_03() throws {
    // Example-03
    // ===================
    print("Example-03 =============================")

    //let queue = DispatchQueue(label: "TestCoroutine")
    let queue = DispatchQueue.global()

    let coDelay = CoLauncher.launch(dispatchQueue: queue) { () throws -> String in
        print("coDelay - start \(Thread.current)")
        let start = Date.timeIntervalSinceReferenceDate
        try CoroutineImpl<Any>.delay(.seconds(2))
        let end = Date.timeIntervalSinceReferenceDate
        print("coDelay - end \(Thread.current)  in \((end - start) * 1000) ms")
        return "coDelay 's result"
    }

    try coDelay.join()
}

func example_04() throws {
    // Example-04
    // ===================
    print("Example-04 =============================")
    let start = Date.timeIntervalSinceReferenceDate
    let queue = DispatchQueue(label: "example_04", attributes: .concurrent)
    let coJob = CoLauncher.launch(name: "coTestNestFuture", dispatchQueue: queue) { () throws -> Void in
        var sum: Int = 0
        for i in (1...100) {
            //print("--------------------   makeCoFuture_01_\(i) --- await(\(co)) -- before")
            try CoroutineImpl<Any>.continueOn(.global())
            sum += try makeCoFuture_01("makeCoFuture_01_\(i)", queue, i).await()
            try CoroutineImpl<Any>.continueOn(.main)
            //print("--------------------   makeCoFuture_01_\(i) --- await(\(co)) -- end")
        }
        print("sum = \(sum)")
    }
    try coJob.join()

    //print("Thread.sleep(forTimeInterval: 5)")
    let end = Date.timeIntervalSinceReferenceDate
    print("coFuture - end \(Thread.current)  in \((end - start) * 1000) ms")
    //Thread.sleep(forTimeInterval: 1)
}

func makeCoFuture_01(_ name: String, _ dispatchQueue: DispatchQueue, _ i: Int) -> CoFuture<Int> {
    return CoFuture(name, dispatchQueue) { () in
        var sum: Int = 0
        for j in (1...100) {
            //print("--------------------   makeCoFuture_02_\(j) --- await(\(co)) -- before")
            try CoroutineImpl<Any>.continueOn(.main)
            sum += try makeCoFuture_02("makeCoFuture_02_\(j)", dispatchQueue, j).await()
            try CoroutineImpl<Any>.continueOn(.global())
            //print("--------------------   makeCoFuture_02_\(j) --- await(\(co)) -- end")
        }
        return sum
    }
}

func makeCoFuture_02(_ name: String, _ dispatchQueue: DispatchQueue, _ i: Int) -> CoFuture<Int> {
    return CoFuture(name, dispatchQueue) { () in
        //try CoroutineImpl<Any>.delay(.milliseconds(5))
        return i
    }
}

func example_05() throws {
    // Example-05
    // ===================
    print("Example-05 =============================")

    let consumerQueue = DispatchQueue(label: "consumerQueue", qos: .userInteractive, attributes: .concurrent)
    let producerQueue_01 = DispatchQueue(label: "producerQueue_01", /*qos: .background,*/ attributes: .concurrent)
    let producerQueue_02 = DispatchQueue(label: "producerQueue_02", /*qos: .background,*/ attributes: .concurrent)
    let producerQueue_03 = DispatchQueue(label: "producerQueue_03", /*qos: .background,*/ attributes: .concurrent)
    let closeQueue = DispatchQueue(label: "closeQueue", /*qos: .background,*/ attributes: .concurrent)
    let channel = CoChannel<Int>(name: "CoChannel_Example-05", capacity: 1)

    let coClose = CoLauncher.launch(name: "coClose", dispatchQueue: closeQueue) { () throws -> Void in
        try CoroutineImpl<Any>.delay(.milliseconds(100))
        print("coClose before  --  delay")
        //try CoroutineImpl<Any>.yield()
        channel.close()
        print("coClose after  --  delay")
    }

    let coConsumer = CoLauncher.launch(name: "coConsumer", dispatchQueue: consumerQueue) { () throws -> Void in
        var time: Int = 1
        for item in try channel.receive() {
            try CoroutineImpl<Any>.delay(.milliseconds(15))
            //try CoroutineImpl<Any>.delay(.milliseconds(5))
            print("consumed : \(item)  --  \(time)  --  \(Thread.current)")
            time += 1
        }
        print("coConsumer  --  end")
    }

    let coProducer01 = CoLauncher.launch(name: "coProducer01", dispatchQueue: producerQueue_01) { () throws -> Void in
        for time in (1...20).reversed() {
            try CoroutineImpl<Any>.delay(.milliseconds(10))
            //print("coProducer01  --  before produce : \(time)")
            try channel.send(time)
            print("coProducer01  --  after produce : \(time)")
        }
        print("coProducer01  --  end")
    }

    let coProducer02 = CoLauncher.launch(name: "coProducer02", dispatchQueue: producerQueue_02) { () throws -> Void in
        for time in (21...40).reversed() {
            //print("coProducer02  --  before produce : \(time)")
            try CoroutineImpl<Any>.delay(.milliseconds(10))
            try channel.send(time)
            print("coProducer02  --  after produce : \(time)")
        }
        print("coProducer02  --  end")
    }

    let coProducer03 = CoLauncher.launch(name: "coProducer03", dispatchQueue: producerQueue_03) { () throws -> Void in
        for time in (41...60).reversed() {
            //print("coProducer02  --  before produce : \(time)")
            try CoroutineImpl<Any>.delay(.milliseconds(10))
            try channel.send(time)
            print("coProducer03  --  after produce : \(time)")
        }
        print("coProducer03  --  end")
    }

    try coClose.join()
    try coConsumer.join()
    try coProducer01.join()
    try coProducer02.join()
    try coProducer03.join()

    print("channel = \(channel)")
}

func example_06() throws {
    // Example-06
    // ===================
    print("Example-06 =============================")

    let queue = DispatchQueue.global()
    let queue_001 = DispatchQueue(label: "queue_001", attributes: .concurrent)
    let queue_002 = DispatchQueue(label: "queue_002", attributes: .concurrent)

    queue.async {
        Thread.sleep(forTimeInterval: 0.005)
        print("other job \(Thread.current)")
    }

    let coJob1 = CoLauncher.launch(name: "co1", dispatchQueue: queue) { () throws -> String in
        defer {
            print("co 01 - end \(Thread.current)")
        }
        print("co 01 - start \(Thread.current)")
        try CoroutineImpl<Any>.continueOn(queue_001)
        print("co 01 - continueOn - queue_001 -  \(Thread.current)")
        try CoroutineImpl<Any>.continueOn(DispatchQueue.main)
        print("co 01 - continueOn - queue_main -  \(Thread.current)")
        try CoroutineImpl<Any>.continueOn(queue_002)
        print("co 01 - continueOn - queue_002 -  \(Thread.current)")
        try CoroutineImpl<Any>.continueOn(queue)

        return "co1 's result"
    }

    try coJob1.join()

    Thread.sleep(forTimeInterval: 1)
}

/// Coroutine instead of `BackPress` in RxSwift RxJava
func example_07() throws {
    // Example-07
    // ===================
    print("Example-07 =============================")
    let bag = DisposeBag()
    let rxProducerQueue_01 = DispatchQueue(label: "rx_producerQueue_01", qos: .background, attributes: .concurrent)
    let rxProducerQueue_02 = DispatchQueue.global()
    let ob = Observable<Int>.coroutineCreate(dispatchQueue: rxProducerQueue_01) { (eventProducer) in
        for time in (1...20).reversed() {
            if time % 2 == 0 {
                try CoroutineImpl<Any>.continueOn(rxProducerQueue_01)
            } else {
                try CoroutineImpl<Any>.continueOn(rxProducerQueue_02)
            }
            try eventProducer.send(time)
            print("produce: \(time) -- \(Thread.current)")

            if time == 11 {
                return // exit in a half-way, no more event be produced
            }
            /*if time == 10 {
                throw TestError.SomeError(reason: "Occupy some exception in a half-way, no more event be produced") // occupy exception in a half-way, no more event be produced
            }*/
        }
    }

    let _ = ob.subscribe(
                    onNext: { (text) in
                        Thread.sleep(forTimeInterval: 1)
                        print("consume: \(text)")
                    },
                    onError: { (error) in
                        print("onError: \(error)")
                    },
                    onCompleted: {
                        print("onCompleted")
                    },
                    onDisposed: {
                        print("onDisposed")
                    }
            )
            .disposed(by: bag)

    Thread.sleep(forTimeInterval: 15)
}

func main() throws -> Void {
    try example_01()
    try example_02()
    try example_03()
    try example_04()
    try example_05()
    try example_06()
    try example_07()
}

do {
    try main()
} catch {
    print("main : \(error)")
}