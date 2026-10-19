// Runs the canonical XCTest source on Command Line Tools installations without XCTest.
// Assertions live only in Tests/ChargeCoreTests; this adapter supplies a minimal compatible runner.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let coreDirectory = root.appendingPathComponent("Sources/ChargeCore")
let coreFiles = try FileManager.default.contentsOfDirectory(at: coreDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" && $0.lastPathComponent != "HelperClient.swift" }.sorted { $0.path < $1.path }
let core = try coreFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
let testDirectory = root.appendingPathComponent("Tests/ChargeCoreTests")
let files = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
let adapter = #"""
class XCTestCase {}
var assertionFailures = 0
var methodFailures = 0
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { let x = a(); let y = b(); if x != y { assertionFailures += 1; print("FAIL \(line) \(message): \(x) != \(y)") } }
func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { if a() == b() { assertionFailures += 1; print("FAIL \(line): expected different") } }
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if !value() { assertionFailures += 1; print("FAIL \(line): expected true \(message)") } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if value() { assertionFailures += 1; print("FAIL \(line): expected false \(message)") } }
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { if value() != nil { assertionFailures += 1; print("FAIL \(line): expected nil") } }
func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) { assertionFailures += 1; print("FAIL \(line): \(message)") }
"""#
var sources = core + "\n" + adapter
var invocations = "\n"
var count = 0
for (index, file) in files.enumerated() {
 let raw = try String(contentsOf: file, encoding: .utf8)
 let classPattern = try NSRegularExpression(pattern: #"class\s+(\w+)\s*:\s*XCTestCase"#)
 guard let match = classPattern.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)), let nameRange = Range(match.range(at: 1), in: raw) else { fatalError("Missing XCTestCase class in \(file.path)") }
 let typeName = String(raw[nameRange])
 let pattern = try NSRegularExpression(pattern: #"func\s+(test\w+)\s*\(\s*\)"#)
 let matches = pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
 sources += "\n" + raw.replacingOccurrences(of: "import XCTest", with: "import Foundation").replacingOccurrences(of: "@testable import ChargeCore", with: "")
 invocations += "let suite\(index) = \(typeName)()\n"
 for m in matches {
  let method = String(raw[Range(m.range(at: 1), in: raw)!]); count += 1
  invocations += "do { let before = assertionFailures; suite\(index).\(method)(); if assertionFailures > before { methodFailures += 1 }; print(\"\\(assertionFailures == before ? \"PASS\" : \"FAIL\") \(typeName).\(method)\") }\n"
 }
}
guard count > 0 else { fatalError("No test methods found") }
let build = root.appendingPathComponent(".build/core-test-adapter")
try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
let generated = build.appendingPathComponent("main.swift")
try (sources + invocations + "\nprint(\"\(count) methods, \\(methodFailures) failed methods, \\(assertionFailures) failed assertions\"); exit(assertionFailures == 0 ? 0 : 1)\n").write(to: generated, atomically: true, encoding: .utf8)
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", generated.path]
try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
