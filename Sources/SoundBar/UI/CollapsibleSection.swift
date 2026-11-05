import SwiftUI

/// A section of the menu with a title that folds and unfolds it, and, while it is open, buttons at the right of the
/// title (`trailing`). The title shows how many items there are, so a folded section still says what is in it.
struct CollapsibleSection<Trailing: View, Content: View>: View {
    @EnvironmentObject var sections: SectionState

    private let section: MenuSection
    private let title: String
    private let count: Int?
    private let trailing: Trailing
    private let content: Content

    init(
        _ section: MenuSection, title: String, count: Int? = nil,
        @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.title = title
        self.count = count
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        let expanded = sections.isExpanded(section)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    sections.toggle(section)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))
                            .frame(width: 10)
                        Text(title).font(.caption2.weight(.semibold))
                        if let count {
                            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? L.collapseSection.string : L.expandSection.string)
                .accessibilityLabel(title)
                .accessibilityValue(expanded ? L.sectionExpanded.string : L.sectionCollapsed.string)
                .accessibilityAddTraits(.isHeader)

                if expanded { trailing }
            }

            if expanded { content }
        }
    }
}

extension CollapsibleSection where Trailing == EmptyView {
    init(_ section: MenuSection, title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(section, title: title, count: count, trailing: { EmptyView() }, content: content)
    }
}
