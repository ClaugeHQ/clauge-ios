import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilesView: View {
    @StateObject private var vm = FilesViewModel()

    @State private var pendingDelete: FsEntryDto?
    @State private var showNewDialog = false
    @State private var newKind: NewKind = .file
    @State private var newName = ""
    @State private var showImporter = false
    @State private var shareItem: ShareItem?

    enum NewKind { case file, dir }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importFile(url) }
            case .failure(let err):
                vm.error = err.localizedDescription
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert(newKind == .dir ? "New folder" : "New file", isPresented: $showNewDialog) {
            TextField("Name", text: $newName)
            Button("Create") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if newKind == .dir { vm.mkdir(trimmed) } else { vm.newFile(trimmed) }
                }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert(
            pendingDelete.map { "Delete \($0.name)?" } ?? "Delete?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { vm.delete(entry.path) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.isDir ? "This removes the folder and its contents." : "This permanently deletes the file.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }),
            presenting: vm.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let opened = vm.opened {
            FileViewer(read: opened, name: vm.openedName ?? "File", onClose: { vm.closeFile() })
        } else {
            VStack(spacing: 0) {
                topBar
                Divider().background(Theme.outlineVariant)
                listArea
            }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if vm.searching {
            HStack(spacing: 8) {
                Button { vm.stopSearch() } label: {
                    Image(systemName: "arrow.left").foregroundStyle(Theme.textPrimary)
                }
                TextField("Search this folder", text: Binding(get: { vm.query }, set: { vm.setQuery($0) }))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !vm.query.isEmpty {
                    Button { vm.setQuery("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 4) {
                if vm.parent != nil {
                    Button { if let p = vm.parent { vm.open(p) } } label: {
                        Image(systemName: "arrow.left").foregroundStyle(Theme.textPrimary)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(folderName(vm.path))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let crumb = breadcrumb(vm.path) {
                        Text(crumb)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button { vm.startSearch() } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textPrimary)
                }
                Menu {
                    Button { vm.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button { showImporter = true } label: { Label("Upload File", systemImage: "square.and.arrow.up") }
                    Button { vm.toggleHidden() } label: {
                        Label(vm.hidden ? "Hide hidden files" : "Show hidden files", systemImage: "eye")
                    }
                    Divider()
                    Button { newKind = .file; newName = ""; showNewDialog = true } label: {
                        Label("New File", systemImage: "doc.badge.plus")
                    }
                    Button { newKind = .dir; newName = ""; showNewDialog = true } label: {
                        Label("New Directory", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listArea: some View {
        let rows = vm.visibleEntries()
        if vm.loading && vm.entries.isEmpty {
            centered { ProgressView().tint(Theme.pink) }
        } else if let err = vm.error, vm.entries.isEmpty {
            centered {
                Text(err)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
        } else if rows.isEmpty {
            centered {
                Text(vm.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Empty folder" : "No matches in this folder")
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { entry in
                        FileRow(
                            entry: entry,
                            onOpen: { if entry.isDir { vm.open(entry.path) } else { vm.openFile(entry) } },
                            onDownload: { shareEntry(entry) },
                            onShare: { shareEntry(entry) },
                            onDelete: { pendingDelete = entry }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ inner: () -> V) -> some View {
        ZStack { inner() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Fetch the bytes, write to a temp file, and present the share sheet.
    /// On any fetch or write failure surface an error instead of claiming success.
    private func shareEntry(_ entry: FsEntryDto) {
        Task {
            // A companion-supplied name can contain path traversal; reduce to a
            // basename and confirm the temp URL stays inside the share dir.
            let safeName = (entry.name as NSString).lastPathComponent
            guard !safeName.isEmpty, safeName != ".", safeName != ".." else {
                vm.error = "Can't share a file with that name"
                return
            }
            guard let data = await vm.download(entry.path) else { return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clauge-share", isDirectory: true)
            let url = dir.appendingPathComponent(safeName)
            let base = dir.standardizedFileURL.path
            guard url.standardizedFileURL.path.hasPrefix(base + "/") else {
                vm.error = "Couldn't prepare \(safeName) for sharing"
                return
            }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                shareItem = ShareItem(url: url)
            } catch {
                vm.error = "Couldn't prepare \(safeName) for sharing"
            }
        }
    }

    private func importFile(_ url: URL) {
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // Read the bytes off the main actor so a large selection doesn't
                // freeze the picker return path.
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                vm.upload(name: url.lastPathComponent, data: data)
            } catch {
                vm.error = "Couldn't read the selected file"
            }
        }
    }
}

// MARK: - Rows

private struct FileRow: View {
    let entry: FsEntryDto
    let onOpen: () -> Void
    let onDownload: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let icon = fileIcon(entry)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHighest)
                Image(systemName: icon.0)
                    .font(.system(size: 18))
                    .foregroundStyle(icon.1)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !entry.isDir {
                    Text(formatSize(entry.size))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if entry.isDir {
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            } else {
                Menu {
                    Button { onDownload() } label: { Label("Download", systemImage: "arrow.down.circle") }
                    Button { onShare() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - File viewer

private struct FileViewer: View {
    let read: FsReadDto
    let name: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { onClose() } label: {
                    Image(systemName: "arrow.left").foregroundStyle(Theme.textPrimary)
                }
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().background(Theme.outlineVariant)
            body(for: read)
        }
    }

    @ViewBuilder
    private func body(for read: FsReadDto) -> some View {
        if read.binary {
            centered("Binary file — can't preview")
        } else if read.tooLarge {
            centered("File too large to preview")
        } else {
            let lines = (read.content ?? "").components(separatedBy: "\n")
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                .frame(width: 40, alignment: .trailing)
                            Text(highlight(line))
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func centered(_ text: String) -> some View {
        ZStack { Text(text).foregroundStyle(Theme.textSecondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UIKit bridge

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Helpers

private enum FileAccent {
    static let blue = Color(hex: "#58A6FF")
    static let amber = Color(hex: "#D29922")
    static let green = Color(hex: "#3FB950")
    static let purple = Color(hex: "#D2A8FF")
}

private func folderName(_ path: String?) -> String {
    guard let path, !path.isEmpty, path != "/" else { return "Files" }
    let last = path.split(separator: "/").last.map(String.init) ?? ""
    return last.isEmpty ? "Files" : last
}

private func breadcrumb(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    guard segments.count > 1 else { return nil }
    return segments.suffix(3).joined(separator: " / ")
}

private func fileIcon(_ entry: FsEntryDto) -> (String, Color) {
    if entry.isDir { return ("folder.fill", Theme.pink) }
    let ext = (entry.name as NSString).pathExtension.lowercased()
    switch ext {
    case "sql", "dump", "db", "sqlite":
        return ("cylinder.split.1x2", FileAccent.blue)
    case "html", "htm", "xml":
        return ("chevron.left.forward.slash.chevron.right", FileAccent.amber)
    case "json", "yml", "yaml", "toml":
        return ("curlybraces", FileAccent.green)
    case "kt", "java", "js", "ts", "py", "rs", "go", "c", "cpp", "sh", "rb", "php":
        return ("chevron.left.forward.slash.chevron.right", FileAccent.purple)
    case "key", "pem", "pub", "crt", "cer":
        return ("key.fill", FileAccent.amber)
    case "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp":
        return ("photo", FileAccent.green)
    case "md", "txt", "log", "rtf":
        return ("doc.text", Theme.textSecondary)
    default:
        return ("doc", Theme.textSecondary)
    }
}

/// Lightweight, language-agnostic tinting: headers, comments, strings.
private func highlight(_ line: String) -> AttributedString {
    let trimmed = line.drop { $0 == " " || $0 == "\t" }
    if trimmed.hasPrefix("#") {
        var a = AttributedString(line)
        a.foregroundColor = Color(hex: "#E0A042")
        return a
    }
    if trimmed.hasPrefix("//") {
        var a = AttributedString(line)
        a.foregroundColor = Color(hex: "#6A9955")
        return a
    }
    let stringColor = Color(hex: "#CE9178")
    var result = AttributedString()
    let chars = Array(line)
    var buffer = ""

    func flush() {
        if !buffer.isEmpty {
            var seg = AttributedString(buffer)
            seg.foregroundColor = Theme.textPrimary
            result.append(seg)
            buffer = ""
        }
    }

    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "\"" || c == "'" {
            if let end = nextIndex(of: c, in: chars, after: i) {
                flush()
                var seg = AttributedString(String(chars[i...end]))
                seg.foregroundColor = stringColor
                result.append(seg)
                i = end + 1
                continue
            }
        }
        buffer.append(c)
        i += 1
    }
    flush()
    return result
}

private func nextIndex(of target: Character, in chars: [Character], after start: Int) -> Int? {
    var j = start + 1
    while j < chars.count {
        if chars[j] == target { return j }
        j += 1
    }
    return nil
}

private func formatSize(_ bytes: Int) -> String {
    let b = Double(bytes)
    if b >= 1_000_000_000 { return String(format: "%.1f GB", b / 1_000_000_000) }
    if b >= 1_000_000 { return String(format: "%.1f MB", b / 1_000_000) }
    if b >= 1_000 { return String(format: "%.0f KB", b / 1_000) }
    return "\(bytes) B"
}
