import SwiftUI

/// Sidebar selection wrapper. Using a non-optional sentinel for "All" because
/// SwiftUI's `List(selection: Optional<X>)` won't let users *select* the nil-tagged row.
enum SidebarItem: Hashable {
    case all
    case section(PRTracker.Section)
}

struct Sidebar: View {
    let viewer: User?
    let repoSlug: String
    let counts: [PRTracker.Section: Int]
    @Binding var selection: PRTracker.Section?
    var onOpenSettings: () -> Void

    private var listSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection.map { .section($0) } ?? .all },
            set: { newValue in
                switch newValue {
                case .all, .none: selection = nil
                case .section(let s): selection = s
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repoSlug).font(.system(size: 12).weight(.semibold))
                Spacer()
            }.padding(12)

            List(selection: listSelection) {
                row(label: "All", icon: "tray", item: .all, section: nil)
                ForEach(PRTracker.Section.allCases, id: \.self) { s in
                    row(label: s.lane.label, lane: s.lane, item: .section(s), section: s)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 8) {
                if let v = viewer { AvatarView(user: v, size: 22); Text(v.name ?? v.login).metaText() }
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }.padding(12)
        }
        .background(Tokens.sidebarBg)
        .frame(width: 220)
    }

    @ViewBuilder
    private func row(label: String, icon: String? = nil, lane: Lane? = nil, item: SidebarItem, section: PRTracker.Section?) -> some View {
        HStack(spacing: 8) {
            if let lane { RoundedRectangle(cornerRadius: 1).fill(lane.color).frame(width: 4, height: 14) }
            if let icon { Image(systemName: icon).foregroundStyle(Tokens.textMuted) }
            Text(label).font(.system(size: 12.5))
            Spacer()
            let displayCount: Int = {
                if let section { return counts[section] ?? 0 }
                return counts.values.reduce(0, +)   // "All"
            }()
            if displayCount > 0 { CountPill(count: displayCount, tint: Tokens.textMuted) }
        }
        .tag(item)
    }
}
