import AppKit
import SwiftUI

enum Palette {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let ground = Color(red: 0.953, green: 0.957, blue: 0.965)
    static let line = Color(red: 0.894, green: 0.902, blue: 0.918)
    static let secondary = Color(red: 0.353, green: 0.373, blue: 0.42)
    static let tertiary = Color(red: 0.42, green: 0.44, blue: 0.50)
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.17)
    static let accentInk = Color(red: 0.70, green: 0.23, blue: 0.08)
    static let accentPale = Color(red: 0.99, green: 0.93, blue: 0.906)
    /// Controls, chips, search fields.
    static let fill = Color(red: 0.949, green: 0.953, blue: 0.961)
    /// Emphasis blocks (summary, setting cards).
    static let raised = Color(red: 0.961, green: 0.965, blue: 0.973)
    /// Current row while something is live.
    static let accentWash = Color(red: 1.0, green: 0.98, blue: 0.973)
    static let ok = Color(red: 0.122, green: 0.478, blue: 0.271)
    static let okPale = Color(red: 0.906, green: 0.961, blue: 0.925)
    static let error = Color(red: 0.706, green: 0.137, blue: 0.094)
    static let errorPale = Color(red: 0.992, green: 0.925, blue: 0.918)
}

struct LogoTile: View {
    var size: CGFloat = 34
    var body: some View { BrandMark(size: size) }
}

/// A gray rounded row that opens a menu, used for the language choices.
struct ChoiceRow: View {
    let label: String
    let value: String
    var badge: String? = nil
    let options: [(id: String, title: String)]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in
                Button(o.title) { onPick(o.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(width: 44, alignment: .leading)
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.accentPale))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 11).fill(Palette.ground))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

// MARK: - Menu bar panel

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var sourceOptions: [(id: String, title: String)] {
        let auto = model.candidates.map(\.name).joined(separator: "、")
        return [("auto", auto.isEmpty ? "自动识别" : "自动识别（\(auto)）")] + sourceLanguages.map {
            ($0.locale, model.installed.isEmpty || model.installed.contains($0.locale) ? $0.name : "\($0.name)（需下载）")
        }
    }

    private var targetOptions: [(id: String, title: String)] {
        [("system", "跟随系统（\(settings.systemTargetDescription())）")] + targetLanguages.map { ($0.code, $0.name) }
    }

    private var heardValue: (String, String?) {
        switch settings.sourceMode {
        case .fixed(let l): return (l.name, nil)
        case .auto: return (model.listen.activeLang?.name ?? "自动", "自动识别")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LogoTile(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Live Subs").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
                        if let dev = DevBuild.label {
                            Text("DEV").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Palette.ink))
                                .help(dev)
                        }
                    }
                    if let dev = DevBuild.label {
                        Text(dev).font(.system(size: 10).monospaced()).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(model.running ? Palette.accent : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        Text(model.running ? model.summary : "已暂停")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Toggle("字幕", isOn: Binding(get: { model.running }, set: { model.setRunning($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.ink)
            }

            VStack(spacing: 8) {
                ChoiceRow(label: "听到", value: heardValue.0, badge: heardValue.1, options: sourceOptions) {
                    model.sourceSelection = $0
                }
                ChoiceRow(label: "翻译成",
                          value: targetName(model.listen.resolvedTarget),
                          badge: settings.target == "system" ? "跟随系统" : nil,
                          options: targetOptions) {
                    model.targetSelection = $0
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我说话也翻译").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: 5) {
                        Text("按住").foregroundStyle(Palette.secondary)
                        KeyCap(settings.talkKey.display)
                        Text("说\(settings.speakFromLang.name) → \(targetName(model.speak.targetCode))")
                            .foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    .font(.system(size: 12))
                }
                Spacer()
                Toggle("我说话也翻译", isOn: Binding(get: { settings.speakEnabled }, set: { model.enableSpeaking($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.ink)
            }
            if settings.speakEnabled && model.virtualMic == nil {
                HStack {
                    Text("虚拟麦克风还没设置好，对方听不到").font(.system(size: 12)).foregroundStyle(Palette.accentInk)
                    Spacer()
                    SoftButton("设置") { model.openSettings(.speak) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.accentPale))
            }

            Divider()

            VStack(spacing: 10) {
                HStack {
                    Text("显示").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Picker("显示", selection: Binding(get: { settings.displayMode }, set: { model.setDisplayMode($0) })) {
                        Text("实时纪要").tag("notes")
                        Text("字幕条").tag("bar")
                        Text("不显示").tag("none")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                }
                if settings.displayMode == "notes" {
                    HStack {
                        Text(model.ling.hasKey ? "纪要、文字记录和字幕都在一个窗口里" : "填上 API key 才有纪要；文字记录照常")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer()
                        SoftButton("打开") { model.openNotesWindow() }
                    }
                }
                if settings.displayMode == "bar" {
                    HStack {
                        Text("字幕条").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Picker("字幕条", selection: Binding(get: { settings.overlayAuto }, set: { model.setOverlayAuto($0) })) {
                            Text("说话时显示").tag(true)
                            Text("一直显示").tag(false)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                    }
                }
                if settings.displayMode == "bar" && settings.overlayAuto {
                    HStack {
                        Text("安静多久后收起").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Picker("收起前等待", selection: $settings.overlayHideAfter) {
                            Text("2 秒").tag(2.0)
                            Text("4 秒").tag(4.0)
                            Text("8 秒").tag(8.0)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                    }
                }
                HStack(spacing: 5) {
                    Text("切换显示方式").foregroundStyle(Palette.secondary)
                    Spacer()
                    KeyCap(settings.toggleKey.display)
                }
                .font(.system(size: 12))
            }

            Divider()

            HStack {
                Button("会议记录") { model.openMainWindow?() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Palette.secondary)
        }
        .padding(18)
        .frame(width: 320)
        .background(Color.white)
    }
}

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 0.82), lineWidth: 1))
    }
}

// MARK: - Main window

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @State private var selection: String?
    @State private var query = ""
    @State private var view = "both"
    @State private var titleDraft = ""
    @State private var tab = "notes"
    @State private var jumpTo: Double?

    private var filtered: [Session] {
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { s in
            s.title.localizedCaseInsensitiveContains(query)
                || s.lines.contains { $0.src.localizedCaseInsensitiveContains(query) || ($0.dst ?? "").localizedCaseInsensitiveContains(query) }
        }
    }

    private var current: Session? { store.session(selection ?? store.sessions.first?.id) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 270)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
                .padding(.trailing, 14).padding(.bottom, 14).padding(.top, 38)
        }
        .background(Palette.ground)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoTile(size: 28)
                Text("会议记录").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
                Spacer()
                Button { model.openSettings() } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("设置")
            }
            .padding(.top, 38)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.tertiary)
                TextField("搜索会议内容", text: $query).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { s in
                        sessionRow(s)
                    }
                }
            }
            if store.sessions.isEmpty {
                Text("打开字幕后，每场会议会自动记在这里。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func sessionRow(_ s: Session) -> some View {
        let selected = s.id == (selection ?? store.sessions.first?.id)
        let live = s.id == store.liveID
        return Button {
            selection = s.id
            titleDraft = s.title
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if live { Circle().fill(Palette.accent).frame(width: 7, height: 7) }
                    Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                Text(meta(s, live: live)).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.white : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.line : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
            Button("删除", role: .destructive) { store.delete(s.id) }.disabled(live)
        }
    }

    private func meta(_ s: Session, live: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(s.startedAt) ? "今天 HH:mm" : "M月d日 HH:mm"
        let mins = Int(s.duration / 60)
        let length = mins < 1 ? "不到 1 分钟" : "\(mins) 分钟"
        return live ? "进行中 · \(s.lines.count) 句" : "\(f.string(from: s.startedAt)) · \(length) · \(s.lines.count) 句"
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let s = current {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("标题", text: Binding(
                            get: { titleDraft.isEmpty ? s.title : titleDraft },
                            set: { titleDraft = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .bold))
                        .onSubmit { store.rename(s.id, to: titleDraft) }
                        Text(TranscriptExport.header(s) + " · \(s.lines.count) 句")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Picker("内容", selection: $tab) {
                        Text("纪要").tag("notes")
                        Text("文字记录").tag("transcript")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    if tab == "transcript" {
                        Picker("显示", selection: $view) {
                            Text("双语").tag("both")
                            Text("原文").tag("src")
                            Text("译文").tag("dst")
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    }
                    Menu {
                        Button("复制为 Markdown") { model.export(s, kind: "copy") }
                        Divider()
                        Button("导出 Markdown…") { model.export(s, kind: "md") }
                        Button("导出 Word…") { model.export(s, kind: "word") }
                        Button("导出字幕 SRT…") { model.export(s, kind: "srt") }
                        Divider()
                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
                    } label: {
                        Text("导出").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.ink))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .disabled(s.lines.isEmpty)
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
                .onChange(of: s.id) { _, _ in titleDraft = "" }

                Divider().padding(.horizontal, 28)

                if tab == "notes" && !s.lines.isEmpty {
                    SessionNotesView(model: model, engine: model.notes, ling: model.ling, session: s) { t in
                        jumpTo = t
                        tab = "transcript"
                    }
                } else if s.lines.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(s.id == store.liveID ? "正在听，说话的内容会出现在这里" : "这场会议没有记录到内容")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(s.lines) { l in
                                    lineRow(l).id(l.id)
                                    Divider()
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                        .onChange(of: s.lines.count) { _, _ in
                            if s.id == store.liveID, let last = s.lines.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear {
                            if let t = jumpTo, let l = s.lines.first(where: { $0.t >= t - 1 }) { proxy.scrollTo(l.id, anchor: .top) }
                            jumpTo = nil
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                LogoTile(size: 44)
                Text("还没有会议记录").font(.system(size: 15, weight: .semibold))
                Text("打开字幕后，每场会议会自动保存一份双语稿子。")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func lineRow(_ l: TranscriptLine) -> some View {
        let me = l.speaker == "me"
        return HStack(alignment: .top, spacing: 16) {
            Text(TranscriptExport.clock(l.t))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.tertiary)
                .frame(width: 44, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(me ? Palette.accent : Palette.ink.opacity(0.35)).frame(width: 7, height: 7)
                    Text(me ? "你" : "对方").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                }
                if view != "dst" {
                    Text(l.src)
                        .font(.system(size: view == "src" ? 14 : 13))
                        .foregroundStyle(view == "src" ? Palette.ink : Palette.tertiary)
                        .textSelection(.enabled)
                }
                if view != "src" {
                    Text(l.dst ?? "翻译中…")
                        .font(.system(size: 14))
                        .foregroundStyle(l.dst == nil ? Palette.tertiary : Palette.ink)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}


/// A meeting's notes in the main window: the same notes view as the live window, or a way to
/// make them for a meeting recorded without a key.
struct SessionNotesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: NotesEngine
    @ObservedObject var ling: LingClient
    let session: Session
    let onJump: (Double) -> Void

    private var live: Bool { session.id == model.store.liveID }
    private var notes: MeetingNotes? { live ? engine.notes : session.notes }
    private var generating: Bool { engine.generatingID == session.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let notes, !notes.isEmpty {
                    NotesContentView(notes: notes, fresh: live ? engine.fresh : [], live: live, onJump: onJump)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(generating ? "正在整理纪要…" : live ? "纪要会在会议进行中自动生成" : "这场会议还没有纪要")
                            .font(.system(size: 15, weight: .bold))
                        Text(ling.hasKey ? "用 Ling 从文字记录整理总结、议题、结论和人名，大约半分钟。"
                                         : "在 设置 › AI 服务 填上 Ling 的 API key 后就能生成。")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        if !live {
                            HStack(spacing: 8) {
                                if ling.hasKey {
                                    SoftButton(generating ? "正在生成…" : "生成纪要", dark: true) {
                                        engine.generate(for: session.id)
                                    }
                                    .disabled(generating)
                                } else {
                                    SoftButton("去填 key", dark: true) { model.openSettings(.ai) }
                                }
                            }
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}
