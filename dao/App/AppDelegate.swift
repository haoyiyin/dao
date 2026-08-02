import AppKit

/// 应用代理（AppDelegate）
///
/// 职责：
/// - 单实例：同 bundle id 已有进程则立即退出（防双岛 / 退出两次）
/// - 设置激活策略为 `.accessory`（无 Dock 图标、不抢占焦点）
/// - 创建并启动 AppCoordinator（协调器模式，负责窗口与全局 Manager 装配）
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用协调器（强引用持有，防止释放）
    private var coordinator: AppCoordinator?

    /// 应用启动完成
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 已有同 bundle 实例（含 open -n / 登录项重复拉起）→ 不建第二套窗口
        if Self.hasOtherRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        // 无 Dock 图标的后台常驻应用（Info.plist 中 LSUIElement 已声明）
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    /// 应用即将退出：释放协调器资源
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    /// 是否已有其它 dao 进程（排除自身 PID）
    private static func hasOtherRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != mine }
    }
}
