import 'dart:convert';
import 'dart:io';

import 'reports.dart';

/// Builds CSV text. Fields with commas, quotes or line breaks are quoted.
String toCsv(List<List<Object?>> rows) {
  String field(Object? value) {
    final text = value?.toString() ?? '';
    return text.contains(RegExp('[",\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
  }

  return rows.map((row) => row.map(field).join(',')).join('\r\n');
}

/// Writes UTF-8 with a byte-order mark so Excel shows names like "Peñaflor" correctly.
Future<void> writeCsvFile(String path, List<List<Object?>> rows) =>
    File(path).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(rows))]);

String _grams(double g) => g.toStringAsFixed(1);

String _two(int n) => n.toString().padLeft(2, '0');

List<List<Object?>> monthlyReportCsv(MonthlyReport report) => [
      ['Student ID', 'Name', 'Grade & section', 'Card UID', 'Bottles', 'Grams', 'Points', 'Rejected'],
      for (final r in report.rows)
        [r.studentNo ?? '', r.name, r.gradeSection, r.cardUid, r.bottles, _grams(r.grams), r.points, r.rejected],
      ['', 'TOTAL', '', '', report.bottles, _grams(report.grams), report.points, report.rejected],
    ];

/// One row per processed bottle: the raw test data for accuracy and reliability analysis.
List<List<Object?>> depositsCsv(List<DepositRecord> deposits) => [
      ['Deposit ID', 'Date', 'Time', 'Card UID', 'Student ID', 'Name', 'Grade & section',
        'Grams', 'Points', 'Grams per point', 'Status', 'Reject reason', 'Source'],
      for (final d in deposits)
        [
          d.id,
          '${d.occurredAt.year}-${_two(d.occurredAt.month)}-${_two(d.occurredAt.day)}',
          '${_two(d.occurredAt.hour)}:${_two(d.occurredAt.minute)}:${_two(d.occurredAt.second)}',
          d.cardUid,
          d.studentNo ?? '',
          d.name ?? 'Unregistered',
          d.gradeSection ?? '',
          _grams(d.grams),
          d.points,
          d.gramsPerPoint ?? '',
          d.rejectReason == null ? 'accepted' : 'rejected',
          d.rejectReason ?? '',
          d.source,
        ],
    ];
