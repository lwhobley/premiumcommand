import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/session_controller.dart';

import '../domain/banquet_area.dart';

final banquetAreaRepositoryProvider = Provider<BanquetAreaRepository>((ref) {
  ref.watch(sessionProvider);
  return BanquetAreaRepository(Supabase.instance.client);
});

final banquetAreasProvider = FutureProvider.family<List<BanquetArea>, String>((
  ref,
  venueId,
) {
  return ref.watch(banquetAreaRepositoryProvider).listForVenue(venueId);
});

class BanquetAreaRepository {
  BanquetAreaRepository(this._client);

  final SupabaseClient _client;

  Future<List<BanquetArea>> listForVenue(String venueId) async {
    final rows = await _client
        .from('venue_banquet_areas')
        .select()
        .eq('venue_id', venueId)
        .order('name');
    return rows.cast<Map<String, dynamic>>().map(BanquetArea.fromJson).toList();
  }

  Future<void> save({
    String? id,
    required String venueId,
    required String name,
    required String kind,
    required int spaceCount,
    int? capacityPerSpace,
    int? areaSquareFeet,
    required bool canCombine,
    int? combinedCapacity,
    bool? hasFullServiceBar,
  }) async {
    final fields = <String, dynamic>{
      'venue_id': venueId,
      'name': name,
      'kind': kind,
      'space_count': spaceCount,
      'capacity_per_space': capacityPerSpace,
      'area_square_feet': areaSquareFeet,
      'can_combine': canCombine,
      'combined_capacity': canCombine ? combinedCapacity : null,
      'has_full_service_bar': hasFullServiceBar,
    };
    if (id == null) {
      await _client.from('venue_banquet_areas').insert(fields);
    } else {
      await _client
          .from('venue_banquet_areas')
          .update(fields)
          .eq('id', id)
          .eq('venue_id', venueId);
    }
  }
}
