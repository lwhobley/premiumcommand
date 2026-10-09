import 'package:supabase_flutter/supabase_flutter.dart';

import '../../beo/domain/beo.dart';
import '../../events/domain/readiness.dart';
import '../../staffing/domain/staffing.dart';
import '../../suites/domain/suite.dart';

/// Everything about one event's BEO: the document, every revision, and who has acknowledged the current one.
class BeoBundle {
  const BeoBundle({
    required this.beoId,
    required this.title,
    required this.revisions,
    required this.currentRevisionId,
    required this.acknowledgedDepartments,
  });

  final String beoId;
  final String title;
  final List<BeoRevision> revisions;
  final String? currentRevisionId;
  final Set<String> acknowledgedDepartments;

  BeoRevision? get latest => revisions.isEmpty ? null : revisions.first;

  BeoRevision? get approved {
    for (final r in revisions) {
      if (r.status == RevisionStatus.approved) return r;
    }
    return null;
  }
}

/// Backend-only repository for suites, staffing, briefings, and BEOs. Writes use database functions where
/// the rules matter (state changes, revisions, approvals, acknowledgments).
class PlanningRepository {
  PlanningRepository(this._client);

  final SupabaseClient _client;

  // ---- Tasks ---------------------------------------------------------------

  Future<int> generateTasks(String eventId) async {
    final result = await _client.rpc<int>('generate_event_tasks', params: {'p_event': eventId});
    return result;
  }

  // ---- Suites --------------------------------------------------------------

  Future<List<SuiteAssignment>> listSuites(String eventId) async {
    final rows = await _client
        .from('suite_event_assignments')
        .select('*, venue_suites(name, location, service_zone)')
        .eq('event_id', eventId)
        .order('created_at');
    return rows.cast<Map<String, dynamic>>().map(SuiteAssignment.fromJson).toList();
  }

  /// Configuration write. Row-level security allows this only with manage_configuration.
  Future<void> addVenueSuite({
    required String venueId,
    required String name,
    required String location,
    required String serviceZone,
    int? capacity,
  }) async {
    await _client.from('venue_suites').insert({
      'venue_id': venueId,
      'name': name,
      'location': location,
      'service_zone': serviceZone,
      'capacity': capacity,
    });
  }

  Future<List<Map<String, dynamic>>> listVenueSuites(String venueId) async {
    final rows = await _client.from('venue_suites').select('id, name').eq('venue_id', venueId).order('name');
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> assignSuite({required String venueId, required String eventId, required String suiteId}) async {
    await _client.from('suite_event_assignments').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'suite_id': suiteId,
    });
  }

  Future<SuiteAssignment> setSuiteState(String assignmentId, SuiteState to, int expectedVersion) async {
    final row = await _client.rpc<Map<String, dynamic>>('set_suite_state', params: {
      'p_assignment': assignmentId,
      'p_to': to.code,
      'p_expected_version': expectedVersion,
    });
    return SuiteAssignment.fromJson({...row, 'venue_suites': null});
  }

  Future<void> updateSuiteDetails(String assignmentId, {
    required String attendantName,
    required String runnerName,
    required String guestContact,
    required String dietaryNotes,
    required String specialInstructions,
  }) async {
    await _client.from('suite_event_assignments').update({
      'attendant_name': attendantName,
      'runner_name': runnerName,
      'guest_contact': guestContact,
      'dietary_notes': dietaryNotes,
      'special_instructions': specialInstructions,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  // ---- Staffing ------------------------------------------------------------

  Future<List<StaffPosition>> listStaff(String eventId) async {
    final rows = await _client.from('event_staff').select().eq('event_id', eventId).order('created_at');
    return rows.cast<Map<String, dynamic>>().map(StaffPosition.fromJson).toList();
  }

  Future<void> addStaff({
    required String venueId,
    required String eventId,
    required String displayName,
    required String roleLabel,
    required Department department,
    required String zone,
    required String station,
    String? suiteAssignmentId,
  }) async {
    await _client.from('event_staff').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'display_name': displayName,
      'role_label': roleLabel,
      'department': department.code,
      'zone': zone,
      'station': station,
      'suite_assignment_id': suiteAssignmentId,
    });
  }

  Future<void> importRoster({
    required String venueId,
    required String eventId,
    required List<RosterRow> rows,
  }) async {
    if (rows.isEmpty) return;
    await _client.from('event_staff').insert([
      for (final r in rows)
        {
          'venue_id': venueId,
          'event_id': eventId,
          'display_name': r.displayName,
          'role_label': r.roleLabel,
          'department': r.department.code,
          'zone': r.zone,
          'station': r.station,
        },
    ]);
  }

  Future<void> reassignStaff(String staffId, {required String displayName, String? suiteAssignmentId}) async {
    await _client.from('event_staff').update({
      'display_name': displayName,
      'suite_assignment_id': suiteAssignmentId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', staffId);
  }

  // ---- Briefings -----------------------------------------------------------

  Future<List<Briefing>> listBriefings(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    final briefings = (await _client
            .from('event_briefings')
            .select()
            .eq('event_id', eventId)
            .order('created_at', ascending: false))
        .cast<Map<String, dynamic>>();
    final acks = (await _client
            .from('briefing_acknowledgments')
            .select('briefing_id')
            .eq('user_id', userId ?? ''))
        .cast<Map<String, dynamic>>();
    final acked = {for (final a in acks) a['briefing_id'] as String};

    return [
      for (final b in briefings)
        Briefing(
          id: b['id'] as String,
          eventId: b['event_id'] as String,
          title: b['title'] as String,
          body: (b['body'] as String?) ?? '',
          createdAt: DateTime.parse(b['created_at'] as String).toLocal(),
          acknowledgedByMe: acked.contains(b['id']),
        ),
    ];
  }

  Future<void> createBriefing({required String venueId, required String eventId, required String title, required String body}) async {
    await _client.from('event_briefings').insert({
      'venue_id': venueId,
      'event_id': eventId,
      'title': title,
      'body': body,
    });
  }

  Future<void> acknowledgeBriefing({required String venueId, required String briefingId}) async {
    await _client.from('briefing_acknowledgments').upsert({
      'briefing_id': briefingId,
      'venue_id': venueId,
    }, onConflict: 'briefing_id,user_id', ignoreDuplicates: true);
  }

  // ---- BEO -----------------------------------------------------------------

  Future<BeoBundle?> loadBeo(String eventId) async {
    final doc = await _client.from('beo_documents').select().eq('event_id', eventId).maybeSingle();
    if (doc == null) return null;
    final beoId = doc['id'] as String;
    final revisions = (await _client
            .from('beo_revisions')
            .select()
            .eq('beo_id', beoId)
            .order('revision_no', ascending: false))
        .cast<Map<String, dynamic>>()
        .map(BeoRevision.fromJson)
        .toList();

    final currentId = doc['current_revision_id'] as String?;
    final acks = currentId == null
        ? const <Map<String, dynamic>>[]
        : (await _client.from('beo_acknowledgments').select('department').eq('revision_id', currentId))
            .cast<Map<String, dynamic>>();

    return BeoBundle(
      beoId: beoId,
      title: doc['title'] as String,
      revisions: revisions,
      currentRevisionId: currentId,
      acknowledgedDepartments: {for (final a in acks) a['department'] as String},
    );
  }

  Future<void> createBeo({
    required String eventId,
    required String title,
    required BeoContent content,
    required String summary,
  }) async {
    await _client.rpc<Map<String, dynamic>>('create_beo', params: {
      'p_event': eventId,
      'p_title': title,
      'p_content': content.toJson(),
      'p_summary': summary,
    });
  }

  Future<void> proposeRevision({
    required String beoId,
    required BeoContent content,
    required String summary,
    required int expectedRevision,
  }) async {
    await _client.rpc<Map<String, dynamic>>('propose_beo_revision', params: {
      'p_beo': beoId,
      'p_content': content.toJson(),
      'p_summary': summary,
      'p_expected_revision': expectedRevision,
    });
  }

  Future<void> approveRevision(String revisionId) async {
    await _client.rpc<Map<String, dynamic>>('approve_beo_revision', params: {'p_revision': revisionId});
  }

  Future<void> acknowledgeRevision(String revisionId, String department) async {
    await _client.rpc<bool>('acknowledge_beo_revision', params: {
      'p_revision': revisionId,
      'p_department': department,
    });
  }
}
