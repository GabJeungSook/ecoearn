import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// One student's (or one unregistered card's) totals for a month.
class MonthlyRow {
  const MonthlyRow({
    required this.studentNo,
    required this.name,
    required this.gradeSection,
    required this.cardUid,
    required this.bottles,
    required this.grams,
    required this.points,
    required this.rejected,
  });

  /// Null for deposits made with a card nobody owns.
  final String? studentNo;
  final String name;
  final String gradeSection;
  final String cardUid;
  final int bottles;
  final double grams;
  final int points;
  final int rejected;

  bool get isRegistered => studentNo != null;
}

class MonthlyReport {
  const MonthlyReport(this.year, this.month, this.rows);

  final int year;
  final int month;

  /// Highest points first.
  final List<MonthlyRow> rows;

  String get title => '${monthNames[month - 1]} $year';

  int get bottles => rows.fold(0, (sum, r) => sum + r.bottles);
  double get grams => rows.fold(0.0, (sum, r) => sum + r.grams);
  int get points => rows.fold(0, (sum, r) => sum + r.points);
  int get rejected => rows.fold(0, (sum, r) => sum + r.rejected);
  int get students => rows.where((r) => r.isRegistered).length;
}

/// One saved deposit with its student details, for CSV export.
class DepositRecord {
  const DepositRecord(this.row);

  final Map<String, Object?> row;

  int get id => row['id'] as int;
  DateTime get occurredAt => DateTime.parse(row['occurred_at'] as String);
  String get cardUid => row['rfid_uid'] as String;
  String? get studentNo => row['student_no'] as String?;
  String? get name => row['name'] as String?;
  String? get gradeSection => row['grade_section'] as String?;
  double get grams => (row['grams'] as num).toDouble();
  int get points => row['points'] as int;
  String? get rejectReason => row['reject_reason'] as String?;
  String get source => row['source'] as String;
}

// occurred_at is stored as ISO 8601 text, so date ranges compare as strings.
String _monthStart(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';

String _nextMonthStart(int year, int month) =>
    month == 12 ? _monthStart(year + 1, 1) : _monthStart(year, month + 1);

class Reports {
  Reports(this._db);

  final Database _db;

  Future<MonthlyReport> monthly(int year, int month) async {
    final rows = await _db.rawQuery('''
      SELECT s.student_no, s.name, s.grade_section, MIN(d.rfid_uid) AS rfid_uid,
             SUM(d.reject_reason IS NULL) AS bottles,
             SUM(CASE WHEN d.reject_reason IS NULL THEN d.grams ELSE 0 END) AS grams,
             SUM(d.points) AS points,
             SUM(d.reject_reason IS NOT NULL) AS rejected
      FROM deposits d LEFT JOIN students s ON s.id = d.student_id
      WHERE d.occurred_at >= ? AND d.occurred_at < ?
      GROUP BY COALESCE('student:' || s.id, 'card:' || d.rfid_uid)
      ORDER BY points DESC, s.name COLLATE NOCASE''',
        [_monthStart(year, month), _nextMonthStart(year, month)]);

    return MonthlyReport(year, month, [
      for (final r in rows)
        MonthlyRow(
          studentNo: r['student_no'] as String?,
          name: (r['name'] as String?) ?? 'Unregistered card ${r['rfid_uid']}',
          gradeSection: (r['grade_section'] as String?) ?? '',
          cardUid: r['rfid_uid'] as String,
          bottles: r['bottles'] as int,
          grams: (r['grams'] as num).toDouble(),
          points: r['points'] as int,
          rejected: r['rejected'] as int,
        ),
    ]);
  }

  /// Every deposit, oldest first. Pass [year] and [month] for just that month.
  Future<List<DepositRecord>> deposits({int? year, int? month}) async {
    final inMonth = year != null && month != null;
    final rows = await _db.rawQuery('''
      SELECT d.*, s.student_no, s.name, s.grade_section
      FROM deposits d LEFT JOIN students s ON s.id = d.student_id
      ${inMonth ? 'WHERE d.occurred_at >= ? AND d.occurred_at < ?' : ''}
      ORDER BY d.occurred_at, d.id''',
        inMonth ? [_monthStart(year, month), _nextMonthStart(year, month)] : null);
    return rows.map(DepositRecord.new).toList();
  }
}
