# GoodbyeDPI iOS

DPI circumvention for iPhone (Discord / blocked TLS sites). Same techniques as [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) / Turkey fork, adapted to iOS Network Extension.

iOS cannot load WinDivert. This app uses a **Packet Tunnel** that:
- Hijacks UDP/53 to **DoH** (Cloudflare 1.1.1.1) so ISP DNS poisoning fails
- Splits TLS ClientHello **before SNI** (and optional reverse-order send)
- Mixes HTTP `Host` case / `hoSt` / strip space
- Drops QUIC (UDP/443) so Discord falls back to TCP where fragmentation works

## Build from Windows (you cannot compile iOS on iPhone or native Windows)

Apple does not ship an iOS compiler for Windows or iPhone. This repo builds on GitHub’s free macOS runner.

1. Put **this folder** (`GoodbyeDPI-iOS`) on GitHub as the repo root.
2. On Windows: `winget install GitHub.cli` → `gh auth login`
3. Run `scripts\build-from-windows.ps1`
4. Download `GoodbyeDPI-unsigned.ipa` from the Actions artifact.
5. Install with **Sideloadly** or **AltStore** on Windows (Apple ID resigns it). Packet Tunnel needs a **paid** Apple Developer account ($99/yr) or TrollStore on a supported iOS. Free 7-day sideload often **cannot** enable Network Extension.

On iPhone you only **install** the IPA (AltStore / TrollStore). You cannot build there.

## Open in Xcode (Mac)

1. Open `GoodbyeDPI.xcodeproj` **or** create a new iOS App + Packet Tunnel target and drop these sources in.
2. Signing: Apple Developer account. Enable **Network Extensions** + **Personal VPN**.
3. App Group: `group.goodbye.dpi` on both the app and the extension.
4. Run on a real device (simulator cannot run Packet Tunnel).

## Use

Tap **Connect**. iOS VPN permission sheet appears. Leave it on while using Discord.

Default hosts: discord.com, discordapp.com, discord.gg, gateway.discord.gg, cdn.discordapp.com, plus a short list you can edit in Settings.

## Modes (maps to GoodbyeDPI)

| Mode | What it does |
|------|----------------|
| 5 | fragment 2 + reverse-frag (default, like `-5`) |
| 6 | fragment + fake ClientHello with wrong seq (best-effort in userspace) |
| 9 | fragment + drop QUIC (like `-9`) |

## Limits

- App Store review often rejects generic “bypass DPI” apps. Sideload (AltStore / TrollStore / developer cert).
- Fake TTL / wrong checksum at IP layer is not available the way WinDivert does it.
- Cellular DPI that resets after seeing a full reassembled ClientHello may still win; try Mode 9 + DoH.

Apache-2.0, same lineage as GoodbyeDPI.
