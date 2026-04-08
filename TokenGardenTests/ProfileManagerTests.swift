import Testing
import SwiftData
import Foundation
@testable import TokenGarden

@Test @MainActor func renameProfileUpdatesUsageReferences() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Profile.self,
        ProfileTokenUsage.self,
        ProjectUsage.self,
        DailyUsage.self,
        configurations: config
    )
    let context = ModelContext(container)

    let profile = Profile(name: "Old Name", email: "dev@example.com", plan: "pro", credentialsJSON: Data())
    profile.isActive = true
    context.insert(profile)

    let today = Calendar.current.startOfDay(for: Date())
    context.insert(ProfileTokenUsage(profileName: "Old Name", date: today, tokens: 123))
    let daily = DailyUsage(date: today)
    let projectUsage = ProjectUsage(projectName: "token-garden-app", tokens: 456, model: "claude-sonnet", profileName: "Old Name")
    projectUsage.dailyUsage = daily
    daily.projectBreakdowns.append(projectUsage)
    context.insert(daily)
    try context.save()

    let manager = ProfileManager(modelContext: context)
    let didRename = manager.renameProfile(from: "Old Name", to: "New Name")

    #expect(didRename)
    #expect(manager.activeProfile?.name == "New Name")

    let renamedProfile = try context.fetch(FetchDescriptor<Profile>()).first
    #expect(renamedProfile?.name == "New Name")

    let tokenUsages = try context.fetch(FetchDescriptor<ProfileTokenUsage>())
    #expect(tokenUsages.count == 1)
    #expect(tokenUsages[0].profileName == "New Name")

    let projectUsages = try context.fetch(FetchDescriptor<ProjectUsage>())
    #expect(projectUsages.count == 1)
    #expect(projectUsages[0].profileName == "New Name")
}
