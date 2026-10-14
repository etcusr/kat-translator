import Foundation
import CryptoKit
import Darwin
let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[1]))
var hasher = SHA256()
let pooled = CommandLine.arguments[2] == "pooled"
func step() throws -> Bool {
    guard let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
    hasher.update(data: chunk)
    return true
}
while try (pooled ? autoreleasepool(invoking: step) : step()) {}
print(hasher.finalize().map { String(format: "%02x", $0) }.joined())
var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
print("peakRSSBytes=\(usage.ru_maxrss)")
