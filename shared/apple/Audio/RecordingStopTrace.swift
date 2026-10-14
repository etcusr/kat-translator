import Foundation

/// Opt-in interaction timing, no audio or transcript content. Disabled in normal launches.
@MainActor enum RecordingStopTrace {
    private static let enabled = ProcessInfo.processInfo.environment["OT_RECORDING_STOP_TRACE"] == "1"
    private static var events: [[String: Any]] = []
    static func mark(_ event: String) {
        guard enabled else { return }
        events.append(["event": event, "time": ProcessInfo.processInfo.systemUptime])
        guard let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted]),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: directory.appendingPathComponent("recording-stop-trace.json"), options: .atomic)
    }
}
