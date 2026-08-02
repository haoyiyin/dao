import SwiftUI

/// 首次启动引导（Onboarding）
///
/// 三页流程：欢迎 → 权限申请（屏幕录制/辅助功能）→ 完成（提示重启生效）。
/// 权限可跳过，不阻断使用（媒体功能降级）。
/// 文案跟随 `LanguageManager`（首次安装默认跟系统语言）。
struct OnboardingView: View {
    /// 当前页索引
    @State private var page = 0
    /// 界面语言（与岛内 UI 同源）
    @ObservedObject private var language = LanguageManager.shared
    /// 是否完成引导（由 AppCoordinator 注入回调）
    var onFinish: () -> Void

    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcomePage
                case 1: permissionPage
                default: donePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(language.language)

            // 底部导航
            HStack {
                if page > 0 {
                    Button(language.text("上一步", "Back")) { page -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if page < totalPages - 1 {
                    Button(language.text("下一步", "Next")) { page += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(language.text("开始使用", "Get Started")) { onFinish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 380)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.1), Color(red: 0.12, green: 0.12, blue: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - 页面 1：欢迎

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .cyan.opacity(0.35), radius: 16, y: 4)
            Text(language.text("欢迎使用 dao", "Welcome to dao"))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(language.text(
                "悬浮在屏幕顶部的灵动岛\n媒体控制 · 文件暂存 · 系统信息",
                "A floating island at the top of your screen\nMedia · File shelf · System info"
            ))
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(30)
    }

    // MARK: - 页面 2：权限

    private var permissionPage: some View {
        VStack(spacing: 12) {
            Text(language.text("授权以下权限", "Grant these permissions"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            permissionRow(
                icon: "display",
                title: language.text("屏幕录制", "Screen Recording"),
                subtitle: language.text(
                    "用于获取媒体播放信息（可在设置中关闭，仅影响媒体控制）",
                    "Used for now-playing info (can skip; media control may degrade)"
                ),
                granted: PermissionManager.shared.hasScreenRecordingPermission
            ) {
                PermissionManager.shared.requestScreenRecording()
            }

            permissionRow(
                icon: "keyboard",
                title: language.text("辅助功能", "Accessibility"),
                subtitle: language.text(
                    "AppleScript 媒体控制兜底需要（Apple Music / Spotify）",
                    "Needed for AppleScript media fallback (Apple Music / Spotify)"
                ),
                granted: PermissionManager.shared.hasAccessibilityPermission
            ) {
                PermissionManager.shared.requestAccessibility()
            }

            Text(language.text(
                "隐私说明：所有数据仅在本地处理，不上传任何信息。",
                "Privacy: all data stays on device; nothing is uploaded."
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(30)
    }

    /// 单项权限行
    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if granted {
                Label(language.text("已授权", "Granted"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(language.text("授权", "Allow"), action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    // MARK: - 页面 3：完成

    private var donePage: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(language.text("一切就绪", "You're all set"))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(language.text(
                "部分权限需要重启应用后生效。\n灵动岛会出现在屏幕顶部，悬停即可展开。",
                "Some permissions need an app restart.\nThe island appears at the top of the screen — hover to expand."
            ))
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(30)
    }
}
