import Foundation

/// Project entity representing a user-defined collection of data sources
public struct Project: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var description: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, description: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Node type for project graph
public enum ProjectNodeType: String, Codable, Sendable {
    case repo
    case calendar
    case board
    case other
}

/// Minimal point type for storing positions (Codable-friendly)
public struct GraphPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }
}

/// Node within a project graph
public struct ProjectNode: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let projectId: String
    public var provider: String
    public var accountId: String
    public var sourceId: String
    public var type: ProjectNodeType
    public var metadata: [String: String]?
    public var position: GraphPoint

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        provider: String,
        accountId: String,
        sourceId: String,
        type: ProjectNodeType,
        metadata: [String: String]? = nil,
        position: GraphPoint = GraphPoint()
    ) {
        self.id = id
        self.projectId = projectId
        self.provider = provider
        self.accountId = accountId
        self.sourceId = sourceId
        self.type = type
        self.metadata = metadata
        self.position = position
    }
}

/// Relationship between nodes
public enum ProjectRelationship: String, Codable, Sendable {
    case contains
    case relates
    case depends
}

/// Edge connecting two nodes
public struct ProjectEdge: Codable, Sendable, Identifiable, Equatable {
    public var id: String { fromNodeId + "->" + toNodeId + ":" + relationship.rawValue }
    public let fromNodeId: String
    public let toNodeId: String
    public let relationship: ProjectRelationship

    public init(fromNodeId: String, toNodeId: String, relationship: ProjectRelationship = .contains) {
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.relationship = relationship
    }
}

/// Complete project graph state (nodes + edges)
public struct ProjectGraph: Codable, Sendable, Equatable {
    public var project: Project
    public var nodes: [ProjectNode]
    public var edges: [ProjectEdge]

    public init(project: Project, nodes: [ProjectNode] = [], edges: [ProjectEdge] = []) {
        self.project = project
        self.nodes = nodes
        self.edges = edges
    }
}

