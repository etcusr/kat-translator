public enum TransferPhase: Sendable { case downloading, checking, installed, failed, restartRequired, paused, cancelled }
@MainActor class BGTask {
 let identifier: String
 var expirationHandler: (() -> Void)?
 var completions = [Bool]()
 init(_ id: String) { identifier = id }
 func setTaskCompleted(success: Bool) { completions.append(success); expirationHandler = nil }
}
@MainActor final class BGContinuedProcessingTask: BGTask {
 var progress = Progress(totalUnitCount: 0)
 func updateTitle(_ title: String, subtitle: String) {}
}
@MainActor final class BGContinuedProcessingTaskRequest {
 enum SubmissionStrategy { case fail, queue }
 let identifier: String
 var strategy = SubmissionStrategy.queue
 init(identifier: String, title: String, subtitle: String) { self.identifier = identifier }
}
@MainActor final class BGTaskScheduler {
 static let shared = BGTaskScheduler()
 var reject = false
 var requests = [BGContinuedProcessingTaskRequest]()
 var handlers = [String: (BGTask) -> Void]()
 var cancelled = [String]()
 func register(forTaskWithIdentifier id: String, using: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool { handlers[id] = launchHandler; return true }
 func submit(_ request: BGContinuedProcessingTaskRequest) throws {
  if reject { throw NSError(domain: "Busy", code: 1) }; requests.append(request)
 }
 func cancel(taskRequestWithIdentifier id: String) { cancelled.append(id) }
 func deliver(_ id: String) -> BGContinuedProcessingTask {
  let task = BGContinuedProcessingTask(id); handlers[id]!(task); return task
 }
}
enum L10n { static func text(_ string: String) -> String { string } }
@main struct Probe {
 @MainActor static func main() async {
  let scheduler = BGTaskScheduler.shared
  var pauses = 0
  func start() -> Bool { DownloadContinuedTask.start(onChange: {}, onExpiration: { pauses += 1 }) }
  func publish(_ count: Int64, _ phase: TransferPhase = .downloading, ready: Bool = false) {
   let value = DownloadProgress([.init(id: "voice", expected:100, received:100, phase:.installed, ready:true), .init(id:"mt", expected:900, received:count, phase:phase, ready:ready)])
   DownloadContinuedTask.publish(value, title:"Download", detail:"Models")
  }
  precondition(start(), "Foreground download must request continued execution")
  precondition(DownloadContinuedTask.ownsPresentation)
  precondition(start()); precondition(scheduler.requests.count == 1, "One batch must not submit one task per file")
  let first = scheduler.requests[0]; precondition(first.strategy == .fail)
  publish(100)
  let task = scheduler.deliver(first.identifier)
  for _ in 0..<20 { await Task.yield() }
  publish(400)
  precondition(abs(task.progress.fractionCompleted-0.5)<0.001, "Completed voice must remain in aggregate")
  publish(900,.checking)
  precondition(task.completions.isEmpty, "Downloaded bytes are not verified packages")
  publish(900,.installed,ready:true)
  precondition(task.completions == [true]); precondition(!DownloadContinuedTask.ownsPresentation)
  scheduler.reject = true
  precondition(!start()); precondition(!DownloadContinuedTask.ownsPresentation, "Rejected request must allow fallback")
  scheduler.reject = false
  precondition(start())
  let second = scheduler.deliver(scheduler.requests.last!.identifier)
  for _ in 0..<20 { await Task.yield() }
  second.expirationHandler?()
  for _ in 0..<40 { await Task.yield() }
  precondition(pauses == 1, "System stop must pause transfers without deleting models")
  precondition(second.completions == [false]); precondition(!DownloadContinuedTask.ownsPresentation)
  precondition(start()); let lateID=scheduler.requests.last!.identifier
  publish(0,.paused)
  precondition(!DownloadContinuedTask.ownsPresentation)
  precondition(scheduler.cancelled.contains(lateID))
  let late=scheduler.deliver(lateID)
  for _ in 0..<20 { await Task.yield() }
  precondition(late.completions == [false], "Late delivery must not resurrect paused batch")
  print("PASS: continued download lifecycle")
 }
}
