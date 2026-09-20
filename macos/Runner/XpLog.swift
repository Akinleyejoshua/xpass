import Foundation

/// Append-only diagnostic log.
///
/// The unified log does not reliably capture NSLog from a bundle launched by
/// launchd, and stdout is unreachable there too — which leaves no way to see
/// why a permission decision went the way it did. A plain file always works.
///
/// Written to `~/Library/Logs/xpass-debug.log`.
enum XpLog {
  private static let queue = DispatchQueue(label: "ai.xpass.log")

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  static var path: String {
    let home = NSHomeDirectory()
    return "\(home)/Library/Logs/xpass-debug.log"
  }

  static func write(_ message: String) {
    NSLog("xpass: %@", message)
    let line = "\(formatter.string(from: Date()))  \(message)\n"
    queue.async {
      guard let data = line.data(using: .utf8) else { return }
      let url = URL(fileURLWithPath: path)
      if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
      } else {
        try? FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? data.write(to: url)
      }
    }
  }

  /// Starts a fresh file each launch so a session is readable on its own.
  static func reset() {
    queue.async {
      try? FileManager.default.removeItem(atPath: path)
    }
    write("--- xpass launched (pid \(getpid()), parent \(getppid())) ---")
  }
}
