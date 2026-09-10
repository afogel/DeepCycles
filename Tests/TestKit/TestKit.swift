import Foundation
import ObjectiveC

// A small stand-in for XCTest, which the Command Line Tools do not ship. Subclass `XCTestCase`,
// write `func test…()` methods (throwing or not), assert with the `XCTAssert…` functions, and run
// with `swift run DeepCyclesCoreTests`. The names match XCTest so the tests move to a real
// .testTarget unchanged: swap `import TestKit` for `import XCTest`.

/// Base class for tests. A fresh instance is made for every test method.
@objcMembers
open class XCTestCase: NSObject {
    public required override init() { super.init() }
    open func setUp() throws {}
    open func tearDown() throws {}
}

public enum TestKit {
    private static var failures = 0
    private static var failuresInCurrentTest = 0

    /// Record a failure at a source location, in the `file:line: error:` form editors understand.
    public static func fail(_ message: String, file: StaticString, line: UInt) {
        failures += 1
        failuresInCurrentTest += 1
        print("\(file):\(line): error: \(message)")
    }

    /// Runs every `test…` method of every XCTestCase subclass linked into the process.
    /// Returns the process exit code: 0 when everything passed.
    public static func runAll() -> Int32 {
        let started = Date()
        var ran = 0
        for cls in testClasses() {
            for sel in testSelectors(of: cls) {
                ran += 1
                failuresInCurrentTest = 0
                let t0 = Date()
                run(cls, sel)
                let name = "\(NSStringFromClass(cls)).\(NSStringFromSelector(sel))".replacingOccurrences(of: "AndReturnError:", with: "")
                let status = failuresInCurrentTest == 0 ? "passed" : "failed"
                print(String(format: "Test Case '%@' %@ (%.3f s)", name, status, Date().timeIntervalSince(t0)))
            }
        }
        print(String(format: "Executed %d tests, with %d failures in %.3f s", ran, failures, Date().timeIntervalSince(started)))
        return failures == 0 ? 0 : 1
    }

    private static func testClasses() -> [AnyClass] {
        let count = objc_getClassList(nil, 0)
        let buffer = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }
        let found = objc_getClassList(AutoreleasingUnsafeMutablePointer(buffer), count)
        var out: [AnyClass] = []
        for i in 0..<Int(min(count, found)) {
            guard let cls = buffer[i], cls != XCTestCase.self, isTestCase(cls) else { continue }
            out.append(cls)
        }
        return out.sorted { NSStringFromClass($0) < NSStringFromClass($1) }
    }

    private static func isTestCase(_ cls: AnyClass) -> Bool {
        var c: AnyClass? = class_getSuperclass(cls)
        while let cur = c {
            if cur == XCTestCase.self { return true }
            c = class_getSuperclass(cur)
        }
        return false
    }

    /// `test…` methods with no arguments, plus throwing ones (exposed as `test…AndReturnError:`).
    private static func testSelectors(of cls: AnyClass) -> [Selector] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return [] }
        defer { free(methods) }
        var out: [Selector] = []
        for i in 0..<Int(count) {
            let sel = method_getName(methods[i])
            let name = NSStringFromSelector(sel)
            guard name.hasPrefix("test") else { continue }
            if !name.contains(":") || name.hasSuffix("AndReturnError:") { out.append(sel) }
        }
        return out.sorted { NSStringFromSelector($0) < NSStringFromSelector($1) }
    }

    private static func run(_ cls: AnyClass, _ sel: Selector) {
        guard let type = cls as? XCTestCase.Type else { return }
        let test = type.init()
        do { try test.setUp() } catch { fail("setUp threw \(error)", file: #filePath, line: #line) }
        if NSStringFromSelector(sel).hasSuffix("AndReturnError:") {
            typealias ThrowingIMP = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
            if let method = class_getInstanceMethod(cls, sel) {
                let imp = unsafeBitCast(method_getImplementation(method), to: ThrowingIMP.self)
                var error: NSError? = nil
                if !imp(test, sel, &error) {
                    // A failed XCTUnwrap has already been reported at its own line.
                    if !(error is UnwrapFailure) { fail("threw \(error.map { String(describing: $0) } ?? "an error")", file: #filePath, line: #line) }
                }
            }
        } else {
            _ = test.perform(sel)
        }
        do { try test.tearDown() } catch { fail("tearDown threw \(error)", file: #filePath, line: #line) }
    }
}

/// Thrown by `XCTUnwrap` after the failure has been recorded.
public final class UnwrapFailure: NSError, @unchecked Sendable {
    public init() { super.init(domain: "TestKit", code: 1) }
    public required init?(coder: NSCoder) { nil }
}

// MARK: - Assertions

public func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if a != b { TestKit.fail("XCTAssertEqual failed: (\"\(a)\") is not equal to (\"\(b)\") \(message)", file: file, line: line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if a == b { TestKit.fail("XCTAssertNotEqual failed: (\"\(a)\") is equal to (\"\(b)\") \(message)", file: file, line: line) }
}

public func XCTAssertTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !value { TestKit.fail("XCTAssertTrue failed \(message)", file: file, line: line) }
}

public func XCTAssertFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if value { TestKit.fail("XCTAssertFalse failed \(message)", file: file, line: line) }
}

public func XCTAssertNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let value { TestKit.fail("XCTAssertNil failed: \"\(value)\" \(message)", file: file, line: line) }
}

public func XCTAssertNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if value == nil { TestKit.fail("XCTAssertNotNil failed \(message)", file: file, line: line) }
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !(a > b) { TestKit.fail("XCTAssertGreaterThan failed: (\"\(a)\") is not greater than (\"\(b)\") \(message)", file: file, line: line) }
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    TestKit.fail("XCTFail \(message)", file: file, line: line)
}

public func XCTUnwrap<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        TestKit.fail("XCTUnwrap failed: expected non-nil value \(message)", file: file, line: line)
        throw UnwrapFailure()
    }
    return value
}
