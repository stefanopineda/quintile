import Foundation

/// Minimal test harness with a Swift-Testing-shaped API.
///
/// This environment (Command Line Tools without Xcode) has no runnable
/// XCTest/Testing harness, so tests are a plain executable. `expect(...)`
/// maps 1:1 onto Swift Testing's `#expect(...)`, and each `test("name") {}`
/// onto an `@Test func`, so migrating to `swift test` under full Xcode is
/// mechanical.
final class TestHarness {
    private(set) var testCount = 0
    private(set) var failures: [String] = []
    private var currentTest = ""
    private var currentTestFailed = false

    func suite(_ name: String, _ body: (TestHarness) -> Void) {
        print("▶ \(name)")
        body(self)
    }

    func test(_ name: String, _ body: () throws -> Void) {
        testCount += 1
        currentTest = name
        currentTestFailed = false
        do {
            try body()
        } catch {
            record("unexpected error: \(error)")
        }
        print("  \(currentTestFailed ? "✘" : "✔") \(name)")
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "",
                file: StaticString = #filePath, line: UInt = #line) {
        guard !condition else { return }
        let detail = message()
        record("\(file):\(line)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "",
                                   file: StaticString = #filePath, line: UInt = #line) {
        expect(a == b, "\(a) != \(b)\(message().isEmpty ? "" : " — \(message())")",
               file: file, line: line)
    }

    func expectNearlyEqual(_ a: Double, _ b: Double, accuracy: Double = 0.001,
                           file: StaticString = #filePath, line: UInt = #line) {
        expect(abs(a - b) < accuracy, "\(a) !≈ \(b) (±\(accuracy))", file: file, line: line)
    }

    private func record(_ failure: String) {
        currentTestFailed = true
        failures.append("[\(currentTest)] \(failure)")
    }

    /// Prints the summary and exits nonzero on any failure.
    func finish() -> Never {
        print("")
        if failures.isEmpty {
            print("All \(testCount) tests passed.")
            exit(0)
        } else {
            print("\(failures.count) failure(s) across \(testCount) tests:")
            for failure in failures { print("  ✘ \(failure)") }
            exit(1)
        }
    }
}
