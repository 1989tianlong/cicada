import AppKit
import SwiftUI

/// Onboarding step 2: connect a Ling key. Notes, Ling translation and Ming voices all need it, so it
/// sits right after the permissions; "稍后在设置里填" skips it (the notes window asks again later).
struct OnboardingKeyStep: View {
    @ObservedObject var ling: LingClient
    @ObservedObject var settings: AppSettings
    @State private var draft = ""
    @State private var clipboardEmpty = false

    static let platform = URL(string: "https://chat.ant-ling.com/platform/api")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("接上 Ling，用上完整的知了").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.ink)
                Text("纪要、更准的翻译和自然的同传语音都靠它，约 1 分钟。")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }
            if case .ok = ling.keyState { connected } else { entry }
            HStack(spacing: 10) {
                Text("Ling 每月赠送 ¥10 额度").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.accentPale))
                Text("约够 10–50 小时会议 · 不填也能用实时字幕和会议记录")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: Not connected yet

    private var entry: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                number(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("在 Ling 开放平台创建令牌").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("注册或登录后点“创建令牌”").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Button { NSWorkspace.shared.open(Self.platform) } label: {
                    HStack(spacing: 5) {
                        Text("打开 Ling 开放平台")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Palette.fill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)
            Divider()
            HStack(alignment: .top, spacing: 14) {
                number(2)
                VStack(alignment: .leading, spacing: 10) {
                    Text("复制 sk- 开头的 key，回来粘贴").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        SecureField("sk-…", text: $draft)
                            .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.ink.opacity(0.35), lineWidth: 1))
                            .onSubmit { save(draft) }
                        Button(action: pasteAndCheck) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard").font(.system(size: 12))
                                Text(draft.isEmpty ? L("粘贴并检查") : L("保存并检查"))
                            }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.ink))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    status
                }
            }
            .padding(.top, 18)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }

    @ViewBuilder private var status: some View {
        switch ling.keyState {
        case .checking, .unchecked:
            line(Palette.accent, L("正在检查…"), Palette.secondary)
        case .invalid:
            line(Palette.error, L("Ling 提示此令牌无效，请检查是否复制完整，或重新创建一个"), Palette.accentInk)
        case .unreachable(let why):
            line(Palette.error, why, Palette.accentInk)
        default:
            if clipboardEmpty {
                line(Palette.error, L("剪贴板里没有 sk- 开头的 key，先在 Ling 开放平台复制。"), Palette.accentInk)
            } else {
                Label("只保存在这台 Mac 上，只发给 Ling", systemImage: "lock")
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
        }
    }

    // MARK: Connected

    private var connected: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ok)
                    .frame(width: 24, height: 24).background(Circle().fill(Palette.okPale))
                Text("已连接").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                if case .ok(let s) = ling.keyState {
                    Text(L("\(settings.aiModel) · 响应约 \(String(format: "%.1f", s)) 秒"))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if let key = ling.key {
                    Text(AIKey.masked(key)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.secondary)
                }
            }
            Divider()
            Text("现在可以用了").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                benefit(L("实时纪要"), L("会中每 45 秒更新"))
                benefit(L("更准的翻译"), L("人名、术语前后一致"))
                benefit(L("自然人声"), L("同传约 2 秒出声"))
            }
            Text("下一步放示例视频，字幕和纪要会一起出现。").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }

    // MARK: Pieces

    private func number(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
            .frame(width: 26, height: 26).background(Circle().fill(Palette.fill))
    }

    private func line(_ dot: Color, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func benefit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.ground))
    }

    /// Reads the clipboard only when the button is clicked (a deliberate paste, so macOS's paste
    /// privacy prompt, if any, makes sense to the user); a typed key is checked as typed.
    private func pasteAndCheck() {
        if !draft.isEmpty { save(draft); return }
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.hasPrefix("sk-"), !text.contains(where: \.isWhitespace) else { clipboardEmpty = true; return }
        save(text)
    }

    private func save(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        clipboardEmpty = false
        draft = ""
        Task { await ling.setKey(k) }
    }
}

/// Step 2's 继续: it waits for a working key (the full experience needs one); skipping is the quieter choice.
struct OnboardingKeyFooter: View {
    @ObservedObject var ling: LingClient
    var skip: () -> Void
    var next: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if case .ok = ling.keyState {
                Button(action: next) {
                    HStack(spacing: 8) { Text("继续"); Image(systemName: "arrow.right") }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.ink))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("稍后在设置里填", action: skip).buttonStyle(.plain).foregroundStyle(Palette.secondary)
                HStack(spacing: 8) { Text("继续"); Image(systemName: "arrow.right") }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.8)))
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("先连接 Ling"))
            }
        }
    }
}
