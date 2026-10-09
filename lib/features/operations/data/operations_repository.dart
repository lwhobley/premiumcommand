import 'package:supabase_flutter/supabase_flutter.dart';

import '../../events/domain/readiness.dart';
import '../domain/operations.dart';

class OperationsRepository {
  OperationsRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  // ---- Banquet timeline ---------------------------------------------------

  Future<List<TimelineItem>> listTimeline(String eventId) async {
    final rows = await _client
        .from('banquet_timeline_items')
        .select()
        .eq('event_id', eventId)
        .order('scheduled_start');
    return rows.cast<Map<String, dynamic>>().map(TimelineItem.fromJson).toList();
  }

  Future<void> addTimelineItem({
    required String venueId,
    required String eventId,
    required String title,
    required Department department,
    required String assignee,
    required DateTime scheduledStart,
    DateTime? target,
    String? dependsOn,
  }) async {
    await _client.from('banquet_timeline_items').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'title': title,
      'department': department.code,
      'assignee_name': assignee,
      'scheduled_start': scheduledStart.toUtc().toIso8601String(),
      'target_completion': target?.toUtc().toIso8601String(),
      'depends_on': dependsOn,
    });
  }

  Future<TimelineItem> setTimelineStatus(TimelineItem item, TimelineStatus to, {String note = ''}) async {
    final row = await _client.rpc<Map<String, dynamic>>('update_timeline_item', params: {
      'p_item': item.id,
      'p_status': to.code,
      'p_expected_version': item.version,
      'p_note': note,
    });
    return TimelineItem.fromJson(row);
  }

  // ---- Culinary -------------------------------------------------------------

  Future<List<MenuItem>> listMenu(String eventId) async {
    final rows = await _client.from('event_menu_items').select().eq('event_id', eventId).order('course');
    return rows.cast<Map<String, dynamic>>().map(MenuItem.fromJson).toList();
  }

  Future<void> addMenuItem({
    required String venueId,
    required String eventId,
    required String name,
    required String course,
    required String allergens,
    required List<String> dietaryTags,
  }) async {
    await _client.from('event_menu_items').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'name': name,
      'course': course,
      'allergens': allergens,
      'dietary_tags': dietaryTags,
    });
  }

  Future<List<CulinaryBatch>> listBatches(String eventId) async {
    final rows = await _client
        .from('culinary_batches')
        .select()
        .eq('event_id', eventId)
        .order('created_at');
    return rows.cast<Map<String, dynamic>>().map(CulinaryBatch.fromJson).toList();
  }

  Future<void> createBatch({
    required String venueId,
    required String eventId,
    required String description,
    required int quantity,
    required String destination,
    DateTime? dueAt,
  }) async {
    await _client.from('culinary_batches').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'description': description,
      'quantity': quantity,
      'destination': destination,
      'due_at': dueAt?.toUtc().toIso8601String(),
    });
  }

  Future<CulinaryBatch> advanceBatch(CulinaryBatch batch, BatchState to, {String receiver = ''}) async {
    final row = await _client.rpc<Map<String, dynamic>>('advance_culinary_batch', params: {
      'p_batch': batch.id,
      'p_to': to.code,
      'p_expected_version': batch.version,
      'p_receiver': receiver,
    });
    return CulinaryBatch.fromJson(row);
  }

  // ---- Inspections ----------------------------------------------------------

  Future<List<ChecklistTemplate>> listTemplates() async {
    final rows = (await _client
            .from('checklist_templates')
            .select('id, category, name, checklist_items(id, label, response_type, requires_manager_approval, department, position)')
            .order('name'))
        .cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        ChecklistTemplate(
          id: r['id'] as String,
          category: r['category'] as String,
          name: r['name'] as String,
          items: ((r['checklist_items'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ChecklistItem.fromJson)
              .toList()
            ..sort((a, b) => a.label.compareTo(b.label)),
        ),
    ];
  }

  Future<List<InspectionInstance>> listInspections(String eventId) async {
    final rows = await _client.from('inspection_instances').select().eq('event_id', eventId).order('created_at');
    return rows.cast<Map<String, dynamic>>().map(InspectionInstance.fromJson).toList();
  }

  Future<void> createInspection({
    required String venueId,
    required String eventId,
    required String templateId,
    required String subject,
  }) async {
    await _client.from('inspection_instances').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'template_id': templateId,
      'subject': subject,
    });
  }

  /// Each response: item_id, passed, optional numeric_value, text_value.
  Future<int> completeInspection(String instanceId, List<Map<String, dynamic>> responses) async {
    return _client.rpc<int>('complete_inspection', params: {
      'p_instance': instanceId,
      'p_responses': responses,
    });
  }

  Future<void> approveInspection(String instanceId) async {
    await _client.rpc<Map<String, dynamic>>('approve_inspection', params: {'p_instance': instanceId});
  }

  // ---- Communications -------------------------------------------------------

  Future<List<Map<String, dynamic>>> listAnnouncements(String eventId) async {
    final rows = await _client
        .from('event_announcements')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> postAnnouncement({required String venueId, required String eventId, required String body}) async {
    await _client.from('event_announcements').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'body': body,
      'author_id': _userId,
    });
  }

  Future<List<AppNotification>> listNotifications() async {
    final rows = await _client.from('notifications').select().order('created_at', ascending: false).limit(50);
    return rows.cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList();
  }

  Future<void> markNotificationRead(String id) async {
    await _client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> reportIncident({required String eventId, required String kind, required String description}) async {
    await _client.rpc<Map<String, dynamic>>('report_incident', params: {
      'p_event': eventId,
      'p_kind': kind,
      'p_description': description,
    });
  }

  // ---- Closeout -------------------------------------------------------------

  Future<Closeout?> loadCloseout(String eventId) async {
    final row = await _client.from('event_closeouts').select().eq('event_id', eventId).maybeSingle();
    return row == null ? null : Closeout.fromJson(row);
  }

  Future<List<Closeout>> listCloseouts() async {
    final rows = await _client.from('event_closeouts').select().order('submitted_at', ascending: false);
    return rows.cast<Map<String, dynamic>>().map(Closeout.fromJson).toList();
  }

  Future<void> startCloseout(String eventId) async {
    await _client.rpc<Map<String, dynamic>>('start_event_closeout', params: {'p_event': eventId});
  }

  /// [step] is one of: submit, manager, director.
  Future<void> signCloseout(String eventId, String step) async {
    await _client.rpc<Map<String, dynamic>>('sign_event_closeout', params: {
      'p_event': eventId,
      'p_role': step,
    });
  }
}
