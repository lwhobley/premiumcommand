import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../application/guest_service_providers.dart';
import '../domain/guest_service.dart';

/// Opens a suite's preference card. Staff can read it; only those with request access can save.
Future<void> showGuestPreferenceSheet(
  BuildContext context, {
  required String venueId,
  required String eventId,
  required String suiteAssignmentId,
  required String suiteName,
  required bool canEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GuestPreferenceSheet(
      venueId: venueId,
      eventId: eventId,
      suiteAssignmentId: suiteAssignmentId,
      suiteName: suiteName,
      canEdit: canEdit,
    ),
  );
}

class _GuestPreferenceSheet extends ConsumerStatefulWidget {
  const _GuestPreferenceSheet({
    required this.venueId,
    required this.eventId,
    required this.suiteAssignmentId,
    required this.suiteName,
    required this.canEdit,
  });

  final String venueId;
  final String eventId;
  final String suiteAssignmentId;
  final String suiteName;
  final bool canEdit;

  @override
  ConsumerState<_GuestPreferenceSheet> createState() =>
      _GuestPreferenceSheetState();
}

class _GuestPreferenceSheetState extends ConsumerState<_GuestPreferenceSheet> {
  final _seating = TextEditingController();
  final _drink = TextEditingController();
  final _allergies = TextEditingController();
  final _notes = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  int _version = 0;
  String? _error;

  @override
  void dispose() {
    _seating.dispose();
    _drink.dispose();
    _allergies.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _fill(GuestPreferences card) {
    if (_loaded) return;
    _loaded = true;
    _version = card.version;
    _seating.text = card.seating;
    _drink.text = card.drink;
    _allergies.text = card.allergies;
    _notes.text = card.notes;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(guestServiceRepositoryProvider)
          .savePreferences(
            widget.venueId,
            widget.eventId,
            GuestPreferences(
              suiteAssignmentId: widget.suiteAssignmentId,
              seating: _seating.text,
              drink: _drink.text,
              allergies: _allergies.text,
              notes: _notes.text,
              version: _version,
            ),
          );
      ref.invalidate(guestPreferencesProvider(widget.suiteAssignmentId));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(guestPreferencesProvider(widget.suiteAssignmentId));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.screen,
          AppSpace.screen,
          AppSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + AppSpace.screen,
        ),
        child: card.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(userMessageFor(error), style: AppText.body),
          data: (prefs) {
            _fill(prefs);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preference card: ${widget.suiteName}',
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpace.m),
                  _field(
                    'Allergies and dietary (read before serving)',
                    _allergies,
                    enabled: widget.canEdit,
                  ),
                  _field('Seating', _seating, enabled: widget.canEdit),
                  _field('Drink', _drink, enabled: widget.canEdit),
                  _field('Notes', _notes, enabled: widget.canEdit, lines: 3),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpace.s),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.accent2700),
                    ),
                  ],
                  if (widget.canEdit) ...[
                    const SizedBox(height: AppSpace.m),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Save card'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required bool enabled,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
