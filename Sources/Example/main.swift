import Foundation
import Swift_Coroutine
import Swift_Boost_Context

enum TestError: Error {
    case SomeError(reason: String)
}

func example_01() throws {
    // Example-01
    // ===================
    print("Example-01 =============================")

    //let queue = DispatchQueue(label: "TestCoroutine")
    let queue = DispatchQueue.global()

    let coJob1 = CoLauncher.launch(name: "co1", dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 01 - end \(Thread.current)")
        }
        print("co 01 - start \(Thread.current)")
        try co.yield()
        return "co1 's result"
    }

    let coJob2 = CoLauncher.launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 02 - end \(Thread.current)")
        }
        print("co 02 - start \(Thread.current)")
        try co.yield()
        throw TestError.SomeError(reason: "Occupy some error in co2")
        return "co2 's result"
    }

    let coJob3 = CoLauncher.launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        defer {
            print("co 03 - end \(Thread.current)")
        }
        print("co 03 - start \(Thread.current)")
        try co.yield()
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
    let semMutex = DispatchSemaphore(value: 1)
    var buffer: [Int] = []

    let coConsumer = CoLauncher.launch(dispatchQueue: consumerQueue) { (co: Coroutine) throws -> Void in
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

    let coProducer = CoLauncher.launch(dispatchQueue: producerQueue) { (co: Coroutine) throws -> Void in
        for time in (1...32).reversed() {
            try semFull.wait(co)
            semMutex.wait()
            buffer.append(time)
            print("produced : \(time)   \(Thread.current)")
            semMutex.signal()
            semEmpty.signal()
        }
    }

    try coConsumer.join()
    try coProducer.join()

    print("finally, buffer = \(buffer)")
    print("semFull = \(semFull)")
    print("semEmpty = \(semEmpty)")
}

func example_03() throws {
    // Example-03
    // ===================
    print("Example-03 =============================")

    //let queue = DispatchQueue(label: "TestCoroutine")
    let queue = DispatchQueue.global()

    let coDelay = CoLauncher.launch(dispatchQueue: queue) { (co: Coroutine) throws -> String in
        print("coDelay - start \(Thread.current)")
        let start = CFAbsoluteTimeGetCurrent()
        try co.delay(.seconds(2))
        let end = CFAbsoluteTimeGetCurrent()
        print("coDelay - end \(Thread.current)  in \((end - start) * 1000) ms")
        return "coDelay 's result"
    }

    try coDelay.join()
}

func example_04() throws {
    // Example-04
    // ===================
    print("Example-04 =============================")
    let start = CFAbsoluteTimeGetCurrent()
    let queue = DispatchQueue(label: "example_04", attributes: .concurrent)
    let coJob = CoLauncher.launch(name: "coTestNestFuture", dispatchQueue: queue) { (co: Coroutine) throws -> Void in
        var sum: Int = 0
        for i in (1...100) {
            //print("--------------------   makeCoFuture_01_\(i) --- await(\(co)) -- before")
            sum += try makeCoFuture_01("makeCoFuture_01_\(i)", queue, i).await(co)
            //print("--------------------   makeCoFuture_01_\(i) --- await(\(co)) -- end")
        }
        print("sum = \(sum)")
    }
    try coJob.join()

    //print("Thread.sleep(forTimeInterval: 5)")
    let end = CFAbsoluteTimeGetCurrent()
    //Thread.sleep(forTimeInterval: 1)
    print("g_DefaultContextAllocator = \(g_DefaultContextAllocator)")
}

func makeCoFuture_01(_ name: String, _ dispatchQueue: DispatchQueue, _ i: Int) -> CoFuture<Int> {
    return CoFuture(name, dispatchQueue) { (co: Coroutine) in
        var sum: Int = 0
        for j in (1...100) {
            //print("--------------------   makeCoFuture_02_\(j) --- await(\(co)) -- before")
            sum += try makeCoFuture_02("makeCoFuture_02_\(j)", dispatchQueue, j).await(co)
            //print("--------------------   makeCoFuture_02_\(j) --- await(\(co)) -- end")
        }
        return sum
    }
}

func makeCoFuture_02(_ name: String, _ dispatchQueue: DispatchQueue, _ i: Int) -> CoFuture<Int> {
    return CoFuture(name, dispatchQueue) { (co: Coroutine) in
        //try co.delay(.milliseconds(5))
        return i
    }
}

func example_05() throws {
    // Example-05
    // ===================
    print("Example-05 =============================")

    let producerQueue = DispatchQueue(label: "producerQueue", attributes: .concurrent)
    let consumerQueue = DispatchQueue(label: "consumerQueue", attributes: .concurrent)
    let closeQueue = DispatchQueue(label: "closeQueue", attributes: .concurrent)
    let channel = CoChannel<Int>(capacity: 7)

    let coClose = CoLauncher.launch(name: "coClose", dispatchQueue: closeQueue) { (co: Coroutine) throws -> Void in
        print("coClose before  --  delay")
        try co.delay(.milliseconds(10))
        //try co.yield()
        print("coClose after  --  delay")
        channel.close()
        print("coClose  --  end")
    }

    let coConsumer = CoLauncher.launch(name: "coConsumer", dispatchQueue: consumerQueue) { (co: Coroutine) throws -> Void in
        var time: Int = 1
        for item in try channel.receive(co) {
            print("consumed : \(item)  --  \(time)  --  \(Thread.current)")
            time += 1
        }
    }

    let coProducer01 = CoLauncher.launch(name: "coProducer01", dispatchQueue: producerQueue) { (co: Coroutine) throws -> Void in
        for time in (1...32).reversed() {
            //print("coProducer01  --  before produce : \(time)")
            try channel.send(co, time)
            print("coProducer01  --  after produce : \(time)")
            try co.delay(.milliseconds(1))
        }
        print("coProducer01  --  end")
    }

    /*let coProducer02 = CoLauncher.launch(name: "coProducer02", dispatchQueue: producerQueue) { (co: Coroutine) throws -> Void in
        for time in (33...50).reversed() {
            //print("coProducer02  --  before produce : \(time)")
            try channel.send(co, time)
            print("coProducer02  --  after produce : \(time)")
        }
        print("coProducer02  --  end")
    }*/

    try coClose.join()
    try coConsumer.join()
    try coProducer01.join()
    //try coProducer02.join()

    print("channel = \(channel)")
}

func main() throws -> Void {

    try example_01()
    try example_02()
    try example_03()
    try example_04()
    try example_05()
}

do {
    try main()
} catch {
    print("main : \(error)")
}