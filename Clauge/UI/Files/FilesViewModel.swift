import Foundation

@MainActor
final class FilesViewModel: ObservableObject {
    @Published var path: String?
    @Published var parent: String?
    @Published var entries: [FsEntryDto] = []
    @Published var loading = false
    @Published var error: String?
    @Published var hidden = false
    @Published var searching = false
    @Published var query = ""
    @Published var opened: FsReadDto?
    @Published var openedName: String?

    private let client = Services.shared.client

    /// The in-flight folder load. Cancelled before a new `fsList` so a slow,
    /// stale response can't overwrite the state of a newer navigation.
    private var loadTask: Task<Void, Never>?

    init() {
        open(nil) // home directory
    }

    /// Entries filtered by the in-folder search query (current folder only).
    func visibleEntries() -> [FsEntryDto] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.range(of: q, options: .caseInsensitive) != nil }
    }

    func canGoBack() -> Bool {
        opened != nil || searching || parent != nil
    }

    func back() {
        if opened != nil { closeFile() }
        else if searching { stopSearch() }
        else if let p = parent { open(p) }
    }

    func startSearch() { searching = true }
    func stopSearch() { searching = false; query = "" }
    func setQuery(_ q: String) { query = q }

    func open(_ path: String?) {
        loadTask?.cancel()
        loading = true
        error = nil
        searching = false
        query = ""
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.client.fsList(path: path, hidden: self.hidden)
                try Task.checkCancellation()
                self.path = list.path
                self.parent = list.parent
                self.entries = list.entries
                self.loading = false
            } catch is CancellationError {
                // Superseded by a newer load — leave state to the winner.
            } catch {
                if Task.isCancelled { return }
                self.loading = false
                self.error = Self.message(error, fallback: "Couldn't load folder")
            }
        }
    }

    func refresh() { open(path) }

    func toggleHidden() {
        hidden.toggle()
        open(path)
    }

    func openFile(_ entry: FsEntryDto) {
        Task { [weak self] in
            guard let self else { return }
            self.loading = true
            self.error = nil
            do {
                let read = try await self.client.fsRead(path: entry.path)
                self.loading = false
                self.opened = read
                self.openedName = entry.name
            } catch is CancellationError {
            } catch {
                self.loading = false
                self.error = Self.message(error, fallback: "Couldn't open file")
            }
        }
    }

    func closeFile() {
        opened = nil
        openedName = nil
    }

    func mkdir(_ name: String) { mutate { try await self.client.fsMkdir(path: self.childPath(name)) } }
    func newFile(_ name: String) { mutate { try await self.client.fsWrite(path: self.childPath(name), content: "") } }
    func delete(_ path: String) { mutate { try await self.client.fsDelete(path: path) } }

    /// Fetches a file's bytes for Download/Share; returns nil and sets `error`
    /// on failure so callers never report success on a failed fetch.
    func download(_ path: String) async -> Data? {
        do {
            return try await client.fsDownload(path: path)
        } catch is CancellationError {
            return nil
        } catch {
            self.error = Self.message(error, fallback: "Download failed")
            return nil
        }
    }

    func upload(name: String, data: Data) {
        mutate { try await self.client.fsUpload(dir: self.path ?? "", name: name, data: data) }
    }

    // MARK: - Helpers

    private func childPath(_ name: String) -> String {
        guard let base = path else { return name }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(trimmed)/\(name)"
    }

    private func mutate(_ op: @escaping () async throws -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await op()
                self.open(self.path)
            } catch is CancellationError {
            } catch {
                self.error = Self.message(error, fallback: "Operation failed")
            }
        }
    }

    private static func message(_ error: Error, fallback: String) -> String {
        let desc = error.localizedDescription
        return desc.isEmpty ? fallback : desc
    }
}
