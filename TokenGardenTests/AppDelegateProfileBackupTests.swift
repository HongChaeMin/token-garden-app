import Testing
import Foundation
import SQLite3
@testable import TokenGarden

/// Verifies the two defects that caused silent profile loss on DB reset:
///   1. `backupProfiles` used to skip the WAL checkpoint, so recently-written rows were invisible.
///   2. The reset path used `removeItem`, so an empty-but-unreliable backup destroyed the original files.
@MainActor
struct AppDelegateProfileBackupTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenGardenBackupTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("TokenGarden.store")
    }

    private func run(_ db: OpaquePointer?, _ sql: String) {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        _ = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// Opens a SQLite DB, enables WAL, creates ZPROFILE, inserts a row — and returns the open
    /// connection. Keeping it open prevents the "last-connection close" auto-checkpoint, so the
    /// inserted row genuinely lives only in the WAL file when `backupProfiles` runs.
    private func seedWALOnlyProfile(at storeURL: URL, name: String, email: String) -> OpaquePointer? {
        var db: OpaquePointer?
        #expect(sqlite3_open(storeURL.path, &db) == SQLITE_OK)

        run(db, "PRAGMA journal_mode=WAL;")
        run(db, "PRAGMA wal_autocheckpoint=0;")
        run(db, """
            CREATE TABLE ZPROFILE (
                ZNAME TEXT, ZEMAIL TEXT, ZPLAN TEXT,
                ZCREDENTIALSJSON BLOB, ZISACTIVE INTEGER,
                ZMONTHLYLIMIT INTEGER, ZCOLORNAME TEXT
            );
        """)

        var stmt: OpaquePointer?
        let sql = "INSERT INTO ZPROFILE VALUES (?, ?, 'pro', NULL, 1, 100, 'blue')"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, transient)
        sqlite3_bind_text(stmt, 2, email, -1, transient)
        #expect(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
        // Deliberately do NOT checkpoint — this mirrors the crash scenario.
        return db
    }

    @Test func backupProfilesReadsRowsThatLiveOnlyInTheWAL() {
        let storeURL = makeTempStoreURL()
        let keepAlive = seedWALOnlyProfile(at: storeURL, name: "minhong", email: "minhong@example.com")
        defer { sqlite3_close(keepAlive) }

        // SQLite uses a dash for the WAL sidecar (`store-wal`), not a dot.
        let walPath = storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent)-wal").path
        #expect(FileManager.default.fileExists(atPath: walPath))

        let backup = AppDelegate.backupProfiles(from: storeURL)

        #expect(backup.didReadDatabase == true)
        #expect(backup.claudeProfiles.count == 1)
        #expect(backup.claudeProfiles.first?.email == "minhong@example.com")
    }

    @Test func backupProfilesReportsUnreliableWhenFileIsMissing() {
        let storeURL = makeTempStoreURL()
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)

        let backup = AppDelegate.backupProfiles(from: storeURL)

        #expect(backup.didReadDatabase == false)
        #expect(backup.claudeProfiles.isEmpty)
        #expect(backup.codexProfiles.isEmpty)
    }

    @Test func backupProfilesReportsUnreliableWhenSchemaIsMissing() {
        let storeURL = makeTempStoreURL()
        var db: OpaquePointer?
        #expect(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
        run(db, "CREATE TABLE OTHER_TABLE (id INTEGER);")
        sqlite3_close(db)

        let backup = AppDelegate.backupProfiles(from: storeURL)

        // Important: must NOT claim "0 profiles" as authoritative.
        #expect(backup.didReadDatabase == false)
        #expect(backup.claudeProfiles.isEmpty)
    }

    @Test func archiveStoreFilesRenamesInsteadOfDeleting() throws {
        let storeURL = makeTempStoreURL()
        let dir = storeURL.deletingLastPathComponent()
        let shm = dir.appendingPathComponent("\(storeURL.lastPathComponent)-shm")
        let wal = dir.appendingPathComponent("\(storeURL.lastPathComponent)-wal")
        try "store".write(to: storeURL, atomically: true, encoding: .utf8)
        try "shm".write(to: shm, atomically: true, encoding: .utf8)
        try "wal".write(to: wal, atomically: true, encoding: .utf8)

        AppDelegate.archiveStoreFiles(at: storeURL)

        // Originals no longer at their canonical paths...
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: shm.path) == false)
        #expect(FileManager.default.fileExists(atPath: wal.path) == false)

        // ...but a `.corrupted-*` archive for each sibling survives in the same directory.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
        let archived = siblings.filter { $0.contains(".corrupted-") }
        #expect(archived.count == 3)
    }
}
