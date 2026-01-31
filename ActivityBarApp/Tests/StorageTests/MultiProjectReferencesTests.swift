import Foundation
import Testing
@testable import Storage
@testable import Core

@Suite("ProjectStore multi-project shared nodes")
struct MultiProjectReferencesTests {
    @Test("Two projects can reference the same datasource")
    func sharedNodeAcrossProjects() async throws {
        // Use a workspace-local temp directory to avoid sandbox issues
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tmp = cwd.appendingPathComponent(".tmp-tests/projstore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = DiskProjectStore(baseDirectory: tmp)

        // Shared datasource identity
        let provider = "gitlab"
        let accountId = "gl:me"
        let sourceId = "repo-xyz"

        // Project A
        let projectA = Project(name: "Project A")
        var graphA = ProjectGraph(project: projectA)
        graphA.nodes.append(ProjectNode(projectId: projectA.id, provider: provider, accountId: accountId, sourceId: sourceId, type: .repo))
        await store.saveGraph(graphA)

        // Project B
        let projectB = Project(name: "Project B")
        var graphB = ProjectGraph(project: projectB)
        graphB.nodes.append(ProjectNode(projectId: projectB.id, provider: provider, accountId: accountId, sourceId: sourceId, type: .repo))
        await store.saveGraph(graphB)

        // Both projects should list and load independently
        let list = await store.listProjects()
        #expect(Set(list.map { $0.name }) == Set(["Project A", "Project B"]))

        let loadedA = await store.loadGraph(projectId: projectA.id)
        let loadedB = await store.loadGraph(projectId: projectB.id)
        #expect(loadedA?.nodes.first?.sourceId == sourceId)
        #expect(loadedB?.nodes.first?.sourceId == sourceId)

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
    }
}
