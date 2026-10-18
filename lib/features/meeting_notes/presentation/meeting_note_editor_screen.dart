import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/ops_event.dart';
import '../application/meeting_notes_providers.dart';
import '../domain/meeting_note.dart';
import 'meeting_notes_screen.dart';

const _maxBody = 20000;

/// Write a meeting note, let the assistant find its event and propose changes, review them,
/// and apply. Also works without the assistant: choose the event and write the summary.
class MeetingNoteEditorScreen extends ConsumerStatefulWidget {
  const MeetingNoteEditorScreen({super.key, this.noteId, this.initialEventId});

  final String? noteId;

  /// Set when the note is started from an event, so matching is skipped.
  final String? initialEventId;

  @override
  ConsumerState<MeetingNoteEditorScreen> createState() =>
      _MeetingNoteEditorScreenState();
}

class _MeetingNoteEditorScreenState
    extends ConsumerState<MeetingNoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _summary = TextEditingController();
  final _newDetail = TextEditingController();

  MeetingNote? _note;
  DateTime? _meetingAt;
  bool _loading = false;
  String? _loadError;
  String? _busy;

  // Review state, filled from the assistant's proposal and edited by the administrator.
  String? _eventId;
  String? _changesForEventId;
  EventMatch? _match;
  List<String> _keyDetails = [];
  List<ProposedChange> _changes = [];
  Set<int> _accepted = {};

  @override
  void initState() {
    super.initState();
    _eventId = widget.initialEventId;
    if (widget.noteId != null) _load(widget.noteId!);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _summary.dispose();
    _newDetail.dispose();
    super.dispose();
  }

  Future<void> _load(String noteId) async {
    setState(() => _loading = true);
    try {
      final note = await ref
          .read(meetingNotesRepositoryProvider)
          .getNote(noteId);
      if (!mounted) return;
      _title.text = note.title;
      _body.text = note.body;
      _meetingAt = note.meetingAt;
      _show(note);
    } catch (error) {
      _loadError = userMessageFor(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fills the review from the note: its applied record, or its latest proposal.
  void _show(MeetingNote note) {
    _note = note;
    if (note.isApplied) {
      _eventId = note.eventId;
      _summary.text = note.summary;
      _keyDetails = [...note.keyDetails];
      _changes = note.appliedChanges;
      return;
    }
    final analysis = note.analysis;
    if (analysis != null) {
      _applyAnalysis(analysis);
    } else {
      _eventId ??= note.eventId;
    }
  }

  void _applyAnalysis(NoteAnalysis analysis) {
    _match = analysis.match;
    _eventId = analysis.eventId ?? _eventId;
    _changesForEventId = analysis.eventId;
    _summary.text = analysis.summary;
    _keyDetails = [...analysis.keyDetails];
    _changes = analysis.changes;
    _accepted = {for (var i = 0; i < _changes.length; i++) i};
  }

  bool get _dirty {
    final note = _note;
    if (note == null) return _body.text.trim().isNotEmpty;
    return _title.text.trim() != note.title ||
        _body.text.trim() != note.body ||
        _meetingAt?.toUtc() != note.meetingAt?.toUtc();
  }

  Future<T?> _run<T>(String label, Future<T> Function() action) async {
    setState(() => _busy = label);
    try {
      return await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessageFor(error))));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Saves the note if it is new or edited. Editing clears an earlier proposal.
  Future<MeetingNote?> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return null;
    if (_body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write the meeting notes first.')),
      );
      return null;
    }
    if (!_dirty && _note != null) return _note;
    final repo = ref.read(meetingNotesRepositoryProvider);
    final saved = await _run('Saving…', () {
      final note = _note;
      return note == null
          ? repo.createNote(
              venueId: session.venueId,
              title: _title.text,
              body: _body.text,
              meetingAt: _meetingAt,
              eventId: widget.initialEventId,
            )
          : repo.updateNote(
              note.id,
              title: _title.text,
              body: _body.text,
              meetingAt: _meetingAt,
            );
    });
    if (saved == null || !mounted) return null;
    setState(() {
      _note = saved;
      // The text changed, so any earlier proposal no longer matches it.
      _match = null;
      _changes = [];
      _accepted = {};
      _changesForEventId = null;
    });
    ref.invalidate(meetingNotesProvider);
    return saved;
  }

  /// Asks the assistant. With [eventId] it proposes changes for that event without matching.
  Future<void> _analyze({String? eventId}) async {
    final note = await _save();
    if (note == null || !mounted) return;
    final chosen =
        eventId ??
        (_match == null && _changesForEventId == null
            ? widget.initialEventId
            : null);
    final analysis = await _run(
      'The assistant is reading the notes…',
      () => ref
          .read(meetingNotesRepositoryProvider)
          .analyze(note.id, eventId: chosen),
    );
    if (analysis == null || !mounted) return;
    setState(() => _applyAnalysis(analysis));
    ref.invalidate(meetingNotesProvider);
    if (analysis.eventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The assistant could not tell which event this is. Choose it below.',
          ),
        ),
      );
    }
  }

  Future<void> _apply(OpsEvent event) async {
    final note = await _save();
    if (note == null || !mounted) return;
    final changes = [
      for (var i = 0; i < _changes.length; i++)
        if (_accepted.contains(i) && _changesForEventId == event.id)
          _changes[i],
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply to event?'),
        content: Text(
          'This links the note to ${event.name}'
          '${changes.isEmpty ? ' without changing the event.' : ' and makes ${changes.length} '
                    '${changes.length == 1 ? 'change' : 'changes'}.'}'
          ' An applied note cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final applied = await _run(
      'Applying…',
      () => ref
          .read(meetingNotesRepositoryProvider)
          .apply(
            noteId: note.id,
            eventId: event.id,
            summary: _summary.text,
            keyDetails: _keyDetails,
            changes: changes,
          ),
    );
    if (applied == null || !mounted) return;
    setState(() => _show(applied));
    ref.invalidate(meetingNotesProvider);
    ref.invalidate(eventSnapshotsProvider);
    ref.invalidate(eventMeetingNotesProvider(event.id));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Applied to ${event.name}.')));
  }

  Future<void> _dismiss(bool dismissed) async {
    final note = _note;
    if (note == null) return;
    final repo = ref.read(meetingNotesRepositoryProvider);
    final done = await _run('Saving…', () async {
      await repo.setDismissed(note.id, dismissed);
      return repo.getNote(note.id);
    });
    if (done == null || !mounted) return;
    setState(() => _note = done);
    ref.invalidate(meetingNotesProvider);
  }

  Future<void> _delete() async {
    final note = _note;
    if (note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text(
          'The note and its suggestions are removed. The event is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await _run('Deleting…', () async {
      await ref.read(meetingNotesRepositoryProvider).deleteNote(note.id);
      return true;
    });
    if (done == true && mounted) {
      ref.invalidate(meetingNotesProvider);
      context.pop();
    }
  }

  Future<void> _pickMeetingDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _meetingAt ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null) return;
    setState(() => _meetingAt = DateTime(date.year, date.month, date.day, 12));
  }

  Future<void> _editChange(int index) async {
    final change = _changes[index];
    final controller = TextEditingController(text: change.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(change.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    setState(
      () => _changes = [..._changes]..[index] = change.withText(value.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final header = ScreenHeader(
      padded: false,
      back: const BackLink(),
      kicker: 'Meeting notes',
      title: note == null ? 'New meeting note' : note.displayTitle,
      actions: [
        if (note != null && !note.isApplied)
          PopupMenuButton<String>(
            icon: const PhosphorIcon(PhosphorIconsDuotone.dotsThree),
            onSelected: (value) => switch (value) {
              'dismiss' => _dismiss(true),
              'restore' => _dismiss(false),
              _ => _delete(),
            },
            itemBuilder: (context) => [
              if (note.status == MeetingNoteStatus.dismissed)
                const PopupMenuItem(value: 'restore', child: Text('Restore'))
              else
                const PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
      ],
    );
    final top = <Widget>[
      header,
      if (note != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Tag(note.status.label, meetingNoteStatusTone(note.status)),
        ),
        const SizedBox(height: AppSpace.l),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? _page([...top, const LinearProgressIndicator()])
            : _loadError != null
            ? _page([...top, Text(_loadError!)])
            : Column(
                children: [
                  if (_busy != null)
                    Material(
                      color: AppColors.accent100,
                      child: ListTile(
                        dense: true,
                        leading: const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text(_busy!),
                      ),
                    ),
                  Expanded(
                    child: note?.isApplied == true
                        ? _appliedView(note!, top)
                        : _editView(top),
                  ),
                ],
              ),
      ),
    );
  }

  /// The page's scroll view, flush left and at most 820 wide.
  Widget _page(List<Widget> children) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          0,
          AppSpace.screen,
          48,
        ),
        children: children,
      ),
    ),
  );

  String _venueTime(DateTime instant) {
    final zone = ref.read(sessionProvider)?.timeZone ?? 'UTC';
    return DateFormat('EEE MMM d, y · h:mm a').format(atVenue(instant, zone));
  }

  /// Event times are shown in venue time; everything else as written.
  String _displayText(ProposedChange change) {
    final field = change.fields['field'];
    if (change.type == ProposedChangeType.updateEvent &&
        (field == 'service_start' || field == 'service_end')) {
      final parsed = DateTime.tryParse(change.text);
      if (parsed != null) return _venueTime(parsed);
    }
    return change.text;
  }

  List<OpsEvent> _events() {
    final snapshots = ref.watch(eventSnapshotsProvider).value ?? const [];
    return [for (final s in snapshots) s.event];
  }

  Widget _editView(List<Widget> top) {
    final busy = _busy != null;
    final events = _events();
    final event = events.where((e) => e.id == _eventId).firstOrNull;
    final changesMatchEvent =
        _changesForEventId != null && _changesForEventId == _eventId;
    final match = _match;

    return _page([
      ...top,
      TextField(
        controller: _title,
        decoration: const InputDecoration(
          labelText: 'Title (optional)',
          hintText: 'Client walkthrough',
        ),
        maxLength: 200,
        onChanged: (_) => setState(() {}),
      ),
      Row(
        children: [
          const PhosphorIcon(PhosphorIconsDuotone.calendarBlank, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _meetingAt == null
                  ? 'Meeting date not set'
                  : 'Met on ${DateFormat('EEE MMM d, y').format(_meetingAt!)}',
            ),
          ),
          TextButton(
            onPressed: busy ? null : _pickMeetingDate,
            child: const Text('Set date'),
          ),
          if (_meetingAt != null)
            IconButton(
              tooltip: 'Clear date',
              onPressed: busy ? null : () => setState(() => _meetingAt = null),
              icon: const PhosphorIcon(PhosphorIconsDuotone.x),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _body,
        decoration: const InputDecoration(
          labelText: 'Meeting notes',
          hintText: 'Who met, what was agreed, numbers, times, dietary needs, follow-ups…',
          alignLabelWithHint: true,
        ),
        minLines: 8,
        maxLines: 24,
        maxLength: _maxBody,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: AppSpace.s,
        runSpacing: AppSpace.s,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => _analyze(),
            icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
            label: Text(
              _note?.analysis == null && _match == null
                  ? 'Find the event and suggest changes'
                  : 'Ask the assistant again',
            ),
          ),
          OutlinedButton(
            onPressed: busy || !_dirty ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      if (_dirty && _note?.analysis != null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Saving edits clears the current suggestions.',
            style: AppText.meta,
          ),
        ),
      if (_note != null) ...[
        const SectionHeading('Event'),
        if (match != null && !match.chosenByAdministrator) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tag(match.confidence.label, switch (match.confidence) {
                MatchConfidence.high => Tone.accent,
                _ => Tone.alert,
              }),
              const Text('Assistant match', style: AppText.meta),
            ],
          ),
          if (match.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(match.reason),
          ],
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey(_eventId),
          initialValue: event?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Apply to event'),
          items: [
            for (final e in events)
              DropdownMenuItem(
                value: e.id,
                child: Text(
                  '${e.name} · ${DateFormat('MMM d').format(atVenue(e.serviceStart, ref.read(sessionProvider)?.timeZone ?? 'UTC'))}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy ? null : (id) => setState(() => _eventId = id),
        ),
        if (match != null && match.alternativeEventIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Could also be:', style: AppText.meta),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in match.alternativeEventIds)
                if (events.where((e) => e.id == id).firstOrNull case final alt?)
                  ActionChip(
                    label: Text(alt.name),
                    onPressed: busy
                        ? null
                        : () => setState(() => _eventId = alt.id),
                  ),
            ],
          ),
        ],
        if (event != null &&
            _changesForEventId != null &&
            !changesMatchEvent) ...[
          const SizedBox(height: 12),
          const Text(
            'The suggested changes were for a different event.',
            style: TextStyle(color: AppColors.accent2700),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => _analyze(eventId: event.id),
              icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
              label: Text('Suggest changes for ${event.name}'),
            ),
          ),
        ] else if (event != null && _changesForEventId == null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => _analyze(eventId: event.id),
              icon: const PhosphorIcon(PhosphorIconsDuotone.sparkle),
              label: const Text('Suggest changes for this event'),
            ),
          ),
        ],
        const SectionHeading('Added to the event'),
        TextField(
          controller: _summary,
          decoration: const InputDecoration(
            labelText: 'Summary',
            hintText: 'What the meeting decided, in a few sentences',
            alignLabelWithHint: true,
          ),
          minLines: 2,
          maxLines: 8,
          maxLength: 4000,
        ),
        const SizedBox(height: 8),
        Text(
          'Key details',
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        for (var i = 0; i < _keyDetails.length; i++)
          Row(
            children: [
              const PhosphorIcon(PhosphorIconsDuotone.circle, size: 8),
              const SizedBox(width: 12),
              Expanded(child: Text(_keyDetails[i])),
              IconButton(
                tooltip: 'Remove',
                icon: const PhosphorIcon(PhosphorIconsDuotone.x),
                onPressed: () =>
                    setState(() => _keyDetails = [..._keyDetails]..removeAt(i)),
              ),
            ],
          ),
        TextField(
          controller: _newDetail,
          decoration: InputDecoration(
            hintText: 'Add a detail',
            suffixIcon: IconButton(
              tooltip: 'Add',
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              onPressed: _addDetail,
            ),
          ),
          onSubmitted: (_) => _addDetail(),
        ),
        const SectionHeading('Changes to make'),
        if (!changesMatchEvent || _changes.isEmpty)
          Text(
            !changesMatchEvent
                ? 'Ask the assistant for suggestions, or apply the note with just the summary.'
                : 'The assistant found nothing in these notes that should change the event.',
            style: AppText.meta,
          )
        else
          for (var i = 0; i < _changes.length; i++) _changeTile(i),
        const SizedBox(height: AppSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy || event == null ? null : () => _apply(event),
            icon: const PhosphorIcon(PhosphorIconsDuotone.check),
            label: Text(
              event == null
                  ? 'Choose an event to apply'
                  : changesMatchEvent && _accepted.isNotEmpty
                  ? 'Apply ${_accepted.length} ${_accepted.length == 1 ? 'change' : 'changes'} to event'
                  : 'Link note to event',
            ),
          ),
        ),
      ],
    ]);
  }

  void _addDetail() {
    final text = _newDetail.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _keyDetails = [..._keyDetails, text];
      _newDetail.clear();
    });
  }

  Widget _changeTile(int index) {
    final change = _changes[index];
    final accepted = _accepted.contains(index);
    final due = change.dueAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: accepted,
            onChanged: _busy != null
                ? null
                : (value) => setState(() {
                    _accepted = {..._accepted};
                    value == true
                        ? _accepted.add(index)
                        : _accepted.remove(index);
                  }),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(change.title, style: AppText.meta),
                  const SizedBox(height: 2),
                  Text(
                    _displayText(change),
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (change.detail case final detail?)
                    Text(detail, style: AppText.meta),
                  if (due != null)
                    Text('Due ${_venueTime(due)}', style: AppText.meta),
                  if (change.reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'From the notes: ${change.reason}',
                      style: AppText.meta.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: _busy != null ? null : () => _editChange(index),
            icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
          ),
        ],
      ),
    );
  }

  Widget _appliedView(MeetingNote note, List<Widget> top) {
    final event = _events().where((e) => e.id == note.eventId).firstOrNull;
    return _page([
      ...top,
      OpenRow(
        leading: const PhosphorIcon(
          PhosphorIconsDuotone.checkCircle,
          color: AppColors.accent700,
        ),
        title: event == null ? 'Applied' : 'Applied to ${event.name}',
        meta: note.appliedAt == null ? null : _venueTime(note.appliedAt!),
        trailing: event == null
            ? null
            : TextButton(
                onPressed: () => context.push('/events/${event.id}'),
                child: const Text('Open event'),
              ),
      ),
      if (note.summary.isNotEmpty) ...[
        const SectionHeading('Summary'),
        Text(note.summary, style: AppText.body),
      ],
      if (note.keyDetails.isNotEmpty) ...[
        const SectionHeading('Key details'),
        for (final detail in note.keyDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('•  $detail', style: AppText.body),
          ),
      ],
      const SectionHeading('Changes made'),
      if (note.appliedChanges.isEmpty)
        const Text(
          'None. The note was linked to the event only.',
          style: AppText.meta,
        )
      else
        for (final change in note.appliedChanges)
          OpenRow(title: _displayText(change), meta: change.title),
      const SizedBox(height: AppSpace.section),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Original notes'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(note.body),
          ),
        ],
      ),
    ]);
  }
}
