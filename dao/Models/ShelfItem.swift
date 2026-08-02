import Foundation
import UniformTypeIdentifiers

/// Shelf 条目类型
enum ShelfItemType: String, Codable, Equatable {
    case file
    case image
    case video
    case document
    case text
    case link

    /// 显示图标（SF Symbol）
    var icon: String {
        switch self {
        case .file: return "doc"
        case .image: return "photo"
        case .video: return "film"
        case .document: return "doc.richtext"
        case .text: return "text.alignleft"
        case .link: return "link"
        }
    }

    /// 根据 UTType 推断类型
    static func type(for url: URL) -> ShelfItemType {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .file
        }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        // 注意：文本类文件（MD/TXT 等）判为 .file——.text 仅用于纯文本拖拽条目
        // （type(for:) 只接收文件 URL；若判 .text，拖出会走文本分支写名字）
        if type.conforms(to: .pdf) { return .document }
        return .file
    }
}

/// Shelf 条目（Codable，JSON 持久化于 Application Support）
struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    /// 显示名称（文件名 / 文本摘要 / 链接标题）
    var name: String
    /// 条目类型
    var type: ShelfItemType
    /// 加入时间
    var dateAdded: Date
    /// security-scoped bookmark（跨重启安全访问，兼容未来沙盒化）
    var bookmarkData: Data?
    /// 纯文本 / 链接内容（非文件条目）
    var text: String?
    /// 来源 URL（文件条目：应用存储内的副本路径）
    var sourceURL: URL?

    init(
        id: UUID = UUID(),
        name: String,
        type: ShelfItemType,
        dateAdded: Date = Date(),
        bookmarkData: Data? = nil,
        text: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.dateAdded = dateAdded
        self.bookmarkData = bookmarkData
        self.text = text
        self.sourceURL = sourceURL
    }
}
