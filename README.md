# elz0mbi33

Floating Spotify lyrics app for macOS and Windows.

Current release: v1.1

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
