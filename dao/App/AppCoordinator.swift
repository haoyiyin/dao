import AppKit
import Combine

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

    /// 协调器级订阅
    private var coordinatorCancellables = Set<AnyCancellable>()

    // MARK: - 生命周期

    /// 启动应用：创建灵动岛窗口
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
