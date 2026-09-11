# RealiBre (LibreMe)

An open-source, telemetry-free companion app and custom pairer for the **Realme Buds T310** — a Flutter + Kotlin Android app that replaces the stock Realme Link app for this device with something fully local and auditable.

![platform](https://img.shields.io/badge/platform-Android%207.0%2B-3ddc84) ![license](https://img.shields.io/badge/license-MIT-blue) ![ci](https://img.shields.io/badge/APK%20CI-GitHub%20Actions-2088FF)

- **Device:** Realme Buds T310 (MAC `88:0E:85:EF:12:24`)
- **Chipset:** Bestechnic (BES) Audio SoC
- **Fast Pair Model ID:** `891148`
- **Transport:** Classic Bluetooth RFCOMM (SPP), channel 1
- **SPP UUID:** `00001101-0000-1000-8000-00805F9B34FB`, max MTU 990

## Non-negotiables (enforced by design)

- **No telemetry, no analytics SDKs, no network calls** — the only radios used are Bluetooth OS APIs. The dependency list is `flutter` + `cupertino_icons` alone; auditable in `pubspec.yaml`.
- **Every Bluetooth write goes through the framed path.** `RfcommManager.writeRaw` is `private`, so no caller can bypass `FrameBuilder`.
- **Kotlin and Dart tables must never drift.** `ProtocolConstants.kt` and `lib/core/constants/bud_enums.dart` mirror each other 1:1 — if you change one side, update the other and the tests.

## Protocol summary

The T310 speaks the **Oppo/Realme "HeyThings" SPP protocol**, reverse-engineered by the [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) project (T100/T300/Enco Buds2 share it; protocol details only — no code copied).

Frames: `[0xAA][totalLen][0000][cmd u16 LE][seq][payloadLen u16 LE][payload]` — **no CRC, no authentication handshake** (an earlier "RMV+CRC16+HMAC" spec did not match the real firmware; the buds silently ignore unknown frames).

| Command (u16 LE) | Purpose |
|---|---|
| `0x0106` / `0x8106` | Battery request / reply (L/R/Case, true 1%, charging bit) |
| `0x010C` / `0x810C` | ANC config query / reply |
| `0x0404` / `0x8404` | ANC config set / ack — payload `[type=MODE, 0x01, value]` |
| `0x010D` / `0x810D` | Misc config query / reply (game mode, multipoint) |
| `0x0403` / `0x8403` | Misc config set / ack — payload `[type, value]` |
| `0x0205` / `0x8205` | Subscribe to push updates (battery, ANC selector, game mode) |
| `0x0204` | Pushed subscription updates |
| `0x0105` / `0x8105` | Firmware version |
| `0x0400` / `0x8400` | Find device (locator tone) |

ANC mode values: `0x01` off, `0x02` transparency, `0x08` ANC (not 0/1/2!). Battery payload: `[status, count, (index, level)...]` with index 1=L, 2=R, 3=case and `level & 0x7F` percent, `& 0x80` charging flag.

## App layout

- **Pairing screen** — only shown when the buds were never bonded or a reconnect failed; the app auto-connects on launch.
- **Dashboard** — a compact earbud **status bar at ~1/4 screen height** showing current ANC mode and mini L/R/Case battery fills; tapping it expands the full settings (noise selector, EQ, effects toggles) with an animated crossfade.
- **Notification** — ongoing low-priority battery notification with a quick ANC-cycle action.
- **Quick Settings tile** — cycles ANC → Transparency → Off through the same authenticated connection.
- **Fast Pair popup button** — queries fresh 1% battery and re-fires the GMS Nearby battery broadcast with exact values (see limitation below).
- **Wire debug console** — every RFCOMM frame as a hex dump, in-app (dashboard bug icon).

## Building

### Locally

```bash
flutter pub get
flutter test          # Dart-side protocol + widget tests
flutter build apk --release
# or: cd android && ./gradlew assembleRelease
```

### Via CI (recommended)

Push to `main` or open a PR — [.github/workflows/build-apk.yml](.github/workflows/build-apk.yml) builds a signed (debug-key) release APK and uploads it as an artifact. Tag `v*` pushes also create a GitHub Release with the APK attached.

## Known limitations (honest notes, no silent rounding)

1. **Fast Pair popup redraw** — GMS does not allow third-party apps to force the Fast Pair battery UI to redraw on all OEM builds. Where the popup cannot be triggered, RealiBre fires the `com.google.android.gms.nearby.discovery.ACTION_BATTERY_CHANGED` broadcast itself with true 1% values so any listener (including RealiBre's own notification) reflects exact numbers.
2. **HFP fallback is coarse** — when RFCOMM is unavailable, HFP `+VDBTY`/`+IPHONEACCEV` only gives ~10% steps; the UI flags this with a "coarse" chip instead of pretending it's precise.
3. **T310 specifics** — Gadgetbridge has shipped support for T100/T300/Enco Buds2 on this protocol family; the T310 is expected to match but command support (e.g. which misc configs exist) may differ slightly. The in-app wire-debug console (bug icon on the dashboard) shows every frame so mismatches are immediately visible.

## Project structure

```
realibre/
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   └── kotlin/com/realibre/app/
│       ├── MainActivity.kt            # MethodChannel + EventChannel bridge
│       ├── bluetooth/
│       │   ├── ProtocolConstants.kt   # wire protocol constants (Kotlin truth)
│       │   ├── FrameBuilder.kt        # 0xAA frame build/parse
│       │   └── RfcommManager.kt       # single socket owner + init sequence
│       ├── service/
│       │   ├── BatteryNotificationService.kt
│       │   ├── BluetoothStateReceiver.kt
│       │   └── NoiseControlTileService.kt
│       └── pairing/DevicePairer.kt
├── lib/
│   ├── main.dart
│   ├── core/{constants/bud_enums.dart, platform/method_channels.dart}
│   ├── state/bud_controller.dart
│   ├── ui/
│   │   ├── theme/app_theme.dart
│   │   ├── screens/{dashboard_screen,pairing_screen}.dart
│   │   └── widgets/{battery_card,noise_control_selector,sound_effects_card}.dart
│   └── models/bud_telemetry.dart
├── assets/icons/
├── pubspec.yaml
└── .gitignore
```

## License

MIT — do whatever, just keep it libre.
