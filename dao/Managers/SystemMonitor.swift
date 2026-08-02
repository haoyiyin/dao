import Combine
import Foundation

/// 系统监控聚合器（全局单例）
///
/// - 后台队列采样（CPU/网络为差值采样，需后台计算）
/// - 主线程发布快照（@Published，1.5s 间隔，可配置）
/// - 各采样器失败时对应字段为 nil，UI 自动隐藏
@MainActor
final class SystemMonitor: ObservableObject {
    /// 全局单例
    static let shared = SystemMonitor()

    /// 最新系统快照
    @Published private(set) var snapshot = SystemSnapshot()

    /// 采样间隔（秒）
    var interval: TimeInterval = 1.5

    /// 采样队列（CPU/网络差值计算不阻塞主线程）
    private let sampleQueue = DispatchQueue(label: "com.dao.system-monitor", qos: .utility)
    private var timer: Timer?

    private init() {}

    // MARK: - 生命周期

    /// 启动采样（幂等）
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleNow()
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 立即采样一次（建立差值基线）
        sampleNow()
    }

    /// 停止采样
    func stop() {
        timer?.invalidate()
        timer = nil
        CPUMonitor.reset()
        NetworkMonitor.reset()
    }

    // MARK: - 采样

    /// 采样一次：后台计算 → 主线程发布
    func sampleNow() {
        sampleQueue.async { [weak self] in
            let cpu = CPUMonitor.sample()
            let network = NetworkMonitor.sample()
            let memory = MemoryMonitor.sample()
            let disk = DiskMonitor.sample()
            let battery = BatteryMonitor.sample()

            Task { @MainActor in
                guard let self else { return }
                var snapshot = SystemSnapshot()
                snapshot.cpuUsage = cpu
                snapshot.networkUpload = network?.upload
                snapshot.networkDownload = network?.download
                snapshot.memoryUsed = memory?.used
                snapshot.memoryTotal = memory?.total
                snapshot.memoryUsage = memory.map { Double($0.used) / Double($0.total) }
                snapshot.diskUsed = disk?.used
                snapshot.diskTotal = disk?.total
                snapshot.batteryLevel = battery?.level
                snapshot.isCharging = battery?.isCharging
                snapshot.batteryTimeRemaining = battery?.timeRemaining
                snapshot.timestamp = Date()
                self.snapshot = snapshot
            }
        }
    }
}
