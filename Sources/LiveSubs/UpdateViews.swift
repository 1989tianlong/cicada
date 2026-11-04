import SwiftUI

/// The panel's update strip, shown only while there is a newer release: install it, watch it
/// download, or read why installing in place failed (the release page was opened instead).
struct UpdateBanner: View {
    @ObservedObject var updates: Updates
    let model: AppModel

    var body: some View {
        if let update = updates.update {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(Palette.accent).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("新版本 \(update.version)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(detail(update)).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if updates.progress == nil {
                        SoftButton(updates.failure == nil ? L("安装") : L("重试")) { updates.install(model: model) }
                    }
                }
                if let p = updates.progress {
                    ProgressView(value: p).controlSize(.small).tint(Palette.accent).accessibilityLabel(L("下载进度"))
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.accentPale))
            .contextMenu { Button("更新说明") { NSWorkspace.shared.open(update.url) } }
        }
    }

    private func detail(_ update: UpdateChecker.Update) -> String {
        if let p = updates.progress { return L("正在下载 \(Int(p * 100))%，完成后自动重新打开") }
        if let f = updates.failure { return L("没能自动更新：\(f)。已打开下载页") }
        let size = update.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(update.size), countStyle: .file) + " · " : ""
        return size + L("安装后自动重新打开")
    }
}

/// Settings › 会议记录, the app-wide rows: open at login and the version with a check button.
struct AppRows: View {
    @ObservedObject var updates: Updates
    @ObservedObject var loginItem: LoginItem
    let model: AppModel

    var body: some View {
        SettingsCard {
            SettingsRow(title: L("登录时打开"), detail: loginDetail) {
                Toggle("登录时打开", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
            }
            SettingsRow(title: L("版本 \(Updates.current)"), detail: checkDetail) {
                if updates.update != nil {
                    SoftButton(L("安装并重新打开"), dark: true) { updates.install(model: model) }
                        .disabled(updates.progress != nil)
                } else {
                    SoftButton(L("检查更新")) { updates.checkNow() }.disabled(updates.check == .checking)
                }
            }
            SettingsRow(title: L("首次引导"), divider: false) {
                SoftButton(L("重新看")) { model.onboardingStep = 1; model.openOnboarding?() }
            }
        }
        .onAppear { loginItem.refresh() }
    }

    private var loginDetail: String {
        if let e = loginItem.error { return e }
        if loginItem.needsApproval { return L("请在“系统设置 › 通用 › 登录项”中允许") }
        return L("开机后在菜单栏待命，不弹窗口")
    }

    private var checkDetail: String? {
        if let u = updates.update {
            if let p = updates.progress { return L("正在下载 \(u.version)：\(Int(p * 100))%") }
            if let f = updates.failure { return L("没能自动更新：\(f)") }
            return L("有新版本 \(u.version)")
        }
        switch updates.check {
        case .checking: return L("正在检查…")
        case .upToDate: return L("已是最新版本")
        case .failed: return L("连不上 GitHub，请稍后再试")
        case .idle:
            guard let d = updates.lastChecked else { return nil }
            return L("上次检查 \(dateText(d, Calendar.current.isDateInToday(d) ? "HHmm" : "MMMdHHmm"))")
        }
    }
}
