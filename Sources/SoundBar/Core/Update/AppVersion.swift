import Foundation

/// A version number of the form major.minor.patch, as in the release tags (`v0.1.2`).
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    /// Reads `0.1.2`, `v0.1.2` or `0.1` (the patch is then 0). Anything else (`0.1.2-beta`, `latest`, `1.a`) is not a
    /// version of ours and gives nil, so a tag that is not a release is never taken for an update.
    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part in
            part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil
        }
        guard numbers.count == parts.count else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers.count > 2 ? numbers[2] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
