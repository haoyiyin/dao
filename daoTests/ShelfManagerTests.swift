import XCTest
@testable import dao

/// ShelfManager 单元测试：持久化往返、bookmark、失效处理（隔离存储目录）
@MainActor
final class ShelfManagerTests: XCTestCase {
    private var tempDir: URL!
    private var originalBaseURL: URL!
    private var manager: ShelfManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        originalBaseURL = ShelfManager.baseURL
        ShelfManager.baseURL = tempDir.appendingPathComponent("storage", isDirectory: true)
        manager = ShelfManager()
    }

    override func tearDownWithError() throws {
        ShelfManager.baseURL = originalBaseURL
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeSourceFile(named name: String, content: String = "data") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.data(using: .utf8)?.write(to: url)
        return url
    }

    /// 添加文件 → 文件被复制进存储，条目带 bookmark
    func testAddFileCopiesAndBookmarks() throws {
        let source = try makeSourceFile(named: "photo.png", content: "png-data")
        manager.addFiles([source])

        let item = try XCTUnwrap(manager.items.first)
        XCTAssertEqual(item.name, "photo.png")
        XCTAssertEqual(item.type, .image)
        XCTAssertNotNil(item.bookmarkData)
        XCTAssertNotNil(item.sourceURL)
        // 副本存在且内容一致
        let stored = try XCTUnwrap(item.sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        XCTAssertEqual(try Data(contentsOf: stored), Data("png-data".utf8))
        // 副本保留原始文件名（拖出时文件名正确；重名才加后缀）
        XCTAssertEqual(stored.lastPathComponent, "photo.png")
    }

    /// 添加文本/链接
    func testAddTextAndLink() {
        manager.addText("  你好，世界！  ")
        manager.addLink(URL(string: "https://example.com")!)

        XCTAssertEqual(manager.items.count, 2)
        XCTAssertEqual(manager.items[0].type, .link)
        XCTAssertEqual(manager.items[1].type, .text)
        XCTAssertEqual(manager.items[1].name, "你好，世界！")
    }

    /// 持久化往返：新实例 restore 后条目完整恢复
    func testPersistenceRoundTrip() throws {
        let source = try makeSourceFile(named: "report.txt")
        manager.addFiles([source])
        manager.addText("notes")

        let restored = ShelfManager()
        restored.restore()

        XCTAssertEqual(restored.items.count, 2)
        XCTAssertEqual(restored.items[0].type, .text)
        XCTAssertEqual(restored.items[1].name, "report.txt")
        // bookmark 可解析
        let fileItem = restored.items[1]
        XCTAssertNotNil(restored.accessibleURL(for: fileItem))
    }

    /// 移除条目：索引移除；文件副本保留（拖出复制安全），由孤儿清理兜底
    func testRemoveKeepsCopyUntilCleanup() throws {
        let source = try makeSourceFile(named: "temp.pdf")
        let items = manager.addFiles([source])
        let item = try XCTUnwrap(items.first)
        let stored = try XCTUnwrap(item.sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))

        manager.removeItems(withIDs: [item.id])
        XCTAssertTrue(manager.items.isEmpty)
        // 副本保留（不立即删除——拖出时目标应用可能仍在复制）
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))

        // restore 时孤儿清理
        let restored = ShelfManager()
        restored.restore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    }

    /// 损坏索引 → 不崩溃，标记备份
    func testCorruptedIndexRecovery() throws {
        try FileManager.default.createDirectory(at: ShelfManager.baseURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: ShelfManager.baseURL.appendingPathComponent("shelf.json"))
        manager.restore()
        XCTAssertTrue(manager.items.isEmpty)
    }

    /// 不存在的存储目录 → restore 空安全
    func testRestoreWhenNothingSaved() {
        manager.restore()
        XCTAssertTrue(manager.items.isEmpty)
    }

    /// 文本类文件（MD/TXT）判为 .file（不是 .text——.text 仅用于纯文本拖拽）
    func testTextFileTypeIsFile() throws {
        let md = tempDir.appendingPathComponent("README.md")
        try Data("# title\n".utf8).write(to: md)
        XCTAssertEqual(ShelfItemType.type(for: md), .file)

        let txt = tempDir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: txt)
        XCTAssertEqual(ShelfItemType.type(for: txt), .file)

        let image = tempDir.appendingPathComponent("pic.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        XCTAssertEqual(ShelfItemType.type(for: image), .image)
    }
}
