class Student {
  const Student({
    this.id,
    required this.studentNo,
    required this.name,
    this.gradeSection = '',
    this.rfidUid,
    this.earned = 0,
    this.spent = 0,
  });

  factory Student.fromRow(Map<String, Object?> row) => Student(
        id: row['id'] as int,
        studentNo: row['student_no'] as String,
        name: row['name'] as String,
        gradeSection: row['grade_section'] as String,
        rfidUid: row['rfid_uid'] as String?,
        earned: (row['earned'] as int?) ?? 0,
        spent: (row['spent'] as int?) ?? 0,
      );

  /// Null until the student is saved.
  final int? id;
  final String studentNo;
  final String name;
  final String gradeSection;
  final String? rfidUid;

  /// Points earned from deposits.
  final int earned;

  /// Points used to pay fees (not voided). Payments are made on the officer's
  /// computer, so on the machine's computer this is always 0.
  final int spent;

  /// Points left to spend.
  int get points => earned - spent;

  /// Card UIDs are stored as uppercase hex with no separators, e.g. "A3F29B11".
  static String? normalizeUid(String? input) {
    final uid = input?.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    return (uid == null || uid.isEmpty) ? null : uid;
  }
}
