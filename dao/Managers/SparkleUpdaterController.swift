import Sparkle

/// Sparkle 更新控制器（自动更新）
///
/// - 开发构建：不启用自动检查（Info.plist SUEnableAutomaticChecks=false）
/// - 发布构建：配置 SUFeedURL 后由 build.sh 签名/公证，走完整更新链路
/// - 菜单栏"检查更新…"手动触发
final class SparkleUpdaterController: NSObject {
    /// 全局单例
    static let shared = SparkleUpdaterController()

    /// Sparkle 标准更新控制器
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// 检查更新（菜单动作）
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
