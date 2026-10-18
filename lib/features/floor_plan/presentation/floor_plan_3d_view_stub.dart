import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class FloorPlan3DView extends StatelessWidget {
  const FloorPlan3DView({super.key, required this.sceneData});
  final Map<String, Object?> sceneData;

  @override
  Widget build(BuildContext context) {
    if (sceneData['mode'] != 'banquet_area_schematic') {
      return Container(
        height: 320,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.all,
        ),
        padding: const EdgeInsets.all(AppSpace.l),
        child: const Text(
          'Interactive measured 3D floor plans are available in the web app.',
          style: AppText.body,
        ),
      );
    }

    final count = ((sceneData['spaceCount'] as num?)?.toInt() ?? 1).clamp(1, 8);
    final combined = sceneData['combined'] == true && count > 1;
    return Container(
      height: 320,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.all,
      ),
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 3,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1.6,
            child: CustomPaint(
              painter: _BanquetSchematicPainter(
                count: count,
                combined: combined,
                kind: sceneData['kind'] as String? ?? '',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A static isometric preview for native platforms; no dimensions are implied.
class _BanquetSchematicPainter extends CustomPainter {
  const _BanquetSchematicPainter({
    required this.count,
    required this.combined,
    required this.kind,
  });

  final int count;
  final bool combined;
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final floorColor = switch (kind) {
      'arena_floor' => AppColors.neutral400,
      'premium_lounge' => AppColors.accent300,
      _ => AppColors.neutral300,
    };
    final blocks = combined ? 1 : count;
    final gap = size.width * 0.025;
    final blockWidth = (size.width * 0.68 - gap * (blocks - 1)) / blocks;
    final depth = size.width * 0.13;
    final top = size.height * 0.31;
    final left = size.width * 0.09;
    final height = size.height * 0.34;
    final thickness = size.height * 0.09;

    for (var i = 0; i < blocks; i++) {
      final x = left + i * (blockWidth + gap);
      final a = Offset(x, top + depth * 0.5);
      final b = Offset(x + blockWidth, top);
      final c = Offset(x + blockWidth + depth, top + height);
      final d = Offset(x + depth, top + height + depth * 0.5);

      final side = Path()
        ..moveTo(d.dx, d.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(c.dx, c.dy + thickness)
        ..lineTo(d.dx, d.dy + thickness)
        ..close();
      canvas.drawPath(
        side,
        Paint()..color = Color.lerp(floorColor, AppColors.text, 0.2)!,
      );
      final topFace = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
        ..close();
      canvas.drawPath(topFace, Paint()..color = floorColor);
      canvas.drawPath(
        topFace,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.neutral700,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BanquetSchematicPainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.combined != combined ||
      oldDelegate.kind != kind;
}
