import '../models/permisos_operador.dart';

const kTeFaltanPermisos = 'Te faltan permisos: pedíselos al jefe';

/// Lo que se le dice en la web a quien no es la Encargada de barra.
const kDesdeElNavegadorNo = 'Desde el navegador no se cobra ni se vende: usá la app';

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

  /// **[enLaWeb] (el iPhone, 6.5.0): entra solo la Encargada de barra**, derecho a la
  /// barra aunque tenga otros permisos. Desde el navegador no se cobra, no se entrega
  /// ni se vende: no hay base del equipo, caja ni impresora.
  factory OpcionesDeEntrada.de(PermisosEfectivos p, {bool enLaWeb = false}) {
    final lista = p.lista;
    if (lista.isEmpty) return const OpcionesDeEntrada._(aviso: kTeFaltanPermisos);
    if (enLaWeb) {
      return p.encargadaBarra
          ? const OpcionesDeEntrada._(directo: PermisoOperador.barra)
          : const OpcionesDeEntrada._(aviso: kDesdeElNavegadorNo);
    }
    if (lista.length == 1) return OpcionesDeEntrada._(directo: lista.single);
    return OpcionesDeEntrada._(paraElegir: lista);
  }
}
