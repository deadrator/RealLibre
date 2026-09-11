# RealLibre
custom companion application for the realme t310 tws, removing telemetry and excessive bloatware


Build a Flutter + Kotlin Android app called **RealiBre** ("LibreMe") — an open-source, telemetry-free companion app and custom pairer for the Realme Buds T310. This replaces the stock Realme Link app for this device with something fully local and auditable.

## Target hardware
- Device: Realme Buds T310, MAC 88:0E:85:EF:12:24
- Chipset: Bestechnic (BES) Audio SoC
- Google Fast Pair Model ID: FAST_PAIR_891148 (hex 891148)
- Transport: Classic Bluetooth RFCOMM (SPP), channel 1
- SPP UUID: 00001101-0000-1000-8000-00805F9B34FB
- Max MTU: 990 bytes

## Packet protocol
Implement a `FrameBuilder` + `Crc16` module for this frame layout:
```
[0..2]   Magic header: 0x52 0x4D 0x56 ("RMV")
[3]      Command type (0x01-0x04)
[4]      Sequence number (uint8, wraps 0x00-0xFF)
[5..6]   Payload length (uint16 BE)
[7..N]   Payload
[N+1..N+2] CRC16 checksum (uint16 BE)
```
CRC16 is a custom bitwise polynomial CRC (initial value 0, XOR-masked shifts) — implement and unit test it against known-good frames before wiring it into the transport layer.

## Auth handshake (required before any control command)
Shared secret: `b"hmac_key"` (HMAC-SHA256).
1. Connect via RFCOMM to the MAC on channel 1.
2. Send Cmd 0x01 with 16 cryptographically random client challenge bytes.
3. Buds reply Cmd 0x01: byte 0 = status, bytes 1-32 = HMAC-SHA256(hmac_key, client_random), bytes 33-48 = 16 random earbud challenge bytes.
4. Verify the earbud's signature locally.
5. Send Cmd 0x02: `[0x0A]` + HMAC-SHA256(hmac_key, earbud_random).
6. Buds confirm with Cmd 0x02 — session unlocked; only now send Cmd 0x03/0x04.

Implement this in `HmacAuth.kt`, called from `RfcommManager.kt` right after socket connect and before exposing the channel to the rest of the app.

## Control commands (Cmd 0x04, ATTR_SET)
Payload format: `[Length=0x02, Attr_ID, Value]`. Implement an enum/sealed class per attribute in `bud_enums.dart` (Dart side) and `ProtocolConstants.kt` (Kotlin side):

| Feature | Attr ID | Values |
|---|---|---|
| Noise control | 0x05 | 0x00 Off, 0x01 ANC, 0x02 Transparency |
| ANC sub-level | 0x14 | 0x00 Mild, 0x01 Moderate, 0x02 Deep |
| Gaming (low latency) | 0x06 | 0x01 on / 0x00 off |
| Spatial audio (360°) | 0x10 | 0x01 on / 0x00 off |
| EQ mode | 0x0A | 0x00 Default, 0x01 Bass Boost+, 0x02 Clear Bass, 0x03 Clear Vocals |
| Volume enhancer (gain boost) | 0x0E | 0x01 on / 0x00 off |
| Wind noise reduction | 0x12 | 0x01 on / 0x00 off |
| Enhance voices (transparency sub-option) | 0x13 | 0x01 on / 0x00 off |
| Multipoint (dual device) | 0x09 | 0x01 on / 0x00 off |
| Fit sweep test | 0x15 | 0x01 trigger |

## Battery monitoring
- Cmd 0x03 status query returns true 1% integers for Left, Right, Case (preferred source).
- Fall back to HFP `+VDBTY` / `+IPHONEACCEV` (coarse 10% steps) when RFCOMM is unavailable.
- Also listen for Fast Pair's `com.google.android.gms.nearby.discovery.ACTION_BATTERY_CHANGED` broadcast as a secondary signal.
- Run a persistent foreground `BatteryNotificationService` (NotificationCompat, ongoing, low priority) showing L/R/Case % with quick ANC toggle actions.

## Tech stack
- Flutter, Material 3 with dynamic color
- State management: Riverpod or Bloc (pick one and use it consistently)
- Native Android: Kotlin, via Flutter MethodChannel + EventChannel
- Bluetooth: `android.bluetooth.BluetoothSocket` (RFCOMM), `BluetoothAdapter.createBond()` for pairing
- Background: Android Foreground Service with a custom notification

## Project layout
Scaffold exactly this structure (fill in real code, not stubs, for every file):
```
realibre/
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   └── kotlin/com/realibre/app/
│       ├── MainActivity.kt
│       ├── bluetooth/{ProtocolConstants,FrameBuilder,Crc16,HmacAuth,RfcommManager}.kt
│       ├── service/{BatteryNotificationService,BluetoothStateReceiver}.kt
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
├── README.md
└── .gitignore
```

## Build order (do this incrementally, testing each layer before moving on)
1. `Crc16.kt` + unit tests — verify checksum math in isolation first.
2. `FrameBuilder.kt` — frame assembly/parsing using the CRC module.
3. `RfcommManager.kt` — raw socket connect/read/write, no auth yet.
4. `HmacAuth.kt` — wire the handshake into `RfcommManager` before any command is allowed through.
5. `ProtocolConstants.kt` + `bud_enums.dart` — attribute IDs/values, kept in sync between Kotlin and Dart.
6. `DevicePairer.kt` — discovery + bonding flow, MethodChannel bridge, `pairing_screen.dart`.
7. Battery: Cmd 0x03 polling + `BatteryNotificationService.kt` + `battery_card.dart`.
8. Control UI: `noise_control_selector.dart`, `sound_effects_card.dart`, `bud_controller.dart` wired to `ProtocolConstants` via EventChannel/MethodChannel.
9. `dashboard_screen.dart` tying it together, `app_theme.dart` for Material 3 dynamic color.

## Polished animations
- Use Flutter's `AnimatedSwitcher`/`Hero`/implicit animations (not just static Material widgets) throughout — animated battery level fills (radial or liquid-style progress), a smooth crossfade/slide when switching Noise Control modes, a satisfying press/ripple + haptic on every toggle, and a subtle earbud/case illustration that animates connection state (searching → connected → charging).
- Keep animations on the Flutter side (`ui/widgets`, `ui/theme`) so they stay snappy and don't need native changes; target 300-500ms curves (`Curves.easeOutCubic` or similar) rather than default linear.

## Manual Fast Pair battery popup trigger
Add a button (dashboard or a debug/dev section) that forces the native Google Fast Pair battery UI (the little card that pops up over other apps showing L/R/Case %) to appear on demand, using the **true 1% values from Cmd 0x03**, not the coarse HFP 10%-step numbers:
- On the Kotlin side, add a method to `RfcommManager`/`DevicePairer` that: (1) queries Cmd 0x03 for fresh L/R/Case battery, (2) writes those exact percentages into the on-device Fast Pair provider data / GMS Nearby battery broadcast path so the system draws its own popup with real numbers instead of rounding to 10%.
- Expose this as `triggerBatteryPopup()` over the MethodChannel so the Dart button just calls it.
- If the Fast Pair battery UI can't be forced to redraw directly (OEM/GMS restriction), fall back to firing the `ACTION_BATTERY_CHANGED` broadcast yourself with the precise values so any listener (including your own overlay) reflects true 1% accuracy, and note this limitation clearly in the code comments/README rather than silently rounding.

## Control Center quick controls (ANC / Transparency / Off)
Add an Android Quick Settings Tile service (`android/.../service/`, e.g. `NoiseControlTileService.kt` extending `TileService`) so the three noise modes are reachable from the system Control Center/notification shade without opening the app:
- Three-state tile that cycles **ANC → Transparency → Off (No cancellation)** on tap, sending Cmd 0x04 / Attr 0x05 (0x01 / 0x02 / 0x00) through the same authenticated `RfcommManager` path used by the in-app selector — no duplicate/insecure write path.
- Tile icon and label update to reflect the current mode (query state on `onStartListening`, don't assume).
- Register it in `AndroidManifest.xml` with the `android.service.quicksettings.action.QS_TILE` intent filter, and keep the max-1-active-connection constraint in mind — if the phone isn't connected/authenticated when the tile is tapped, show a toast/quick reconnect rather than failing silently.
- Mirror the same three-way toggle as a control in the in-app `noise_control_selector.dart` so behavior is consistent whether triggered from the tile or the app.

## Non-negotiables
- No telemetry, no analytics SDKs, no network calls except what's strictly needed for Fast Pair/Bluetooth OS APIs.
- Every Bluetooth write must go through the framed + authenticated path — no raw payloads bypassing `FrameBuilder`/`HmacAuth`.
- Keep the Kotlin attribute table and the Dart attribute table as a single source of truth (generate one from the other if convenient) so they can't drift.
