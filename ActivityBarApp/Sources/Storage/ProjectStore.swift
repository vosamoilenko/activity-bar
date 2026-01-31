import Foundation
import Core

/// Persistence protocol for project graphs
public protocol ProjectStore: Sendable {
    func listProjects() async -> [Project]
    func loadGraph(projectId: String) async -> ProjectGraph?
    func saveGraph(_ graph: ProjectGraph) async
    func deleteProject(projectId: String) async
}

/// File-backed project store under Application Support
public final class DiskProjectStore: ProjectStore, @unchecked Sendable {
    private let baseDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.activitybar.projects", qos: .utility)

    public init(baseDirectory: URL? = nil) {
        self.fileManager = .default
        if let dir = baseDirectory {
            self.baseDirectory = dir
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("com.activitybar.projects", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func listProjects() async -> [Project] {
        await withCheckedContinuation { continuation in
            queue.async {
                var projects: [Project] = []
                let dir = self.baseDirectory
                guard let contents = try? self.fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                    continuation.resume(returning: [])
                    return
                }
                for url in contents where url.pathExtension == "json" {
                    if let data = try? Data(contentsOf: url), let graph = try? self.decoder.decode(ProjectGraph.self, from: data) {
                        projects.append(graph.project)
                    }
                }
                continuation.resume(returning: projects.sorted { $0.updatedAt > $1.updatedAt })
            }
        }
    }

    public func loadGraph(projectId: String) async -> ProjectGraph? {
        await withCheckedContinuation { continuation in
            queue.async {
                let url = self.fileURL(for: projectId)
                guard self.fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                let graph = try? self.decoder.decode(ProjectGraph.self, from: data)
                continuation.resume(returning: graph)
            }
        }
    }

    public func saveGraph(_ graph: ProjectGraph) async {
        await withCheckedContinuation { continuation in
            queue.async {
                var updated = graph
                updated.project.updatedAt = Date()
                guard let data = try? self.encoder.encode(updated) else {
                    continuation.resume()
                    return
                }
                let url = self.fileURL(for: updated.project.id)
                try? data.write(to: url, options: .atomic)
                continuation.resume()
            }
        }
    }

    public func deleteProject(projectId: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let url = self.fileURL(for: projectId)
                try? self.fileManager.removeItem(at: url)
                continuation.resume()
            }
        }
    }

    private func fileURL(for projectId: String) -> URL {
        baseDirectory.appendingPathComponent("\(projectId).json")
    }
}
