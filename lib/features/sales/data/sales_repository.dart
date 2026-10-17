import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/sales_package.dart';

/// Sales packages. Everyone at the venue can read them; the database allows changes only with
/// manage_sales, and records each change in the audit log.
class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;

  Future<List<SalesPackage>> list(String venueId) async {
    final rows = await _client
        .from('sales_packages')
        .select()
        .eq('venue_id', venueId)
        .order('sort_order');
    return rows
        .cast<Map<String, dynamic>>()
        .map(SalesPackage.fromJson)
        .toList();
  }

  Future<void> create(
    String venueId,
    SalesPackageDraft draft, {
    required int sortOrder,
  }) async {
    await _client.from('sales_packages').insert({
      ...draft.toColumns(),
      'venue_id': venueId,
      'sort_order': sortOrder,
    });
  }

  /// Saves only if nobody else changed the package since it was loaded.
  Future<void> update(SalesPackage package, SalesPackageDraft draft) async {
    final rows = await _client
        .from('sales_packages')
        .update({
          ...draft.toColumns(),
          'version': package.version + 1,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', package.id)
        .eq('version', package.version)
        .select('id');
    if (rows.isEmpty) {
      throw const AppFailure(
        'This package was changed by someone else, or you can no longer edit it. Refresh and try again.',
      );
    }
  }

  Future<void> delete(String packageId) async {
    await _client.from('sales_packages').delete().eq('id', packageId);
  }

  /// Swaps the display order of two packages, to move one up or down.
  Future<void> swapOrder(SalesPackage a, SalesPackage b) async {
    final aOrder = a.sortOrder;
    final bOrder = b.sortOrder == a.sortOrder ? a.sortOrder + 1 : b.sortOrder;
    await _client
        .from('sales_packages')
        .update({'sort_order': bOrder})
        .eq('id', a.id);
    await _client
        .from('sales_packages')
        .update({'sort_order': aOrder})
        .eq('id', b.id);
  }
}
