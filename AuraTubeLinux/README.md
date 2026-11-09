# AuraTube for Linux (native)

A native port of the macOS app (`AuraTubeNative/`) for Ubuntu 22.04+, written in Rust with
GTK4 + libadwaita, using GStreamer for playback. The UI is in Vietnamese, like the Mac app.

## Build

```bash
sudo apt install libgtk-4-dev libadwaita-1-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev libdbus-1-dev pkg-config \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav
cargo run --release
cargo run --release -- --selftest   # headless check: InnerTube, yt-dlp, GStreamer
```

Package: put a `yt-dlp_linux` build at `bin/yt-dlp`, then run `cargo install cargo-deb && cargo deb`.
CI: `.github/workflows/linux-native.yml` builds on ubuntu-22.04, installs the .deb, starts the
app under Xvfb and runs `--selftest`. The `linux-native` job in `release.yml` uploads
`AuraTube-linux-vX.Y.Z-amd64.deb` to the tag's release, then publishes `version-linux.json`.

## Layout

| File | Ports |
|---|---|
| `innertube.rs` | `YTDLPService` / `RecommendationService` (search, trending, channel, `/next`, suggestions, link parsing) |
| `ytdlp.rs` | `YTDLPBinary` + `getStreamInfo` (managed binary in `~/.local/share/AuraTube/bin`, refreshed every 3 days, `--js-runtimes` with deno auto-install) |
| `player.rs` | `PlayerManager`: one pipeline, one `uridecodebin` per URL (split video/audio and HLS), appsink → `gdk::MemoryTexture` |
| `widgets.rs` | cards, grid, `PlayerControlOverlay` |
| `app.rs` | `ContentView`, `HomeView`, `WatchView`, `ChannelDetailView`, `NativeShortsFeedView`, `SettingsSheetView`, mini player, MPRIS |
| `downloads.rs` | `DownloadManager` (MP4/MP3, no-ffmpeg fallbacks) |
| `sponsorblock.rs`, `speed.rs`, `update.rs`, `tray.rs`, `settings.rs` | matching Mac services |

## Known limitations

* Google sign-in / subscription sync is not implemented. Ubuntu 22.04 ships no WebKitGTK 6.0
  for GTK4. Subscriptions are kept locally instead, as `ChannelSubscriptionManager` does.
* GTK4 has no always-on-top API. The mini player asks the window manager through `wmctrl`
  on X11 when it is installed. On Wayland it is a normal window.
* Frames are copied to the CPU (RGBA appsink), which uses more CPU than GL zero-copy at 1080p.
* Not ported: comments, chapters, the autoplay countdown overlay, watch-history recommendations, AppImage/Flatpak.
