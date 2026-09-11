import 'package:flutter/foundation.dart';

/// Latest known bud telemetry (kept immutable for easy diffing/animations).
@immutable
class BudTelemetry {
  const BudTelemetry({
    this.left = 0,
    this.right = 0,
    this.caseLevel = 0,
    this.source = 'rfcomm',
    this.timestamp,
  });

  final int left;
  final int right;
  final int caseLevel;

  /// "rfcomm" = true 1% values (Cmd 0x03). "hfp"/"fastpair" = coarse 10% steps.
  final String source;
  final int? timestamp;

  bool get isCoarse => source != 'rfcomm';

  factory BudTelemetry.fromMap(Object? map) {
    final m = map as Map<Object?, Object?>?;
    return BudTelemetry(
      left: (m?['left'] as num?)?.toInt() ?? 0,
      right: (m?['right'] as num?)?.toInt() ?? 0,
      caseLevel: (m?['case'] as num?)?.toInt() ?? 0,
      source: (m?['source'] as String?) ?? 'rfcomm',
      timestamp: (m?['timestamp'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toMap() => {
        'left': left,
        'right': right,
        'case': caseLevel,
        'source': source,
        if (timestamp != null) 'timestamp': timestamp,
      };

  /// Seed values for widget tests / previews.
  static const BudTelemetry seed = BudTelemetry(left: 84, right: 79, caseLevel: 91);
}
