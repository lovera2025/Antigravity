import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import 'supabase_service.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(supabaseProvider);
  return SupabaseService(client: client);
});
