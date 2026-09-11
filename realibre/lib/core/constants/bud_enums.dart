/// Shared attribute tables for the Realme Buds T310.
///
/// MIRRORS `ProtocolConstants.kt` 1:1 — keep both in sync (spec: single
/// source of truth; see README for the sync checklist).
library;

/// Noise control modes (Attr 0x05).
enum NoiseMode {
  off(0x00, 'Off', 'No cancellation'),
  anc(0x01, 'ANC', 'Noise cancelling'),
  transparency(0x02, 'Transparency', 'Hear your surroundings');

  const NoiseMode(this.value, this.label, this.subtitle);

  /// Wire value for Cmd 0x04 / Attr 0x05.
  final int value;
  final String label;
  final String subtitle;

  static NoiseMode fromValue(int v) =>
      NoiseMode.values.firstWhere((m) => m.value == v, orElse: () => NoiseMode.off);
}

/// ANC strength (Attr 0x14), only meaningful while ANC is active.
enum AncLevel {
  mild(0x00, 'Mild'),
  moderate(0x01, 'Moderate'),
  deep(0x02, 'Deep');

  const AncLevel(this.value, this.label);
  final int value;
  final String label;

  static AncLevel fromValue(int v) =>
      AncLevel.values.firstWhere((m) => m.value == v, orElse: () => AncLevel.mild);
}

/// EQ presets (Attr 0x0A).
enum EqMode {
  defaultMode(0x00, 'Default', 'Balanced studio curve'),
  bassBoost(0x01, 'Bass Boost+', 'Deep, punchy low end'),
  clearBass(0x02, 'Clear Bass', 'Tight low end, no muddle'),
  clearVocals(0x03, 'Clear Vocals', 'Forward mids for podcasts');

  const EqMode(this.value, this.label, this.subtitle);
  final int value;
  final String label;
  final String subtitle;

  static EqMode fromValue(int v) =>
      EqMode.values.firstWhere((m) => m.value == v, orElse: () => EqMode.defaultMode);
}

/// Attribute IDs for Cmd 0x04 (ATTR_SET).
class AttrId {
  static const int noiseControl = 0x05;
  static const int ancSubLevel = 0x14;
  static const int gaming = 0x06;
  static const int spatialAudio = 0x10;
  static const int eqMode = 0x0A;
  static const int volumeEnhancer = 0x0E;
  static const int windNoise = 0x12;
  static const int enhanceVoices = 0x13;
  static const int multipoint = 0x09;
  static const int fitTest = 0x15;
}
