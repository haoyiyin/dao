import SwiftUI

/// Shelf 条目行：缩略图/图标 + 名称 + 选中态 + 悬停移除按钮
struct ShelfItemRowView: View {
    @EnvironmentObject private var shelfManager: ShelfManager

    let item: ShelfItem
    let isSelected: Bool
    /// 预览打开中（隐藏 hover 操作按钮，避免与预览面板重叠）
    var isPreviewing: Bool = false
    var onSelect: () -> Void
    var onRemove: () -> Void
    var onPreview: (() -> Void)?

    /// 悬停状态
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    // 选中标记
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }
            Text(item.name)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 48)
        .contentShape(Rectangle())
        // 交互 + 拖出统一走 ClickableView（AppKit 层）：
        // SwiftUI onTapGesture 会抢走命中导致 overlay 的 AppKit 视图收不到
        // 事件；ClickableView 的 mouseDown（点击）+ mouseDragged（拖出）
        // 在非激活面板稳定
        .overlay(
            ClickableView(
                perform: onSelect,
                onHover: { hovering in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isHovering = hovering
                    }
                },
                onDragBegan: makeDraggingItem,
                onDragEnded: { operation in
                    // 拖出成功 → 延迟移除：等目标应用完成复制（1.5s），
                    // 避免复制未完成就删除副本导致内容丢失
                    if !operation.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            shelfManager.remove(item)
                        }
                    }
                }
            )
        )
        // 悬停操作按钮（预览/移除）在 ClickableView 之上（后添加）
        // 用 onTapGesture（非激活面板 SwiftUI Button 不触发）
        .overlay(alignment: .topLeading) {
            if isHovering && !isSelected && !isPreviewing {
                HStack(spacing: 2) {
                    if onPreview != nil {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                            .contentShape(Rectangle())
                            .onTapGesture { onPreview?() }
                    }
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentShape(Rectangle())
                        .onTapGesture { onRemove() }
                }
                .padding(2)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .offset(x: -4, y: -4)
            }
        }
    }

    // MARK: - 拖出

    /// 诊断日志（临时）
    private func diag(_ msg: String) {
        if !FileManager.default.fileExists(atPath: "/tmp/shelf_diag.txt") {
            FileManager.default.createFile(atPath: "/tmp/shelf_diag.txt", contents: nil)
        }
        if let data = (msg + "\n").data(using: .utf8),
           let fh = FileHandle(forWritingAtPath: "/tmp/shelf_diag.txt") {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        }
    }

    /// 构建拖拽项（文件：fileURL；链接：URL；文本：string）
    private func makeDraggingItem() -> NSDraggingItem? {
        let pasteboard = NSPasteboardItem()

        // 有存储文件（sourceURL/bookmark）→ 一律按文件拖出
        // （MD 等文本类文件 type 可能误判为 .text，但实际是文件）
        if let url = shelfManager.accessibleURL(for: item) {
            pasteboard.setString(url.absoluteString, forType: .fileURL)
            pasteboard.setString(url.path, forType: .string)
        } else {
            switch item.type {
            case .link:
                if let url = item.sourceURL {
                    pasteboard.setString(url.absoluteString, forType: .URL)
                    pasteboard.setString(url.absoluteString, forType: .string)
                } else {
                    pasteboard.setString(item.name, forType: .string)
                }
            default:
                // 纯文本条目：完整文本（原只写 name（前 40 字符）导致内容截断）
                pasteboard.setString(item.text ?? item.name, forType: .string)
            }
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboard)
        // 拖拽图像：类型图标
        let icon = NSImage(
            systemSymbolName: item.type.icon,
            accessibilityDescription: item.name
        ) ?? NSImage()
        draggingItem.setDraggingFrame(
            NSRect(x: 0, y: 0, width: 40, height: 40),
            contents: icon
        )
        return draggingItem
    }

    // MARK: - 缩略图

    @ViewBuilder
    private var thumbnail: some View {
        if item.type == .image,
           let url = shelfManager.accessibleURL(for: item),
           let image = NSImage(contentsOf: url) {
            // 图片条目：真实缩略图
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            iconPlaceholder
        }
    }

    /// 类型图标占位
    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
            Image(systemName: item.type.icon)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 40, height: 40)
    }
}
