import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
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
        if (_pin.text.length != 4) {
          throw const AppFailure('Enter your 4-digit PIN.');
        }
        await notifier.signInWithPin(pin: _pin.text);
      } else {
        await notifier.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = AppConfig.hasSupabase;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CUTX Premium Command',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Premium hospitality operations',
                  style: TextStyle(color: AppColors.charcoalMuted),
                ),
                const SizedBox(height: 28),
                if (supabase) ...[
                  SegmentedButton<_SignInMode>(
                    segments: const [
                      ButtonSegment(
                        value: _SignInMode.staffPin,
                        label: Text('Staff PIN'),
                      ),
                      ButtonSegment(
                        value: _SignInMode.adminEmail,
                        label: Text('Admin email'),
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
                  const SizedBox(height: 16),
                  if (_mode == _SignInMode.staffPin) ...[
                    TextField(
                      controller: _pin,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _signIn(),
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
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _signIn(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: Text(_busy ? 'Signing in…' : 'Sign in'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.blocked),
                    ),
                  ],
                  const SizedBox(height: 28),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text(
                      'No Supabase connection is configured. The app is in demo mode with sample data only.',
                      style: TextStyle(color: AppColors.charcoalMuted),
                    ),
                  ),
                // Demo sign-in bypasses authentication, so it exists only without a backend.
                if (!supabase) ...[
                  Text(
                    'Demo roles (sample data)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final role in AppRole.values)
                        OutlinedButton(
                          onPressed: () => ref
                              .read(sessionProvider.notifier)
                              .signInAsDemo(role),
                          child: Text(role.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
