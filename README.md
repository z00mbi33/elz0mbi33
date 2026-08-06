# elz0mbi33

Menu-bar Spotify lyric app for macOS.

## Features

- Live Spotify track detection
- Synchronized lyrics from LRCLIB
- Persistent menu-bar lyric text
- Clickable popover for details and launch-at-login

## Requirements

- macOS 13+
- Spotify
- Xcode or Swift 6 toolchain

## Run locally

```bash
swift run
```

## Build the app bundle

```bash
./scripts/package-app.sh
open dist/elz0mbi33.app
```

## Download a built app

Tagged releases publish a ready-to-run `.app.zip` on GitHub Releases.

```text
git tag v1.0.0
git push origin v1.0.0
```

Then download the zip from the Releases page and unzip it.

## Notes

- Grant Spotify automation access when macOS prompts for it.
- Launch-at-login is available from the popover.
