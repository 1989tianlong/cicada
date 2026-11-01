import AppKit
import Foundation

enum SourceMode: Equatable {
    case auto
    case fixed(Lang)
}

/// Persisted user choices. Everything the menu panel and settings sheet edit lives here.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var sourceMode: SourceMode {
        didSet { save() }
    }
    /// "system" or a translation code.
    @Published var target: String {
        didSet { save() }
    }
    @Published var speakEnabled: Bool {
        didSet { save() }
    }
    /// Locale of the language I speak.
    @Published var speakFrom: String {
        didSet { save() }
    }
    /// "room" (follow the detected room language) or a translation code.
    @Published var speakTo: String {
        didSet { save() }
    }
    /// Output device UID for spoken translations, "" = automatic.
    @Published var speakOutput: String {
        didSet { save() }
    }
    @Published var recordAudio: Bool {
        didSet { save() }
    }
    /// Subtitle bar: show only while someone talks ("auto") or always.
    @Published var overlayAuto: Bool {
        didSet { save() }
    }
    @Published var overlayHideAfter: Double {
        didSet { save() }
    }

    /// Hold to talk: the right ⌥ key (default) or a key combination.
    @Published var talkKey: Shortcut {
        didSet { save() }
    }
    /// Hide / show the subtitle bar.
    @Published var toggleKey: Shortcut {
        didSet { save() }
    }

    /// What shows while listening: "notes" (live notes window, default), "bar" (subtitle bar), "none".
    @Published var displayMode: String {
        didSet { save() }
    }
    /// Ling model for notes and translation.
    @Published var aiModel: String {
        didSet { save() }
    }

    var debug: Bool { defaults.bool(forKey: "debug") }

    init() {
        if let s = defaults.string(forKey: "sourceMode"), s != "auto",
           let lang = sourceLanguages.first(where: { $0.locale == s }) {
            sourceMode = .fixed(lang)
        } else {
            sourceMode = .auto
        }
        target = defaults.string(forKey: "target") ?? "system"
        speakEnabled = defaults.bool(forKey: "speakEnabled")
        let prefersChinese = Locale.preferredLanguages.contains { $0.hasPrefix("zh") }
        speakFrom = defaults.string(forKey: "speakFrom") ?? (prefersChinese ? "zh-CN" : "en-US")
        speakTo = defaults.string(forKey: "speakTo") ?? "room"
        speakOutput = defaults.string(forKey: "speakOutput") ?? ""
        recordAudio = defaults.object(forKey: "recordAudio") as? Bool ?? true
        overlayAuto = defaults.object(forKey: "overlayAuto") as? Bool ?? true
        overlayHideAfter = defaults.object(forKey: "overlayHideAfter") as? Double ?? 4
        talkKey = Shortcut(stored: defaults.string(forKey: "talkKey")) ?? .defaultTalk
        toggleKey = Shortcut(stored: defaults.string(forKey: "toggleKey")) ?? .defaultToggle
        aiModel = defaults.string(forKey: "aiModel") ?? "Ling-3.1-flash"
        displayMode = defaults.string(forKey: "displayMode") ?? "notes"
    }

    private func save() {
        switch sourceMode {
        case .auto: defaults.set("auto", forKey: "sourceMode")
        case .fixed(let lang): defaults.set(lang.locale, forKey: "sourceMode")
        }
        defaults.set(target, forKey: "target")
        defaults.set(speakEnabled, forKey: "speakEnabled")
        defaults.set(speakFrom, forKey: "speakFrom")
        defaults.set(speakTo, forKey: "speakTo")
        defaults.set(speakOutput, forKey: "speakOutput")
        defaults.set(recordAudio, forKey: "recordAudio")
        defaults.set(overlayAuto, forKey: "overlayAuto")
        defaults.set(overlayHideAfter, forKey: "overlayHideAfter")
        defaults.set(talkKey.stored, forKey: "talkKey")
        defaults.set(toggleKey.stored, forKey: "toggleKey")
        defaults.set(aiModel, forKey: "aiModel")
        defaults.set(displayMode, forKey: "displayMode")
    }

    /// Target language. "Follow system" uses the first system language that
    /// differs from what is being spoken.
    func resolvedTarget(source: String?) -> String {
        if target != "system" { return target }
        let prefs = Locale.preferredLanguages.map(translationCode(forSystemLanguage:))
        if let src = source, let other = prefs.first(where: { $0 != src }) { return other }
        return prefs.first ?? "zh-CN"
    }

    func systemTargetDescription() -> String {
        let prefs = Locale.preferredLanguages.map(translationCode(forSystemLanguage:))
        var seen: [String] = []
        for p in prefs where !seen.contains(p) { seen.append(p) }
        return seen.prefix(2).map(targetName).joined(separator: " / ")
    }

    var speakFromLang: Lang {
        sourceLanguages.first(where: { $0.locale == speakFrom }) ?? sourceLanguages[0]
    }
}

func debugLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    let path = DevBuild.logPath
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Transcript content is only logged when `defaults write com.wquguru.cicada debug -bool true`.
func contentLog(_ message: @autoclosure () -> String) {
    if UserDefaults.standard.bool(forKey: "debug") { debugLog(message()) }
}
