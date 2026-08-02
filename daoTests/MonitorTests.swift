import XCTest
@testable import dao

/// 系统采样器集成测试：真实 mach/IOKit 调用（本机环境），验证数值合理性
final class MonitorTests: XCTestCase {
    /// CPU 差值采样：第二次采样返回 0-1 区间（间隔 200ms 确保 tick 前进）
    func testCPUSample() {
        CPUMonitor.reset()
        XCTAssertNil(CPUMonitor.sample()) // 首次建基线
        usleep(200_000) // tick 计数器粒度保护
        guard let usage = CPUMonitor.sample() else {
            return XCTFail("第二次采样应有结果")
        }
        XCTAssertGreaterThanOrEqual(usage, 0)
        XCTAssertLessThanOrEqual(usage, 1)
    }

    /// 内存：总量 > 0，已用 ≤ 总量
    func testMemorySample() {
        guard let (used, total) = MemoryMonitor.sample() else {
            return XCTFail("内存采样失败")
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThanOrEqual(used, total)
        XCTAssertGreaterThan(used, 0)
    }

    /// 磁盘：总量 > 0，已用 ≤ 总量
    func testDiskSample() {
        guard let (used, total) = DiskMonitor.sample() else {
            return XCTFail("磁盘采样失败")
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThanOrEqual(used, total)
    }

    /// 网络差值采样：速率为非负
    func testNetworkSample() {
        NetworkMonitor.reset()
        XCTAssertNil(NetworkMonitor.sample())
        guard let rates = NetworkMonitor.sample() else {
            return XCTFail("第二次采样应有结果")
        }
        XCTAssertGreaterThanOrEqual(rates.upload, 0)
        XCTAssertGreaterThanOrEqual(rates.download, 0)
    }

    /// 电池：本机无电池设备时返回 nil（不崩溃）；有电池时数值合理
    func testBatterySample() {
        guard let battery = BatteryMonitor.sample() else {
            return // 无电池设备（如 Mac mini）→ 正常
        }
        XCTAssertGreaterThanOrEqual(battery.level, 0)
        XCTAssertLessThanOrEqual(battery.level, 1)
    }

    /// 监控项枚举完整性（电池/网络已按需求移除）
    func testMetricEnum() {
        XCTAssertEqual(SystemMetric.allCases.count, 3)
        XCTAssertEqual(SystemMetric.cpu.displayName, "CPU")
        XCTAssertEqual(SystemMetric.cpu.icon, "cpu")
        XCTAssertFalse(SystemMetric.allCases.contains { $0.rawValue == "battery" })
        XCTAssertFalse(SystemMetric.allCases.contains { $0.rawValue == "network" })
    }
}
