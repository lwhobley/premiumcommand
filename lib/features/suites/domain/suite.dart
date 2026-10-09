/// Suite states: Not Started → Setup In Progress → Ready → Occupied (In Service) → Closing → Closed.
enum SuiteState {
  notStarted('not_started', 'Not started'),
  setupInProgress('setup_in_progress', 'Setup in progress'),
  ready('ready', 'Ready'),
  inService('in_service', 'In service'),
  closing('closing', 'Closing'),
  closed('closed', 'Closed');

  const SuiteState(this.code, this.label);

  final String code;
  final String label;

  static SuiteState fromCode(String code) => values.firstWhere((s) => s.code == code);

  /// The only state a suite may move to next. Null once closed.
  SuiteState? get next => index + 1 < values.length ? values[index + 1] : null;

  /// True once setup is complete and the suite can receive guests or service.
  bool get isReadyOrBeyond => index >= SuiteState.ready.index;
}

class SuiteAssignment {
  const SuiteAssignment({
    required this.id,
    required this.eventId,
    required this.suiteId,
    required this.suiteName,
    required this.location,
    required this.serviceZone,
    required this.state,
    required this.version,
    this.attendantName = '',
    this.runnerName = '',
    this.guestContact = '',
    this.dietaryNotes = '',
    this.specialInstructions = '',
  });

  final String id;
  final String eventId;
  final String suiteId;
  final String suiteName;
  final String location;
  final String serviceZone;
  final SuiteState state;
  final int version;
  final String attendantName;
  final String runnerName;
  final String guestContact;
  final String dietaryNotes;
  final String specialInstructions;

  factory SuiteAssignment.fromJson(Map<String, dynamic> json) {
    final suite = (json['venue_suites'] as Map<String, dynamic>?) ?? const {};
    return SuiteAssignment(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      suiteId: json['suite_id'] as String,
      suiteName: (suite['name'] as String?) ?? 'Suite',
      location: (suite['location'] as String?) ?? '',
      serviceZone: (suite['service_zone'] as String?) ?? '',
      state: SuiteState.fromCode(json['state'] as String),
      version: (json['version'] as num).toInt(),
      attendantName: (json['attendant_name'] as String?) ?? '',
      runnerName: (json['runner_name'] as String?) ?? '',
      guestContact: (json['guest_contact'] as String?) ?? '',
      dietaryNotes: (json['dietary_notes'] as String?) ?? '',
      specialInstructions: (json['special_instructions'] as String?) ?? '',
    );
  }
}

/// Counts suites by readiness for the dashboard header.
({int total, int ready, int notStarted}) suiteSummary(List<SuiteAssignment> suites) {
  return (
    total: suites.length,
    ready: suites.where((s) => s.state.isReadyOrBeyond && s.state != SuiteState.closed).length,
    notStarted: suites.where((s) => s.state == SuiteState.notStarted).length,
  );
}
