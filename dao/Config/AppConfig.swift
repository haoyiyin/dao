import AppKit
import Foundation

/// 全局配置常量（AppConfig）
///
/// 集中管理窗口尺寸、交互参数与窗口层级，避免魔法数字散落各处。
enum AppConfig {
    /// 应用名称（用于 Application Support 目录、UserDefaults 命名空间等）
    static let appName = "dao"

    // MARK: - 窗口尺寸

    /// 刘海物理宽度（MacBook 全系机型统一为 185pt）
    static let notchWidth: CGFloat = 185

    /// 收起态宽度（媒体会话时向两侧延伸，左右各 ~40pt 放置媒体信息与频率线）
    static let collapsedWidth: CGFloat = 265

    /// 收起态窗口底部拖拽热区高度（pt）：已废弃，命中区仅视觉胶囊。
    /// 值为 0 表示无额外热区扩展；保留常量用于兼容旧调用点。
    static let dragHotzoneExtra: CGFloat = 0

    /// 非刘海屏（外接显示器 / 老机型）的虚拟刘海宽度
    static let virtualNotchWidth: CGFloat = 120

    /// 非刘海屏的虚拟刘海高度（覆盖菜单栏区域）
    static let virtualNotchHeight: CGFloat = 36

    /// 非刘海屏关闭虚拟刘海时的最小宽度（小胶囊，不遮挡时钟）
    static let minimalNotchWidth: CGFloat = 60

    /// 展开态宽度（横向长方形，左右对称居中，紧凑不浪费空间）
    static let expandedWidth: CGFloat = 400

    /// 展开态高度（紧凑：内容压缩 + 居中布局，无底部空余）
    static let expandedHeight: CGFloat = 166

    // MARK: - 交互

    /// 悬停展开延迟（秒）：须在视觉胶囊内连续停留该时长才展开。
    /// 0.2s 过短——刘海下 32pt 黑条正处于菜单栏中心鼠标通道，路过即误开。
    static let hoverExpandDelay: TimeInterval = 0.5

    /// 移出收起延迟（秒）：离开视觉区后等待该时长再收起
    static let hoverCollapseDelay: TimeInterval = 0.25

    // MARK: - 窗口

    /// 窗口层级：`.mainMenu + 3`，高于菜单栏，确保悬浮于所有普通窗口之上
    static let windowLevel: NSWindow.Level = .mainMenu + 3
}
