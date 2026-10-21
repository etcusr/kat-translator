import Foundation
struct State { var generation = 5; mutating func cancel() { generation += 1 } }
final class DownloadTask {
 var taskDescription: String?
 var cancelled = false
 func cancel() { cancelled = true }
}
final class Session {
 var resumed: Data?
 let disposed = DownloadTask()
 func downloadTask(withResumeData data: Data) -> DownloadTask { resumed = data; return disposed }
}
actor Store { func remove(_ model: String) {} }
@MainActor final class Downloader {
 var isManaging = false
 var state = State()
 var currentTask: DownloadTask?
 var storedTaskID: Int?
 var verification: Task<Void,Never>?
 var installedURL: URL?
 let session = Session(), store = Store(), model = "fixture"
 let root: URL
 var resumeURL: URL { root.appendingPathComponent("resume.data") }
 init(_ root: URL) { self.root = root }
 func stagingURL(generation: Int) -> URL { root.appendingPathComponent("staging-\(generation)") }
 func persist() {}
 // PRODUCTION_CANCEL
}
@main struct Probe {
 @MainActor static func main() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let item=Downloader(root), resume=Data("opaque system resume data".utf8)
  try resume.write(to:item.resumeURL)
  await item.cancel()
  precondition(item.session.resumed == resume, "Removing resume.data alone leaves the system partial file orphaned")
  precondition(item.session.disposed.cancelled)
  precondition(item.session.disposed.taskDescription == "5", "Cleanup callbacks must not mutate the new generation")
  precondition(!FileManager.default.fileExists(atPath:item.resumeURL.path))
  precondition(item.state.generation == 6)
  print("PASS: cancel disposes paused transfer")
 }
}
