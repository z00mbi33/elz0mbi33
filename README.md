# elz0mbi33

Floating Spotify lyrics app for macOS and Windows.

Current release: v1.1.2-windows-test

## Features

- Floating always-on-top desktop window
- Spotify PKCE login
- Synchronized lyrics when available
- Fallback status when lyrics are unavailable

## Download

[Download the latest release](https://github.com/z00mbi33/elz0mbi33/releases/latest)

## Run locally

```bash
flutter pub get
flutter run -d macos
```

```bash
flutter run -d windows
```

## Spotify setup

1. Create a Spotify developer app.
2. Add this redirect URI:
   - `http://127.0.0.1:8888/callback`
3. Click **Connect Spotify** in the app.

## Notes

- Spotify Premium may be required for playback-state access.
- Lyrics depend on LRCLIB availability.
- If lyrics are unavailable, the app shows a fallback status and retries later.
- Logs are written to `elz0mbi33.log` next to the app executable when possible.
- Open **More options → Open logs** to view a live log window.
- If the app folder is not writable, logs fall back to the local app data log folder on Windows.
