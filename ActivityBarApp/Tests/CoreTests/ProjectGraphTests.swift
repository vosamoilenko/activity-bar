import Testing
@testable import Core

@Suite("ProjectGraph models")
struct ProjectGraphTests {
    @Test("Encode/decode round trip")
    func roundTrip() throws {
        let project = Project(name: "Test Project", description: "Desc")
        let nodeA = ProjectNode(projectId: project.id, provider: "gitlab", accountId: "gitlab:user", sourceId: "repo-a", type: .repo, metadata: ["label": "Repo A"], position: GraphPoint(x: 100, y: 120))
        let nodeB = ProjectNode(projectId: project.id, provider: "google-calendar", accountId: "gcal:user", sourceId: "cal-1", type: .calendar, metadata: ["label": "Cal"], position: GraphPoint(x: 220, y: 260))
        let edge = ProjectEdge(fromNodeId: nodeA.id, toNodeId: nodeB.id, relationship: .contains)
        let graph = ProjectGraph(project: project, nodes: [nodeA, nodeB], edges: [edge])

        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(ProjectGraph.self, from: data)
        #expect(decoded == graph)
    }

    @Test("Edge identity is deterministic")
    func edgeIdentity() {
        let e1 = ProjectEdge(fromNodeId: "a", toNodeId: "b", relationship: .relates)
        let e2 = ProjectEdge(fromNodeId: "a", toNodeId: "b", relationship: .relates)
        #expect(e1.id == e2.id)
    }
}

