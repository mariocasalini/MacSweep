import Foundation
@main struct ScanBenchmark {
 static func main() throws {
  let fm = FileManager.default
  let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("work/performance-fixture")
  if CommandLine.arguments.contains("prepare") {
   try fm.createDirectory(at: root, withIntermediateDirectories: true)
   for i in 0..<64 { try Data(repeating: UInt8(i), count: 4 * 1024 * 1024).write(to: root.appendingPathComponent("large-\(i).bin")) }
   try fm.copyItem(at: root.appendingPathComponent("large-0.bin"), to: root.appendingPathComponent("exact-copy.bin"))
   // Equal samples but a different byte outside the three sampled regions.
   var collision = Data(repeating: 0, count: 4 * 1024 * 1024); collision[100_000] = 1
   try collision.write(to: root.appendingPathComponent("sample-collision.bin"))
   for i in 0..<1000 { try Data("item-\(i)".utf8).write(to: root.appendingPathComponent("small-\(i).txt")) }
  }
  for _ in 0..<3 {
   let start = Date()
   let result = Scanner().scan(options: ScanOptions(roots: [root]))
   precondition(result.files.count == 1066 && result.duplicateGroups.count == 1 && result.duplicateGroups[0].count == 2 && result.issues.isEmpty)
   print(String(format: "%.4f seconds; %d files; exact duplicate pair only", Date().timeIntervalSince(start),result.files.count))
  }
 }
}
