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
- **Every Bluetooth write goes through the framed + HMAC-authenticated path.** `RfcommManager.writeRaw` is `private`, so no caller can bypass `FrameBuilder` (CRC) or `HmacAuth` (handshake).
- **Kotlin and Dart attribute tables must never drift.** `ProtocolConstants.kt` and `lib/core/constants/bud_enums.dart` mirror each other 1:1 and a unit test pins every Dart attribute ID against the spec table — if you change one side, update the other and the test.

## Protocol summary

Frames: `[RMV magic][cmd][seq][len u16 BE][payload][CRC16 u16 BE]` with a bitwise CRC-16 (poly `0x1021`, init `0`, XOR-masked shifts). Commands:

| Cmd | Purpose |
|---|---|
| `0x01` | Auth challenge (16 random client bytes → HMAC verify + earbud challenge) |
| `0x02` | Auth response (`0x0A` + HMAC over earbud challenge) → session unlocked |
| `0x03` | Status query → true 1% L/R/Case battery |
| `0x04` | ATTR_SET: `[0x02, attrId, value]` |

The HMAC-SHA256 handshake must complete before any `0x03`/`0x04` is sent; `RfcommManager` gates this with an `authenticated` flag that only flips after a verified two-pass exchange.

## App layout

- **Pairing screen** — pulsing earbud animation, one-tap bond + connect + handshake.
- **Dashboard** — a compact earbud **status bar at ~1/4 screen height** showing current ANC mode and mini L/R/Case battery fills; tapping it expands the full settings (noise selector, EQ, effects toggles) with an animated crossfade.
- **Notification** — ongoing low-priority battery notification with a quick ANC-cycle action.
- **Quick Settings tile** — cycles ANC → Transparency → Off through the same authenticated connection.
- **Fast Pair popup button** — queries fresh 1% battery and re-fires the GMS Nearby battery broadcast with exact values (see limitation below).

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
3. **CRC/auth vectors** — the CRC-16 implementation follows the spec described in this project (poly `0x1021`, init 0, XOR-masked shifts). If you capture real frames from your buds, add them as golden vectors in `android/app/src/test/` to harden the test suite.

## Project structure

```
realibre/
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   └── kotlin/com/realibre/app/
│       ├── MainActivity.kt            # MethodChannel + EventChannel bridge
│       ├── bluetooth/
│       │   ├── ProtocolConstants.kt   # wire protocol constants (Kotlin truth)
│       │   ├── Crc16.kt               # bitwise CRC-16
│       │   ├── FrameBuilder.kt        # frame build/parse
│       │   ├── HmacAuth.kt            # HMAC-SHA256 handshake
│       │   └── RfcommManager.kt       # single authenticated socket owner
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
