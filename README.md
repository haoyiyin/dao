# dao

[中文](README.zh-CN.md)

Native macOS Dynamic Island for the menu bar notch: media controls, a file shelf, and system monitors in a floating capsule.

**macOS 14+** · **v0.1.0** · no Dock icon (menu bar accessory)

## Features

- **Media** — Now playing (artwork, title, artist, seekable progress), play / pause / next / previous, volume. Prefers music when music and video play at once. MediaRemote bridge with AppleScript fallback (Apple Music, Spotify, and more).
- **File shelf** — Drop files, text, or links onto the island; preview (Quick Look), drag out, or share via AirDrop.
- **System** — CPU, memory, and disk usage with live bars; show/hide and reorder metrics in settings.
- **Settings** — Launch at login, Chinese / English UI, default player, metric layout, quit.
- **Onboarding** — First-run guide for Screen Recording and Accessibility (skippable; media falls back if denied).
- **Non-notch displays** — Optional virtual notch / minimal capsule.

Quit from the power icon inside the island settings drawer (no Dock / menu bar icon).

## Install

1. Download `dao-0.1.0.dmg` from [Releases](https://github.com/haoyiyin/dao/releases).
2. Open the DMG and drag **dao** to Applications.
3. First launch: right-click → **Open** if Gatekeeper blocks an unsigned build.
4. Complete onboarding permissions when prompted.

> Current release builds are **not** Developer ID signed / notarized. macOS may warn on open.

## Build from source

```bash
brew install xcodegen cmake swiftlint
xcodegen generate
xcodebuild -project dao.xcodeproj -scheme dao -configuration Debug \
  -destination 'platform=macOS' build
```

Tests:

```bash
xcodebuild test -project dao.xcodeproj -scheme dao -destination 'platform=macOS'
```

Unsigned local DMG (no Developer ID):

```bash
# after a Release build of dao.app
STAGE=$(mktemp -d)
cp -R path/to/dao.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname dao -srcfolder "$STAGE" -ov -format UDZO dao-0.1.0.dmg
```

Full signed / notarized pipeline (fill credentials in `build.sh` first):

```bash
./build.sh 0.1.0
```

## Architecture (short)

| Path | Role |
|------|------|
| `dao/App/` | Entry, `AppDelegate`, `AppCoordinator` |
| `dao/Managers/` | Media, shelf, shortcuts, monitors |
| `dao/Views/` | Notch panel, drawers, settings, onboarding |
| `dao/Config/AppConfig` | Geometry and timing constants |
| `Vendor/mediaremote-adapter` | MediaRemote bridge (BSD-3) |
| `project.yml` | XcodeGen source of truth |

Window stays fixed at expanded size (`400×166`); collapse/expand is a visual mask (`NotchShape`), not an `NSWindow` resize.

## Requirements

- macOS 14.0+
- Xcode (to build), optional: XcodeGen, cmake, SwiftLint
- Runtime: Screen Recording + Accessibility recommended for full media control

## Third-party

Bundled / linked under their own licenses (MIT unless noted):

- [Defaults](https://github.com/sindresorhus/Defaults), [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [Lottie](https://github.com/airbnb/lottie-ios), [Sparkle](https://github.com/sparkle-project/Sparkle)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — **BSD-3-Clause**

## License

[MIT](LICENSE). Vendor and SPM dependencies keep their own terms.

## Links

- [中文说明](README.zh-CN.md)
- [Releases](https://github.com/haoyiyin/dao/releases)
