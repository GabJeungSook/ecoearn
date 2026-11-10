import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';

class PointRateChange {
  const PointRateChange({required this.changedAt, required this.gramsPerPoint, required this.changedBy});

  final DateTime changedAt;
  final int gramsPerPoint;
  final String changedBy;
}

/// The points rate: 1 point for every [gramsPerPoint] grams (decimals dropped).
/// Changing it only affects new deposits; every deposit keeps the points it
/// earned and the rate it was earned at.
class PointRules extends ChangeNotifier {
  PointRules(this._db);

  static const minGramsPerPoint = 1;
  static const maxGramsPerPoint = 1000;

  final Database _db;
  int _gramsPerPoint = AppDatabase.defaultGramsPerPoint;
  List<PointRateChange> _history = const [];

  int get gramsPerPoint => _gramsPerPoint;

  /// Newest first.
  List<PointRateChange> get history => _history;

  int pointsFor(double grams) => grams ~/ _gramsPerPoint;

  Future<void> load() async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: ['grams_per_point']);
    _gramsPerPoint = rows.isEmpty ? AppDatabase.defaultGramsPerPoint : int.parse(rows.first['value'] as String);
    _history = [
      for (final r in await _db.query('point_rate_changes', orderBy: 'changed_at DESC, id DESC'))
        PointRateChange(
          changedAt: DateTime.parse(r['changed_at'] as String),
          gramsPerPoint: r['grams_per_point'] as int,
          changedBy: r['changed_by'] as String,
        ),
    ];
    notifyListeners();
  }

  /// Returns a message to show the user if the value is not allowed, or null on success.
  Future<String?> setGramsPerPoint(int grams, {required String changedBy}) async {
    if (grams < minGramsPerPoint || grams > maxGramsPerPoint) {
      return 'Enter a whole number of grams from $minGramsPerPoint to $maxGramsPerPoint.';
    }
    if (grams == _gramsPerPoint) return null;
    await _db.transaction((txn) async {
      await txn.insert('settings', {'key': 'grams_per_point', 'value': '$grams'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('point_rate_changes', {
        'changed_at': DateTime.now().toIso8601String(),
        'grams_per_point': grams,
        'changed_by': changedBy,
      });
    });
    await load();
    return null;
  }
}
