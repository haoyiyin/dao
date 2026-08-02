import XCTest
@testable import dao

/// StreamPayloadAccumulator 单元测试：流信封 diff 合并逻辑
final class StreamPayloadAccumulatorTests: XCTestCase {
    /// 首次完整 payload → 直接采用
    func testFullPayloadReplaces() {
        var acc = StreamPayloadAccumulator()
        let merged = acc.apply(payload: ["title": "A"], isDiff: false)
        XCTAssertEqual(merged["title"] as? String, "A")
    }

    /// diff payload 缺失字段 = 不变
    func testDiffPreservesUnchangedFields() {
        var acc = StreamPayloadAccumulator()
        _ = acc.apply(payload: ["title": "A", "artist": "B"], isDiff: false)
        let merged = acc.apply(payload: ["title": "C"], isDiff: true)
        XCTAssertEqual(merged["title"] as? String, "C")
        XCTAssertEqual(merged["artist"] as? String, "B")
    }

    /// diff null 值 = 清除字段
    func testDiffNullClearsField() {
        var acc = StreamPayloadAccumulator()
        _ = acc.apply(payload: ["title": "A", "artist": "B"], isDiff: false)
        let merged = acc.apply(payload: ["artist": NSNull()], isDiff: true)
        XCTAssertEqual(merged["title"] as? String, "A")
        XCTAssertNil(merged["artist"])
    }

    /// 清空累积
    func testReset() {
        var acc = StreamPayloadAccumulator()
        _ = acc.apply(payload: ["title": "A"], isDiff: false)
        acc.reset()
        XCTAssertTrue(acc.accumulated.isEmpty)
    }

    /// 空 payload（无会话）→ 空字典
    func testEmptyPayload() {
        var acc = StreamPayloadAccumulator()
        let merged = acc.apply(payload: [:], isDiff: false)
        XCTAssertTrue(merged.isEmpty)
    }
}
