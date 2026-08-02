import SwiftUI

/// Shelf 视图：暂存文件网格
///
/// - 点击条目选中（多选），选中后显示批量操作工具栏（删除所选 / 取消选择）
/// - 条目悬停显示移除按钮
/// - 空状态提示拖入文件
struct ShelfView: View {
    @EnvironmentObject private var shelfManager: ShelfManager
    @EnvironmentObject private var language: LanguageManager

    /// 选中的条目 id 集合
    @State private var selectedIDs: Set<UUID> = []

    /// 正在预览的条目 URL（非 nil 时显示 Quick Look）
    @State private var previewURL: URL?

    /// 分享面板锚点视图（SwiftUI → AppKit 桥接）
    @State private var shareAnchor: NSView?

    private var items: [ShelfItem] { shelfManager.items }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            toolbar

            if let previewURL {
                previewOverlay(url: previewURL)
            } else if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // 先固定高度，再应用圆角背景：背景跟随 100pt 高度，底部圆角完整
        // （背景在 frame 之前会停留在内容高度，底部圆角与 AirDrop 不对齐）
        .frame(height: 90, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Quick Look 预览

    private func previewOverlay(url: URL) -> some View {
        VStack(spacing: 6) {
            // 关闭图标在预览区上方一行（直接叠在 QL 视图上会被其拦截事件；
            // 用 ClickableView——非激活面板 onTapGesture 在子视图不可靠）
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .overlay(
                        ClickableView(perform: { previewURL = nil })
                    )
            }
            QuickLookPreviewView(url: url)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 6) {
            if !selectedIDs.isEmpty {
                // 选中态操作：全部图标表示（onTapGesture：非激活面板 Button 不触发）
                iconButton("airplane", help: "AirDrop") { shareSelected(direct: true) }
                iconButton("square.and.arrow.up", help: "分享") { shareSelected(direct: false) }
                iconButton("xmark", help: "取消选择") { selectedIDs.removeAll() }
                // 预览时隐藏删除图标（避免与预览面板混淆）
                if previewURL == nil {
                    iconButton("trash", help: "删除所选") {
                        shelfManager.removeItems(withIDs: selectedIDs)
                        selectedIDs.removeAll()
                    }
                }
            } else if !items.isEmpty, previewURL == nil {
                iconButton("trash", help: "清空") { shelfManager.removeAll() }
            }
            // 分享面板锚点（零尺寸，仅提供 NSView）
            ShareAnchorView { view in
                shareAnchor = view
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
        }
    }

    /// 分享选中条目：优先文件，无文件时分享文本
    private func shareSelected(direct: Bool) {
        let selectedItems = items.filter { selectedIDs.contains($0.id) }
        let urls = selectedItems.compactMap { shelfManager.accessibleURL(for: $0) }
        if !urls.isEmpty {
            if direct {
                _ = AirDropManager.shared.shareViaAirDrop(urls: urls)
            } else if let anchor = shareAnchor {
                AirDropManager.shared.showSharingPicker(items: urls, from: anchor)
            }
        } else {
            // 纯文本条目：分享字符串
            let texts = selectedItems.compactMap(\.text)
            if !texts.isEmpty, let anchor = shareAnchor {
                AirDropManager.shared.showSharingPicker(items: texts, from: anchor)
            }
        }
    }

    /// 工具栏图标按钮
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 20, height: 18)
            .contentShape(Rectangle())
            .help(help)
            .onTapGesture(perform: action)
    }

    private func smallButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .font(.system(size: 10))
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.6))
            .controlSize(.mini)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.3))
            Text(language.text("拖入文件、链接或文本暂存于此", "Drop files, links or text here"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
    }

    // MARK: - 网格

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // 普通 HStack（非 Lazy）：Lazy 容器在 macOS 26 不实例化
            // NSViewRepresentable（条目的拖出 ClickableView 收不到事件）
            HStack(spacing: 6) {
                ForEach(items) { item in
                    ShelfItemRowView(
                        item: item,
                        isSelected: selectedIDs.contains(item.id),
                        isPreviewing: previewURL != nil,
                        onSelect: { toggleSelection(item.id) },
                        onRemove: { shelfManager.removeItems(withIDs: [item.id]) },
                        onPreview: previewAction(for: item)
                    )
                }
            }
        }
        .frame(height: 54)
    }

    /// 切换选中状态（单选取消选中；多选累加）
    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// 预览动作：文件条目打开 Quick Look，其余返回 nil
    private func previewAction(for item: ShelfItem) -> (() -> Void)? {
        guard item.type != .text else { return nil }
        return {
            if let url = shelfManager.accessibleURL(for: item) {
                previewURL = url
            }
        }
    }
}
