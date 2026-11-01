import Foundation
import Security

// MARK: - API key (Keychain)

/// The user's Ling API key, kept in the login Keychain (encrypted by the system, readable only by
/// this app's code signature). Never written to UserDefaults, logs or exports.
enum AIKey {
    /// Dev and release builds keep separate keys, like their other settings.
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.wquguru.cicada.swiftrun") + ".ai" }
    private static let account = "ling"
    private static var cached: String??

    static func read() -> String? {
        if let cached { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        let value = status == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        if status != errSecSuccess && status != errSecItemNotFound { debugLog("keychain read failed: \(status)") }
        cached = .some(value)
        return value
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        remove()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Live Subs · Ling API key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { debugLog("keychain save failed: \(status)") }
        cached = .some(status == errSecSuccess ? key : nil)
        return status == errSecSuccess
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        cached = .some(nil)
    }

    /// "sk-…3f9a" for display.
    static func masked(_ key: String) -> String {
        guard key.count > 8 else { return "sk-…" }
        return String(key.prefix(3)) + String(repeating: "•", count: 12) + String(key.suffix(4))
    }
}

// MARK: - Ling client

/// Ling (ant-ling.com), OpenAI-compatible. One shared instance for the whole app: the account
/// allows about 2 requests per second across every model, so request *starts* go through one
/// gate (≥ 0.6 s apart, overlapping is fine) in priority order: speak-back, translation, notes.
///
/// Two quirks found in testing shape every call:
/// - `thinking` is on by default: always disable it (otherwise +2.6 s and billed reasoning).
/// - When the user message reads like a factual question, the gateway answers it with a search
///   essay instead of following the prompt. So the content always goes in the system message and
///   the user message is a fixed instruction; a search-style reply is detected and dropped.
@MainActor
final class LingClient: ObservableObject {
    enum Priority: Int, Comparable {
        case speak = 0, translate = 1, notes = 2
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    enum KeyState: Equatable {
        case none
        case unchecked
        case checking
        case ok(seconds: Double)
        case invalid
        case unreachable(String)
    }

    enum Failure: Error, Equatable {
        case noKey, invalidKey, rateLimited, hijacked, timeout, http(Int), network, parse
    }

    static let models = ["Ling-3.1-flash", "Ling-3.0-flash"]
    private static let base = URL(string: "https://api.ant-ling.com/v1/")!
    private static let hijackPrefixes = ["根据现有检索证据", "暂未找到足够可靠的信息", "根据检索"]

    @Published private(set) var keyState: KeyState
    @Published private(set) var rateLimitedAt: Date?
    var model: () -> String = { "Ling-3.1-flash" }

    /// Debug control only: make every chat call fail this way.
    var simulate: Failure?

    var hasKey: Bool { key != nil }
    var key: String? { AIKey.read() }
    /// The key is known to work (or at least not known to be bad).
    var usable: Bool { hasKey && keyState != .invalid }

    init() {
        keyState = AIKey.read() == nil ? .none : .unchecked
    }

    // MARK: Key

    /// Saves the key and checks it with the cheapest possible request.
    func setKey(_ raw: String) async {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        AIKey.save(k)
        await check()
    }

    func removeKey() {
        AIKey.remove()
        keyState = .none
    }

    func check() async {
        guard let key else { keyState = .none; return }
        keyState = .checking
        let started = Date()
        let body: [String: Any] = [
            "model": "Ling-3.0-tiny",
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "thinking": ["type": "disabled"],
        ]
        do {
            _ = try await post("chat/completions", body: body, key: key, timeout: 15)
            keyState = .ok(seconds: Date().timeIntervalSince(started))
        } catch Failure.invalidKey {
            keyState = .invalid
        } catch Failure.rateLimited {
            keyState = .ok(seconds: Date().timeIntervalSince(started))
        } catch {
            keyState = .unreachable("连不上 Ling，检查网络或代理")
        }
        debugLog("ling: key check → \(keyState)")
    }

    // MARK: Chat

    /// One chat completion. `content` goes in the system message, `instruction` is the fixed user
    /// message. Notes retry 429s with backoff; translation and speak-back fail fast so the caller
    /// can fall back to another translator.
    func chat(content: String, instruction: String, priority: Priority, json: Bool = false,
              maxTokens: Int = 1024, timeout: TimeInterval = 30, model: String? = nil) async throws -> String {
        guard let key else { throw Failure.noKey }
        guard keyState != .invalid else { throw Failure.invalidKey }
        if let simulate {
            if simulate == .rateLimited { rateLimitedAt = Date() }
            throw simulate
        }
        var body: [String: Any] = [
            "model": model ?? self.model(),
            "messages": [
                ["role": "system", "content": content],
                ["role": "user", "content": instruction],
            ],
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "thinking": ["type": "disabled"],
            "stream": false,
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        let attempts = priority == .notes ? 4 : 1
        var delay = 1.0
        for attempt in 1...attempts {
            await acquire(priority)
            let started = Date()
            do {
                let root = try await post("chat/completions", body: body, key: key, timeout: timeout)
                guard let choice = (root["choices"] as? [[String: Any]])?.first,
                      let message = choice["message"] as? [String: Any],
                      let text = message["content"] as? String else { throw Failure.parse }
                let finish = choice["finish_reason"] as? String
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if finish == nil || Self.hijackPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                    debugLog("ling: \(priority) search-style reply dropped (finish=\(finish ?? "nil"))")
                    throw Failure.hijacked
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let usage = root["usage"] as? [String: Any]
                debugLog("ling: \(priority) ok \(ms) ms tokens=\(usage?["prompt_tokens"] ?? "?")/\(usage?["completion_tokens"] ?? "?")")
                if rateLimitedAt != nil { rateLimitedAt = nil }
                return trimmed
            } catch Failure.rateLimited where attempt < attempts {
                let wait = delay + Double.random(in: 0...0.5)
                debugLog("ling: \(priority) 429, retry in \(String(format: "%.1f", wait)) s")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch Failure.rateLimited {
                rateLimitedAt = Date()
                throw Failure.rateLimited
            }
        }
        throw Failure.rateLimited
    }

    // MARK: Transport

    private func post(_ path: String, body: [String: Any], key: String, timeout: TimeInterval) async throws -> [String: Any] {
        var req = URLRequest(url: Self.base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let e as URLError where e.code == .timedOut {
            throw Failure.timeout
        } catch {
            debugLog("ling: network error \(error.localizedDescription)")
            throw Failure.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401, 403:
            if keyState != .invalid { keyState = .invalid }
            throw Failure.invalidKey
        case 429: throw Failure.rateLimited
        default:
            debugLog("ling: HTTP \(code)")
            throw Failure.http(code)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.parse }
        return root
    }

    // MARK: Start gate

    private static let spacing: TimeInterval = 0.6
    private var lastStart = Date.distantPast
    private var waiting: [(priority: Priority, seq: Int, resume: CheckedContinuation<Void, Never>)] = []
    private var seq = 0
    private var pumping = false

    private func acquire(_ priority: Priority) async {
        if waiting.isEmpty && Date().timeIntervalSince(lastStart) >= Self.spacing {
            lastStart = Date()
            return
        }
        seq += 1
        let n = seq
        await withCheckedContinuation { cont in
            waiting.append((priority, n, cont))
            pump()
        }
    }

    private func pump() {
        guard !pumping, !waiting.isEmpty else { return }
        pumping = true
        let wait = max(0, Self.spacing - Date().timeIntervalSince(lastStart))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pumping = false
                guard let i = self.waiting.indices.min(by: {
                    (self.waiting[$0].priority, self.waiting[$0].seq) < (self.waiting[$1].priority, self.waiting[$1].seq)
                }) else { return }
                let next = self.waiting.remove(at: i)
                self.lastStart = Date()
                next.resume.resume()
                self.pump()
            }
        }
    }
}
