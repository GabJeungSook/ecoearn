class Student {
  const Student({
    this.id,
    required this.studentNo,
    required this.name,
    this.gradeSection = '',
    this.rfidUid,
    this.points = 0,
  });

  factory Student.fromRow(Map<String, Object?> row) => Student(
        id: row['id'] as int,
        studentNo: row['student_no'] as String,
        name: row['name'] as String,
        gradeSection: row['grade_section'] as String,
        rfidUid: row['rfid_uid'] as String?,
        points: (row['points'] as int?) ?? 0,
      );

  /// Null until the student is saved.
  final int? id;
  final String studentNo;
  final String name;
  final String gradeSection;
  final String? rfidUid;

  /// Point balance: everything earned from deposits. (Fine deductions come later.)
  final int points;

  /// Card UIDs are stored as uppercase hex with no separators, e.g. "A3F29B11".
  static String? normalizeUid(String? input) {
    final uid = input?.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    return (uid == null || uid.isEmpty) ? null : uid;
  }
}
