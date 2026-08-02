import XCTest
@testable import dao

/// NotchDropDelegate 单元测试：NSItemProvider → 文件 URL / 文本提取管线
final class NotchDropDelegateTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 文件 provider → 提取源文件 URL
    func testProcessFileProvider() async throws {
        let source = tempDir.appendingPathComponent("photo.png")
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        try data.write(to: source)

        let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))
        let items = await NotchDropDelegate().processProviders([provider])

        XCTAssertEqual(items.fileURLs, [source])
        XCTAssertTrue(items.texts.isEmpty)
    }

    /// 文本 provider → 提取字符串
    func testProcessTextProvider() async throws {
        let provider = NSItemProvider(object: "https://example.com" as NSString)
        let items = await NotchDropDelegate().processProviders([provider])

        XCTAssertTrue(items.fileURLs.isEmpty)
        XCTAssertEqual(items.texts, ["https://example.com"])
    }

    /// 混合 provider → 文件与文本分别落位
    func testProcessMixedProviders() async throws {
        let source = tempDir.appendingPathComponent("doc.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: source)
        let fileProvider = try XCTUnwrap(NSItemProvider(contentsOf: source))
        let textProvider = NSItemProvider(object: "notes" as NSString)

        let items = await NotchDropDelegate().processProviders([fileProvider, textProvider])

        XCTAssertEqual(items.fileURLs, [source])
        XCTAssertEqual(items.texts, ["notes"])
    }

    /// 空 providers → 空结果
    func testProcessEmptyProviders() async {
        let items = await NotchDropDelegate().processProviders([])
        XCTAssertTrue(items.isEmpty)
    }
}
