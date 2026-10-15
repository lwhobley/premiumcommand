import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/floor_plan.dart';

/// A one-page PDF of a measured floor plan: the room outline, the round tables at their saved
/// positions, and the capacity. Unverified plans are marked, because their dimensions were not
/// confirmed on site.
Future<Uint8List> buildFloorPlanPdf({
  required String spaceName,
  required VenueSpaceFloorPlan plan,
  String? venueName,
}) async {
  final doc = pw.Document();
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans.ttf'));
  final theme = pw.ThemeData.withFont(base: font, bold: font);
  final capacity = floorPlanCapacity(plan);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter.landscape.copyWith(
        marginLeft: 36,
        marginRight: 36,
        marginTop: 36,
        marginBottom: 36,
      ),
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            spaceName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          if (venueName != null && venueName.isNotEmpty)
            pw.Text(
              venueName,
              style: const pw.TextStyle(color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_feet(plan.widthFeet)} × ${_feet(plan.depthFeet)} · '
            '${plan.tables.length} tables · seats up to $capacity guests',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text(
            plan.verified ? 'Measurements verified.' : 'Measurements not verified. Confirm on site before relying on this layout.',
            style: pw.TextStyle(
              fontSize: 10,
              color: plan.verified ? PdfColors.grey700 : PdfColors.red800,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Expanded(
            child: pw.Center(child: _FloorDrawing(plan: plan)),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Drawn to scale against the room dimensions above. Tables are round, '
            '${_feet(plan.tableDiameterFeet)} across, with ${plan.seatsPerTable} seats each.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Opens the system print and share sheet for the plan.
Future<void> shareFloorPlanPdf({
  required String spaceName,
  required VenueSpaceFloorPlan plan,
  String? venueName,
}) async {
  final bytes = await buildFloorPlanPdf(
    spaceName: spaceName,
    plan: plan,
    venueName: venueName,
  );
  final fileName =
      '${spaceName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-floor-plan.pdf';
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
}

String _feet(double value) => value == value.roundToDouble()
    ? '${value.round()} ft'
    : '${value.toStringAsFixed(1)} ft';

/// The room outline with each table drawn as a circle, scaled to fit the available space.
class _FloorDrawing extends pw.StatelessWidget {
  _FloorDrawing({required this.plan});

  final VenueSpaceFloorPlan plan;

  @override
  pw.Widget build(pw.Context context) {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final rawWidth = constraints?.maxWidth;
        final rawHeight = constraints?.maxHeight;
        final maxWidth = rawWidth != null && rawWidth.isFinite
            ? rawWidth
            : 600.0;
        final maxHeight = rawHeight != null && rawHeight.isFinite
            ? rawHeight
            : 300.0;
        final scale = math.min(
          maxWidth / math.max(plan.widthFeet, 1),
          maxHeight / math.max(plan.depthFeet, 1),
        );
        final width = plan.widthFeet * scale;
        final height = plan.depthFeet * scale;
        final diameter = plan.tableDiameterFeet * scale;

        return pw.SizedBox(
          width: width,
          height: height,
          child: pw.Stack(
            children: [
              pw.Container(
                width: width,
                height: height,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey800, width: 1.2),
                  color: PdfColors.grey100,
                ),
              ),
              for (final table in plan.tables)
                pw.Positioned(
                  left: table.x * scale - diameter / 2,
                  top: table.y * scale - diameter / 2,
                  child: pw.Container(
                    width: diameter,
                    height: diameter,
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColors.white,
                      border: pw.Border.fromBorderSide(
                        pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
