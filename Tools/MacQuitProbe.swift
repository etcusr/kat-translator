import AppKit

// NSRunningApplication.terminate sends the same normal Quit request as the Dock.
// No forceTerminate or signals: the app delegate must finish cleanup itself.
guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else { exit(2) }
exit(app.terminate() ? 0 : 3)
