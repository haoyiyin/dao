import Defaults
import SwiftUI

/// 媒体控制视图（展开态媒体抽屉）
///
/// 布局：左侧小封面，右侧上方进度条、右侧下方控制按键（无音量键）
/// 数据：MediaManager（@EnvironmentObject），进度显示用 TimelineView 平滑外推
struct MediaControlView: View {
    @EnvironmentObject private var mediaManager: MediaManager
    @EnvironmentObject private var language: LanguageManager

    /// 拖拽中的进度位置（秒，nil = 未拖拽）
    @State private var dragPosition: TimeInterval?

    private var state: MediaState { mediaManager.state }

    /// 默认播放器显示名（设置中选择）
    private var defaultPlayerName: String {
        let bundleID = Defaults[.defaultPlayer] ?? DefaultPlayerOption.appleMusic.rawValue
        return DefaultPlayerOption(rawValue: bundleID)?.displayName ?? "Apple Music"
    }

    var body: some View {
        // 无媒体会话：显示开始播放页面；播放时：显示进度条与控制按键
        if state.isActive {
            content
        } else {
            noMediaContent
        }
    }

    /// 无媒体：开始播放页面（大播放按钮，hover 聚焦，点击打开默认播放器；紧凑适配面板高度）
    private var noMediaContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.3))
            Text(language.text("当前没有正在播放的媒体", "No media playing"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            // 播放按钮（点击打开默认播放器）
            HoverIconButton(
                symbol: "play.fill",
                size: 36,
                help: language.text("开始播放（\(defaultPlayerName)）", "Play (\(defaultPlayerName))")
            ) {
                Task { await mediaManager.startPlayback() }
            }
            Text(defaultPlayerName)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    /// 媒体控制内容：左图 + 右侧（进度 + 控制），底层为封面流动背景
    private var content: some View {
        ZStack(alignment: .top) {
            // 专辑封面流动背景（播放中缓慢流动，暂停静止）
            flowingArtworkBackground

            HStack(spacing: 8) {
                // 左侧：小封面
                artwork

                // 右侧：上方进度条 + 下方控制按键
                VStack(spacing: 4) {
                    // 标题信息（单行紧凑）
                    HStack(spacing: 8) {
                        Text(state.title ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(state.artist ?? "")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }

                    // 进度条（上方）
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        MediaProgressBar(
                            progress: displayProgress(at: context.date),
                            duration: state.duration ?? 0,
                            dragPosition: $dragPosition
                        ) { target in
                            Task { await mediaManager.seek(to: target) }
                        }
                    }

                    // 控制按键（下方）
                    controls
                }
            }
            .padding(8)
        }
        // 撑满整个抽屉内容区：流动背景覆盖到窗口底部（媒体内容高度小于窗口）
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 专辑封面流动背景：封面图模糊放大 + 缓慢流动（Apple Music 风格）
    /// 播放中流动、暂停静止；10fps 驱动
    /// 先 clip 再 opacity：限制发光溢出，避免 drawingGroup 在展开淡入时栅格成空白
    private var flowingArtworkBackground: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !state.isPlaying)) { context in
            if let data = state.artworkData, let image = NSImage(data: data) {
                let time = context.date.timeIntervalSinceReferenceDate
                Image(nsImage: image)
                    .resizable()
                    .blur(radius: 20)
                    .scaleEffect(1.5)
                    // 缓慢流动：左右 ±14pt、上下 ±8pt、微旋转
                    .offset(
                        x: sin(time * 0.5) * 14,
                        y: cos(time * 0.37) * 8
                    )
                    .rotationEffect(.degrees(sin(time * 0.21) * 2))
                    .opacity(0.25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    // 四周圆角（Apple 设计美学：连续圆角，与窗口底部大圆角呼应）
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 封面

    private var artwork: some View {
        Group {
            if let data = state.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 无封面占位
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }

    // MARK: - 进度

    /// 显示进度：拖拽中显示拖拽位置，否则按状态外推
    private func displayProgress(at date: Date) -> TimeInterval {
        if let dragPosition {
            return dragPosition
        }
        return MediaManager.extrapolateElapsed(
            state: state,
            now: date.timeIntervalSince1970
        ) ?? state.elapsedTime ?? 0
    }

    // MARK: - 控制按钮

    private var controls: some View {
        HStack(spacing: 24) {
            // 上一首（无媒体时无操作）
            controlButton("backward.end.fill", size: 20) {
                guard mediaManager.state.isActive else { return }
                Task { await mediaManager.previousTrack() }
            }
            // 播放/暂停：无媒体时点击打开默认播放器
            controlButton(state.isPlaying ? "pause.fill" : "play.fill", size: 28) {
                Task { await mediaManager.startPlayback() }
            }
            // 下一首（无媒体时无操作）
            controlButton("forward.end.fill", size: 20) {
                guard mediaManager.state.isActive else { return }
                Task { await mediaManager.nextTrack() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        // HoverIconButton：悬停聚焦高亮 + ClickableView 稳定点击
        HoverIconButton(symbol: symbol, size: size + 8, action: action)
    }
}
