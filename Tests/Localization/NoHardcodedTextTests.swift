import Foundation
import Testing

/// The texts the user reads are in `L`. This looks through the sources for a string literal with an accented letter
/// (which is Portuguese or Spanish) anywhere else, which would be a text that stays in one language.
@Suite("No hardcoded text")
struct NoHardcodedTextTests {
    /// The files that hold the names or the texts on purpose.
    private let allowed = ["Localization/L.swift", "Localization/AppLanguage.swift"]

    @Test("the sources have no accented text outside the translations")
    func sourcesAreFree() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return  // not run from the repository: nothing to look at
        }
        let literal = try Regex(#""[^"\n]*[À-ÿ][^"\n]*""#)
        var found: [String] = []
        var looked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let path = file.path
            if allowed.contains(where: path.hasSuffix) { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            looked += 1
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                if code.contains(literal) { found.append("\(file.lastPathComponent):\(number + 1): \(code)") }
            }
        }
        #expect(looked > 20, "only \(looked) files were looked at")
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
