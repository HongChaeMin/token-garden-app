import Testing
import SwiftData
import Foundation
@testable import TokenGarden

/// Verifies that the rewritten O(n) `applyActiveStatus` produces the same
/// result as the original O(n²) loop: for the matching source, a session is
/// active iff its project is in `activeProjects` AND it is that project's
/// newest session by `lastTime`.
@MainActor
struct ApplyActiveStatusTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: DailyUsage.self,
            ProjectUsage.self,
            SessionUsage.self,
            HourlyUsage.self,
            ProfileTokenUsage.self,
            configurations: config
        )
    }

    private func insert(
        _ ctx: ModelContext,
        id: String,
        project: String,
        source: String,
        lastTime: Date,
        isActive: Bool = false
    ) -> SessionUsage {
        let s = SessionUsage(sessionId: id, projectName: project, startTime: lastTime, source: source)
        s.lastTime = lastTime
        s.isActive = isActive
        ctx.insert(s)
        return s
    }

    @Test func newestSessionInActiveProjectWins() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let t0 = Date()

        let older = insert(ctx, id: "older", project: "repo", source: "claude", lastTime: t0.addingTimeInterval(-100))
        let newer = insert(ctx, id: "newer", project: "repo", source: "claude", lastTime: t0)
        try ctx.save()

        let store = TokenDataStore(modelContainer: container)
        store.applyActiveStatus(source: "claude", activeProjects: ["repo"])

        #expect(newer.isActive == true)
        #expect(older.isActive == false)
    }

    @Test func projectNotInActiveSetMarksAllInactive() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let a = insert(ctx, id: "a", project: "stale-project", source: "claude", lastTime: Date())
        let b = insert(ctx, id: "b", project: "stale-project", source: "claude", lastTime: Date().addingTimeInterval(-60))
        try ctx.save()

        let store = TokenDataStore(modelContainer: container)
        store.applyActiveStatus(source: "claude", activeProjects: [])

        #expect(a.isActive == false)
        #expect(b.isActive == false)
    }

    @Test func differentSourceSessionsAreUntouched() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let codex = insert(ctx, id: "codex-1", project: "repo", source: "codex", lastTime: Date(), isActive: true)
        let claude = insert(ctx, id: "claude-1", project: "repo", source: "claude", lastTime: Date())
        try ctx.save()

        let store = TokenDataStore(modelContainer: container)
        store.applyActiveStatus(source: "claude", activeProjects: ["repo"])

        // Codex row must keep whatever state it had — the call was scoped to claude.
        #expect(codex.isActive == true)
        #expect(claude.isActive == true)
    }

    @Test func multipleProjectsEachGetTheirOwnWinner() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let t0 = Date()

        let repoAOld = insert(ctx, id: "a-old", project: "repo-a", source: "claude", lastTime: t0.addingTimeInterval(-200))
        let repoANew = insert(ctx, id: "a-new", project: "repo-a", source: "claude", lastTime: t0.addingTimeInterval(-10))
        let repoBOld = insert(ctx, id: "b-old", project: "repo-b", source: "claude", lastTime: t0.addingTimeInterval(-150))
        let repoBNew = insert(ctx, id: "b-new", project: "repo-b", source: "claude", lastTime: t0)
        try ctx.save()

        let store = TokenDataStore(modelContainer: container)
        store.applyActiveStatus(source: "claude", activeProjects: ["repo-a", "repo-b"])

        #expect(repoANew.isActive == true)
        #expect(repoAOld.isActive == false)
        #expect(repoBNew.isActive == true)
        #expect(repoBOld.isActive == false)
    }
}
