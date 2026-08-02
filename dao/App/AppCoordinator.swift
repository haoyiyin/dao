import AppKit
import Combine
import Defaults
import SwiftUI

/// 应用协调器（AppCoordinator，MVVM-C 中的 C）
///
/// 职责：
/// - 装配全局单例 Manager（MediaManager / ShelfManager / SystemMonitor，M2-M4 引入）
/// - 创建并持有灵动岛窗口（NotchWindowController）
/// - 路由应用级状态（启动 / 退出 / 显示隐藏）
@MainActor
final class AppCoordinator {
    /// 灵动岛窗口控制器
    private var windowController: NotchWindowController?

    /// 引导窗口（首次启动）
    private var onboardingWindow: NSWindow?

    /// 协调器级订阅
    private var coordinatorCancellables = Set<AnyCancellable>()

    // MARK: - 生命周期

    /// 启动应用：创建灵动岛窗口与菜单栏图标
    func start() {
        // 媒体监控（M2）
        MediaManager.shared.start()
        // 恢复 Shelf 暂存内容（M3）
        ShelfManager.shared.restore()
        // 系统信息采样（M4）
        SystemMonitor.shared.start()

        let controller = NotchWindowController()
        controller.show()
        windowController = controller

        // 设置窗口内的"显示/隐藏灵动岛"按钮
        NotificationCenter.default
            .publisher(for: .toggleNotchVisibility)
            .sink { [weak self] _ in
                Task { @MainActor in self?.toggleWindowVisibility() }
            }
            .store(in: &coordinatorCancellables)

        // 全局快捷键（M2.5）
        ShortcutRegistrar.register()

        // 首次启动引导
        showOnboardingIfNeeded()
    }

    /// 首次启动显示引导窗口
    private func showOnboardingIfNeeded() {
        guard !Defaults[.hasCompletedOnboarding] else { return }

        let view = OnboardingView { [weak self] in
            Defaults[.hasCompletedOnboarding] = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用 dao"
        window.styleMask = [.titled, .closable]
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 退出应用：释放资源
    func stop() {
        MediaManager.shared.stop()
        SystemMonitor.shared.stop()
        windowController?.hide()
        windowController = nil
        coordinatorCancellables.removeAll()
    }

    // MARK: - 菜单栏动作

    /// 显示/隐藏灵动岛窗口
    private func toggleWindowVisibility() {
        guard let windowController else { return }
        if windowController.isVisible {
            windowController.hide()
        } else {
            windowController.show()
        }
    }

    /// 退出应用
    private func quit() {
        NSApp.terminate(nil)
    }
}
