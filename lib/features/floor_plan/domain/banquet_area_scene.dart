import '../../admin/domain/banquet_area.dart';

/// A deliberately unscaled 3D schematic. No room measurements or guest seating
/// positions are inferred from square footage or capacity.
Map<String, Object?> buildBanquetAreaSceneData(
  BanquetArea area, {
  bool combined = false,
}) => {
  'mode': 'banquet_area_schematic',
  'kind': area.kind,
  'spaceCount': area.spaceCount,
  'combined': area.canCombine && combined,
};
