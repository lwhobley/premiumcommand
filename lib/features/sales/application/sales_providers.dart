import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../data/sales_repository.dart';
import '../domain/sales_package.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  ref.watch(sessionProvider);
  return SalesRepository(Supabase.instance.client);
});

final salesPackagesProvider = FutureProvider.family<List<SalesPackage>, String>(
  (ref, venueId) {
    ref.watch(sessionProvider);
    return ref.watch(salesRepositoryProvider).list(venueId);
  },
);
