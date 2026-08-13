import SwiftUI

/// "Its way of working" — renders the project's own markdown docs natively,
/// rather than inventing a separate diagram that could drift from the truth
/// already written down in ARCHITECTURE.md / JARVIS-FEATURES.md etc.
struct ArchitectureView: View {
    @State private var selectedIndex = 0

    private var docs: [(title: String, path: String)] { JarvisPaths.architectureDocs }

    /// The first 4 entries describe what the system *is* (stable reference);
    /// the rest are living working notes (audit findings, open items, design
    /// rules) — same real-grouping idea as Code's Python/Shell/Docs sections,
    /// instead of one flat list of 7 unrelated-looking rows.
    private var groups: [(label: String, icon: String, range: Range<Int>)] {
        let split = min(4, docs.count)
        return [
            ("Reference", "book", 0..<split),
            ("Working notes", "pencil.and.list.clipboard", split..<docs.count),
        ]
    }

    private var lastModified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: docs[selectedIndex].path))?[.modificationDate] as? Date
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionLabel(icon: group.icon, text: group.label)
                            ForEach(group.range, id: \.self) { i in
                                PaletteRow(title: docs[i].title,
                                           isSelected: selectedIndex == i) {
                                    selectedIndex = i
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .background(Theme.void)
            .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Same invisible-`.navigationTitle` gap found and fixed
                    // in Code this round (the app hides its title bar
                    // entirely, so it never rendered) — a real header here too.
                    detailHeader
                    MarkdownBody(path: docs[selectedIndex].path)
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.void)
            .navigationTitle(docs[selectedIndex].title)
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

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(docs[selectedIndex].title)
                    .font(Theme.serif(18, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Spacer(minLength: 0)
                if let lastModified {
                    Text("Updated \(lastModified.formatted(.relative(presentation: .named)))")
                        .font(Theme.mono(10.5))
                        .foregroundColor(Theme.inkFaint)
                }
            }
            .padding(.bottom, 12)
            Divider().overlay(Color.white.opacity(0.1))
                .padding(.bottom, 16)
        }
    }
}

/// A light line-based renderer: headings get real size/weight hierarchy,
/// everything else goes through AttributedString(markdown:) for bold/
/// italic/code/links. Good enough for reading our own docs without pulling
/// in a full markdown-rendering dependency for one view.
struct MarkdownBody: View {
    let path: String

    private struct Line: Identifiable {
        let id: Int
        let text: String
    }

    /// A contiguous ``` ... ``` run becomes one block sharing a single
    /// background band, not individually-floating lines — code and diagrams
    /// (our ASCII architecture diagrams especially) read as distinct blocks
    /// this way instead of blending into the surrounding prose.
    private enum Block: Identifiable {
        case fenced(id: Int, lines: [String])
        case line(Line)

        var id: Int {
            switch self {
            case .fenced(let id, _): return id
            case .line(let l): return l.id
            }
        }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var inFence = false
        var fenceStart = 0
        var fenceLines: [String] = []
        for (i, raw) in CodeReader.content(path: path).components(separatedBy: "\n").enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inFence {
                    out.append(.fenced(id: fenceStart, lines: fenceLines))
                    fenceLines = []
                } else {
                    fenceStart = i
                }
                inFence.toggle()
                continue // the fence markers themselves render as nothing
            }
            if inFence {
                fenceLines.append(raw)
            } else {
                out.append(.line(Line(id: i, text: raw)))
            }
        }
        if inFence && !fenceLines.isEmpty { out.append(.fenced(id: fenceStart, lines: fenceLines)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .fenced(_, let codeLines):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(codeLines.enumerated()), id: \.offset) { _, text in
                            Text(text.isEmpty ? " " : text)
                                .font(Theme.mono(11.5))
                                .foregroundColor(Theme.inkDim)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(10)
                    .background(Theme.inkFaint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                case .line(let line):
                    lineView(line)
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: Line) -> some View {
        if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            // Tables: verbatim mono, tight spacing, no wrap — alignment IS the content here.
            Text(line.text)
                .font(Theme.mono(11.5))
                .foregroundColor(Theme.inkDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, -3)
        } else if let (level, text) = headingLevel(line.text) {
            // Real prose content gets Claude's own serif — verified from the
            // real site's font stack, not the plain system sans this used
            // to render with.
            Text(inline(text))
                .font(Theme.serif(headingSize(level), weight: .semibold))
                .foregroundColor(Theme.ink)
                .padding(.top, level <= 2 ? 10 : 4)
        } else if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}").foregroundColor(Theme.inkFaint)
                Text(inline(String(line.text.trimmingCharacters(in: .whitespaces).dropFirst(2))))
            }
            .font(Theme.serif(13))
            .foregroundColor(Theme.inkDim)
        } else if line.text.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(line.text))
                .font(Theme.serif(13))
                .foregroundColor(Theme.inkDim)
        }
    }

    private func headingLevel(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix(while: { $0 == "#" }).count
        guard level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 22; case 2: return 18; case 3: return 15; default: return 13 }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
