import AppKit
import Quartz
import SwiftUI

/// Quick Look 嵌入式预览
///
/// 使用 QLPreviewView（视图嵌入，无需 key window），
/// 规避非激活面板下 QLPreviewPanel 的焦点问题。
struct QuickLookPreviewView: NSViewRepresentable {
    /// 预览目标（文件 URL）
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            // 理论不可达（样式合法）
            return QLPreviewView(frame: .zero)
        }
        view.previewItem = url as NSURL
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}
