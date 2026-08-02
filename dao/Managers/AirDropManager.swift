import AppKit
import SwiftUI

/// AirDrop / 系统分享管理器
///
/// - 一键 AirDrop：NSSharingService(.sendViaAirDrop) 直接分享（无需面板）
/// - 分享面板：NSSharingServicePicker（含 AirDrop 与所有可用服务）
/// 注意：NSSharingServicePicker 在 macOS 14 起标记 deprecated 但功能完整；
/// SwiftUI ShareLink 无法限定 AirDrop，故保留 Picker 方案。
@MainActor
final class AirDropManager {
    /// 全局单例
    static let shared = AirDropManager()

    /// 通过 AirDrop 直接分享文件（无成功信号，调用即视为已发起）
    func shareViaAirDrop(urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        service.perform(withItems: urls)
        return true
    }

    /// AirDrop 直接分享，失败（不可用/无设备）时回退系统分享面板
    func shareViaAirDropWithFallback(urls: [URL], from anchor: NSView?) {
        if !shareViaAirDrop(urls: urls), let anchor {
            showSharingPicker(items: urls, from: anchor)
        }
    }

    /// 弹出系统分享面板（以 anchorView 为锚点）
    func showSharingPicker(items: [Any], from anchorView: NSView) {
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
    }
}

/// 分享锚点视图：为 NSSharingServicePicker 提供 NSView 引用（SwiftUI → AppKit）
struct ShareAnchorView: NSViewRepresentable {
    /// 视图挂载后回调（提供锚点 NSView）
    var onReady: (NSView) -> Void

    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.onReady = onReady
        return view
    }

    func updateNSView(_ nsView: AnchorNSView, context: Context) {}

    /// 锚点 NSView（挂窗后回调）
    final class AnchorNSView: NSView {
        var onReady: ((NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                onReady?(self)
                onReady = nil // 一次性
            }
        }
    }
}
