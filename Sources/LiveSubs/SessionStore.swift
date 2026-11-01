import AppKit
import Foundation

struct TranscriptLine: Codable, Identifiable, Equatable {
    var id: String
    /// Seconds from the start of the session.
    var t: Double
    /// "them" (system audio) or "me" (microphone).
    var speaker: String
    var src: String
    var dst: String?
    var srcLang: String
    var dstLang: String
}

struct Session: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var lines: [TranscriptLine]
    var hasAudio: Bool

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}

/// One folder per meeting under ~/Library/Application Support/LiveSubs/Sessions/<id>/:
/// session.json, system.m4a (what you heard) and mic.m4a (what you said).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var liveID: String?

    let root: URL
    private var saveWork: DispatchWorkItem?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("\(DevBuild.supportFolder)/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func systemAudioURL(_ id: String) -> URL { folder(id).appendingPathComponent("system.m4a") }
    func micAudioURL(_ id: String) -> URL { folder(id).appendingPathComponent("mic.m4a") }

    private func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [Session] = []
        for dir in dirs {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
               var s = try? decoder.decode(Session.self, from: data) {
                if s.endedAt == nil { s.endedAt = s.lines.last.map { s.startedAt.addingTimeInterval($0.t + 5) } ?? s.startedAt }
                out.append(s)
            }
        }
        sessions = out.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Live session

    @discardableResult
    func begin() -> Session {
        let now = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        let fid = DateFormatter()
        fid.dateFormat = "yyyyMMdd-HHmmss"
        let s = Session(id: fid.string(from: now), title: "会议 \(f.string(from: now))",
                        startedAt: now, endedAt: nil, lines: [], hasAudio: false)
        sessions.insert(s, at: 0)
        liveID = s.id
        try? FileManager.default.createDirectory(at: folder(s.id), withIntermediateDirectories: true)
        return s
    }

    func end() {
        guard let id = liveID, let i = index(id) else { liveID = nil; return }
        sessions[i].endedAt = Date()
        liveID = nil
        if sessions[i].lines.isEmpty {
            // Nothing was said: don't keep an empty meeting around.
            try? FileManager.default.removeItem(at: folder(id))
            sessions.remove(at: i)
            return
        }
        sessions[i].hasAudio = FileManager.default.fileExists(atPath: systemAudioURL(id).path)
            || FileManager.default.fileExists(atPath: micAudioURL(id).path)
        saveNow(id)
    }

    var liveStart: Date? { liveID.flatMap { index($0) }.map { sessions[$0].startedAt } }

    func append(_ line: TranscriptLine) {
        guard let id = liveID, let i = index(id) else { return }
        sessions[i].lines.append(line)
        scheduleSave(id)
    }

    func setTranslation(lineID: String, _ text: String) {
        guard let id = liveID, let i = index(id),
              let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].dst = text
        scheduleSave(id)
    }

    // MARK: Editing

    func rename(_ id: String, to title: String) {
        guard let i = index(id) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sessions[i].title = t
        saveNow(id)
    }

    func delete(_ id: String) {
        guard id != liveID, let i = index(id) else { return }
        try? FileManager.default.removeItem(at: folder(id))
        sessions.remove(at: i)
    }

    func session(_ id: String?) -> Session? { id.flatMap { index($0) }.map { sessions[$0] } }

    private func index(_ id: String) -> Int? { sessions.firstIndex(where: { $0.id == id }) }

    private func scheduleSave(_ id: String) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow(id) }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func saveNow(_ id: String) {
        guard let s = session(id) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(s) else { return }
        try? FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        try? data.write(to: folder(id).appendingPathComponent("session.json"), options: .atomic)
    }
}

// MARK: - Export

enum TranscriptExport {
    static func clock(_ t: Double) -> String {
        let s = Int(max(0, t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func speakerName(_ line: TranscriptLine) -> String { line.speaker == "me" ? "你" : "对方" }

    static func header(_ s: Session) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        let mins = Int(s.duration / 60)
        return "\(f.string(from: s.startedAt)) · " + (mins < 1 ? "不到 1 分钟" : "\(mins) 分钟")
    }

    static func markdown(_ s: Session) -> String {
        var out = "# \(s.title)\n\n\(header(s))\n\n"
        for l in s.lines {
            out += "**[\(clock(l.t))] \(speakerName(l))**  \n\(l.src)\n"
            if let d = l.dst, d != l.src { out += "> \(d)\n" }
            out += "\n"
        }
        return out
    }

    static func srt(_ s: Session) -> String {
        func ts(_ t: Double) -> String {
            let ms = Int((max(0, t) * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        var out = ""
        for (i, l) in s.lines.enumerated() {
            let next = i + 1 < s.lines.count ? s.lines[i + 1].t : l.t + 4
            let end = max(l.t + 1, min(next, l.t + 8))
            out += "\(i + 1)\n\(ts(l.t)) --> \(ts(end))\n\(l.src)\n"
            if let d = l.dst, d != l.src { out += "\(d)\n" }
            out += "\n"
        }
        return out
    }

    static func docx(_ s: Session) throws -> Data {
        let doc = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = after
            doc.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: p,
            ]))
        }
        add(s.title, size: 20, weight: .bold, after: 6)
        add(header(s), size: 10, color: .darkGray, after: 14)
        for l in s.lines {
            add("[\(clock(l.t))] \(speakerName(l))", size: 9, weight: .semibold, color: .darkGray, after: 2)
            add(l.src, size: 11, after: 2)
            if let d = l.dst, d != l.src { add(d, size: 11, color: NSColor(calibratedWhite: 0.3, alpha: 1), after: 10) }
        }
        return try doc.data(from: NSRange(location: 0, length: doc.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }
}
