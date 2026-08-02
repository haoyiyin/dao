# AGENTS.md

> Native macOS 灵动岛（Dynamic Island）app：SwiftUI + AppKit `NSPanel` 悬浮窗，媒体控制 / 文件暂存架 / 系统监控。XcodeGen 工程。

## Architecture

In `dao/` where app source lives:

| Path | Role |
|------|------|
| `dao/App/` | `@main` entry (`DaoApp`), `AppDelegate`, `AppCoordinator` (MVVM-C 的 C) |
| `dao/Config/` | `AppConfig` — 全部窗口尺寸 / 延迟 / 层级常量 |
| `dao/Managers/` | 全局单例 Manager（`.shared`），`@MainActor` |
| `dao/Models/` | 状态模型 + `AppSettings`（Defaults keys）+ `LanguageManager` |
| `dao/Monitors/` | Battery / CPU / Disk / Memory / Network 采样 |
| `dao/Views/` | Notch 窗体、收展态、媒体/架/设置 UI |
| `dao/Resources/` | 打包资源（`mediaremote-adapter.pl`、`Assets.xcassets`） |
| `dao/Utils/` | 屏幕刘海检测、扩展 |
| `daoTests/` | XCTest，`@testable import dao` |
| `assets/` | 源 logo（`logo.png`）；`logo-candidates/` 工作稿 gitignore |
| `dist/` | 本地 DMG 输出（gitignore，不提交） |
| `Vendor/` | MediaRemote 适配器源码 + 构建产物（framework 不提交） |
| `Scripts/` | 适配器构建脚本 |
| `project.yml` | **XcodeGen 源真相**（勿手改 `dao.xcodeproj`） |

### Rules

1. **Edit `project.yml` then regenerate**. Never hand-edit `project.pbxproj`.
   ```bash
   xcodegen generate
   ```
   New Swift files under existing `dao/` groups are picked up automatically. New targets / packages / Info.plist keys → edit `project.yml`.

2. **MVVM-C wiring stays in `AppCoordinator`**. Managers are singletons; Views bind `@Published`. Do not spawn parallel coordinators or put startup order in Views.

3. **Media control path is fixed**:
   - Primary: `MediaRemoteStreamAdapter` (perl + `MediaRemoteAdapter.framework`)
   - Fallback: `AppleScriptController`
   - Router: `MediaCommandRouter` over protocol `MediaControlling`
   - Do **not** call MediaRemote private APIs directly from the app binary (macOS 15.4+ blocks this; perl path is intentional and verified).

4. **Magic numbers live in `AppConfig` only**. Window geometry, hover delays, window level (`.mainMenu + 3`) — add constants there; update `SmokeTests` when geometry contracts change.

5. **Fixed window strategy (Strategy A)**: window frame is always expanded geometry (`400×166`). Collapse/expand is visual (`NotchShape` + mask), not `NSWindow` resize.
   - Content that should clip with the capsule: put under `.mask(NotchShape)` driven by the same `visualSize` animation.
   - Toast / chrome that must not ghost: keep **outside** the mask.
   - Residual wing ghosting after mask: prefer asymmetric fade / tighten `mediaActive` collapse — do not "fix" by resizing the window.

6. **`@MainActor` on managers / window controllers**. Background work (monitor sampling, stream IO) stays off main; publish state back on main.

7. **Settings via `Defaults` keys in `AppSettings`**. No raw `UserDefaults` string keys scattered in Views.

8. **Comments / docs: Simplified Chinese. Identifiers: English.**

9. **App icon source of truth = asset catalog**.
   - Edit / replace sizes under `dao/Resources/Assets.xcassets/AppIcon.appiconset/`.
   - SwiftUI UI image: `AppIconImage` imageset（onboarding 等）。
   - Master raster: `assets/logo.png`（再导出各尺寸）。
   - `dao/Resources/AppIcon.icns` / `AppIcon.iconset` 为本地生成物，**gitignore**；`project.yml` 已 exclude，勿当提交源。
   - `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 写在 `project.yml` target settings。

10. **`LSUIElement` = 无 Dock / 菜单栏图标**。启动“没反应”时先查：
    - 进程是否在跑（Activity Monitor / `pgrep -x dao`）
    - 屏幕**顶中刘海**是否有胶囊；悬停约 `hoverExpandDelay`（0.5s）展开
    - arm64 未签名二进制会被 `SIGKILL`（`Killed: 9` / runningboard spawn fail）——见下方 Packaging

### Anti-patterns

```swift
// WRONG: hand-edit pbxproj or add target only in Xcode UI without project.yml
// CORRECT: project.yml → xcodegen generate

// WRONG: call MediaRemote from app process
// CORRECT: MediaRemoteStreamAdapter → perl → framework; AppleScript fallback

// WRONG: resize NSWindow for collapse/expand
// CORRECT: fixed expanded frame; animate NotchShape + mask visualSize

// WRONG: magic numbers in Views
// CORRECT: AppConfig.expandedWidth / hoverExpandDelay / …

// WRONG: commit Vendor/MediaRemoteAdapter.framework or build-mediaremote-adapter/
// CORRECT: gitignore binaries; rebuild via Scripts/build-mediaremote-adapter.sh

// WRONG: commit dist/*.dmg or Assets only as loose AppIcon.icns without appiconset
// CORRECT: AppIcon.appiconset + assets/logo.png; DMG 仅挂 GitHub Release / 本地 dist/
```

## Build / Run / Test

Requirements: Xcode (macOS 14+ SDK), Homebrew tools:

```bash
brew install xcodegen swiftlint cmake
```

```bash
# Regenerate Xcode project after project.yml / source layout changes
xcodegen generate

# Build
xcodebuild -project dao.xcodeproj -scheme dao -destination 'platform=macOS' build

# Test
xcodebuild test -project dao.xcodeproj -scheme dao -destination 'platform=macOS'

# Lint (non-blocking in Xcode pre-build: swiftlint || true)
swiftlint

# Adapter framework only
Scripts/build-mediaremote-adapter.sh
# missing cmake → warning + AppleScript fallback at runtime (exit 0)
```

Debug: open `dao.xcodeproj`, scheme `dao`. App is `LSUIElement` (no Dock icon) — look for notch panel / Activity Monitor.

若 `xcode-select` 仍指向 Command Line Tools，构建时：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### Packaging / DMG（本地 ad-hoc）

本机常无 Developer ID。`build.sh` 需证书 + notary 才完整；日常本地分发：

1. Release 构建（Documents 下 iCloud xattr 常导致 Xcode `CodeSign` 失败——**产物仍可能完整**，到 `/tmp` 再签）。
2. `ditto --norsrc --noextattr --noqtn` 拷到 `/tmp/.../dao.app`，`find … xattr -c`。
3. **由内向外 ad-hoc 签**：每个 Mach-O → `.xpc` / nested `.app` → `.framework` → 主 bundle（全部 `codesign --force --sign -`）。嵌套 framework 与主程序 Team ID 必须一致（都 ad-hoc / 都空 Team），否则 dyld：`different Team IDs`。
4. `codesign --verify --deep` + 直接跑二进制冒烟（勿只 `open`）。
5. `hdiutil create -volname dao -srcfolder stage -format UDZO dist/dao-VERSION.dmg`（stage 含 `dao.app` + `Applications` 符号链接）。
6. GitHub：`gh release upload vX.Y.Z dist/dao-X.Y.Z.dmg --clobber`。DMG **不进 git**。

正式发布（有 Developer ID 时）：

```bash
./build.sh [version]   # archive → licenses → sign → DMG → notary → stapler → appcast sign
```

Sparkle fields in `project.yml` (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`) are placeholders until ship config is real.

Public repo：`https://github.com/haoyiyin/dao`（`main`；Release 挂 DMG）。

## Media remote adapter

- Source: `Vendor/mediaremote-adapter` (ungive/mediaremote-adapter，**BSD-3-Clause**，vendored — not a submodule)。脚本注释若写 MIT 以 `Vendor/mediaremote-adapter/LICENSE` 为准。
- Output: `Vendor/MediaRemoteAdapter.framework` (gitignored); pre-build script always rebuilds when cmake present.
- Bundled script: `dao/Resources/mediaremote-adapter.pl` **must stay in sync** with `Vendor/mediaremote-adapter/bin` counterpart.
- Stream protocol: JSON lines; `diff=false` full snapshot, `diff=true` partial (NSNull clears fields). Merge logic in `StreamPayloadAccumulator` (unit-tested).

## Testing

- Framework: XCTest only (`@testable import dao`).
- Prefer pure structs for logic (`StreamPayloadAccumulator`) and injectable paths (`ShelfManager.baseURL`) so tests avoid UI/process.
- Geometry / product invariants: `daoTests/SmokeTests.swift` — keep green when touching `AppConfig` or `ScreenNotchDetector`.
- No CI in repo yet; local `xcodebuild test` is the gate.

## Style

From `.swiftlint.yml`:

- Line length warn 140 / error 200
- Opt-in: `empty_count`, `closure_end_indentation`, `sorted_first_last`
- Disabled: trailing/vertical whitespace
- Lint failure does **not** fail build — still fix new violations you introduce

## Security / privacy notes

- `NSAppleEventsUsageDescription` required for media AppleScript fallback.
- Shelf uses security-scoped bookmarks — preserve bookmark restore path in `ShelfManager`.
- Hardened Runtime on (`ENABLE_HARDENED_RUNTIME: YES`).
- Never commit signing secrets, notary passwords, or filled Developer ID lines from a local `build.sh` edit.

## Code review checklist

- [ ] `project.yml` updated if targets/packages/plist/scripts changed; ran `xcodegen generate`
- [ ] No framework/build binaries under `Vendor/` staged
- [ ] Media path still primary→fallback via `MediaControlling`
- [ ] Window still fixed expanded size; visual collapse uses mask, not window resize
- [ ] New constants in `AppConfig`; SmokeTests adjusted if geometry contracts moved
- [ ] Settings keys only via `AppSettings` / Defaults
- [ ] Main-actor boundaries respected for UI state
- [ ] `mediaremote-adapter.pl` still synced if adapter script changed
- [ ] Release path: licenses still copied in `build.sh` for new deps
- [ ] AppIcon：`AppIcon.appiconset` + `ASSETCATALOG_COMPILER_APPICON_NAME`；未误提 `AppIcon.icns` / `dist/`
- [ ] 本地 DMG：ad-hoc 内→外签名通过 `codesign --verify --deep` 且二进制能启动（非仅 Gatekeeper 对话框）

## Do not

- Add npm/JS tooling or rewrite as Catalyst/iOS
- Replace perl MediaRemote bridge with in-process private API calls
- Introduce a second settings store beside Defaults
- Commit `DerivedData/`, `.swiftpm/`、adapter build products、`dist/*.dmg`、`assets/logo-candidates/`
- Ship unsigned arm64 main binary（会被系统直接杀进程，表现为“点了没反应”）
