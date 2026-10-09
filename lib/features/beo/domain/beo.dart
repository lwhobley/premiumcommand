import '../../events/domain/readiness.dart';

/// Structured BEO content. Stored as JSON on each immutable revision.
class BeoContent {
  const BeoContent({
    required this.guests,
    required this.departments,
    required this.timeline,
    required this.menu,
    required this.dietary,
    required this.beverage,
    required this.equipment,
    required this.specialRequests,
  });

  final int guests;
  final Set<Department> departments;
  final String timeline;
  final String menu;
  final String dietary;
  final String beverage;
  final String equipment;
  final String specialRequests;

  Map<String, dynamic> toJson() => {
        'guests': guests,
        'departments': [for (final d in departments) d.code],
        'timeline': timeline,
        'menu': menu,
        'dietary': dietary,
        'beverage': beverage,
        'equipment': equipment,
        'special_requests': specialRequests,
      };

  factory BeoContent.fromJson(Map<String, dynamic> json) {
    final codes = (json['departments'] as List?)?.cast<String>() ?? const <String>[];
    return BeoContent(
      guests: (json['guests'] as num?)?.toInt() ?? 0,
      departments: {
        for (final code in codes)
          if (Department.values.any((d) => d.code == code)) Department.fromCode(code),
      },
      timeline: (json['timeline'] as String?) ?? '',
      menu: (json['menu'] as String?) ?? '',
      dietary: (json['dietary'] as String?) ?? '',
      beverage: (json['beverage'] as String?) ?? '',
      equipment: (json['equipment'] as String?) ?? '',
      specialRequests: (json['special_requests'] as String?) ?? '',
    );
  }
}

enum RevisionStatus {
  draft('draft', 'Awaiting approval'),
  approved('approved', 'Approved'),
  superseded('superseded', 'Superseded');

  const RevisionStatus(this.code, this.label);

  final String code;
  final String label;

  static RevisionStatus fromCode(String code) => values.firstWhere((s) => s.code == code);
}

class BeoRevision {
  const BeoRevision({
    required this.id,
    required this.beoId,
    required this.revisionNo,
    required this.status,
    required this.content,
    required this.summary,
    required this.createdAt,
  });

  final String id;
  final String beoId;
  final int revisionNo;
  final RevisionStatus status;
  final BeoContent content;
  final String summary;
  final DateTime createdAt;

  factory BeoRevision.fromJson(Map<String, dynamic> json) {
    return BeoRevision(
      id: json['id'] as String,
      beoId: json['beo_id'] as String,
      revisionNo: (json['revision_no'] as num).toInt(),
      status: RevisionStatus.fromCode(json['status'] as String),
      content: BeoContent.fromJson((json['content'] as Map).cast<String, dynamic>()),
      summary: (json['summary'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
