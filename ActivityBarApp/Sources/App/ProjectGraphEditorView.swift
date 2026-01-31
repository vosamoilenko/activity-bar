import SwiftUI
import Core
import Storage

/// Projects tab wrapper with project list and editor
struct ProjectsSettingsView: View {
    let appState: AppState
    let projectStore: ProjectStore
    let tokenStore: TokenStore

    @State private var projects: [Project] = []
    @State private var selectedProjectId: String?
    @State private var isCreating: Bool = false
    @State private var newProjectName: String = ""
    @State private var showingDeleteConfirm: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                HStack(spacing: 8) {
                    Text("Projects").font(.headline)
                    Spacer()
                    Button {
                        isCreating = true
                        newProjectName = ""
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedProjectId == nil)
                    .help("Delete selected project")
                }
                List(selection: $selectedProjectId) {
                    ForEach(projects) { p in
                        Text(p.name)
                            .tag(Optional(p.id))
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
            .frame(width: 180)
            .padding()

            Divider()

            Group {
                if let pid = selectedProjectId {
                    ProjectGraphEditor(projectId: pid, projectStore: projectStore, appState: appState, tokenStore: tokenStore)
                        .id(pid)
                } else {
                    VStack {
                        Text("Select a project to edit")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $isCreating) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Project").font(.headline)
                TextField("Name", text: $newProjectName)
                HStack {
                    Spacer()
                    Button("Cancel") { isCreating = false }
                    Button("Create") { Task { await createProject() } }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .frame(width: 360)
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteSelectedProject() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the project and its graph from disk. This cannot be undone.")
        }
    }

    private func reload() async {
        let list = await projectStore.listProjects()
        await MainActor.run {
            self.projects = list
            if self.selectedProjectId == nil { self.selectedProjectId = list.first?.id }
        }
    }

    private func createProject() async {
        let project = Project(name: newProjectName)
        let graph = ProjectGraph(project: project)
        await projectStore.saveGraph(graph)
        isCreating = false
        await reload()
        await MainActor.run { self.selectedProjectId = project.id }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            for idx in offsets { await projectStore.deleteProject(projectId: projects[idx].id) }
            await reload()
        }
    }

    private func deleteSelectedProject() async {
        guard let pid = selectedProjectId else { return }
        await projectStore.deleteProject(projectId: pid)
        await reload()
        await MainActor.run { self.selectedProjectId = projects.first?.id }
    }
}

/// Simple visual graph editor with draggable nodes and edge creation
struct ProjectGraphEditor: View {
    let projectId: String
    let projectStore: ProjectStore
    let appState: AppState
    let tokenStore: TokenStore

    @State private var graph: ProjectGraph?
    // Simplified editor: nodes act as rules; edges/"connect" removed for clarity
    @State private var canvasSize: CGSize = .zero
    @State private var showingAddNodeSheet: Bool = false
    @State private var newNodeType: ProjectNodeType = .repo
    @State private var newProvider: Provider = .gitlab
    @State private var newAccountId: String = ""
    @State private var newSourceId: String = ""
    @State private var newLabel: String = ""
    // Calendar-specific fields
    private struct CalendarOption: Identifiable { let id: String; let summary: String; let primary: Bool }
    @State private var availableCalendars: [CalendarOption] = []
    @State private var selectedCalendarIds: Set<String> = []
    @State private var calendarTitleRegexes: [String] = []
    // Repo-specific regex
    @State private var repoRegex: String = ""

    private func displayName(for provider: Provider) -> String {
        switch provider {
        case .gitlab: return "GitLab"
        case .azureDevops: return "Azure DevOps"
        case .googleCalendar: return "Google Calendar"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(graph?.project.name ?? "").font(.title3.weight(.semibold))
                Spacer()
                Button { showingAddNodeSheet = true } label: { Label("Add Source", systemImage: "plus.square.on.square") }
            }
            .padding(.horizontal)

            ZStack {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { canvasSize = geo.size }
                        .onChange(of: geo.size) { _, new in canvasSize = new }

                    // Nodes
                    ForEach(graph?.nodes ?? []) { node in
                        NodeView(node: node)
                            .position(CGPoint(x: node.position.x, y: node.position.y))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        updateNodePosition(nodeId: node.id, to: GraphPoint(x: value.location.x, y: value.location.y))
                                    }
                                    .onEnded { _ in Task { await save() } }
                            )
                    }
                }
            }
            .background(Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .bottom])
        }
        .task { await load() }
        .sheet(isPresented: $showingAddNodeSheet) {
            AddNodeSheet
        }
        .onChange(of: newNodeType) { _, _ in constrainProviderToType() }
        .onChange(of: newProvider) { _, _ in loadCalendarsIfNeeded() }
        .onChange(of: newAccountId) { _, _ in loadCalendarsIfNeeded() }
    }

    private func load() async {
        let loaded = await projectStore.loadGraph(projectId: projectId)
        await MainActor.run { self.graph = loaded }
    }

    private func save() async {
        guard let g = graph else { return }
        await projectStore.saveGraph(g)
    }

    private func updateNodePosition(nodeId: String, to: GraphPoint) {
        guard var g = graph, let idx = g.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        g.nodes[idx].position = to
        self.graph = g
    }

    private var AddNodeSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Source").font(.headline)

            Picker("Type", selection: $newNodeType) {
                Text("Repository").tag(ProjectNodeType.repo)
                Text("Calendar").tag(ProjectNodeType.calendar)
                Text("Other").tag(ProjectNodeType.other)
            }
            .pickerStyle(.segmented)

            Picker("Provider", selection: $newProvider) {
                ForEach(providerOptions, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            }

            Picker("Account", selection: $newAccountId) {
                let accounts = appState.session.accounts.filter { $0.provider == newProvider }
                if accounts.isEmpty {
                    Text("No accounts for provider").tag("")
                } else {
                    ForEach(accounts, id: \.id) { acc in
                        Text(acc.displayName).tag(acc.id)
                    }
                }
            }

            if newNodeType == .repo {
                TextField("Repository name or path (e.g., group/repo)", text: $newSourceId)
                Text("This should match the project name in the activity list, or appear in the URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Repository regex (optional)", text: $repoRegex)
                    .textFieldStyle(.roundedBorder)
            } else if newNodeType == .calendar {
                if availableCalendars.isEmpty {
                    Text("Select account to load calendars…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Calendars")
                        .font(.subheadline)
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(availableCalendars) { cal in
                                Toggle(isOn: Binding(
                                    get: { selectedCalendarIds.contains(cal.id) },
                                    set: { newValue in
                                        if newValue { selectedCalendarIds.insert(cal.id) } else { selectedCalendarIds.remove(cal.id) }
                                    }
                                )) {
                                    Text(cal.summary)
                                }
                            }
                        }
                    }
                    .frame(height: 160)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Event Title Regexps")
                            .font(.subheadline)
                        Spacer()
                        Button { calendarTitleRegexes.append("") } label: { Label("Add", systemImage: "plus") }
                            .buttonStyle(.plain)
                    }
                    ForEach(Array(calendarTitleRegexes.enumerated()), id: \.offset) { index, _ in
                        HStack(spacing: 8) {
                            TextField("Regex pattern", text: Binding(
                                get: { calendarTitleRegexes[index] },
                                set: { calendarTitleRegexes[index] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                calendarTitleRegexes.remove(at: index)
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Pick specific calendars and/or add multiple regex patterns to match event titles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Label (optional)", text: $newLabel)

            HStack {
                Spacer()
                Button("Cancel") { showingAddNodeSheet = false }
                Button("Add") { Task { await addNode() } }
                    .disabled(newAccountId.isEmpty || (newNodeType == .repo && newSourceId.trimmingCharacters(in: .whitespaces).isEmpty && repoRegex.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { presetDefaults() }
    }

    private func presetDefaults() {
        // Choose a default account for the selected provider
        if let first = appState.session.accounts.first(where: { $0.provider == newProvider }) {
            newAccountId = first.id
        } else {
            newAccountId = ""
        }
        newSourceId = ""
        newLabel = ""
        repoRegex = ""
        calendarTitleRegexes = []
        availableCalendars = []
        selectedCalendarIds = []
        constrainProviderToType()
        loadCalendarsIfNeeded()
    }

    private func addNode() async {
        guard var g = graph else { return }
        let center = GraphPoint(x: Double(max(60, canvasSize.width / 2)), y: Double(max(60, canvasSize.height / 2)))
        var metadata: [String: String] = [:]
        if !newLabel.isEmpty { metadata["label"] = newLabel }
        if newNodeType == .repo {
            if !repoRegex.trimmingCharacters(in: .whitespaces).isEmpty { metadata["repoRegex"] = repoRegex }
        } else if newNodeType == .calendar {
            if !selectedCalendarIds.isEmpty { metadata["calendarIds"] = selectedCalendarIds.joined(separator: ",") }
            let patterns = calendarTitleRegexes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !patterns.isEmpty, let data = try? JSONSerialization.data(withJSONObject: patterns), let json = String(data: data, encoding: .utf8) {
                metadata["titleRegexes"] = json
            }
        }

        let node = ProjectNode(
            projectId: g.project.id,
            provider: newProvider.rawValue,
            accountId: newAccountId,
            sourceId: newNodeType == .repo ? newSourceId.trimmingCharacters(in: .whitespaces) : "",
            type: newNodeType,
            metadata: metadata.isEmpty ? nil : metadata,
            position: center
        )
        g.nodes.append(node)
        await projectStore.saveGraph(g)
        await load()
        showingAddNodeSheet = false
    }

    private var providerOptions: [Provider] {
        switch newNodeType {
        case .repo: return [.gitlab, .azureDevops]
        case .calendar: return [.googleCalendar]
        case .board, .other: return Provider.allCases
        }
    }

    private func constrainProviderToType() {
        if !providerOptions.contains(newProvider) {
            newProvider = providerOptions.first ?? .gitlab
        }
    }

    private func loadCalendarsIfNeeded() {
        guard newNodeType == .calendar, newProvider == .googleCalendar, !newAccountId.isEmpty else {
            availableCalendars = []
            selectedCalendarIds = []
            return
        }
        guard let account = appState.session.accounts.first(where: { $0.id == newAccountId }) else { return }
        Task {
            do {
                // Get token for this account
                let tokenOpt = try await tokenStore.getToken(for: account.id)
                guard let token = tokenOpt else { return }
                // Fetch calendars
                if let list = try? await fetchGoogleCalendars(token: token) {
                    await MainActor.run {
                        self.availableCalendars = list
                        // Preselect primary
                        if let primary = list.first(where: { $0.primary }) {
                            self.selectedCalendarIds.insert(primary.id)
                        }
                    }
                }
            } catch {
                // Ignore errors here; sheet can continue without calendar list
            }
        }
    }

    private func fetchGoogleCalendars(token: String) async throws -> [CalendarOption] {
        struct Resp: Decodable { let items: [Item]? }
        struct Item: Decodable { let id: String; let summary: String?; let primary: Bool? }
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return (decoded.items ?? []).map { CalendarOption(id: $0.id, summary: $0.summary ?? $0.id, primary: $0.primary ?? false) }
    }
}

private struct NodeView: View {
    let node: ProjectNode
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
            Text(displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 100)
        }
        .padding(8)
        .background(.thinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch node.type {
        case .repo: return "folder"
        case .calendar: return "calendar"
        case .board: return "rectangle.grid.2x2"
        case .other: return "circle"
        }
    }

    private var displayName: String {
        if let label = node.metadata?["label"], !label.isEmpty { return label }
        return node.sourceId.isEmpty ? node.type.rawValue.capitalized : node.sourceId
    }
}

private struct EdgeView: View, Identifiable {
    var id: String { "edge_\(start.x)_\(start.y)_\(end.x)_\(end.y)" }
    let start: CGPoint
    let end: CGPoint

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
    }
}
