import 'dart:convert';

/// One message from the ESP32. The firmware sends one JSON object per line,
/// e.g. `{"event":"weight","uid":"A3F29B11","grams":18,"points":2}`.
sealed class DeviceEvent {
  DeviceEvent({DateTime? receivedAt, this.simulated = false}) : receivedAt = receivedAt ?? DateTime.now();

  final DateTime receivedAt;

  /// Made up by the demo simulator (simulator.dart), not sent by the ESP32. Never saved.
  final bool simulated;

  /// Parses one serial line. Returns null for lines that aren't event JSON,
  /// such as the startup text the ESP32 prints after every reset.
  static DeviceEvent? tryParse(String line, {DateTime? receivedAt}) {
    final text = line.trim();
    if (!text.startsWith('{')) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }

    return switch (decoded) {
      {'event': 'boot', 'version': String version} => BootEvent(
          version: version,
          gramsPerPoint: decoded['grams_per_point'] is int ? decoded['grams_per_point'] as int : null,
          receivedAt: receivedAt,
        ),
      {'event': 'card', 'uid': String uid} =>
        CardEvent(uid: uid, receivedAt: receivedAt),
      {'event': 'stage', 'uid': String uid, 'stage': String stage} => StageEvent(
          uid: uid,
          stage: stage,
          expectedMs: decoded['ms'] is int ? decoded['ms'] as int : null,
          receivedAt: receivedAt,
        ),
      {'event': 'scan', 'uid': String uid} =>
        ScanEvent(uid: uid, receivedAt: receivedAt),
      {'event': 'weight', 'uid': String uid, 'grams': num grams, 'points': int points} =>
        WeightEvent(
          uid: uid,
          grams: grams.toDouble(),
          points: points,
          gramsPerPoint: decoded['grams_per_point'] is int ? decoded['grams_per_point'] as int : null,
          receivedAt: receivedAt,
        ),
      {'event': 'reject', 'uid': String uid, 'reason': String reason, 'grams': num grams} =>
        RejectEvent(
          uid: uid,
          reason: reason,
          grams: grams.toDouble(),
          detail: decoded['detail'] is String ? decoded['detail'] as String : null,
          receivedAt: receivedAt,
        ),
      {'event': 'bin', 'level': int level} =>
        BinEvent(level: level, receivedAt: receivedAt),
      {'event': String name} =>
        UnknownEvent(name: name, raw: text, receivedAt: receivedAt),
      _ => null,
    };
  }
}

/// The ESP32 (re)started.
class BootEvent extends DeviceEvent {
  BootEvent({required this.version, this.gramsPerPoint, super.receivedAt, super.simulated});
  final String version;

  /// The points rate the machine is using (firmware 0.3.0+), so the app can
  /// correct it if it differs from the app's setting.
  final int? gramsPerPoint;
}

/// A student tapped their RFID card; a bottle is now being processed.
class CardEvent extends DeviceEvent {
  CardEvent({required this.uid, super.receivedAt, super.simulated});
  final String uid;
}

/// The machine started a step of a deposit (firmware 0.3.1+), so screens can
/// show what it is really doing. [stage]: `ready` (zeroing the scale),
/// `crushing`, `draining`, `dropping` (trapdoor), `weighing`, `tipping`.
/// [expectedMs] is a typical duration for progress bars; the step lasts until
/// the next stage or the result.
class StageEvent extends DeviceEvent {
  StageEvent({required this.uid, required this.stage, this.expectedMs, super.receivedAt, super.simulated});
  final String uid;
  final String stage;
  final int? expectedMs;
}

/// A card was read in register mode (after the laptop sent `register`):
/// no bottle is processed, the UID is only for assigning the card to a student.
class ScanEvent extends DeviceEvent {
  ScanEvent({required this.uid, super.receivedAt, super.simulated});
  final String uid;
}

/// A bottle was crushed, drained and weighed, and points were awarded.
class WeightEvent extends DeviceEvent {
  WeightEvent({
    required this.uid,
    required this.grams,
    required this.points,
    this.gramsPerPoint,
    super.receivedAt,
    super.simulated,
  });
  final String uid;
  final double grams;
  final int points;

  /// The points rate this deposit was computed with (firmware 0.3.0+).
  final int? gramsPerPoint;
}

/// A deposit earned no points. [reason] is one of the firmware's reject codes:
/// `bin_full`, `mechanism`, `no_item`, `too_heavy`. [detail] optionally says
/// more, e.g. `scale_not_calibrated` for a `mechanism` reject.
class RejectEvent extends DeviceEvent {
  RejectEvent({required this.uid, required this.reason, required this.grams, this.detail, super.receivedAt, super.simulated});
  final String uid;
  final String reason;
  final double grams;
  final String? detail;
}

/// Storage bin fill level, 0-100 percent.
class BinEvent extends DeviceEvent {
  BinEvent({required this.level, super.receivedAt, super.simulated});
  final int level;
}

/// Valid JSON with an event name this app doesn't know (or with missing fields).
/// Kept so newer firmware messages still show up in the log.
class UnknownEvent extends DeviceEvent {
  UnknownEvent({required this.name, required this.raw, super.receivedAt, super.simulated});
  final String name;
  final String raw;
}
