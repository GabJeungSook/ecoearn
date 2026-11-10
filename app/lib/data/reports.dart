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

class StudentSummary {
  const StudentSummary({
    required this.bottles,
    required this.grams,
    required this.rejected,
    required this.monthPoints,
    required this.monthTotalPoints,
    required this.recent,
  });

  final int bottles;
  final double grams;
  final int rejected;
  final int monthPoints;

  /// Points everyone earned this month.
  final int monthTotalPoints;

  /// Newest first.
  final List<DepositRecord> recent;

  /// Share of this student's deposits that were accepted, 0–1.
  double get acceptanceRate => bottles + rejected == 0 ? 0 : bottles / (bottles + rejected);

  /// This student's share of all points earned this month, 0–1.
  double get monthShare => monthTotalPoints == 0 ? 0 : monthPoints / monthTotalPoints;
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

  /// The points rate the deposit was earned at; null in data from before it was recorded.
  int? get gramsPerPoint => row['grams_per_point'] as int?;
}

// occurred_at is stored as ISO 8601 text, so date ranges compare as strings.
String _monthStart(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';

String _nextMonthStart(int year, int month) =>
    month == 12 ? _monthStart(year + 1, 1) : _monthStart(year, month + 1);

class Reports {
  Reports(this._db);

  final Database _db;

  Future<MonthlyReport> monthly(int year, int month) async =>
      MonthlyReport(year, month, await _totals(_monthStart(year, month), _nextMonthStart(year, month)));

  /// Per-student totals for one calendar day, highest points first.
  Future<List<MonthlyRow>> day(DateTime day) {
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return _totals(date(day), date(DateTime(day.year, day.month, day.day + 1)));
  }

  /// Totals per student (or unregistered card) for deposits in [from, to).
  Future<List<MonthlyRow>> _totals(String from, String to) async {
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
        [from, to]);

    return [
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
    ];
  }

  /// One student's lifetime totals, this month's share of points, and latest deposits.
  Future<StudentSummary> studentSummary(int studentId, {int recentCount = 6}) async {
    final totals = (await _db.rawQuery('''
      SELECT COALESCE(SUM(reject_reason IS NULL), 0) AS bottles,
             COALESCE(SUM(CASE WHEN reject_reason IS NULL THEN grams ELSE 0 END), 0) AS grams,
             COALESCE(SUM(reject_reason IS NOT NULL), 0) AS rejected
      FROM deposits WHERE student_id = ?''', [studentId])).first;

    final now = DateTime.now();
    final month = (await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN student_id = ? THEN points ELSE 0 END), 0) AS mine,
             COALESCE(SUM(points), 0) AS total
      FROM deposits WHERE occurred_at >= ? AND occurred_at < ?''',
        [studentId, _monthStart(now.year, now.month), _nextMonthStart(now.year, now.month)])).first;

    final recent = await _db.rawQuery('''
      SELECT d.*, s.student_no, s.name, s.grade_section
      FROM deposits d LEFT JOIN students s ON s.id = d.student_id
      WHERE d.student_id = ?
      ORDER BY d.occurred_at DESC, d.id DESC LIMIT ?''', [studentId, recentCount]);

    return StudentSummary(
      bottles: totals['bottles'] as int,
      grams: (totals['grams'] as num).toDouble(),
      rejected: totals['rejected'] as int,
      monthPoints: month['mine'] as int,
      monthTotalPoints: month['total'] as int,
      recent: recent.map(DepositRecord.new).toList(),
    );
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
