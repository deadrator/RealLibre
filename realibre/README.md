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
| `0x0404` / `0x8404` | ANC config set / ack — payload `[type, 0x01, value]` |
| `0x010D` / `0x810D` | Misc config query / reply |
| `0x0403` / `0x8403` | Misc config set / ack — payload `[type, value]` |
| `0x0205` / `0x8205` | Subscribe to push updates (battery, ANC selector, game mode) |
| `0x0204` | Pushed subscription updates |
| `0x0105` / `0x8105` | Firmware version |
| `0x0400` / `0x8400` | Find device (locator tone) |
| `0x0108` / `0x8108` | Touch/button config query / reply |

## Wire values (ProtocolConstants.kt ⇄ bud_enums.dart)

The two tables **must** stay in sync — the Dart enums mirror the Kotlin constants 1:1.

### ANC modes (`ANC_CONFIG_SET`, type `0x01`)

| Mode | Hex | Dart enum (`NoiseMode`) |
|---|---|---|
| Off | `0x01` | `NoiseMode.off` |
| Transparency | `0x02` | `NoiseMode.transparency` |
| Noise cancellation (ANC) | `0x08` | `NoiseMode.anc` |

> NOT 0/1/2 — that was the wrong old spec. `0x08` for ANC is the real value.

### ANC sub-level (`ANC_CONFIG_SET`, type `0x14` — "Noise cancellation" depth)

| Level | Hex | Dart enum (`AncCycleMode`) |
|---|---|---|
| Mild | `0x00` | `AncCycleMode.mild` |
| Moderate | `0x01` | `AncCycleMode.moderate` |
| Deep | `0x02` | `AncCycleMode.deep` |

### Misc config types (`MISC_CONFIG_SET` / `MISC_CONFIG_REQ`, payload `[type, value]`)

| Feature | Type hex | Values | Dart enum |
|---|---|---|---|
| Game mode (low latency) | `0x06` | `0x00` off / `0x01` on | `GameMode` |
| EQ mode | `0x0A` | `0x00` Default / `0x01` Bass Boost+ / `0x02` Clear Bass / `0x03` Clear Vocals | `EQMode` |
| Volume enhancer | `0x0E` | `0x00` off / `0x01` on | `VolumeEnhancer` |
| Spatial Audio (360°) | `0x10` | `0x00` off / `0x01` on | `SpatialAudio` |
| Dual-device connection (multipoint) | `0x11` | `0x00` off / `0x01` on | `MultipointMode` |
| Wind noise reduction | `0x12` | `0x00` off / `0x01` on | `WindNoiseReduction` |
| Enhance voices | `0x13` | `0x00` off / `0x01` on | `EnhanceVoices` |
| Earbud fit test (fit sweep) | `0x15` | `0x01` trigger | `FitSweepCmd` |

### Subscription types (`SUBSCRIPTION_SET`, payload `[count, types…]`)

| Type | Hex | Pushes |
|---|---|---|
| Battery | `0x01` | `BATTERY_RET` frames on change |
| Status | `0x02` | in-ear / case events |
| ANC selector | `0x03` | mode changed on-bud |
| Game mode | `0x05` | game mode toggled elsewhere |

Battery payload: `[status, count, (index, level)...]` with index `0x01`=L, `0x02`=R, `0x03`=case; `level & 0x7F` = percent, `& 0x80` = charging flag.

## App layout

- **Pairing screen** — only shown when the buds were never bonded or a reconnect failed; the app auto-connects on launch.
- **Dashboard** — a compact earbud **status bar at ~1/4 screen height** showing current ANC mode and mini L/R/Case battery fills; tapping it expands the full settings with an animated crossfade:
  - **Noise control card** (`noise_control_selector.dart`) — three circular mode buttons (Off / Noise cancellation / Transparency) mirroring Realme Link; when ANC is active, a sub-level row of Mild / Moderate / Deep chips appears (`setAncCycleMode`).
  - **Sound effects card** (`sound_effects_card.dart`) — EQ mode picker (dialog with the 4 presets), Spatial Audio, Volume enhancer, Dynamic audio, Enhance voices, Wind noise reduction toggles.
  - **Device features card** — Dual-device connection (multipoint), Game mode, Earbud fit test (fires `0x15` fit sweep), Find my buds (locator tone).
  - **Keep alive** toggle — whether to hold the RFCOMM socket when the app is backgrounded.
- **Notification** — ongoing low-priority battery notification with a quick ANC-cycle action.
- **Quick Settings tile** — cycles ANC → Transparency → Off through the same authenticated connection.
- **Fast Pair popup button** — queries fresh 1% battery and re-fires the GMS Nearby battery broadcast with exact values (see limitation below).
- **Wire debug console** — every RFCOMM frame as a hex dump, in-app (dashboard bug icon).

## Feature flow (UI → wire)

| UI control | Dart call | Platform channel | Native call | Wire frame |
|---|---|---|---|---|
| Noise mode buttons | `controller.setNoiseMode(mode)` | `setNoiseMode {value}` | `RfcommManager.setNoiseMode` | `0x0404 [01 01 value]` |
| Mild/Moderate/Deep chips | `controller.setAncCycleMode(level)` | `setAncCycleMode {value}` | `RfcommManager.setAncCycleMode` | `0x0404 [14 01 value]` |
| EQ preset dialog | `controller.setEQMode(mode)` | `setMiscConfig {type:0x0A, value}` | `RfcommManager.setMiscConfig` | `0x0403 [0A value]` |
| Spatial Audio toggle | `controller.setSpatialAudio(on)` | `setMiscConfig {type:0x10, value}` | `RfcommManager.setMiscConfig` | `0x0403 [10 value]` |
| Volume enhancer toggle | `controller.setVolumeEnhancer(on)` | `setMiscConfig {type:0x0E, value}` | `RfcommManager.setMiscConfig` | `0x0403 [0E value]` |
| Enhance voices toggle | `controller.setEnhanceVoices(on)` | `setMiscConfig {type:0x13, value}` | `RfcommManager.setMiscConfig` | `0x0403 [13 value]` |
| Wind reduction toggle | `controller.setWindNoiseReduction(on)` | `setMiscConfig {type:0x12, value}` | `RfcommManager.setMiscConfig` | `0x0403 [12 value]` |
| Dual-device toggle | `controller.setMultipoint(on)` | `setMultipoint {enabled}` | `RfcommManager.setMultipoint` | `0x0403 [11 value]` |
| Game mode toggle | `controller.setGameMode(on)` | `setGameMode {enabled}` | `RfcommManager.setGameMode` | `0x0403 [06 value]` |
| Earbud fit test | `controller.triggerFitSweep()` | `triggerFitSweep` | `RfcommManager.triggerFitSweep` | `0x0403 [15 01]` |
| Find my buds | `controller.findDevice()` | `findDevice` | `RfcommManager.findDevice` | `0x0400 [01]` then `[00]` |
| Battery refresh | `controller.refreshBattery()` | `queryBattery` | `RfcommManager.queryBattery` | `0x0106` → `0x8106` |

All writes funnel through `BudChannels` (`method_channels.dart`) → `MainActivity` → `RfcommManager` → the single sanctioned `writeRaw` → `FrameBuilder.build`. No caller can bypass the framing.

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

## Project structure — what every file does

```
realibre/
├── .github/workflows/build-apk.yml   # CI: analyze + test + release APK on push/PR; Release on v* tags
├── android/app/src/main/
│   ├── AndroidManifest.xml           # permissions (BT connect/scan, notifications, FGS) + service/receiver registrations
│   └── kotlin/com/realibre/app/
│       ├── MainActivity.kt           # Flutter bridge: realibre/methods (commands) + realibre/events (telemetry stream)
│       ├── bluetooth/
│       │   ├── ProtocolConstants.kt  # single source of truth: MAC, UUID, command codes, type bytes, mode values (Kotlin side)
│       │   ├── FrameBuilder.kt       # 0xAA frame build/parse + readFrame stream reader + hex logging helper
│       │   ├── RfcommManager.kt      # owns the single RFCOMM socket: connect, init sequence, reader loop, all commands
│       │   └── BudStateCache.kt      # StateFlow cache so QS tile/notification/UI share one copy of bud state
│       ├── service/
│       │   ├── BatteryNotificationService.kt   # foreground notification: live L/R/Case % + ANC-cycle action
│       │   ├── BluetoothStateReceiver.kt        # Fast Pair battery broadcast + bond-state listener
│       │   └── NoiseControlTileService.kt       # Quick Settings tile: cycles ANC → Transparency → Off
│       └── pairing/DevicePairer.kt   # bond flow + precise-battery broadcast for the Fast Pair popup
├── lib/
│   ├── main.dart                     # app entry: theme wiring + dashboard/pairing screen switch + auto-connect
│   ├── core/
│   │   ├── constants/bud_enums.dart  # mirrors ProtocolConstants.kt 1:1: NoiseMode, AncCycleMode, EQMode, etc. (Dart side)
│   │   └── platform/method_channels.dart  # typed BudChannels wrapper: every method/event the native side speaks
│   ├── state/bud_controller.dart     # ChangeNotifier: connection state, telemetry, optimistic setters for every feature
│   ├── models/bud_telemetry.dart     # immutable battery snapshot (L/R/Case + source + charging)
│   └── ui/
│       ├── theme/app_theme.dart      # Material 3 + dynamic color; noise-mode accent colors
│       ├── screens/
│       │   ├── dashboard_screen.dart # 1/4-screen status bar + expandable settings + wire-debug console
│       │   └── pairing_screen.dart   # pulsing earbud + pair-and-connect flow (only when never bonded)
│       └── widgets/
│           ├── battery_card.dart           # liquid-fill L/R/Case battery cells (legacy/preview card)
│           ├── noise_control_selector.dart # circular ANC mode buttons + Mild/Moderate/Deep sub-level chips
│           └── sound_effects_card.dart     # EQ picker dialog + Spatial/Volume/Voices/Wind toggles
├── test/bud_enums_test.dart          # wire-value tests + widget smoke tests with stubbed channels
├── assets/icons/realibre_logo.svg    # app logo source
├── pubspec.yaml                      # deps: flutter + cupertino_icons + dynamic_color (pinned) — auditable
└── .gitignore
```

### Data flow at a glance

```
UI widgets → BudController (setters) → BudChannels (method_channels.dart)
    → MainActivity.kt (when-block dispatch) → RfcommManager.kt → FrameBuilder.build → socket

socket → FrameBuilder.readFrame → RfcommManager reader loop → Incoming events
    → MainActivity EventChannel → BudChannels.events() stream → BudController._onEvent → notifyListeners → UI
```

The QS tile and notification bypass Flutter entirely and share state through `BudStateCache`, so they always agree with the app on a single socket.

## License

MIT — do whatever, just keep it libre.
