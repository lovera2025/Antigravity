import '../../models/egreso.dart';
import '../cierre_caja/models/turno_caja.dart';
import 'bolsa_personal_helpers.dart';

/// Plata que salió del negocio sin ser un gasto del negocio.
///
/// En el panel SALDO DEL NEGOCIO van aparte de "En qué se fue", en una sección
/// cerrada: "Aparté para mí, −$82M" era el renglón más grande de los gastos, a
/// la vista de cualquiera que abriera el panel, y además no es un gasto.
enum RubroExtraccion {
  /// Lo que el dueño pasó a su bolsillo ("Traer del negocio").
  apartado,

  /// Plata del cajón del turno que pasó a la oficina: no se gastó.
  retiroCaja,

  /// Un gasto personal del dueño pagado directo con plata del negocio.
  gastoPersonal;

  String get nombre => switch (this) {
        RubroExtraccion.apartado => 'Aparté para mí',
        RubroExtraccion.retiroCaja => 'Retiro de caja',
        RubroExtraccion.gastoPersonal => 'Gastos tuyos desde el negocio',
      };
}

/// El rubro de extracción de [e], o `null` si es un gasto del negocio o si no
/// resta del negocio (un gasto que salió del bolsillo).
///
/// Se decide por la categoría cargada, igual que el resto del panel: un
/// "EXTRACCION" cargado como Operadores sigue en Operadores.
RubroExtraccion? rubroExtraccion(Egreso e) {
  if (!finanzasEgresoAfectaCajaEmpresa(e)) return null;
  return switch ((e.categoria ?? '').trim()) {
    kCategoriaRetiroDueno => RubroExtraccion.apartado,
    kCategoriaRetiroCaja => RubroExtraccion.retiroCaja,
    kCategoriaGastoPersonal => RubroExtraccion.gastoPersonal,
    _ => null,
  };
}

bool esExtraccion(Egreso e) => rubroExtraccion(e) != null;

bool _esTransferencia(Egreso e) =>
    (e.medioPago ?? '').toLowerCase().trim() == 'transferencia';

/// Un rubro de extracciones con su parte en cada medio.
class ResumenExtraccion {
  final RubroExtraccion rubro;
  final int cantidad;
  final double efectivo;
  final double transferencia;

  const ResumenExtraccion({
    required this.rubro,
    required this.cantidad,
    required this.efectivo,
    required this.transferencia,
  });

  double get total => efectivo + transferencia;
}

/// Las extracciones de [egresos], por rubro y en el orden de [RubroExtraccion].
/// Solo los rubros que tienen algo.
List<ResumenExtraccion> resumenExtracciones(Iterable<Egreso> egresos) {
  final cantidad = <RubroExtraccion, int>{};
  final efectivo = <RubroExtraccion, double>{};
  final transferencia = <RubroExtraccion, double>{};
  for (final e in egresos) {
    final r = rubroExtraccion(e);
    if (r == null) continue;
    cantidad[r] = (cantidad[r] ?? 0) + 1;
    final medio = _esTransferencia(e) ? transferencia : efectivo;
    medio[r] = (medio[r] ?? 0) + e.monto;
  }
  return [
    for (final r in RubroExtraccion.values)
      if (cantidad.containsKey(r))
        ResumenExtraccion(
          rubro: r,
          cantidad: cantidad[r]!,
          efectivo: efectivo[r] ?? 0,
          transferencia: transferencia[r] ?? 0,
        ),
  ];
}
