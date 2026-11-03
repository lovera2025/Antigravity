import '../models/operador_caja.dart';
import '../models/permisos_operador.dart';

/// Qué le falta a la ficha de un operador para poder guardarse. Null si está bien.
///
/// Dice en palabras lo mismo que frena el repositorio, antes de cerrar el diálogo:
/// así no se pierde lo escrito. **El PIN no puede ser el de otro operador activo ni
/// el maestro:** con el mismo PIN no se sabría quién cobró o quién entregó.
String? problemaDelOperador({
  required String nombre,
  required String pin,
  String? idPropio,
  required Iterable<OperadorCaja> otros,
  required bool esMaestro,
}) {
  if (nombre.trim().isEmpty) return 'Falta el nombre.';
  final p = pin.trim();
  if (p.length < 4) return 'El PIN tiene que tener al menos 4 dígitos.';
  if (esMaestro) return 'Ese PIN es el del modo jefe: elegí otro.';
  for (final o in otros) {
    if (o.id != idPropio && o.pin == p) {
      return 'Ese PIN ya lo tiene ${o.nombre}.';
    }
  }
  return null;
}

/// Lo que puede hacer un operador, en palabras, para la lista de OPERADORES.
String textoDePermisos(PermisosEfectivos p) {
  if (p.ninguno) return 'Sin permisos: no puede entrar';
  return [for (final x in p.lista) nombreDePermiso(x)].join(' · ');
}

String nombreDePermiso(PermisoOperador p) => switch (p) {
      PermisoOperador.cobros => 'Cobros',
      PermisoOperador.entradas => 'Entradas',
      PermisoOperador.barra => 'Barra',
    };
