import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 灵动岛拖放接收结果
struct DroppedItems {
    /// 文件 URL 列表（源文件，由 ShelfManager 复制入应用存储）
    var fileURLs: [URL] = []
    /// 数据文件（provider 无 fileURL 时按 suggestedName + 数据保存）
    var fileDatas: [(data: Data, name: String)] = []
    /// 纯文本 / 链接列表
    var texts: [String] = []
    /// 是否为空
    var isEmpty: Bool { fileURLs.isEmpty && fileDatas.isEmpty && texts.isEmpty }
}

/// 灵动岛拖放接收器（DropDelegate 实现）
///
/// 接收类型：文件（public.file-url）、链接（public.url）、纯文本（public.plain-text）。
/// 文件由 ShelfManager 复制进应用存储并生成 security-scoped bookmark（跨重启保留）。
final class NotchDropDelegate: DropDelegate {
    /// 拖拽进入窗口（主线程）
    var onEnter: () -> Void = {}
    /// 拖拽离开窗口（主线程）
    var onExit: () -> Void = {}
    /// 接收完成（主线程，等待所有异步加载结束后回调）
    var onReceive: (DroppedItems) -> Void = { _ in }

    /// 支持的拖放类型
    /// 注意：不要添加 .data/.utf8PlainText——声明后系统对文件拖拽只提供
    /// 内容类型（PDF→com.adobe.pdf 数据）不再提供 fileURL，导致文件无法
    /// 作为文件接收（M3 时期仅 [.fileURL, .url, .plainText] 全格式正常）
    static let supportedTypes: [UTType] = [.fileURL, .url, .plainText]

    // MARK: - DropDelegate

    func dropEntered(info: DropInfo) {
        onEnter()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        Task { @MainActor in
            let items = await processProviders(info.itemProviders(for: NotchDropDelegate.supportedTypes))
            onReceive(items)
        }
        return true
    }

    /// 处理拖放 providers 并汇总结果（独立方法，便于单元测试）
    func processProviders(_ providers: [NSItemProvider]) async -> DroppedItems {
        var items = DroppedItems()

        // 文件：直接尝试加载 URL（部分文本类文件如 MD 未声明 fileURL 类型，
        // 但 loadObject(URL) 仍可解析）；数据加载兜底保存为文件；
        // 纯文本路径字符串也转 URL
        for provider in providers {
            var url: URL?
            if provider.canLoadObject(ofClass: URL.self),
               let loaded = await loadURL(from: provider),
               loaded.isFileURL,
               FileManager.default.fileExists(atPath: loaded.path) {
                url = loaded
            }
            if url == nil,
               provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = await loadText(from: provider),
               let fileURL = urlFromPathText(text) {
                url = fileURL
            }
            if let url {
                items.fileURLs.append(url)
                continue
            }
            // 兜底：suggestedName 非空 → 内容类型数据保存为文件
            if let name = provider.suggestedName, !name.isEmpty,
               let type = provider.registeredTypeIdentifiers.first,
               let data = await loadData(from: provider, type: type) {
                items.fileDatas.append((data, name))
            }
        }

        // 文本 / 链接（排除已被识别为文件路径/已作为文件保存的字符串）
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            // 该 provider 已作为文件保存则跳过（MD 等文本文件）
            if let name = provider.suggestedName, !name.isEmpty,
               items.fileDatas.contains(where: { $0.name == name }) {
                continue
            }
            if let text = await loadText(from: provider),
               urlFromPathText(text) == nil {
                items.texts.append(text)
            }
        }

        return items
    }

    /// 诊断日志（临时）
    private func diag(_ msg: String) {
        if !FileManager.default.fileExists(atPath: "/tmp/drop_diag.txt") {
            FileManager.default.createFile(atPath: "/tmp/drop_diag.txt", contents: nil)
        }
        if let data = (msg + "\n").data(using: .utf8),
           let fh = FileHandle(forWritingAtPath: "/tmp/drop_diag.txt") {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        }
    }

    /// 纯文本是否为文件路径（存在且非目录返回 URL；目录视为文件也接受）
    private func urlFromPathText(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 加载辅助

    /// 异步加载文件 URL
    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// 异步加载数据（provider 内容类型）
    private func loadData(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// 异步加载文本
    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { text, _ in
                continuation.resume(returning: text as? String)
            }
        }
    }
}
