import SwiftUI
import UserNotifications

struct NotificationsStepView: View {
    @Bindable var model: OnboardingModel
    var onRequestPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Choose how much each repository notifies you. You can change this any time in Settings.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($model.pending) { $repo in
                        HStack(spacing: 9) {
                            Text(repo.id).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
                            Spacer()
                            Picker("", selection: $repo.level) {
                                Text("Everything").tag(NotificationLevel.everything)
                                Text("Personal").tag(NotificationLevel.personal)
                                Text("None").tag(NotificationLevel.none)
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))

            permissionRow
            Spacer()
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch model.notifStatus {
        case .authorized, .provisional, .ephemeral:
            HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.approved); Text("macOS notifications enabled").font(.system(size: 12)).foregroundStyle(Tokens.textMuted) }
        case .denied:
            Text("macOS notifications are turned off. Enable them in System Settings → Notifications → PR Tracker.")
                .font(.system(size: 11)).foregroundStyle(Tokens.textFaint)
        default:
            Button("Enable macOS notifications") { onRequestPermission() }
        }
    }
}
