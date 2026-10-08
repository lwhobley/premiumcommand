import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import 'app_section.dart';

/// Phone-width list of every section the user is permitted to open.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sections = AppSection.values
        .where((s) => session != null && s.allows(session.permissions))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          for (final section in sections)
            ListTile(
              leading: Icon(section.icon),
              title: Text(section.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(section.path),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
