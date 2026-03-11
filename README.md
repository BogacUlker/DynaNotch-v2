<h1 align="center">
  <br>
  <img src="dynanotchlogo.png" alt="DynaNotch" width="150">
  <br>
  DynaNotch
  <br>
</h1>

<p align="center">
  <b>Transform your MacBook's notch into a powerful, dynamic command center.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" />
  <img src="https://img.shields.io/github/license/BogacUlker/DynaNotch-v2?style=flat-square" />
  <img src="https://img.shields.io/github/v/release/BogacUlker/DynaNotch-v2?style=flat-square" />
</p>

---

DynaNotch turns your MacBook's notch into an interactive hub — music controls, live sports, weather, system stats, pomodoro timer, file shelf, and more. All accessible with a simple hover.

> Fork of [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) with significant new features and improvements.

## Features

### Music & Media
- **Now Playing controls** — Play, pause, skip, shuffle, repeat with album art
- **Multiple controllers** — Apple Music, Spotify, YouTube Music, and system Now Playing
- **Synced lyrics** — Real-time lyrics display, both in expanded and closed notch
- **Music visualizer** — Animated audio spectrum or Lottie-based visualizer
- **Album art tinting** — UI colors adapt to current album artwork

### Productivity
- **Pomodoro timer** — Work/short break/long break cycle with configurable durations
- **Daily stats** — Track completed cycles and focus minutes
- **Weekly history** — Visual chart of your productivity across the week
- **Calendar & Reminders** — View upcoming events and manage reminders inline

### Live Data
- **Weather** — Current temperature, conditions, and forecasts with location services
- **Sports scores** — Live results for Football (5 leagues), NBA, EuroLeague, and Formula 1
- **System Monitor** — Real-time CPU, RAM, network, disk I/O, and battery health widgets

### System Integration
- **HUD replacement** — Volume, brightness, and keyboard backlight indicators in the notch
- **Battery indicator** — Charge level, charging status, and low power mode
- **Download monitor** — Track file downloads from Safari and Chromium browsers
- **Webcam mirror** — Quick camera preview from the notch header

### File Shelf
- **Drag & drop** — Drop files, URLs, and text onto the notch for quick access
- **Quick share** — Share items via AirDrop, email, and other services
- **Persistent storage** — Items survive app restarts with bookmark-based persistence

### Customization
- Custom accent colors and corner radius
- Configurable gestures and hover behavior
- Per-display notch selection (multi-monitor support)
- Adjustable music control layout
- Camera mirror shape options

## Installation

**Requirements:** macOS 14 Sonoma or later

### Download

Download the latest `.dmg` from [Releases](https://github.com/BogacUlker/DynaNotch-v2/releases).

Move **DynaNotch** to `/Applications`, then bypass the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/boringNotch.app
```

Or via System Settings > Privacy & Security > Open Anyway.

## Building from Source

**Prerequisites:** macOS 14+, Xcode 16+

```bash
git clone https://github.com/BogacUlker/DynaNotch-v2.git
cd DynaNotch-v2
open boringNotch.xcodeproj
```

Build and run with `Cmd + R`.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## Acknowledgments

DynaNotch is a fork of [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) by The Bored Team. We're grateful for their work on the original project.

**Notable dependencies:**
- [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter) — Now Playing support for macOS 15.4+
- [NotchDrop](https://github.com/Lakr233/NotchDrop) — Inspiration for the Shelf feature

For full license details, see [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES).

## License

[GPL-3.0](LICENSE)
