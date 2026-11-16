import '../serial/device_event.dart';

/// The steps of a deposit, in order, as the firmware announces them.
enum MachineStage {
  ready('ready', 'Getting ready', 'Getting the scale ready'),
  crushing('crushing', 'Crushing', 'Crushing your bottle'),
  draining('draining', 'Draining', 'Draining leftover liquid'),
  dropping('dropping', 'Dropping', 'Dropping it onto the scale'),
  weighing('weighing', 'Weighing', 'Weighing your bottle');

  const MachineStage(this.code, this.label, this.message);

  final String code;

  /// Short name, e.g. for a step icon.
  final String label;

  /// What a student sees, e.g. "Crushing your bottle".
  final String message;

  static MachineStage? of(StageEvent? event) =>
      event == null ? null : values.where((s) => s.code == event.stage).firstOrNull;
}

/// Overall progress for a processing bar, 0–1: each step fills its share of
/// the bar, and inside a step the bar moves with the time the firmware said the
/// step usually takes, slowing near the end until the next step arrives.
double depositProgress(StageEvent? event, DateTime now) {
  // Share of the bar where each step starts; weighing ends at 0.97 (the result fills the rest).
  const starts = {
    MachineStage.ready: 0.0,
    MachineStage.crushing: 0.08,
    MachineStage.draining: 0.45,
    MachineStage.dropping: 0.78,
    MachineStage.weighing: 0.84,
  };
  final stage = MachineStage.of(event);
  if (stage == null) return 0.02;
  final from = starts[stage]!;
  final next = stage.index + 1 < MachineStage.values.length ? starts[MachineStage.values[stage.index + 1]]! : 0.97;

  final elapsed = now.difference(event!.receivedAt).inMilliseconds;
  final expected = event.expectedMs ?? 0;
  // Linear to 85% of the step over the expected time, then creeping toward 98%.
  final double within;
  if (expected <= 0) {
    within = 1 - 1 / (1 + elapsed / 4000);
  } else if (elapsed < expected) {
    within = 0.85 * elapsed / expected;
  } else {
    within = 0.98 - 0.13 / (1 + (elapsed - expected) / 3000);
  }
  return from + (next - from) * within.clamp(0, 1);
}
