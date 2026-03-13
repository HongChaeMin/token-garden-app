import Foundation

@MainActor
class LogWatcher {
    private let watchPaths: [String]
    private let onNewLine: @MainActor (String) -> Void
    private var stream: FSEventStreamRef?
    private var fileOffsets: [String: Int] = [:]
    private let offsetsKey = "LogWatcherOffsets"

    init(watchPaths: [String], onNewLine: @escaping @MainActor (String) -> Void) {
        self.watchPaths = watchPaths
        self.onNewLine = onNewLine
        loadOffsets()
    }

    func start() {
        let pathsToWatch = watchPaths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            LogWatcher.eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        saveOffsets()
    }

    nonisolated private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<LogWatcher>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        let filteredPaths = paths.filter { path in
            path.hasSuffix(".jsonl") && !URL(fileURLWithPath: path).lastPathComponent.contains("compact")
        }

        Task { @MainActor in
            for path in filteredPaths {
                watcher.processFile(at: path)
            }
        }
    }

    private func processFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        let fileSize = Int(handle.seekToEndOfFile())
        let offset = fileOffsets[path] ?? 0

        if offset > fileSize {
            fileOffsets[path] = 0
            handle.seek(toFileOffset: 0)
        } else {
            handle.seek(toFileOffset: UInt64(offset))
        }

        let data = handle.readDataToEndOfFile()
        fileOffsets[path] = Int(handle.offsetInFile)
        saveOffsets()

        guard let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            onNewLine(line)
        }
    }

    func backfill() {
        for watchPath in watchPaths {
            let enumerator = FileManager.default.enumerator(atPath: watchPath)
            while let relativePath = enumerator?.nextObject() as? String {
                guard relativePath.hasSuffix(".jsonl"),
                      !URL(fileURLWithPath: relativePath).lastPathComponent.contains("compact") else { continue }
                let fullPath = (watchPath as NSString).appendingPathComponent(relativePath)
                if fileOffsets[fullPath] == nil {
                    processFile(at: fullPath)
                }
            }
        }
    }

    private func loadOffsets() {
        fileOffsets = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Int] ?? [:]
    }

    private func saveOffsets() {
        UserDefaults.standard.set(fileOffsets, forKey: offsetsKey)
    }
}
