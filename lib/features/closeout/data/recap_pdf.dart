import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the operational recap PDF from the database recap. Financial data is never part of the recap.
Future<Uint8List> buildRecapPdf(Map<String, dynamic> recap, {required String status}) async {
  final doc = pw.Document();
  final event = (recap['event'] as Map?)?.cast<String, dynamic>() ?? const {};
  final tasks = (recap['tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
  final requests = (recap['requests'] as Map?)?.cast<String, dynamic>() ?? const {};
  final inspections = (recap['inspections'] as Map?)?.cast<String, dynamic>() ?? const {};

  String fmt(Object? v) => v == null ? '—' : v.toString();
  String when(Object? v) =>
      v == null ? '—' : DateFormat('EEE MMM d, y h:mm a').format(DateTime.parse(v as String).toLocal());

  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.SizedBox(width: 170, child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value)),
        ]),
      );

  doc.addPage(pw.Page(
    margin: const pw.EdgeInsets.all(40),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Event operational recap', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Closeout status: $status', style: const pw.TextStyle(color: PdfColors.grey700)),
        pw.Divider(),
        pw.Text('Event', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        row('Name', fmt(event['name'])),
        row('Type', fmt(event['type'])),
        row('Service start', when(event['service_start'])),
        row('Service end', when(event['service_end'])),
        row('Guaranteed guests', fmt(event['guaranteed_guests'])),
        row('Manager', fmt(event['manager'])),
        pw.SizedBox(height: 14),
        pw.Text('Operations', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        row('Required tasks', '${fmt(tasks['completed'])} of ${fmt(tasks['required'])} completed'),
        row('Overdue required tasks', fmt(tasks['overdue'])),
        row('Service requests', '${fmt(requests['completed'])} of ${fmt(requests['total'])} completed'),
        row('Average response (min)', fmt(requests['avg_response_minutes'])),
        row('Failed inspection items', fmt(inspections['failed_items'])),
        row('Corrective actions', fmt(inspections['corrective_actions'])),
        row('Late deliveries', fmt(recap['late_deliveries'])),
        row('Guest and operational incidents', fmt(recap['incidents'])),
        pw.SizedBox(height: 24),
        pw.Text('Management sign-off', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 18),
        pw.Text('Event manager: ______________________________   Date: ____________'),
        pw.SizedBox(height: 18),
        pw.Text('Director of Premium: _________________________   Date: ____________'),
      ],
    ),
  ));

  return doc.save();
}
