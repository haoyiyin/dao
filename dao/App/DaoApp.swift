import SwiftUI

/// 应用入口（@main）
///
/// 灵动岛应用为常驻应用（无 Dock 图标、无菜单栏图标），主界面为悬浮在屏幕
/// 顶部的 NSPanel；设置入口在灵动岛内（右上角齿轮 → 设置抽屉），无需独立
/// 设置窗口，因此不声明 WindowGroup。
@main
struct DaoApp: App {
    /// 应用代理：负责激活策略与协调器装配
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 空 Settings 场景占位（SwiftUI App 协议需要至少一个 Scene）
        Settings {
            EmptyView()
        }
    }
}
