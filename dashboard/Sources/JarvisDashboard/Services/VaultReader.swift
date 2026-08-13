import Foundation

enum VaultReader {
    static func notes(in dir: String, excluding: Set<String> = ["README.md"]) -> [VaultNote] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names
            .filter { $0.hasSuffix(".md") && !excluding.contains($0) }
            .sorted()
            .map { name in
                let fm = frontmatter(path: "\(dir)/\(name)")
                var extra = fm
                let type = extra.removeValue(forKey: "type") ?? ""
                let status = extra.removeValue(forKey: "status") ?? ""
                return VaultNote(name: String(name.dropLast(3)), type: type, status: status, extra: extra)
            }
    }

    static func frontmatter(path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var fm: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            fm[key] = value
        }
        return fm
    }
}
