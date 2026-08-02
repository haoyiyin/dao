# dao

[English](README.md)

原生 macOS 灵动岛：悬浮在屏幕顶部刘海处，提供媒体控制、文件暂存架与系统监控。

**macOS 14+** · **v0.1.0** · 无 Dock 图标（菜单栏附属应用）

## 功能

- **媒体** — 正在播放（封面、标题、艺人、可拖拽进度）、播放 / 暂停 / 上一曲 / 下一曲、音量。跟随系统当前 now-playing（最后激活的媒体会话）。MediaRemote 桥接，失败时回退 AppleScript（Apple Music、Spotify 等）。
- **文件架** — 将文件、文本或链接拖到岛上；Quick Look 预览、拖出、AirDrop 分享。
- **系统** — CPU / 内存 / 磁盘实时条；设置中可显示、隐藏与排序。
- **设置** — 登录启动、中/英界面、默认播放器、指标布局、退出。
- **引导** — 首次启动说明屏幕录制与辅助功能权限（可跳过；拒绝后媒体能力降级）。
- **非刘海屏** — 可选虚拟刘海 / 迷你胶囊。

退出：在岛内设置抽屉的电源图标（无 Dock / 菜单栏图标）。

## 安装

1. 从 [Releases](https://github.com/haoyiyin/dao/releases) 下载 `dao-0.1.0.dmg`。
2. 打开 DMG，将 **dao** 拖入「应用程序」。
3. 首次启动若被拦截：右键 → **打开**（未签名构建常见）。
4. 按引导完成权限。

> 当前发布构建**未**使用 Developer ID 签名 / 公证，系统可能提示无法验证开发者。

## 从源码构建

```bash
brew install xcodegen cmake swiftlint
xcodegen generate
xcodebuild -project dao.xcodeproj -scheme dao -configuration Debug \
  -destination 'platform=macOS' build
```

测试：

```bash
xcodebuild test -project dao.xcodeproj -scheme dao -destination 'platform=macOS'
```

本地未签名 DMG（无 Developer ID）：

```bash
# Release 构建出 dao.app 后
STAGE=$(mktemp -d)
cp -R path/to/dao.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname dao -srcfolder "$STAGE" -ov -format UDZO dao-0.1.0.dmg
```

完整签名 / 公证流程（先填写 `build.sh` 证书与公证信息）：

```bash
./build.sh 0.1.0
```

## 架构（简）

| 路径 | 职责 |
|------|------|
| `dao/App/` | 入口、`AppDelegate`、`AppCoordinator` |
| `dao/Managers/` | 媒体、文件架、监控 |
| `dao/Views/` | 岛窗体、抽屉、设置、引导 |
| `dao/Config/AppConfig` | 尺寸与延迟常量 |
| `Vendor/mediaremote-adapter` | MediaRemote 桥（BSD-3） |
| `project.yml` | XcodeGen 源真相 |

窗口固定展开尺寸（`400×166`）；收展是视觉蒙版（`NotchShape`），不是 `NSWindow` 改尺寸。

## 要求

- macOS 14.0+
- 构建需 Xcode；可选 XcodeGen、cmake、SwiftLint
- 运行时建议开启「屏幕录制」与「辅助功能」以获得完整媒体控制

## 第三方

各自许可证（未注明则为 MIT）：

- [Defaults](https://github.com/sindresorhus/Defaults)、[LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [Lottie](https://github.com/airbnb/lottie-ios)、[Sparkle](https://github.com/sparkle-project/Sparkle)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — **BSD-3-Clause**

## 许可证

[MIT](LICENSE)。Vendor 与 SPM 依赖保留各自条款。

## 链接

- [English](README.md)
- [Releases](https://github.com/haoyiyin/dao/releases)
