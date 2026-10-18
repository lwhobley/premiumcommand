import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../events/domain/readiness.dart';
import '../domain/staff_profile.dart';

/// What the form returns. [roles] and [pin] are set only when adding a staff member.
typedef StaffFormValue = ({
  Map<String, Object?> fields,
  List<String> roles,
  String? pin,
});

/// Roles an administrator can give a staff member. These don't unlock Administration,
/// Event Closeout & Reports, or Banquets & Culinary. Managers keep those roles under People.
final staffAssignableRoles = [
  AppRole.suiteAttendant,
  AppRole.runner,
  AppRole.beverageLead,
];

/// Add or edit one staff member. Returns null when cancelled or when the form is invalid.
Future<StaffFormValue?> showStaffFormDialog(
  BuildContext context, {
  StaffProfile? existing,
}) {
  return showDialog<StaffFormValue>(
    context: context,
    builder: (_) => _StaffFormDialog(existing: existing),
  );
}

class _StaffFormDialog extends StatefulWidget {
  const _StaffFormDialog({this.existing});

  final StaffProfile? existing;

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  late final _employeeId = TextEditingController(
    text: widget.existing?.employeeId ?? '',
  );
  late final _fullName = TextEditingController(
    text: widget.existing?.fullName ?? '',
  );
  late final _jobTitle = TextEditingController(
    text: widget.existing?.jobTitle ?? '',
  );
  late final _email = TextEditingController(
    text: widget.existing?.contactEmail ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.existing?.contactPhone ?? '',
  );
  late final _emergencyName = TextEditingController(
    text: widget.existing?.emergencyContactName ?? '',
  );
  late final _emergencyPhone = TextEditingController(
    text: widget.existing?.emergencyContactPhone ?? '',
  );
  late final _pin = TextEditingController();
  late Department _department =
      widget.existing?.department ?? Department.operations;
  late DateTime? _startDate = widget.existing?.startDate;
  final Set<AppRole> _roles = {};
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [
      _employeeId,
      _fullName,
      _jobTitle,
      _email,
      _phone,
      _emergencyName,
      _emergencyPhone,
      _pin,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final problem = validateStaffFields(
      employeeId: _employeeId.text,
      fullName: _fullName.text,
      jobTitle: _jobTitle.text,
      contactEmail: _email.text,
      contactPhone: _phone.text,
      emergencyContactName: _emergencyName.text,
      emergencyContactPhone: _emergencyPhone.text,
    );
    if (problem != null) return setState(() => _error = problem);
    if (_isNew) {
      if (_roles.isEmpty) {
        return setState(
          () => _error =
              'Choose at least one role so the staff member can use the app.',
        );
      }
      if (!isValidPin(_pin.text)) {
        return setState(
          () => _error =
              'PIN must be 4 digits and not an obvious pattern such as 1234.',
        );
      }
    }
    Navigator.of(context).pop<StaffFormValue>((
      fields: staffFieldsJson(
        employeeId: _employeeId.text,
        fullName: _fullName.text,
        jobTitle: _jobTitle.text,
        department: _department,
        contactEmail: _email.text,
        contactPhone: _phone.text,
        emergencyContactName: _emergencyName.text,
        emergencyContactPhone: _emergencyPhone.text,
        startDate: _startDate,
      ),
      roles: [for (final r in _roles) r.code],
      pin: _isNew ? _pin.text : null,
    ));
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add staff member' : 'Edit staff details'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _employeeId,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Employee ID',
                  helperText:
                      'Shown on the profile. Staff sign in with a PIN only.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _jobTitle,
                decoration: const InputDecoration(labelText: 'Job title'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Department>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  for (final d in Department.values)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (value) =>
                    setState(() => _department = value ?? _department),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _startDate == null
                          ? 'No start date'
                          : 'Starts ${DateFormat.yMMMd().format(_startDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: _pickStartDate,
                    child: const Text('Set start date'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Contact email (optional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact phone'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emergencyName,
                decoration: const InputDecoration(
                  labelText: 'Emergency contact name',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emergencyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Emergency contact phone',
                ),
              ),
              if (_isNew) ...[
                const SizedBox(height: 16),
                Text('Roles', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final role in staffAssignableRoles)
                      FilterChip(
                        label: Text(role.label),
                        selected: _roles.contains(role),
                        onSelected: (on) => setState(() {
                          on ? _roles.add(role) : _roles.remove(role);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: 'PIN (4 digits)',
                    helperText: 'Must be unique across all staff. Shown once after saving.',
                    suffixIcon: IconButton(
                      tooltip: 'Generate a PIN',
                      icon: const PhosphorIcon(
                        PhosphorIconsDuotone.arrowsClockwise,
                      ),
                      onPressed: () =>
                          setState(() => _pin.text = generatePin()),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.accent2700),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isNew ? 'Add staff member' : 'Save'),
        ),
      ],
    );
  }
}
