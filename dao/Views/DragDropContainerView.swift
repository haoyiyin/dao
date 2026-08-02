import AppKit

/// 拖拽接收容器视图（作为窗口 contentView 的根视图）
///
/// 机制：容器注册拖拽类型并实现 NSDraggingDestination——系统把拖拽事件
/// 直接发给 contentView。相比 SwiftUI onDrop，容器可访问完整 pasteboard：
/// - NSFilenamesPboardType：文件真实路径（MD 等文本类文件的 SwiftUI
///   provider 只暴露内容类型拿不到文件名，pasteboard 层面一定有路径）
/// - fileURL / string：链接与纯文本
@MainActor
final class DragDropContainerView: NSView {
    /// 拖拽进入（展开灵动岛）
    var onDragEnter: () -> Void = {}
    /// 拖放完成（文件/文本/链接）
    var onDrop: (DroppedItems) -> Void = { _ in }

    /// 视觉胶囊在本 view 内的 rect（AppKit 坐标，原点左下）。
    /// 固定窗 400×166 时透明翼区 hitTest 返回 nil，避免吞菜单栏点击。
    var visualFrameInView: CGRect = .zero

    private static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("public.url"),
        .string
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.supportedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.supportedTypes)
    }

    /// 仅命中视觉胶囊；其余穿透到菜单栏/桌面
    /// visualFrame 未同步时返回 nil（禁止整窗 400×166 透明区接事件）
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !visualFrameInView.isEmpty else { return nil }
        // visual capsule only; inset ±2pt for edge-pixel tolerance
        let zone = visualFrameInView.insetBy(dx: -2, dy: -2)
        guard zone.contains(point) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        var items = DroppedItems()

        // 1. 文件：NSFilenamesPboardType（真实路径——MD 等文本文件在此）
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            items.fileURLs = paths.map { URL(fileURLWithPath: $0) }
        }

        // 2. 文件：fileURL 类型（兜底）
        if items.fileURLs.isEmpty,
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]
           ) as? [URL] {
            items.fileURLs = urls
        }

        // 3. 文本 / 链接（排除文件路径字符串）
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for text in strings {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if FileManager.default.fileExists(atPath: trimmed) { continue }
                if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" {
                    items.texts.append(url.absoluteString)
                } else {
                    items.texts.append(trimmed)
                }
            }
        }

        if !items.isEmpty {
            onDrop(items)
        }
        return true
    }
}
