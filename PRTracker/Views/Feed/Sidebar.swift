import SwiftUI

struct Sidebar: View {
    let viewer: User?
    let repoSlug: String
    let counts: [Section: Int]
    @Binding var selection: Section?
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repoSlug).font(.system(size: 12).weight(.semibold))
                Spacer()
            }.padding(12)

            List(selection: $selection) {
                row(label: "All", icon: "tray", section: nil)
                ForEach(PRTracker.Section.allCases, id: \.self) { s in
                    row(label: s.lane.label, lane: s.lane, section: s)
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
    private func row(label: String, icon: String? = nil, lane: Lane? = nil, section: Section?) -> some View {
        HStack(spacing: 8) {
            if let lane { RoundedRectangle(cornerRadius: 1).fill(lane.color).frame(width: 4, height: 14) }
            if let icon { Image(systemName: icon).foregroundStyle(Tokens.textMuted) }
            Text(label).font(.system(size: 12.5))
            Spacer()
            let displayCount = section.flatMap { counts[$0] } ?? counts.values.reduce(0, +)
            if displayCount > 0 { CountPill(count: displayCount, tint: Tokens.textMuted) }
        }
        .tag(section)
    }
}
