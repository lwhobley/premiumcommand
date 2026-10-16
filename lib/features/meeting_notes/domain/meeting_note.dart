import '../../events/domain/readiness.dart';

enum MeetingNoteStatus {
  draft('draft', 'Draft'),
  analyzed('analyzed', 'Ready to review'),
  applied('applied', 'Applied'),
  dismissed('dismissed', 'Dismissed');

  const MeetingNoteStatus(this.code, this.label);

  final String code;
  final String label;

  static MeetingNoteStatus fromCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => MeetingNoteStatus.draft,
  );
}

enum MatchConfidence {
  high('high', 'High confidence'),
  medium('medium', 'Medium confidence'),
  low('low', 'Low confidence'),
  none('none', 'No match');

  const MatchConfidence(this.code, this.label);

  final String code;
  final String label;

  static MatchConfidence fromCode(String? code) => values.firstWhere(
    (c) => c.code == code,
    orElse: () => MatchConfidence.none,
  );
}

/// The kinds of change the assistant may propose. Codes match `apply_meeting_note`.
enum ProposedChangeType {
  updateEvent('update_event', 'Update event'),
  appendEventNotes('append_event_notes', 'Add to event notes'),
  addTask('add_task', 'Add task'),
  postAnnouncement('post_announcement', 'Post announcement'),
  addMenuItem('add_menu_item', 'Add menu item'),
  updateSuite('update_suite', 'Update suite');

  const ProposedChangeType(this.code, this.label);

  final String code;
  final String label;

  static ProposedChangeType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// The field holding the text a reviewer may edit before applying.
  String get textKey => switch (this) {
    updateEvent || updateSuite => 'value',
    appendEventNotes => 'text',
    addTask => 'title',
    postAnnouncement => 'body',
    addMenuItem => 'name',
  };
}

const _eventFieldLabels = {
  'name': 'Event name',
  'guaranteed_guests': 'Guaranteed guests',
  'manager_name': 'Manager',
  'service_start': 'Service start',
  'service_end': 'Service end',
};

const _suiteFieldLabels = {
  'dietary_notes': 'dietary notes',
  'special_instructions': 'special instructions',
  'guest_contact': 'guest contact',
};

/// One change proposed by the assistant, or applied from a note. [fields] is the payload sent
/// to `apply_meeting_note`; display-only values (current, suite_name) are kept beside it.
class ProposedChange {
  const ProposedChange({
    required this.type,
    required this.fields,
    this.reason = '',
    this.current,
    this.suiteName,
  });

  final ProposedChangeType type;
  final Map<String, Object?> fields;
  final String reason;

  /// The value this change replaces, for event and suite edits.
  final String? current;
  final String? suiteName;

  String get text => (fields[type.textKey] as String?) ?? '';

  /// Returns null for change types this version of the app does not know.
  static ProposedChange? fromJson(Map<String, dynamic> json) {
    final type = ProposedChangeType.fromCode(json['type'] as String?);
    if (type == null) return null;
    final fields = <String, Object?>{
      for (final entry in json.entries)
        if (!const {'reason', 'current', 'suite_name'}.contains(entry.key))
          entry.key: entry.value,
    };
    return ProposedChange(
      type: type,
      fields: fields,
      reason: (json['reason'] as String?) ?? '',
      current: json['current'] as String?,
      suiteName: json['suite_name'] as String?,
    );
  }

  /// The payload for `apply_meeting_note`. The reason and the replaced value ride along so the
  /// applied note shows them; the database ignores keys it does not use.
  Map<String, Object?> toApplyJson() => {
    ...fields,
    'type': type.code,
    'reason': reason,
    'current': ?current,
    'suite_name': ?suiteName,
  };

  /// When an added task is due, if the assistant set a deadline.
  DateTime? get dueAt => type == ProposedChangeType.addTask
      ? DateTime.tryParse((fields['due_at'] as String?) ?? '')
      : null;

  ProposedChange withText(String value) => ProposedChange(
    type: type,
    fields: {...fields, type.textKey: value},
    reason: reason,
    current: current,
    suiteName: suiteName,
  );

  /// A one-line description for review lists.
  String get title {
    switch (type) {
      case ProposedChangeType.updateEvent:
        return 'Change ${(_eventFieldLabels[fields['field']] ?? 'event').toLowerCase()}';
      case ProposedChangeType.appendEventNotes:
        return 'Add to event notes';
      case ProposedChangeType.addTask:
        final department = Department.fromCode(
          (fields['department'] as String?) ?? '',
        );
        final required = fields['is_required'] == true ? ', required' : '';
        return 'Add ${department.label} task$required';
      case ProposedChangeType.postAnnouncement:
        return 'Announce to rostered staff';
      case ProposedChangeType.addMenuItem:
        return 'Add menu item';
      case ProposedChangeType.updateSuite:
        final field = _suiteFieldLabels[fields['field']] ?? 'details';
        return '${suiteName ?? 'Suite'} $field';
    }
  }

  /// Extra context shown under the text, such as the menu course or the old value. A task's
  /// deadline is shown separately from [dueAt] so it can be written in venue time.
  String? get detail {
    switch (type) {
      case ProposedChangeType.updateEvent:
      case ProposedChangeType.updateSuite:
        final before = current ?? '';
        return before.isEmpty ? 'Currently empty' : 'Currently: $before';
      case ProposedChangeType.addTask:
      case ProposedChangeType.appendEventNotes:
      case ProposedChangeType.postAnnouncement:
        return null;
      case ProposedChangeType.addMenuItem:
        final parts = [
          if ((fields['course'] as String? ?? '').isNotEmpty)
            fields['course'] as String,
          ...((fields['dietary_tags'] as List?) ?? const []).cast<String>(),
          if ((fields['allergens'] as String? ?? '').isNotEmpty)
            'Allergens: ${fields['allergens']}',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
    }
  }
}

/// How the assistant chose the event.
class EventMatch {
  const EventMatch({
    required this.confidence,
    required this.reason,
    this.alternativeEventIds = const [],
    this.chosenByAdministrator = false,
  });

  final MatchConfidence confidence;
  final String reason;
  final List<String> alternativeEventIds;
  final bool chosenByAdministrator;

  factory EventMatch.fromJson(Map<String, dynamic> json) => EventMatch(
    confidence: MatchConfidence.fromCode(json['confidence'] as String?),
    reason: (json['reason'] as String?) ?? '',
    alternativeEventIds: ((json['alternative_event_ids'] as List?) ?? const [])
        .cast<String>(),
    chosenByAdministrator: json['chosen_by'] == 'administrator',
  );
}

/// The assistant's proposal for one note, written by the meeting-notes-ai Edge Function.
class NoteAnalysis {
  const NoteAnalysis({
    required this.eventId,
    required this.match,
    required this.summary,
    required this.keyDetails,
    required this.changes,
    this.analyzedAt,
  });

  final String? eventId;
  final EventMatch match;
  final String summary;
  final List<String> keyDetails;
  final List<ProposedChange> changes;
  final DateTime? analyzedAt;

  factory NoteAnalysis.fromJson(Map<String, dynamic> json) => NoteAnalysis(
    eventId: json['event_id'] as String?,
    match: EventMatch.fromJson(
      (json['match'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    summary: (json['summary'] as String?) ?? '',
    keyDetails: ((json['key_details'] as List?) ?? const []).cast<String>(),
    changes: _changesFrom(json['changes']),
    analyzedAt: json['analyzed_at'] == null
        ? null
        : DateTime.tryParse(json['analyzed_at'] as String)?.toLocal(),
  );
}

List<ProposedChange> _changesFrom(Object? value) => [
  for (final item in (value as List?) ?? const [])
    if (item is Map) ?ProposedChange.fromJson(item.cast<String, dynamic>()),
];

class MeetingNote {
  const MeetingNote({
    required this.id,
    required this.venueId,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.eventId,
    this.meetingAt,
    this.analysis,
    this.summary = '',
    this.keyDetails = const [],
    this.appliedChanges = const [],
    this.appliedAt,
  });

  final String id;
  final String venueId;
  final String? eventId;
  final String title;
  final String body;
  final DateTime? meetingAt;
  final MeetingNoteStatus status;
  final NoteAnalysis? analysis;
  final String summary;
  final List<String> keyDetails;
  final List<ProposedChange> appliedChanges;
  final DateTime? appliedAt;
  final DateTime createdAt;

  bool get isApplied => status == MeetingNoteStatus.applied;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    return firstLine.length > 60
        ? '${firstLine.substring(0, 57)}...'
        : firstLine;
  }

  factory MeetingNote.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => json[key] == null
        ? null
        : DateTime.parse(json[key] as String).toLocal();
    final analysis = json['analysis'];
    return MeetingNote(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      eventId: json['event_id'] as String?,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      meetingAt: time('meeting_at'),
      status: MeetingNoteStatus.fromCode(json['status'] as String),
      analysis: analysis is Map
          ? NoteAnalysis.fromJson(analysis.cast<String, dynamic>())
          : null,
      summary: (json['summary'] as String?) ?? '',
      keyDetails: ((json['key_details'] as List?) ?? const []).cast<String>(),
      appliedChanges: _changesFrom(json['applied_actions']),
      appliedAt: time('applied_at'),
      createdAt: time('created_at') ?? DateTime.now(),
    );
  }
}
