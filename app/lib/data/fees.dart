import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'sync_id.dart';

class Fee {
  const Fee({required this.id, required this.syncId, required this.name, required this.amount, required this.active});

  factory Fee.fromRow(Map<String, Object?> r) => Fee(
        id: r['id'] as int,
        syncId: r['sync_id'] as String,
        name: r['name'] as String,
        amount: (r['amount'] as num).toDouble(),
        active: r['active'] == 1,
      );

  final int id;
  final String syncId;
  final String name;

  /// In pesos.
  final double amount;

  /// Archived fees can't be paid anymore but stay for old payments' sake.
  final bool active;
}

class PesoRateChange {
  const PesoRateChange({required this.changedAt, required this.pesosPerPoint, required this.changedBy});

  final DateTime changedAt;
  final double pesosPerPoint;
  final String changedBy;
}

String pesos(double amount) =>
    '₱${amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';

/// The fees students can pay with points, and what a point is worth in pesos.
/// Managed by the admin (sent to officers with the data file) and by officers
/// on their own computer; when both change something, the newest change wins
/// on the officer's side.
class FeeBook extends ChangeNotifier {
  FeeBook(this._db);

  final Database _db;
  List<Fee> _fees = const [];
  double _pesosPerPoint = AppDatabase.defaultPesosPerPoint;
  List<PesoRateChange> _history = const [];

  /// Active first, then archived; each by name.
  List<Fee> get fees => _fees;
  List<Fee> get activeFees => _fees.where((f) => f.active).toList();
  double get pesosPerPoint => _pesosPerPoint;

  /// Newest first.
  List<PesoRateChange> get history => _history;

  /// Points needed to pay [amount] pesos in full: a fee is paid exactly, so any
  /// fraction of a point rounds up.
  int pointsFor(double amount) => (amount / _pesosPerPoint - 1e-9).ceil();

  Future<void> load() async {
    _fees = (await _db.query('fees', orderBy: 'active DESC, name COLLATE NOCASE')).map(Fee.fromRow).toList();
    final rate = await _db.query('settings', where: 'key = ?', whereArgs: ['pesos_per_point']);
    _pesosPerPoint = rate.isEmpty ? AppDatabase.defaultPesosPerPoint : double.parse(rate.first['value'] as String);
    _history = [
      for (final r in await _db.query('peso_rate_changes', orderBy: 'changed_at DESC, id DESC'))
        PesoRateChange(
          changedAt: DateTime.parse(r['changed_at'] as String),
          pesosPerPoint: (r['pesos_per_point'] as num).toDouble(),
          changedBy: r['changed_by'] as String,
        ),
    ];
    notifyListeners();
  }

  String? _check(String name, double amount, {int? exceptId}) {
    if (name.trim().isEmpty) return 'Enter the fee name, e.g. Late fee.';
    if (amount <= 0 || amount > 100000) return 'Enter an amount in pesos above 0.';
    final taken = _fees.any((f) => f.active && f.id != exceptId && f.name.toLowerCase() == name.trim().toLowerCase());
    return taken ? 'There is already a fee called "${name.trim()}".' : null;
  }

  /// Returns a message to show if it can't be saved, or null on success.
  Future<String?> addFee(String name, double amount) async {
    final error = _check(name, amount);
    if (error != null) return error;
    await _db.insert('fees', {
      'sync_id': newSyncId(),
      'name': name.trim(),
      'amount': amount,
      'active': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await load();
    return null;
  }

  /// Changes a fee's name or amount. Payments already made keep what they were.
  Future<String?> updateFee(Fee fee, String name, double amount) async {
    final error = _check(name, amount, exceptId: fee.id);
    if (error != null) return error;
    await _db.update('fees', {'name': name.trim(), 'amount': amount, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [fee.id]);
    await load();
    return null;
  }

  Future<String?> setActive(Fee fee, bool active) async {
    if (active) {
      final error = _check(fee.name, fee.amount, exceptId: fee.id);
      if (error != null) return error;
    }
    await _db.update('fees', {'active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [fee.id]);
    await load();
    return null;
  }

  Future<String?> setPesosPerPoint(double rate, {required String changedBy}) async {
    if (rate <= 0 || rate > 1000) return 'Enter how many pesos one point is worth, e.g. 1.';
    if (rate == _pesosPerPoint) return null;
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('settings', {'key': 'pesos_per_point', 'value': '$rate'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {'key': 'pesos_per_point_changed_at', 'value': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('peso_rate_changes', {'changed_at': now, 'pesos_per_point': rate, 'changed_by': changedBy});
    });
    await load();
    return null;
  }
}
