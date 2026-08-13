import SwiftUI

/// "Its code files" — a read-only browser over the daemon's own source, so
/// you can see exactly what's running, not a description of it.
struct CodeBrowserView: View {
    @State private var files: [CodeFile] = CodeReader.files()
    @State private var selected: CodeFile?
    @State private var content: String = ""

    /// A flat, alphabetically-sorted list mixed `.py`/`.sh`/`.md` together
    /// with no way to tell what's a script vs. reference at a glance — real
    /// grouping instead, same icon+label language `LogRailView`'s sections
    /// already use.
    private var groupedFiles: [(label: String, icon: String, files: [CodeFile])] {
        let py = files.filter { $0.path.hasSuffix(".py") }
        let sh = files.filter { $0.path.hasSuffix(".sh") }
        let md = files.filter { $0.path.hasSuffix(".md") }
        var out: [(label: String, icon: String, files: [CodeFile])] = []
        if !py.isEmpty { out.append(("Python", "chevron.left.forwardslash.chevron.right", py)) }
        if !sh.isEmpty { out.append(("Shell", "terminal", sh)) }
        if !md.isEmpty { out.append(("Docs", "doc.text", md)) }
        return out
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedFiles, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionLabel(icon: group.icon, text: group.label)
                            ForEach(group.files) { file in
                                FileRow(file: file, isSelected: selected == file) {
                                    selected = file
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .background(Theme.void)
            .navigationSplitViewColumnWidth(min: 190, ideal: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The title bar is hidden app-wide, so `.navigationTitle`
                    // below has never actually rendered anywhere visible —
                    // the same "dead, invisible-effect" pattern found and
                    // fixed elsewhere this round. A real header instead.
                    detailHeader
                    detailContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.void)
            .navigationTitle(selected?.name ?? "Select a file")
        }
        .onChange(of: selected) { _, file in
            content = file.map { CodeReader.content(path: $0.path) } ?? ""
        }
        .onAppear {
            if selected == nil { selected = files.first }
        }
    }

    private func sectionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .medium))
            Text(text.uppercased()).font(.system(size: 10, weight: .medium)).tracking(1)
        }
        .foregroundColor(Theme.inkFaint)
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var detailHeader: some View {
        if let selected {
            let meta = CodeReader.metadata(path: selected.path)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(for: selected.path))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.inkFaint)
                    Text(selected.name).font(Theme.serif(15, weight: .medium)).foregroundColor(Theme.ink)
                    Spacer(minLength: 0)
                    Text("\(meta.size) \u{00B7} \(meta.mtime)")
                        .font(Theme.mono(10.5)).foregroundColor(Theme.inkFaint)
                }
                .padding(.bottom, 10)
                Divider().overlay(Color.white.opacity(0.1))
                    .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected, selected.path.hasSuffix(".md") {
            // A .md file shouldn't look like a worse-rendered document just
            // because it happened to open from the code browser instead of
            // Way of Working — same renderer, same real hierarchy.
            MarkdownBody(path: selected.path)
        } else {
            let ext = (selected?.path as NSString?)?.pathExtension ?? ""
            let lines = content.components(separatedBy: "\n")
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    GridRow {
                        Text("\(i + 1)")
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.inkFaint)
                            .frame(minWidth: 30, alignment: .trailing)
                        CodeHighlighter.line(line, ext: ext)
                            .font(Theme.mono(12))
                    }
                }
            }
            .textSelection(.enabled)
        }
    }
}

private func fileIcon(for path: String) -> String {
    switch (path as NSString).pathExtension {
    case "py": return "chevron.left.forwardslash.chevron.right"
    case "sh": return "terminal"
    case "md": return "doc.text"
    default: return "doc"
    }
}

/// Same hover/selection language as `PaletteRow`, extended with the second
/// line of metadata a code file actually has that a plain nav row doesn't:
/// size and last-modified. No per-row icon any more — the file-type section
/// header above each group already carries that, so repeating it per row was
/// pure duplication.
private struct FileRow: View {
    let file: CodeFile
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var meta: (size: String, mtime: String) { CodeReader.metadata(path: file.path) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).font(Theme.mono(12)).foregroundColor(isSelected ? Theme.ink : Theme.inkDim).lineLimit(1)
                    Text("\(meta.size) \u{00B7} \(meta.mtime)").font(Theme.mono(9.5)).foregroundColor(Theme.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.09) : (hovering ? Color.white.opacity(0.04) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
