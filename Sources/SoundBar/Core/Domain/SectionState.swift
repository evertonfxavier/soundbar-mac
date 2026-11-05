import Combine
import Foundation

/// The sections of the menu that can be folded.
enum MenuSection: String, CaseIterable {
    case chromeTabs
    case apps
    case soundboard
}

/// Which sections of the menu the user folded, kept between runs. Every section starts open, and each one opens and
/// closes on its own.
@MainActor
final class SectionState: ObservableObject {
    private static let key = "collapsedSections"

    @Published private(set) var collapsed: Set<MenuSection>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        collapsed = Set(stored.compactMap(MenuSection.init(rawValue:)))
    }

    func isExpanded(_ section: MenuSection) -> Bool { !collapsed.contains(section) }

    func toggle(_ section: MenuSection) {
        if collapsed.contains(section) {
            collapsed.remove(section)
        } else {
            collapsed.insert(section)
        }
        defaults.set(collapsed.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
