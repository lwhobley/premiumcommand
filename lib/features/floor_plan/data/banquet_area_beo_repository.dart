import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/session_controller.dart';

final banquetAreaBeoRepositoryProvider = Provider<BanquetAreaBeoRepository>((
  ref,
) {
  ref.watch(sessionProvider);
  return BanquetAreaBeoRepository(Supabase.instance.client);
});

final banquetAreaBeosProvider =
    FutureProvider.family<List<BanquetAreaBeoLink>, String>((ref, areaId) {
      return ref.watch(banquetAreaBeoRepositoryProvider).listForArea(areaId);
    });

class BanquetAreaBeoLink {
  const BanquetAreaBeoLink({
    required this.eventId,
    required this.eventName,
    required this.serviceStart,
    this.beoId,
    this.beoTitle,
  });

  final String eventId;
  final String eventName;
  final DateTime serviceStart;
  final String? beoId;
  final String? beoTitle;

  factory BanquetAreaBeoLink.fromJson(Map<String, dynamic> json) {
    final event = (json['events'] as Map).cast<String, dynamic>();
    final rawBeo = event['beo_documents'];
    final beo = rawBeo is Map ? rawBeo.cast<String, dynamic>() : null;
    return BanquetAreaBeoLink(
      eventId: event['id'] as String,
      eventName: event['name'] as String,
      serviceStart: DateTime.parse(event['service_start'] as String).toLocal(),
      beoId: beo?['id'] as String?,
      beoTitle: beo?['title'] as String?,
    );
  }
}

class BanquetAreaBeoRepository {
  BanquetAreaBeoRepository(this._client);

  final SupabaseClient _client;

  Future<List<BanquetAreaBeoLink>> listForArea(String areaId) async {
    final rows = await _client
        .from('event_banquet_areas')
        .select('events!inner(id,name,service_start,beo_documents(id,title))')
        .eq('banquet_area_id', areaId);
    final links = rows
        .cast<Map<String, dynamic>>()
        .map(BanquetAreaBeoLink.fromJson)
        .toList();
    links.sort((a, b) => a.serviceStart.compareTo(b.serviceStart));
    return links;
  }

  Future<void> linkEvent({
    required String venueId,
    required String areaId,
    required String eventId,
  }) async {
    await _client
        .from('event_banquet_areas')
        .upsert(
          {'venue_id': venueId, 'banquet_area_id': areaId, 'event_id': eventId},
          onConflict: 'event_id,banquet_area_id',
          ignoreDuplicates: true,
        );
  }

  Future<void> unlinkEvent({
    required String areaId,
    required String eventId,
  }) async {
    await _client
        .from('event_banquet_areas')
        .delete()
        .eq('banquet_area_id', areaId)
        .eq('event_id', eventId);
  }
}
