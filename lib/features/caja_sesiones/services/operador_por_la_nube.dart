import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../main.dart' show supabaseProvider;
import '../models/modo_jefe_caja.dart';
import '../models/operador_caja.dart';
import '../models/permisos_operador.dart';

/// No se le pudo preguntar a la nube de quién es el PIN (sin internet, o tardó de más).
/// **No es "PIN incorrecto":** la pantalla de entrada lo dice aparte ([kSinNubeParaElPin]).
class SinNubeParaElPin implements Exception {
  const SinNubeParaElPin();

  @override
  String toString() => kSinNubeParaElPin;
}

const kSinNubeParaElPin =
    'No se pudo comprobar el PIN: revisá internet y probá de nuevo';

/// Lo que se le pide a la nube para saber de quién es un PIN. Los tests lo reemplazan
/// por una lista.
abstract class OperadoresDeLaNube {
  /// Las filas de `operadores_caja` con ese PIN (puede haber una dada de baja y otra
  /// activa con el mismo).
  Future<List<Map<String, dynamic>>> conPin(String pin);

  /// La fila de `permisos_operador` de ese operador, si tiene.
  Future<List<Map<String, dynamic>>> permisosDe(String operadorId);
}

/// La nube de verdad. **Siempre el cliente que le pasan** (`supabaseProvider`), nunca el
/// singleton de Supabase.
class OperadoresEnSupabase implements OperadoresDeLaNube {
  const OperadoresEnSupabase(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<Map<String, dynamic>>> conPin(String pin) => _supabase
      .from('operadores_caja')
      .select()
      .eq('pin', pin)
      .order('id', ascending: true)
      .limit(10);

  @override
  Future<List<Map<String, dynamic>>> permisosDe(String operadorId) => _supabase
      .from('permisos_operador')
      .select()
      .eq('operador_id', operadorId)
      .order('id', ascending: true)
      .limit(1);
}

final operadoresDeLaNubeProvider = Provider<OperadoresDeLaNube>(
  (ref) => OperadoresEnSupabase(ref.watch(supabaseProvider)),
);

/// De quién es [pin] según la nube, con sus permisos. Null si no es de nadie activo.
///
/// **Es el camino de la web** (6.5.0): ahí no hay base del equipo donde buscarlo. En la
/// PC y en la tablet el PIN se sigue buscando en la base (`AppRoleNotifier.buscarOperador`).
///
/// - **En la nube `activo` es booleano** y en la base del equipo, 0 o 1: se aceptan los dos.
/// - El operador del modo jefe no entra con PIN.
/// - Sin fila de permisos es de Cobros solo, como en la PC ([PermisosEfectivos.de]).
///
/// Un error de la nube sube tal cual: quien llama decide qué decir.
Future<({OperadorCaja operador, PermisosEfectivos permisos})?> operadorPorLaNube(
  OperadoresDeLaNube nube,
  String pin,
) async {
  final limpio = pin.trim();
  if (limpio.isEmpty) return null;
  OperadorCaja? operador;
  for (final fila in await nube.conPin(limpio)) {
    final activo = fila['activo'];
    if (activo != true && activo != 1) continue;
    if ((fila['pin'] ?? '').toString() != limpio) continue;
    final op = OperadorCaja.fromMap({...fila, 'activo': 1});
    if (esOperadorModoJefeId(op.id)) continue;
    operador = op;
    break;
  }
  if (operador == null) return null;
  final filas = await nube.permisosDe(operador.id);
  final permisos = PermisosEfectivos.de(
    filas.isEmpty ? null : PermisosOperador.fromMap(filas.first),
  );
  return (operador: operador, permisos: permisos);
}
