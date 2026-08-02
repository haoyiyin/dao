import Combine
import Defaults
import Foundation

/// 媒体管理器（全局单例，MVVM 中的 VM 层）
///
/// 职责：
/// - 聚合媒体状态：MediaRemoteStreamAdapter（主链路）流式信息
/// - 命令路由：主链路失败自动降级 AppleScript（MediaCommandRouter）
/// - 进度插值：流更新间隙按 playbackRate 外推已播放时间（1s 计时器）
/// - 暴露 @Published state 供视图层订阅
@MainActor
final class MediaManager: ObservableObject {
    /// 全局单例
    static let shared = MediaManager()

    // MARK: - 状态

    /// 当前媒体状态（视图层唯一数据源）
    @Published private(set) var state = MediaState.empty
    /// 是否处于降级模式（主链路不可用）
    @Published private(set) var isUsingFallback = false

    // MARK: - 依赖

    /// MediaRemote 流适配器（主链路）
    let streamAdapter = MediaRemoteStreamAdapter()
    /// AppleScript 控制器（兜底链路）
    let appleScriptController = AppleScriptController()
    /// 命令路由
    private lazy var commandRouter = MediaCommandRouter(
        primary: streamAdapter,
        fallback: appleScriptController
    )

    // MARK: - 私有

    private var cancellables = Set<AnyCancellable>()
    /// 进度插值计时器（1s）
    private var progressTimer: Timer?
    /// 浏览器垫底任务（定时探测原生音乐是否在播）
    private var browserDemotionTask: Task<Void, Never>?
    /// true：正在用原生音乐覆盖浏览器 MediaRemote 会话，忽略浏览器流更新
    private var browserDemoted = false

    /// AppleScript 可探测的原生音乐 App（覆盖浏览器会话用）
    private static let nativeMusicBundleIDs = ["com.apple.Music", "com.spotify.client"]

    private init() {
        // 订阅流适配器状态
        streamAdapter.$state
            .removeDuplicates()
            .sink { [weak self] newState in
                self?.handleStreamUpdate(newState)
            }
            .store(in: &cancellables)

        startProgressTicker()
    }

    // MARK: - 生命周期

    /// 启动媒体监控（AppCoordinator 调用）
    func start() {
        streamAdapter.startStream()
        startBrowserDemotionCheck()
    }

    /// 停止媒体监控
    func stop() {
        streamAdapter.stopStream()
        browserDemotionTask?.cancel()
        browserDemotionTask = nil
        browserDemoted = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - 浏览器垫底（网页会话永远排在原生 App 之后）

    /// 处理 MediaRemote 流更新：非浏览器直接显示；垫底锁定时忽略浏览器流
    private func handleStreamUpdate(_ newState: MediaState) {
        let decision = MediaState.browserDemotionDecision(
            newState: newState,
            browserDemoted: browserDemoted
        )
        if decision.clearDemotion {
            browserDemoted = false
        }
        guard decision.apply else { return }
        applyDisplayedState(newState)
    }

    /// 写入岛上展示状态
    private func applyDisplayedState(_ newState: MediaState) {
        state = newState
        isUsingFallback = false
        appleScriptController.lastBundleID = newState.bundleIdentifier
    }

    /// 每 3 秒：浏览器为当前会话时探测 Music/Spotify；有播则覆盖并锁定
    private func startBrowserDemotionCheck() {
        browserDemotionTask?.cancel()
        browserDemotionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                await self.checkBrowserDemotion()
            }
        }
    }

    /// 浏览器垫底检查
    private func checkBrowserDemotion() async {
        // 已垫底：确认原生音乐仍在播，停则解锁恢复流
        if browserDemoted {
            let bundleID = state.bundleIdentifier ?? ""
            if let info = await appleScriptController.fetchMusicInfo(bundleID: bundleID),
               info.isPlaying {
                applyNativeMusic(info, bundleID: bundleID)
                return
            }
            browserDemoted = false
            applyDisplayedState(streamAdapter.state)
            return
        }

        // 仅当当前流是浏览器会话时，才尝试用原生音乐盖过
        let stream = streamAdapter.state
        guard stream.isActive, MediaState.isBrowserApp(stream.bundleIdentifier) else { return }

        for bundleID in Self.nativeMusicBundleIDs {
            if let info = await appleScriptController.fetchMusicInfo(bundleID: bundleID),
               info.isPlaying {
                applyNativeMusic(info, bundleID: bundleID)
                browserDemoted = true
                return
            }
        }
    }

    /// 用 AppleScript 拉到的原生音乐覆盖展示（浏览器会话仍在流里）
    private func applyNativeMusic(_ info: MusicPlaybackInfo, bundleID: String) {
        var merged = MediaState()
        merged.title = info.title
        merged.artist = info.artist
        merged.album = info.album
        merged.duration = info.duration
        merged.elapsedTime = info.position
        merged.timestamp = Date().timeIntervalSince1970
        merged.playbackRate = info.isPlaying ? 1 : 0
        merged.playingFlag = info.isPlaying
        merged.bundleIdentifier = bundleID
        merged.isMusicApp = true
        merged.isActive = true
        state = merged
        appleScriptController.lastBundleID = bundleID
    }

    // MARK: - 进度插值

    /// 启动 1s 进度插值计时器（仅在播放中生效）
    private func startProgressTicker() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickProgress()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    /// 上次进度推算记录（无时间戳时的本地推算兜底）
    private var lastProgressTick: (elapsed: TimeInterval, time: TimeInterval)?

    /// 按 playbackRate 外推已播放时间；无时间戳时用本地推算兜底
    private func tickProgress() {
        let now = Date().timeIntervalSince1970
        guard state.isActive, state.isPlaying else {
            lastProgressTick = nil
            return
        }
        if let elapsed = MediaManager.extrapolateElapsed(state: state, now: now) {
            state.elapsedTime = elapsed
            // 关键：更新时间戳，否则下次外推的 delta 持续累积（进度越走越快）
            state.timestamp = now
            lastProgressTick = (elapsed, now)
        } else if let last = lastProgressTick {
            // 流未提供时间戳：按上次记录继续推算（保证进度持续前进）
            let projected = last.elapsed + (now - last.time) * state.playbackRate
            if let duration = state.duration, duration > 0 {
                state.elapsedTime = min(projected, duration)
            } else {
                state.elapsedTime = projected
            }
            if let current = state.elapsedTime {
                lastProgressTick = (current, now)
            }
        } else if let elapsed = state.elapsedTime {
            lastProgressTick = (elapsed, now)
        } else {
            lastProgressTick = (0, now)
        }
    }

    /// 外推已播放时间：elapsed + (now - timestamp) × rate，封顶 duration
    /// - 无时间戳 / 未播放 → nil（不做外推）
    nonisolated static func extrapolateElapsed(state: MediaState, now: TimeInterval) -> TimeInterval? {
        guard state.isActive, state.isPlaying,
              let elapsed = state.elapsedTime,
              let timestamp = state.timestamp
        else { return nil }
        let delta = max(0, now - timestamp)
        let projected = elapsed + delta * state.playbackRate
        if let duration = state.duration, duration > 0 {
            return min(projected, duration)
        }
        return projected
    }

    // MARK: - 命令（视图层调用）

    func togglePlayPause() async {
        _ = await commandRouter.togglePlayPause()
    }

    func nextTrack() async {
        _ = await commandRouter.nextTrack()
    }

    func previousTrack() async {
        _ = await commandRouter.previousTrack()
    }

    func seek(to time: TimeInterval) async {
        _ = await commandRouter.seek(to: time)
        // 立即更新本地进度：流确认前从目标位置继续外推（避免进度条跳回旧位置）
        var updated = state
        updated.elapsedTime = time
        updated.timestamp = Date().timeIntervalSince1970
        state = updated
    }

    /// 开始播放：有媒体会话则切换播放/暂停；无会话则唤起 Apple Music 播放
    func startPlayback() async {
        if state.isActive {
            _ = await commandRouter.togglePlayPause()
        } else {
            let bundleID = Defaults[.defaultPlayer] ?? DefaultPlayerOption.appleMusic.rawValue
            _ = await appleScriptController.execute(.play, for: bundleID)
        }
    }

    /// 音量控制（无全局标准，按应用走 AppleScript）
    func setVolume(_ level: Double) async {
        _ = await appleScriptController.execute(.setVolume(level), for: state.bundleIdentifier)
    }
}
