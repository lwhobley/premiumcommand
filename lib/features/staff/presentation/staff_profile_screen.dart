import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../application/staff_providers.dart';
import '../domain/staff_profile.dart';
import 'staff_form_dialog.dart';

/// A staff member's profile. Pass [profileId] to open a specific person (administrators), or
/// leave it null to open the signed-in user's own profile. Staff see their own profile read-only.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key, this.profileId});

  final String? profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final staff = ref.watch(staffListProvider(session.venueId));

    return Scaffold(
      appBar: AppBar(title: const Text('Staff profile')),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Note(text: userMessageFor(error)),
        data: (all) {
          final StaffProfile? profile = profileId == null
              ? all.where((p) => p.userId == session.userId).firstOrNull
              : all.where((p) => p.id == profileId).firstOrNull;
          if (profile == null) {
            return _Note(
              text: profileId == null
                  ? 'Your account has no staff profile. Contact your administrator.'
                  : 'That staff profile was not found or you cannot view it.',
            );
          }
          final canManage = session.can(AppPermission.manageConfiguration);
          return _ProfileView(
            profile: profile,
            canManage: canManage,
            isSelf: profile.userId == session.userId,
          );
        },
      ),
    );
  }
}

class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({
    required this.profile,
    required this.canManage,
    required this.isSelf,
  });

  final StaffProfile profile;
  final bool canManage;
  final bool isSelf;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  bool _busy = false;

  StaffProfile get profile => widget.profile;
  String get _venueId => profile.venueId;

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(staffListProvider(_venueId));
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final value = await showStaffFormDialog(context, existing: profile);
    if (value == null) return;
    await _run(
      () => ref
          .read(staffRepositoryProvider)
          .updateDetails(profile, value.fields),
      success: 'Staff details saved.',
    );
  }

  Future<void> _changePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run(
      () => ref
          .read(staffRepositoryProvider)
          .uploadPhoto(_venueId, profile.id, bytes),
      success: 'Photo updated.',
    );
  }

  Future<void> _resetPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (pin == null || !mounted) return;
    await _run(
      () => ref.read(staffRepositoryProvider).setPin(profile.id, pin),
      success:
          'PIN changed. Any lockout is cleared. Give the new PIN to ${profile.fullName}.',
    );
  }

  Future<void> _setActive(bool active) async {
    final ok = await _confirm(
      title: active
          ? 'Reactivate ${profile.fullName}?'
          : 'Deactivate ${profile.fullName}?',
      body: active ? 'They will be able to sign in with their PIN again.' : 'They lose access immediately and cannot sign in until reactivated.',
      action: active ? 'Reactivate' : 'Deactivate',
    );
    if (!ok) return;
    await _run(
      () => ref.read(staffRepositoryProvider).setActive(profile.id, active),
      success: active ? 'Account reactivated.' : 'Account deactivated.',
    );
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final ok = await _confirm(
      title: 'Remove ${profile.fullName}?',
      body: 'This deletes their profile, PIN, and sign-in. Past audit records remain.',
      action: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).remove(profile.id);
      ref.invalidate(staffListProvider(_venueId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Staff member removed.')),
      );
      if (router.canPop()) router.pop();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.blocked)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = profile.photoPath;
    final photo = photoPath == null
        ? null
        : ref.watch(staffPhotoUrlProvider(photoPath));
    final dateFormat = DateFormat.yMMMd();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: photo?.hasValue == true
                    ? NetworkImage(photo!.value!)
                    : null,
                child: photo?.hasValue == true
                    ? null
                    : Text(
                        profile.initials,
                        style: const TextStyle(fontSize: 28),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.fullName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              StatusChip(
                label: profile.status.label,
                color: profile.isActive ? AppColors.ready : AppColors.neutral,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Employee',
          rows: [
            ('Employee ID', profile.employeeId),
            ('Job title', profile.jobTitle.isEmpty ? '—' : profile.jobTitle),
            ('Department', profile.department.label),
            (
              'Start date',
              profile.startDate == null
                  ? '—'
                  : dateFormat.format(profile.startDate!),
            ),
          ],
        ),
        _Section(
          title: 'Contact',
          rows: [
            (
              'Email',
              profile.contactEmail.isEmpty ? '—' : profile.contactEmail,
            ),
            (
              'Phone',
              profile.contactPhone.isEmpty ? '—' : profile.contactPhone,
            ),
          ],
        ),
        _Section(
          title: 'Emergency contact',
          rows: [
            (
              'Name',
              profile.emergencyContactName.isEmpty
                  ? '—'
                  : profile.emergencyContactName,
            ),
            (
              'Phone',
              profile.emergencyContactPhone.isEmpty
                  ? '—'
                  : profile.emergencyContactPhone,
            ),
          ],
        ),
        if (widget.canManage) ...[
          const SizedBox(height: 16),
          Text(
            'Administrator actions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit details'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _changePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Change photo'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _resetPin,
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Reset PIN'),
              ),
              if (!widget.isSelf) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _setActive(!profile.isActive),
                  icon: Icon(
                    profile.isActive ? Icons.block : Icons.check_circle_outline,
                  ),
                  label: Text(profile.isActive ? 'Deactivate' : 'Reactivate'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blocked,
                  ),
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Roles are changed under Administration & Configuration › People.',
            style: TextStyle(fontSize: 12, color: AppColors.charcoalMuted),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Only administrators can change these details. Ask your administrator if something is wrong.',
              style: TextStyle(fontSize: 12, color: AppColors.charcoalMuted),
            ),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        label,
                        style: const TextStyle(color: AppColors.charcoalMuted),
                      ),
                    ),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Enters a new PIN or generates one for the administrator to hand over.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _save() {
    if (!isValidPin(_pin.text)) {
      return setState(
        () => _error =
            'PIN must be 4 digits and not an obvious pattern such as 1234.',
      );
    }
    Navigator.of(context).pop(_pin.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: 'New PIN (4 digits)',
              suffixIcon: IconButton(
                tooltip: 'Generate a PIN',
                icon: const Icon(Icons.autorenew),
                onPressed: () =>
                    setState(() => _pin.text = generatePin(Random.secure())),
              ),
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.blocked)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Set PIN')),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
