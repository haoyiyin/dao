import AppKit

/// 灵动岛专属空间（CGS 私有 API，机制参考 boring.notch——独立实现）
///
/// 对比 SkyLightWindow 包的 SLS 方案（SLSSpaceAddWindowsAndRemoveFromSpaces
/// 会把窗口从正常空间移除，导致系统拖拽目标判定找不到窗口、文件拖拽
/// 穿透落到桌面）；CGS 方案只把窗口加入专属空间（不移除正常空间），
/// 拖拽命中正常，同时窗口随桌面切换动画滑动跟随（跨桌面保持刘海位置）。
///
/// 风险：CGS 为私有 API，系统更新可能失效；创建失败自动降级为普通行为。
@MainActor
final class NotchSpaceManager {
    /// 全局单例
    static let shared = NotchSpaceManager()

    /// 专属空间标识（0 = 创建失败，降级）
    private let spaceID: UInt64

    /// 加入空间的窗口集合（变化时同步到系统）
    private var windowNumbers: Set<Int> = [] {
        didSet {
            guard spaceID != 0 else { return }
            let removed = oldValue.subtracting(windowNumbers)
            let added = windowNumbers.subtracting(oldValue)
            if !removed.isEmpty {
                CGSRemoveWindowsFromSpaces(conn, Array(removed) as NSArray, [spaceID])
            }
            if !added.isEmpty {
                CGSAddWindowsToSpaces(conn, Array(added) as NSArray, [spaceID])
            }
        }
    }

    private let conn: UInt

    private init() {
        conn = _CGSDefaultConnection()
        // flag 必须为 1（否则 Finder 会在桌面绘制图标）
        let newSpace = CGSSpaceCreate(conn, 1, nil)
        spaceID = newSpace
        if newSpace != 0 {
            CGSSpaceSetAbsoluteLevel(conn, newSpace, Int(Int32.max))
            CGSShowSpaces(conn, [newSpace])
        }
    }

    /// 窗口加入专属空间（跨桌面跟随；失败自动降级）
    func addWindow(_ window: NSWindow) {
        guard spaceID != 0 else { return }
        windowNumbers.insert(window.windowNumber)
    }
}

// MARK: - CGS 符号（SkyLight 私有 API，动态符号）

private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
