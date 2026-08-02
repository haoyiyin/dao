import AppKit
import Foundation

/// AppleScript 命令类型
enum AppleScriptCommand {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(TimeInterval)
    case setVolume(Double) // 0-1
}

/// AppleScript 媒体控制器（兜底链路）
///
/// 兼容旧版 macOS / MediaRemote 不可用场景，通过 AppleScript 控制：
/// - Apple Music（com.apple.Music）
/// - Spotify（com.spotify.client）
/// - YouTube Music 依赖浏览器 MediaRemote 发布，无 AppleScript 兜底（见 KnownIssues）
///
/// 执行方式：osascript 子进程（避免 NSAppleScript 与沙盒的兼容问题）
@MainActor
final class AppleScriptController: MediaControlling {
    var isAvailable: Bool { true }

    // MARK: - MediaControlling

    func play() async -> Bool { await execute(.play, for: lastBundleID) }
    func pause() async -> Bool { await execute(.pause, for: lastBundleID) }
    func togglePlayPause() async -> Bool { await execute(.togglePlayPause, for: lastBundleID) }
    func nextTrack() async -> Bool { await execute(.nextTrack, for: lastBundleID) }
    func previousTrack() async -> Bool { await execute(.previousTrack, for: lastBundleID) }
    func seek(to time: TimeInterval) async -> Bool { await execute(.seek(time), for: lastBundleID) }

    /// 目标应用 bundle id（由 MediaManager 在收到流更新时设置）
    var lastBundleID: String?

    // MARK: - 执行

    /// 执行命令（默认按上次已知的播放应用选择目标）
    /// 未知应用：尝试直接打开应用（用户手动开始播放）
    func execute(_ command: AppleScriptCommand, for bundleID: String?) async -> Bool {
        if let app = Self.appName(for: bundleID) {
            let script = Self.script(for: app, command: command)
            return await Self.runScript(script)
        }
        // 无 AppleScript 支持：打开应用/网页
        return Self.launchApp(bundleID: bundleID)
    }

    /// 启动播放器应用（未知 AppleScript 支持时）；YouTube Music 打开网页
    nonisolated static func launchApp(bundleID: String?) -> Bool {
        if bundleID == DefaultPlayerOption.youtubeMusic.rawValue {
            guard let url = URL(string: "https://music.youtube.com") else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    // MARK: - 脚本构造（纯函数，可单测）

    /// bundle id → AppleScript 应用名（未知应用返回 nil，调用方自动跳过）
    nonisolated static func appName(for bundleID: String?) -> String? {
        switch bundleID {
        case "com.apple.Music": return "Music"
        case "com.spotify.client": return "Spotify"
        case "com.netease.163music": return "NeteaseMusic"
        case "com.tencent.QQMusicMac": return "QQMusic"
        default: return nil
        }
    }

    /// 生成控制脚本
    nonisolated static func script(for app: String, command: AppleScriptCommand) -> String {
        switch command {
        case .play:
            return "tell application \"\(app)\" to play"
        case .pause:
            return "tell application \"\(app)\" to pause"
        case .togglePlayPause:
            return "tell application \"\(app)\" to playpause"
        case .nextTrack:
            return "tell application \"\(app)\" to next track"
        case .previousTrack:
            return "tell application \"\(app)\" to previous track"
        case .seek(let time):
            return "tell application \"\(app)\" to set player position to \(time)"
        case .setVolume(let level):
            let percent = Int((max(0, min(1, level))) * 100)
            return "tell application \"\(app)\" to set sound volume to \(percent)"
        }
    }

    /// 执行 AppleScript 并获取输出（osascript 子进程），失败返回 nil
    static func runScriptWithOutput(_ script: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 执行 AppleScript（osascript 子进程），返回是否成功
    @discardableResult
    static func runScript(_ script: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return false
        }

        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
        return status == 0
    }
}


/// 音乐播放信息（AppleScript 拉取）
struct MusicPlaybackInfo {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let position: TimeInterval?
    let isPlaying: Bool
}

extension AppleScriptController {
    /// 拉取播放器当前播放信息（Apple Music / Spotify）
    /// 输出格式："playing, 标题, 艺术家, 专辑, 时长, 位置"
    func fetchMusicInfo(bundleID: String) async -> MusicPlaybackInfo? {
        guard let app = Self.appName(for: bundleID) else { return nil }
        // 仅查询正在运行的应用：AppleScript 的 tell 会启动未运行的应用
        // （导致"播放时打开多个播放器"）
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
            return nil
        }
        // 注意：player state 是应用全局属性（不能写 "player state of current track"，
        // 否则 Spotify/Music 报 -1728）；逐项独立取值再组合返回
        let script = """
        tell application "\(app)"
            return {player state, name of current track, artist of current track,
                album of current track, duration of current track, player position}
        end tell
        """
        guard let output = await Self.runScriptWithOutput(script) else { return nil }
        let parts = output.split(separator: ",", maxSplits: 5).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2 else { return nil }
        return MusicPlaybackInfo(
            title: parts.count > 1 ? parts[1] : nil,
            artist: parts.count > 2 ? parts[2] : nil,
            album: parts.count > 3 ? parts[3] : nil,
            duration: parts.count > 4 ? Double(parts[4]) : nil,
            position: parts.count > 5 ? Double(parts[5]) : nil,
            isPlaying: parts[0] == "playing"
        )
    }
}
