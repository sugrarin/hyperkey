# Hyperkey

A small macOS menu bar app that turns Caps Lock into a Hyperkey (⌃⌥⌘⇧) and uses it to launch apps and scripts with global hotkeys. It can also switch keyboard layouts by tapping a modifier key.

## Features

- Caps Lock as Hyperkey (⌃⌥⌘⇧)
- Global hotkeys for apps and folders
- Global hotkeys for `.sh` scripts
- Lang Switcher: tap a left or right modifier on its own to switch keyboard layout
- Launch at login, optional hidden menu bar icon

## Requirements

- macOS 15 or later
- Apple Silicon

Hyperkey needs Accessibility access to capture keys.

## Install

Download `Hyperkey-*.zip` from [Releases](https://github.com/sugrarin/hyperkey/releases), unzip it and move `Hyperkey.app` to `/Applications`.

The app is not notarized. On first launch, right-click it and choose Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Hyperkey.app
```

## Build from source

```bash
./build.sh
```

The script builds a release binary, assembles `/Applications/Hyperkey.app`, signs it and launches it. It needs the Swift 6 toolchain.

## Third-party software

Hyperkey has no third-party libraries. It uses only Apple system frameworks: SwiftUI, AppKit, Carbon, ApplicationServices, ServiceManagement and UniformTypeIdentifiers.

## Support

If Hyperkey is useful to you, you can support me: [ko-fi.com/sugrarin](https://ko-fi.com/sugrarin)

## License

[MIT](LICENSE)
