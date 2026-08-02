import Foundation

/// 媒体控制命令协议（命令层抽象，支持主链路与降级链路的测试）
protocol MediaControlling {
    /// 是否可用
    var isAvailable: Bool { get }

    func play() async -> Bool
    func pause() async -> Bool
    func togglePlayPause() async -> Bool
    func nextTrack() async -> Bool
    func previousTrack() async -> Bool
    func seek(to time: TimeInterval) async -> Bool
}

/// 媒体命令路由：主链路失败时自动降级到兜底链路
///
/// 链路：MediaRemoteStreamAdapter（perl 子进程，主）→ AppleScriptController（兜底）
struct MediaCommandRouter {
    /// 主链路（MediaRemote 流适配器）
    let primary: MediaControlling
    /// 兜底链路（AppleScript）
    let fallback: MediaControlling

    /// 执行命令：优先主链路，失败或不可用时回退
    private func run(_ command: (MediaControlling) async -> Bool) async -> Bool {
        if primary.isAvailable, await command(primary) {
            return true
        }
        return await command(fallback)
    }

    func play() async -> Bool { await run { await $0.play() } }
    func pause() async -> Bool { await run { await $0.pause() } }
    func togglePlayPause() async -> Bool { await run { await $0.togglePlayPause() } }
    func nextTrack() async -> Bool { await run { await $0.nextTrack() } }
    func previousTrack() async -> Bool { await run { await $0.previousTrack() } }
    func seek(to time: TimeInterval) async -> Bool { await run { await $0.seek(to: time) } }
}
