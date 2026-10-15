/// An operational banquet area. A group can contain multiple physical rooms
/// without pretending that their individual names or combined capacity are known.
class BanquetArea {
  const BanquetArea({
    required this.id,
    required this.venueId,
    required this.name,
    required this.kind,
    required this.spaceCount,
    this.venueSpaceId,
    this.capacityPerSpace,
    this.areaSquareFeet,
    required this.canCombine,
    this.combinedCapacity,
    this.hasFullServiceBar,
  });

  final String id;
  final String venueId;
  final String? venueSpaceId;
  final String name;
  final String kind;
  final int spaceCount;
  final int? capacityPerSpace;
  final int? areaSquareFeet;
  final bool canCombine;
  final int? combinedCapacity;
  final bool? hasFullServiceBar;

  factory BanquetArea.fromJson(Map<String, dynamic> json) => BanquetArea(
    id: json['id'] as String,
    venueId: json['venue_id'] as String,
    venueSpaceId: json['venue_space_id'] as String?,
    name: json['name'] as String,
    kind: json['kind'] as String,
    spaceCount: (json['space_count'] as num).toInt(),
    capacityPerSpace: (json['capacity_per_space'] as num?)?.toInt(),
    areaSquareFeet: (json['area_square_feet'] as num?)?.toInt(),
    canCombine: json['can_combine'] as bool,
    combinedCapacity: (json['combined_capacity'] as num?)?.toInt(),
    hasFullServiceBar: json['has_full_service_bar'] as bool?,
  );
}
