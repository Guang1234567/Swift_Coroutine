import XCTest
@testable import Swift_Coroutine

final class Swift_CoroutineTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Swift_Coroutine().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
