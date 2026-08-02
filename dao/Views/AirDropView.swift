import SwiftUI
import UniformTypeIdentifiers

/// AirDrop 抽屉：拖放即投送（支持从文件暂存拖入）
struct AirDropView: View {
    /// 拖拽悬停高亮
    @State private var isDropTarget = false

    /// 分享面板回退锚点
    @State private var shareAnchor: NSView?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 拖放投送区（正方形主体，拖入文件即发起 AirDrop）
            dropZone
                .frame(maxHeight: .infinity)
        }
        // 分享面板锚点放入 overlay：不占布局空间（否则 dropZone 无法撑满 100 高）
        .overlay(alignment: .bottom) {
            ShareAnchorView { view in
                shareAnchor = view
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
        }
    }

    // MARK: - 拖放区

    private var dropZone: some View {
        VStack(spacing: 5) {
            Image(systemName: "airplane")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(isDropTarget ? 1 : 0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isDropTarget ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isDropTarget ? 1 : 0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .onDrop(of: [.fileURL], delegate: AirDropDropDelegate(
            onEnter: { withAnimation(.easeOut(duration: 0.12)) { isDropTarget = true } },
            onExit: { isDropTarget = false },
            onReceive: { urls in
                isDropTarget = false
                guard !urls.isEmpty else { return }
                // 优先 AirDrop 直达，失败（无设备/不可用）回退系统分享面板
                AirDropManager.shared.shareViaAirDropWithFallback(urls: urls, from: shareAnchor)
            }
        ))
    }
}


/// AirDrop 抽屉拖放接收器（收集文件 URL）
private struct AirDropDropDelegate: DropDelegate {
    var onEnter: () -> Void
    var onExit: () -> Void
    var onReceive: ([URL]) -> Void

    func dropEntered(info: DropInfo) {
        onEnter()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in info.itemProviders(for: [.fileURL]) {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }
            onReceive(urls)
        }
        return true
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
