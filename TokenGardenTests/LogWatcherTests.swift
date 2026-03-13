import Testing
import Foundation
@testable import TokenGarden

@Test @MainActor func logWatcherDetectsNewContent() async throws {
    // Use a temp dir inside the project to avoid SentinelOne EDR issues
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    let tempDir = projectRoot
        .appendingPathComponent(".claude/tmp/TokenGardenTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let logFile = tempDir.appendingPathComponent("test.jsonl")
    FileManager.default.createFile(atPath: logFile.path, contents: nil)

    var receivedLines: [String] = []

    let watcher = LogWatcher(watchPaths: [tempDir.path]) { line in
        receivedLines.append(line)
    }
    watcher.start()
    defer { watcher.stop() }

    // Append a line to the log file
    let handle = try FileHandle(forWritingTo: logFile)
    handle.seekToEndOfFile()
    handle.write("{\"type\":\"assistant\"}\n".data(using: .utf8)!)
    handle.closeFile()

    // Wait for FSEvents (up to 3 seconds)
    for _ in 0..<30 {
        if !receivedLines.isEmpty { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    #expect(receivedLines.count >= 1)
    #expect(receivedLines[0].contains("assistant"))
}
