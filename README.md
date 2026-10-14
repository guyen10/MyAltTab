# MyAltTab

Windows-style Alt+Tab for macOS: switch between individual **windows** with ⌥ Option + Tab.

## Usage
- Hold **⌥ Option**, press **Tab** to cycle windows (most recently used first).
- **Shift+Tab**, **←/→** or **↑/↓** (between rows) to move, **Esc** to cancel, click a tile to pick it.
- Release **⌥ Option** to switch to the selected window.
- Menu bar icon → **Launch at Login**, **Settings…**, **Quit**.

## Build & install
Requires macOS 14+ and Xcode or the Command Line Tools.

```sh
./build.sh
open ~/Applications/MyAltTab.app
```

On first launch, grant **Accessibility** access when prompted (System Settings → Privacy & Security → Accessibility).
The app starts working as soon as access is granted.

Window previews need **Screen Recording** access (Privacy & Security → Screen & System Audio Recording);
relaunch the app after granting it (Settings → Relaunch). Without it, app icons are shown instead.

Builds are signed with a self-signed certificate (created once by `scripts/setup_signing.sh` in its own keychain,
`~/Library/Keychains/myalttab-signing.keychain-db`), so permissions survive rebuilds.
That keychain's password is random and kept in your login keychain ("MyAltTab signing keychain").

## Icon
The app icon is drawn by `scripts/make_icon.swift`. Regenerate it with `swift scripts/make_icon.swift`.

## Notes
- Only windows on the current Space are listed; minimized windows and windows of hidden apps can be included (Settings).
- Launch at Login uses `SMAppService`, so it shows up under System Settings → General → Login Items.
