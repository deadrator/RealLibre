/// Shared attribute tables for the Realme Buds T310.
///
/// MIRRORS `ProtocolConstants.kt` 1:1 — keep both in sync. Protocol is the
/// Oppo/Realme "HeyThings" SPP protocol reverse-engineered by Gadgetbridge
/// (Freeyourgadget/Gadgetbridge).
///
/// CONFIDENCE LEGEND (honesty about what is proven vs guessed):
/// - [NoiseMode], [AncCycleMode], [GameMode], [MultipointMode] values are
///   confirmed: either answered by real T310 hardware or present in
///   Gadgetbridge's shipped enums.
/// - [EQMode], [SpatialAudio], [VolumeEnhancer], [EnhanceVoices],
///   [WindNoiseReduction] features EXIST in Realme Link but
///   their wire type bytes are NOT in the reverse-engineered protocol.
///   The buds reject unknown misc-config types with ACK status=0x01
///   (verified on hardware). Enums kept for UI display only until the real
///   values are discovered — see README "Protocol discovery".
library;

/// Noise control modes (ANC_CONFIG_SET, type MODE).
/// Wire values are the real ones: 0x01=off, 0x02=transparency, 0x08=ANC.
enum NoiseMode {
  off(0x01, 'Off', 'No cancellation'),
  transparency(0x02, 'Transparency', 'Hear your surroundings'),
  anc(0x08, 'Noise cancellation', 'Active noise cancelling');

  const NoiseMode(this.value, this.label, this.subtitle);

  /// Wire value for ANC_CONFIG_SET / MODE.
  final int value;
  final String label;
  final String subtitle;

  static NoiseMode fromValue(int v) =>
      NoiseMode.values.firstWhere((m) => m.value == v, orElse: () => NoiseMode.off);
}

/// ANC sub-level labels (Mild / Moderate / Deep) as shown in Realme Link.
///
/// The T310's Realme Link page offers these, but NO wire command for them is
/// present in the reverse-engineered protocol (AncConfigType only has
/// MODE=0x01 and TOUCH_CYCLE_MODES=0x02). Shown in the UI for parity with
/// Realme Link; the selector is disabled until a wire value is discovered.
enum AncCycleMode {
  mild(0x00, 'Mild', 'Light noise reduction'),
  moderate(0x01, 'Moderate', 'Balanced cancellation'),
  deep(0x02, 'Deep', 'Maximum noise reduction');

  const AncCycleMode(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;

  static AncCycleMode fromValue(int v) =>
      AncCycleMode.values.firstWhere((e) => e.value == v, orElse: () => AncCycleMode.mild);
}

/// Game (low latency) mode — MISC_CONFIG_SET type 0x06. CONFIRMED working.
enum GameMode {
  off(0x00, 'Off', 'Standard audio latency'),
  on(0x01, 'On', 'Low latency for gaming');

  const GameMode(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

/// Multipoint (dual device connection) — MISC_CONFIG_SET type 0x11. CONFIRMED working.
enum MultipointMode {
  off(0x00, 'Off', 'Single device connection'),
  on(0x01, 'On', 'Connect to 2 devices');

  const MultipointMode(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

/// EQ preset labels as shown in Realme Link.
/// Wire type UNDISCOVERED — UI only; sending does nothing (rejected).
enum EQMode {
  default_(0x00, 'Default', 'Balanced sound profile'),
  bassBoost(0x01, 'Bass Boost+', 'Deeper low end'),
  clearBass(0x02, 'Clear Bass', 'Tight, punchy bass'),
  clearVocals(0x03, 'Clear Vocals', 'Forward, detailed vocals');

  const EQMode(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;

  static EQMode fromValue(int v) =>
      EQMode.values.firstWhere((e) => e.value == v, orElse: () => EQMode.default_);
}

/// Spatial audio (360°) label. Wire type UNDISCOVERED — UI only.
enum SpatialAudio {
  off(0x00, 'Off', 'Standard stereo'),
  on(0x01, 'On', '360° immersive surround sound');

  const SpatialAudio(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

/// Volume enhancer label. Wire type UNDISCOVERED — UI only.
enum VolumeEnhancer {
  off(0x00, 'Off', 'Standard volume'),
  on(0x01, 'On', 'Increased volume level');

  const VolumeEnhancer(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

/// Enhance voices label. Wire type UNDISCOVERED — UI only.
enum EnhanceVoices {
  off(0x00, 'Off', 'Standard transparency'),
  on(0x01, 'On', 'Diminish ambient sounds and enhance voices');

  const EnhanceVoices(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}

/// Wind noise reduction label. Wire type UNDISCOVERED — UI only.
enum WindNoiseReduction {
  off(0x00, 'Off', 'Standard noise handling'),
  on(0x01, 'On', 'Reduce wind noise effectively');

  const WindNoiseReduction(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;
}
