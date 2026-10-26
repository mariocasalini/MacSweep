import Foundation
import Darwin
@main struct TrashJournalBenchmark {
 static func main() throws {
  let fm = FileManager.default
  let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("work/journal-benchmark-\(UUID())")
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: root) }
  let initial = (0..<1000).map { i in RemovalRecord(id: UUID(), originalPath: "/fixture/file-\(i)", trashedPath: "/fixture/trash-\(i)", date: Date(), restored: false, error: nil, identity: FileIdentity(device:1,inode:UInt64(i))) }
  let additions = (0..<500).map { i in RemovalRecord(id: UUID(), originalPath: "/fixture/tiny-\(i)", trashedPath: nil, date: Date(), restored: false, error: "intent", identity: FileIdentity(device:1,inode:UInt64(1000+i))) }
  let old = root.appendingPathComponent("old.json")
  var records = initial
  var written = 0
  let start = Date()
  for record in additions {
   records.append(record)
   for complete in [false,true] {
    if complete { records[records.count-1].trashedPath = "/fixture/trashed"; records[records.count-1].error = nil }
    let data = try JSONEncoder().encode(records); written += data.count
    try data.write(to:old,options:.atomic)
    try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:old.path)
    let handle = try FileHandle(forWritingTo:old); try handle.synchronize(); try handle.close()
    let fd = Darwin.open(root.path,O_RDONLY); precondition(fd >= 0); precondition(fsync(fd)==0); Darwin.close(fd)
   }
  }
  print(String(format:"Previous journal: %.4f seconds; %d bytes encoded/written",Date().timeIntervalSince(start),written))
  let updated = root.appendingPathComponent("new.json")
  try JSONEncoder().encode(initial).write(to:updated)
  let begin = Date()
  for var record in additions {
   try RemovalJournal.append(record,to:updated)
   record.trashedPath = "/fixture/trashed"; record.error = nil
   try RemovalJournal.append(record,to:updated)
  }
  let bytes = try fm.attributesOfItem(atPath:RemovalJournal.eventsURL(for:updated).path)[.size] as! NSNumber
  let loaded = try RemovalJournal.load(from:updated)
  precondition(loaded.count == 1500 && loaded.suffix(500).allSatisfy { $0.trashedPath != nil && $0.error == nil })
  print(String(format:"Append journal: %.4f seconds; %lld bytes appended; replay verified",Date().timeIntervalSince(begin),bytes.int64Value))
 }
}
