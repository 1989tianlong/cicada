import AppKit
import CryptoKit
import Foundation

/// Installs the BlackHole 2ch virtual audio device without the Terminal:
/// download the official, Apple-notarized installer, verify its SHA-256,
/// then run it through the standard macOS administrator password dialog.
/// (We download it rather than bundling it, so we don't redistribute the GPL driver.)
@MainActor
final class VirtualMicInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case installing
        case done
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    static let packageURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg")!
    static let packageSHA256 = "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"

    var isInstalled: Bool { AudioDevices.virtualMic != nil }

    /// `verifyOnly` stops after the download and checksum (used by tests).
    func install(verifyOnly: Bool = false, onInstalled: (() -> Void)? = nil) {
        guard state != .downloading && state != .installing else { return }
        Task { await run(verifyOnly: verifyOnly, onInstalled: onInstalled) }
    }

    private func run(verifyOnly: Bool, onInstalled: (() -> Void)?) async {
        state = .downloading
        let pkg: URL
        do {
            let (tmp, response) = try await URLSession.shared.download(from: Self.packageURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .failed("下载失败，请检查网络")
                return
            }
            let data = try Data(contentsOf: tmp)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == Self.packageSHA256 else {
                debugLog("virtual mic: checksum mismatch \(digest)")
                state = .failed("安装包校验没通过，已停止")
                return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveSubsMic", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            pkg = dir.appendingPathComponent("BlackHole2ch.pkg")
            try? FileManager.default.removeItem(at: pkg)
            try FileManager.default.moveItem(at: tmp, to: pkg)
            debugLog("virtual mic: downloaded and verified \(pkg.path)")
        } catch {
            debugLog("virtual mic: download error \(error)")
            state = .failed("下载失败，请检查网络")
            return
        }
        if verifyOnly {
            state = .idle
            return
        }

        state = .installing
        // Give the UI a beat to show "安装中" before the system dialog appears.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let script = """
        do shell script "/usr/sbin/installer -pkg " & quoted form of "\(pkg.path)" & " -target /" \
        with prompt "Live Subs 要安装虚拟麦克风，让会议里的人听到你的翻译。" with administrator privileges
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            debugLog("virtual mic: installer error \(errorInfo)")
            state = code == -128 ? .idle : .failed("安装没有完成，可以再试一次")
            return
        }
        // Core Audio picks the new device up after a moment.
        for _ in 0..<20 {
            if isInstalled { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if isInstalled {
            debugLog("virtual mic: installed")
            state = .done
            onInstalled?()
        } else {
            state = .failed("装好了，但系统还没识别到，请稍后再看")
        }
    }
}
