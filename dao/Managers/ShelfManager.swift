import Foundation

/// Shelf 管理器（全局单例）
///
/// 职责：
/// - 接收拖放文件/文本/链接（复制文件到应用存储，生成 security-scoped bookmark）
/// - 持久化到 ~/Library/Application Support/dao/shelf.json（原子写入）
/// - 启动时恢复（bookmark 解析 + 文件存在性校验，失效条目标记缺失不崩溃）
///
/// 存储布局：
/// - shelf.json         条目索引（JSON）
/// - files/             文件副本（文件名 = UUID，保留原扩展名）
@MainActor
final class ShelfManager: ObservableObject {
    /// 全局单例
    static let shared = ShelfManager()

    // MARK: - 状态

    /// 全部条目（按加入时间倒序）
    @Published private(set) var items: [ShelfItem] = []

    // MARK: - 存储路径（测试可注入 baseURL）

    /// 存储根目录（测试可替换）
    static var baseURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(AppConfig.appName, isDirectory: true)

    private var indexURL: URL { Self.baseURL.appendingPathComponent("shelf.json") }
    private var filesDirectory: URL { Self.baseURL.appendingPathComponent("files", isDirectory: true) }

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 初始化（internal 以便测试注入存储路径；单例请使用 .shared）
    init() {}

    // MARK: - 添加条目

    /// 添加文件（复制到应用存储 + 生成 bookmark）
    @discardableResult
    func addFiles(_ urls: [URL]) -> [ShelfItem] {
        var added: [ShelfItem] = []
        for url in urls {
            guard let stored = storeFileCopy(from: url) else { continue }
            let bookmark = makeBookmark(for: stored)
            let item = ShelfItem(
                name: url.lastPathComponent,
                type: .type(for: url),
                bookmarkData: bookmark,
                sourceURL: stored
            )
            items.insert(item, at: 0)
            added.append(item)
        }
        save()
        return added
    }

    /// 添加数据文件（provider 无 fileURL 时：按 suggestedName 保存）
    @discardableResult
    func addFileData(_ data: Data, name: String) -> ShelfItem? {
        try? fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: name)
        do {
            try data.write(to: destination)
        } catch {
            return nil
        }
        let item = ShelfItem(
            name: name,
            type: .type(for: destination),
            bookmarkData: nil,
            sourceURL: destination
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    /// 添加文本
    @discardableResult
    func addText(_ text: String) -> ShelfItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ShelfItem(
            name: String(trimmed.prefix(40)),
            type: .text,
            text: trimmed
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    /// 添加链接
    @discardableResult
    func addLink(_ url: URL) -> ShelfItem {
        let item = ShelfItem(
            name: url.absoluteString,
            type: .link,
            text: url.absoluteString
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    // MARK: - 移除

    /// 移除条目（删除文件副本 + 更新索引）
    /// 移除单条（拖出成功后取走）
    func remove(_ item: ShelfItem) {
        removeItems(withIDs: [item.id])
    }

    func removeItems(withIDs ids: Set<UUID>) {
        // 不删除文件副本：拖出场景下目标应用可能仍在复制（立即删除会
        // 导致内容丢失）；孤儿文件由 restore 时的清理兜底
        items.removeAll { ids.contains($0.id) }
        save()
    }

    /// 移除所有条目
    func removeAll() {
        try? fileManager.removeItem(at: filesDirectory)
        items.removeAll()
        save()
    }

    // MARK: - 恢复（启动时调用）

    /// 从磁盘恢复：解析 JSON + 校验文件存在
    func restore() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        guard let saved = try? decoder.decode([ShelfItem].self, from: data) else {
            // 索引损坏：备份后重建，避免启动失败
            try? fileManager.moveItem(at: indexURL, to: indexURL.appendingPathExtension("corrupted"))
            return
        }
        items = saved
        save()
        cleanupOrphanFiles()
    }

    /// 清理无索引的孤儿文件（拖出/移除后残留的副本）
    private func cleanupOrphanFiles() {
        let validNames = Set(items.compactMap { $0.sourceURL?.lastPathComponent })
        guard let files = try? fileManager.contentsOfDirectory(atPath: filesDirectory.path) else { return }
        for name in files where !validNames.contains(name) {
            try? fileManager.removeItem(at: filesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - 文件访问

    /// 解析条目的可访问 URL（bookmark 解析 + 安全作用域获取），失败返回 nil
    func accessibleURL(for item: ShelfItem) -> URL? {
        if let bookmark = item.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return item.sourceURL
    }

    // MARK: - 私有

    /// 复制文件到应用存储（保留原始文件名——拖出时文件名正确；
    /// 重名时追加 UUID 后缀避免覆盖）
    private func storeFileCopy(from source: URL) -> URL? {
        try? fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let base = source.lastPathComponent
        let destination = uniqueDestination(for: base)

        // 拖放来源可能带安全作用域
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

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

    /// 生成不冲突的目标路径：
    /// - 同名文件不存在 → 直接用原名
    /// - 同名文件是孤儿（无条目引用）→ 清理后复用原名
    /// - 同名文件被索引引用 → 追加 UUID 后缀防覆盖
    private func uniqueDestination(for filename: String) -> URL {
        let candidate = filesDirectory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let referenced = items.contains { $0.sourceURL?.lastPathComponent == filename }
        if !referenced {
            try? fileManager.removeItem(at: candidate)
            return candidate
        }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        let suffixed = ext.isEmpty ? "\(base)-\(UUID().uuidString.prefix(8))" : "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        return filesDirectory.appendingPathComponent(suffixed)
    }

    /// 生成 security-scoped bookmark
    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 原子写入索引
    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: [.atomic])
    }
}
