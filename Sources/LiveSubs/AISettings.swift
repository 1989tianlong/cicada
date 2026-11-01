import AppKit
import SwiftUI

/// Settings › AI 服务: the one Ling key the whole app uses, and what uses it.
struct AISettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ling: LingClient
    @ObservedObject var settings: AppSettings
    @State private var draft = ""
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            keyCard
            Text("用在哪里").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                .padding(.top, 4)
            SettingsCard {
                usageRow("实时纪要", tag: ling.usable ? "用 Ling" : "需要 key", on: ling.usable,
                         note: ling.usable ? "会中每 45 秒更新" : "填好 key 后可用")
                usageRow("翻译", tag: ling.usable ? "用 Ling" : "Google", on: ling.usable,
                         note: ling.usable ? "整句用 Ling；不行时换 Google、本机" : "没有 key 时照常可用")
                usageRow("语音识别", tag: "本机", on: false, note: "更快，不花钱")
                SettingsRow(title: "同声传译的声音", detail: ling.usable ? "Ming 的声音或你自己的声音" : "没有 key 时用本机声音",
                            divider: false) {
                    SoftButton("去选声音") { model.settingsSection = .speak }
                }
            }
            SettingsCard {
                SettingsRow(title: "模型", detail: "3.1 更准；3.0 更快、更省", divider: false) {
                    PillMenu(value: settings.aiModel, options: LingClient.models.map { ($0, $0) }) { settings.aiModel = $0 }
                }
            }
            Text("一小时会议约 ¥0.15–1（目前优惠价）。发出去的只有文字（用你自己的声音时还有那段录音），语音识别留在本机。")
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
        }
    }

    // MARK: Key

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                if let detail = statusDetail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
                Spacer()
            }
            if let key = ling.key, !editing {
                HStack(spacing: 8) {
                    Text(AIKey.masked(key)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
                    SoftButton("更换") { draft = ""; editing = true }
                    if case .invalid = ling.keyState {} else if case .unreachable = ling.keyState {
                        SoftButton("重试") { Task { await ling.check() } }
                    }
                }
            } else {
                if ling.key == nil {
                    Text("在 Ling 开放平台点“创建令牌”，复制以 sk- 开头的那串。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                HStack(spacing: 8) {
                    SecureField("sk-…", text: $draft)
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.ink.opacity(0.6), lineWidth: 1))
                        .onSubmit(save)
                    SoftButton("保存并检查", dark: true, action: save)
                    if editing { SoftButton("取消") { editing = false } }
                }
                Button("打开 Ling 开放平台 ↗") {
                    if let url = URL(string: "https://chat.ant-ling.com/open") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                Text("只存在这台 Mac 上（只有你的账户能读），只发给 Ling（ant-ling.com）")
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                Spacer()
                if ling.key != nil && !editing {
                    Button("移除") { ling.removeKey() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.961, green: 0.965, blue: 0.973)))
    }

    private func save() {
        let k = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        draft = ""
        editing = false
        Task { await ling.setKey(k) }
    }

    private var statusColor: Color {
        switch ling.keyState {
        case .ok: Palette.ok
        case .invalid, .unreachable: Palette.error
        case .checking, .unchecked: Palette.accent
        case .none: Color(white: 0.75)
        }
    }

    private var statusTitle: String {
        switch ling.keyState {
        case .none: "还没填 API key"
        case .unchecked, .checking: "正在检查…"
        case .ok: "已连接"
        case .invalid: "这个 key 用不了"
        case .unreachable: "暂时连不上"
        }
    }

    private var statusDetail: String? {
        switch ling.keyState {
        case .ok(let s): "\(settings.aiModel) · 响应约 \(String(format: "%.1f", s)) 秒"
        case .invalid: "Ling 提示此令牌无效，请检查是否复制完整，或重新创建一个"
        case .unreachable(let why): why
        case .none: "不填 key 时，字幕和翻译仍可正常使用"
        default: nil
        }
    }

    private func usageRow(_ title: String, tag: String, on: Bool, note: String, divider: Bool = true) -> some View {
        SettingsRow(title: title, detail: note, divider: divider) {
            Text(tag).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Palette.ok : Palette.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Palette.okPale : Palette.fill))
        }
    }
}
