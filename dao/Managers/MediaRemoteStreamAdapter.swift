import Combine
import Foundation

/// MediaRemote 流适配器（主媒体链路）
///
/// 背景：macOS 15.4+ 上第三方 App 无法直接访问 MediaRemote 私有框架，
/// 但系统二进制 /usr/bin/perl 具有访问权限（Apple 签名授权）。
/// 本适配器通过 perl 子进程动态加载随 App 分发的 MediaRemoteAdapter.framework，
/// 以 JSON lines 流式获取播放信息，并发送播放命令。
/// 方案与 boring.notch 一致，已在 macOS 14–26 验证。
///
/// 依赖（随 App bundle 分发）：
/// - Resources/mediaremote-adapter.pl（ungive/mediaremote-adapter，MIT）
/// - Frameworks/MediaRemoteAdapter.framework（Scripts/build-mediaremote-adapter.sh 构建）
@MainActor
final class MediaRemoteStreamAdapter: ObservableObject {
    // MARK: - 状态

    /// 最新媒体状态（流更新驱动）
    @Published private(set) var state = MediaState.empty
    /// 流是否运行中
    @Published private(set) var isStreamRunning = false

    // MARK: - 私有

    private var streamTask: Task<Void, Never>?
    private var streamProcess: Process?

    /// 最近一次完整 payload（diff 模式需要累积合并）
    private var accumulator = StreamPayloadAccumulator()

    /// perl 脚本路径（App bundle Resources）
    private var scriptURL: URL? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    }

    /// framework 路径（App bundle Frameworks）
    private var frameworkPath: String? {
        guard let path = Bundle.main.privateFrameworksPath else { return nil }
        return path + "/MediaRemoteAdapter.framework"
    }

    // MARK: - 流生命周期

    /// 启动流式监听（幂等）
    func startStream() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            await self?.runStream()
        }
    }

    /// 停止流式监听
    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamProcess?.terminate()
        streamProcess = nil
        isStreamRunning = false
    }

    /// 运行 perl 流子进程并逐行解析 JSON
    private func runStream() async {
        guard let scriptURL, let frameworkPath else {
            state = .empty
            isStreamRunning = false
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        streamProcess = process

        do {
            try process.run()
        } catch {
            state = .empty
            isStreamRunning = false
            streamProcess = nil
            return
        }
        isStreamRunning = true

        // 逐行解析（bytes.lines 提供异步行迭代，进程退出即结束）
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                handleStreamLine(line)
            }
        } catch {
            // 管道读取失败：流结束
        }

        isStreamRunning = false
        streamProcess = nil
        streamTask = nil
    }

    // MARK: - 播放命令

    /// 播放
    func play() async -> Bool { await sendCommand(0) }

    /// 暂停
    func pause() async -> Bool { await sendCommand(1) }

    /// 播放/暂停切换
    func togglePlayPause() async -> Bool { await sendCommand(2) }

    /// 下一首
    func nextTrack() async -> Bool { await sendCommand(4) }

    /// 上一首
    func previousTrack() async -> Bool { await sendCommand(5) }

    /// 跳转到指定时间（秒）
    func seek(to time: TimeInterval) async -> Bool {
        await runCommand(["seek", String(format: "%.3f", time)])
    }

    /// 设置随机播放模式（MediaRemote 模式值透传）
    func setShuffleMode(_ mode: Int) async -> Bool {
        await runCommand(["shuffle", "\(mode)"])
    }

    /// 设置循环模式（MediaRemote 模式值透传）
    func setRepeatMode(_ mode: Int) async -> Bool {
        await runCommand(["repeat", "\(mode)"])
    }

    /// 发送媒体命令（MediaRemote 命令 ID：0 播放 / 1 暂停 / 2 切换 / 4 下一首 / 5 上一首）
    private func sendCommand(_ command: Int) async -> Bool {
        await runCommand(["send", "\(command)"])
    }

    /// 处理一行流输出：信封解析 + diff 合并 + 状态更新
    private func handleStreamLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == "null" {
            // 无活跃媒体会话
            state = .empty
            accumulator.reset()
            return
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any]
        else { return }

        // diff 模式：与累积 payload 合并（null 值表示字段被清除）
        let isDiff = (json["diff"] as? Bool) ?? false
        let merged = accumulator.apply(payload: payload, isDiff: isDiff)

        // 空 payload = 无活跃会话
        guard !merged.isEmpty else {
            state = .empty
            return
        }
        guard let updateData = try? JSONSerialization.data(withJSONObject: merged),
              let update = try? JSONDecoder().decode(MediaRemoteUpdate.self, from: updateData)
        else { return }
        state = MediaState(update: update)
    }

    /// 执行一次性 perl 命令并等待退出码
    private func runCommand(_ arguments: [String]) async -> Bool {
        guard let scriptURL, let frameworkPath else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath] + arguments
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

// MARK: - MediaControlling 协议一致性

extension MediaRemoteStreamAdapter: MediaControlling {
    /// 资源齐备即视为可用（脚本 + framework 随 bundle 分发）
    var isAvailable: Bool { scriptURL != nil && frameworkPath != nil }
}

/// 流 payload 累积器（diff 合并逻辑，纯逻辑可单测）
///
/// stream 输出两种信封：
/// - `diff=false`：完整 payload，直接替换
/// - `diff=true`：仅含变化字段，null 值表示清除，其余与上一份合并
struct StreamPayloadAccumulator {
    private(set) var accumulated: [String: Any] = [:]

    /// 应用一行 payload，返回合并后的完整字典（空字典 = 无活跃会话）
    mutating func apply(payload: [String: Any], isDiff: Bool) -> [String: Any] {
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    accumulated.removeValue(forKey: key)
                } else {
                    accumulated[key] = value
                }
            }
        } else {
            accumulated = payload
        }
        return accumulated
    }

    /// 清空累积状态（会话结束）
    mutating func reset() {
        accumulated.removeAll()
    }
}
