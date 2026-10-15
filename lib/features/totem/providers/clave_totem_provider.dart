import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../services/clave_totem.dart';

/// La clave del tótem de cada evento ([ClaveTotem]), en la ventana principal:
/// es la que tiene usuario para pedirla a la nube (`totem_clave`). La ventana
/// del tótem se la pide a esta por el puente.
final claveTotemProvider = Provider<ClaveTotem>((ref) {
  final cliente = ref.watch(supabaseProvider);
  return ClaveTotem(
    pedirALaNube: (eventoId) async {
      final r = await cliente.rpc('totem_clave', params: {'p_evento': eventoId});
      return r is String ? r : null;
    },
  );
});
