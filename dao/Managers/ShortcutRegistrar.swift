import KeyboardShortcuts

/// 全局快捷键定义（KeyboardShortcuts）
extension KeyboardShortcuts.Name {
    /// 播放/暂停（⌥空格）
    static let togglePlayPause = Self("togglePlayPause", default: .init(.space, modifiers: [.option]))

    /// 下一首（⌥F9，对应键盘媒体键）
    static let nextTrack = Self("nextTrack", default: .init(.f9, modifiers: [.option]))

    /// 上一首（⌥F7，对应键盘媒体键）
    static let previousTrack = Self("previousTrack", default: .init(.f7, modifiers: [.option]))
}

/// 全局快捷键注册（AppCoordinator 启动时调用）
enum ShortcutRegistrar {
    /// 注册快捷键动作
    static func register() {
        KeyboardShortcuts.onKeyUp(for: .togglePlayPause) {
            Task { await MediaManager.shared.togglePlayPause() }
        }
        KeyboardShortcuts.onKeyUp(for: .nextTrack) {
            Task { await MediaManager.shared.nextTrack() }
        }
        KeyboardShortcuts.onKeyUp(for: .previousTrack) {
            Task { await MediaManager.shared.previousTrack() }
        }
    }
}
