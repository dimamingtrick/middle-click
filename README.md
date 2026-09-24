# MiddleClick

Click the trackpad with three fingers to get a middle click: open links in new tabs, close tabs, pan in 3D apps. No windows, no settings, just a menu bar icon. Needs macOS 12 or later.

## Install

```bash
npx github:dimamingtrick/middle-click
```

Or without Node:

```bash
git clone https://github.com/dimamingtrick/middle-click && middle-click/install.sh
```

Both need git, which comes with the Xcode Command Line Tools.

The app goes to `~/Applications` and starts at every login. On first launch macOS asks for **Accessibility** access, which is needed to change clicks: turn MiddleClick on in System Settings → Privacy & Security → Accessibility. Until then the menu bar icon is dimmed. After an update macOS asks again.

Quitting from the menu bar icon stops it until the next login or until you run the install command again.

MiddleClick conflicts with three-finger drag (System Settings → Accessibility → Pointer Control → Trackpad Options): with both on, three-finger drags become middle-button drags.

## Uninstall

```bash
npx github:dimamingtrick/middle-click uninstall
```

From a clone, run `middle-click/install.sh uninstall`. Deleting the app by hand leaves its login item behind.

## How it works

The private MultitouchSupport framework reports how many fingers touch the trackpad. An event tap turns a left click made with exactly three fingers into a middle click, including drags and the release. Touches on a Magic Mouse are ignored.

## Build

`./build.sh` runs the tests and rebuilds `dist/MiddleClick.app` (universal, ad-hoc signed) from `src/`; it needs the Xcode Command Line Tools. The built app is committed so installing doesn't need Xcode.
