/// Shared attribute tables for the Realme Buds T310.
///
/// MIRRORS `ProtocolConstants.kt` 1:1 — keep both in sync. Protocol is the
/// Oppo/Realme "HeyThings" SPP protocol reverse-engineered by Gadgetbridge
/// (Freeyourgadget/Gadgetbridge).
library;

/// Noise control modes (ANC_CONFIG_SET, type MODE).
/// Wire values are the real ones: 0x01=off, 0x02=transparency, 0x08=ANC.
enum NoiseMode {
  off(0x01, 'Off', 'No cancellation'),
  transparency(0x02, 'Transparency', 'Hear your surroundings'),
  anc(0x08, 'ANC', 'Noise cancelling');

  const NoiseMode(this.value, this.label, this.subtitle);

  /// Wire value for ANC_CONFIG_SET / MODE.
  final int value;
  final String label;
  final String subtitle;

  static NoiseMode fromValue(int v) =>
      NoiseMode.values.firstWhere((m) => m.value == v, orElse: () => NoiseMode.off);
}

/// Game (low latency) mode — MISC_CONFIG_SET type 0x06.
enum GameMode {
  off(0x00),
  on(0x01);

  const GameMode(this.value);
  final int value;
}

/// Multipoint (dual device connection) — MISC_CONFIG_SET type 0x11.
enum MultipointMode {
  off(0x00),
  on(0x01);

  const MultipointMode(this.value);
  final int value;
}
