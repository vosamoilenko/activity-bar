import Foundation
import Testing
@testable import Storage
@testable import Core

@Suite("DiskProjectStore")
struct ProjectStoreTests {
    @Test("Save, list, load, delete")
    func saveListLoadDelete() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("projstore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = DiskProjectStore(baseDirectory: tmp)

        var project = Project(name: "Alpha")
        var graph = ProjectGraph(project: project)
        await store.saveGraph(graph)

        var list = await store.listProjects()
        #expect(list.count == 1)
        #expect(list.first?.name == "Alpha")

        // Add node and edge, then save
        let node = ProjectNode(projectId: project.id, provider: "custom", accountId: "", sourceId: "n1", type: .other)
        graph.nodes.append(node)
        await store.saveGraph(graph)

        let loaded = await store.loadGraph(projectId: project.id)
        #expect(loaded?.nodes.count == 1)

        // Delete
        await store.deleteProject(projectId: project.id)
        list = await store.listProjects()
        #expect(list.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(at: tmp)
    }
}

