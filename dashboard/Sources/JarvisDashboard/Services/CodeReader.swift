import Foundation

enum CodeReader {
    static let extensions: Set<String> = ["py", "sh", "md"]

    static func files() -> [CodeFile] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: JarvisPaths.jarvisVoiceDir) else {
            return []
        }
        return names
            .filter { extensions.contains(($0 as NSString).pathExtension) }
            .sorted()
            .map { CodeFile(name: $0, path: "\(JarvisPaths.jarvisVoiceDir)/\($0)") }
    }

    static func content(path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return "(could not read this file)"
        }
        return text
    }

    static func metadata(path: String) -> (size: String, mtime: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return ("-", "-") }
        let bytes = (attrs[.size] as? Int) ?? 0
        let sizeText = bytes < 1024 ? "\(bytes)B" : String(format: "%.1fKB", Double(bytes) / 1024)
        let mtimeText = (attrs[.modificationDate] as? Date)?.formatted(.relative(presentation: .named)) ?? "-"
        return (sizeText, mtimeText)
    }
}
