import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../application/session_controller.dart';

enum _SignInMode { staffPin, adminEmail }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _pin = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _SignInMode _mode = _SignInMode.staffPin;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Explain an automatic sign-out (inactivity or the 12-hour limit) on the next screen.
    _error = ref.read(sessionProvider.notifier).takeEndedNotice();
  }

  @override
  void dispose() {
    for (final c in [_pin, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(sessionProvider.notifier);
      if (_mode == _SignInMode.staffPin) {
        if (_pin.text.length < 4) {
          throw const AppFailure('Enter your PIN.');
        }
        await notifier.signInWithPin(pin: _pin.text);
      } else {
        await notifier.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = userMessageFor(error);
          // A rejected PIN is cleared so the next attempt starts from the first digit.
          if (_mode == _SignInMode.staffPin) _pin.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pressDigit(String digit) {
    if (_busy || _pin.text.length >= 5) return;
    setState(() {
      _pin.text += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.text.isEmpty) return;
    setState(() => _pin.text = _pin.text.substring(0, _pin.text.length - 1));
  }

  /// A hardware keyboard can type the PIN too: digits, backspace, and enter.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // The keypad only exists with a backend; demo mode signs in by role.
    if (!AppConfig.hasSupabase ||
        event is! KeyDownEvent ||
        _mode != _SignInMode.staffPin) {
      return KeyEventResult.ignored;
    }
    final char = event.character;
    if (char != null && RegExp(r'^\d$').hasMatch(char)) {
      _pressDigit(char);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (!_busy) _signIn();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final supabase = AppConfig.hasSupabase;
    return Scaffold(
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.xxl,
                AppSpace.screen,
                AppSpace.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: AppRadius.all,
                        child: Image.asset(
                          'assets/images/premium_command_logo.png',
                          width: 132,
                          semanticLabel: 'Premium Command',
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    const Kicker('Premium hospitality operations'),
                    const SizedBox(height: 8),
                    const Text('Premium Command', style: AppText.screenTitle),
                    const SizedBox(height: 8),
                    Text(
                      'Credit Union of Texas Event Center',
                      style: AppText.meta.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    if (supabase) ...[
                      SegmentedButton<_SignInMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _SignInMode.staffPin,
                            label: Text(
                              'Staff PIN',
                              softWrap: false,
                              maxLines: 1,
                            ),
                          ),
                          ButtonSegment(
                            value: _SignInMode.adminEmail,
                            label: Text(
                              'Admin email',
                              softWrap: false,
                              maxLines: 1,
                            ),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (selected) => setState(() {
                                _mode = selected.first;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: AppSpace.l + 4),
                      if (_mode == _SignInMode.staffPin) ...[
                        _PinDots(length: _pin.text.length),
                        const SizedBox(height: AppSpace.l + 4),
                        _Keypad(
                          enabled: !_busy,
                          onDigit: _pressDigit,
                          onBackspace: _backspace,
                        ),
                      ] else ...[
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          onSubmitted: (_) => _signIn(),
                        ),
                      ],
                      const SizedBox(height: AppSpace.l),
                      FilledButton(
                        onPressed: _busy ? null : _signIn,
                        child: Text(_busy ? 'Signing in…' : 'Sign in'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.accent2700),
                        ),
                      ],
                      const SizedBox(height: AppSpace.xl),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpace.l),
                        child: Text(
                          'No Supabase connection is configured. The app is in demo mode with sample data only.',
                          style: AppText.meta,
                        ),
                      ),
                    // Demo sign-in bypasses authentication, so it exists only without a backend.
                    if (!supabase) ...[
                      const Text(
                        'Demo roles (sample data)',
                        style: AppText.sectionHeading,
                      ),
                      const SizedBox(height: 12),
                      for (final role in AppRole.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: () => ref
                                .read(sessionProvider.notifier)
                                .signInAsDemo(role),
                            child: Text(role.label),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot for each digit, four to start and a fifth once it is typed (PINs are 4 or 5 digits).
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length});

  final int length;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'PIN, $length digits entered',
      child: Row(
        children: [
          for (var i = 0; i < max(4, length); i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < length ? AppColors.text : Colors.transparent,
                border: Border.all(color: AppColors.neutral600, width: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 3 x 4 PIN keypad: 56-high surface keys, digits in the serif at 24.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (r, row) in _rows.indexed) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (final (c, key) in row.indexed) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(
                  child: key.isEmpty
                      ? const SizedBox(height: 56)
                      : _Key(
                          label: key,
                          enabled: enabled,
                          onTap: key == 'del'
                              ? onBackspace
                              : () => onDigit(key),
                        ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.all,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.all,
          hoverColor: AppColors.ink(0.07),
          highlightColor: AppColors.ink(0.14),
          child: SizedBox(
            height: 56,
            child: Center(
              child: label == 'del'
                  ? const PhosphorIcon(
                      PhosphorIconsDuotone.backspace,
                      size: 26,
                      semanticLabel: 'Delete digit',
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
