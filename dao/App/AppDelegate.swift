import AppKit

/// 应用代理（AppDelegate）
///
/// 职责：
/// - 设置激活策略为 `.accessory`（无 Dock 图标、不抢占焦点）
/// - 创建并启动 AppCoordinator（协调器模式，负责窗口与全局 Manager 装配）
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用协调器（强引用持有，防止释放）
    private var coordinator: AppCoordinator?

    /// 应用启动完成
    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
