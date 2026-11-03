import '../models/permisos_operador.dart';

const kTeFaltanPermisos = 'Te faltan permisos: pedíselos al jefe';

/// Qué pasa después de poner un PIN correcto, según sus permisos.
class OpcionesDeEntrada {
  /// No puede entrar a nada: se dice esto y vuelve a la pantalla de entrada.
  final String? aviso;

  /// Tiene una sola cosa: entra derecho.
  final PermisoOperador? directo;

  /// Tiene varias: se despliegan y elige.
  final List<PermisoOperador> paraElegir;

  const OpcionesDeEntrada._({
    this.aviso,
    this.directo,
    this.paraElegir = const [],
  });

  factory OpcionesDeEntrada.de(PermisosEfectivos p) {
    final lista = p.lista;
    if (lista.isEmpty) return const OpcionesDeEntrada._(aviso: kTeFaltanPermisos);
    if (lista.length == 1) return OpcionesDeEntrada._(directo: lista.single);
    return OpcionesDeEntrada._(paraElegir: lista);
  }
}
