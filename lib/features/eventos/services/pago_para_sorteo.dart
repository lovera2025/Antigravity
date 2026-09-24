import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mesas_extra_utils.dart';
import 'salon_mesas.dart';

/// Lo que un alumno lleva pagado de cada cosa, según **sus pagos**.
///
/// Sale de los pagos y no de los campos del contrato a propósito: es la misma
/// clasificación con la que la app calcula el saldo (`recalcularSaldoDesdePagos`)
/// y la que manda. En septiembre de 2026 había un alumno con $30.000 de base según
/// el contrato y ningún pago cargado: con los campos, habría entrado al sorteo.
class PagoAlumno {
  final double base;
  final double mesas;
  final double sillas;

  const PagoAlumno({this.base = 0, this.mesas = 0, this.sillas = 0});

  static const nada = PagoAlumno();

  factory PagoAlumno.desdePagos(Iterable<Map<String, dynamic>> pagos) =>
      PagoAlumno(
        base: grossHistoricoClaseCobro(pagos, CobroConceptoClase.base),
        mesas: grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
        sillas: grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
      );

  bool get pagoBase => base > 0.01;
  bool get pagoMesas => mesas > 0.01;
  bool get pagoSillas => sillas > 0.01;
}

/// Lo pagado por cada alumno, a partir de sus pagos agrupados por contrato.
/// Un alumno sin pagos queda con [PagoAlumno.nada].
Map<String, PagoAlumno> pagosPorAlumno(
  Iterable<ContratoAlumno> alumnos,
  Map<String, List<Map<String, dynamic>>> pagosPorContrato,
) => {
  for (final a in alumnos)
    a.id: PagoAlumno.desdePagos(pagosPorContrato[a.id] ?? const []),
};

/// Quiénes quedarían afuera del sorteo por no tener nada pagado.
///
/// Solo se cuenta a quien el sorteo le haría algo: los de baja no entran, y al
/// que ya tiene sus números no se le mueve nada.
class CandidatosPorPago {
  /// $0 de cuota base y todavía sin mesa: no se les sortea mesa.
  final List<ContratoAlumno> sinPagoBase;

  /// Pagaron algo de la base pero $0 de sus mesas extra, y el sorteo les daría
  /// las extra ahora: reciben solo la mesa base.
  final List<ContratoAlumno> sinPagoMesasExtra;

  /// De [sinPagoBase], los que además tienen mesas extra sin pagar. Si se los
  /// sortea igual por la base, van solo con la base.
  final Set<String> sinPagoBaseConExtras;

  const CandidatosPorPago({
    this.sinPagoBase = const [],
    this.sinPagoMesasExtra = const [],
    this.sinPagoBaseConExtras = const {},
  });

  bool get vacio => sinPagoBase.isEmpty && sinPagoMesasExtra.isEmpty;
}

CandidatosPorPago candidatosPorPago(
  Iterable<ContratoAlumno> alumnos,
  Map<String, PagoAlumno> pagos,
) {
  final sinBase = <ContratoAlumno>[];
  final sinExtras = <ContratoAlumno>[];
  final sinBaseConExtras = <String>{};
  for (final a in alumnos) {
    if (a.esBajaTemporal) continue;
    final pago = pagos[a.id] ?? PagoAlumno.nada;
    final asignadas =
        MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length;
    final extrasSinPago = SalonMesas.mesasExtra(a) > 0 && !pago.pagoMesas;
    if (asignadas == 0 && !pago.pagoBase) {
      sinBase.add(a);
      if (extrasSinPago) sinBaseConExtras.add(a.id);
      continue;
    }
    // Tiene su base (asignada o por sortear) y le faltarían las extra.
    if (extrasSinPago && asignadas < SalonMesas.mesas(a)) sinExtras.add(a);
  }
  int porNombre(ContratoAlumno x, ContratoAlumno y) =>
      x.nombreAlumno.compareTo(y.nombreAlumno);
  return CandidatosPorPago(
    sinPagoBase: sinBase..sort(porNombre),
    sinPagoMesasExtra: sinExtras..sort(porNombre),
    sinPagoBaseConExtras: sinBaseConExtras,
  );
}

/// Qué deja afuera el sorteo, ya con las excepciones que marcó una persona.
class ExclusionSorteo {
  /// No se les sortea mesa.
  final Set<String> sinMesa;

  /// Se les sortea solo la mesa base.
  final Set<String> soloBase;

  const ExclusionSorteo({this.sinMesa = const {}, this.soloBase = const {}});

  static const ninguna = ExclusionSorteo();

  bool get vacia => sinMesa.isEmpty && soloBase.isEmpty;
}

/// Con [soloPagado] en false se sortea todo lo cargado, como antes de la 5.0.0.
///
/// [incluirBase] y [incluirExtras] son las casillas "sortear igual": ids que una
/// persona decidió incluir aunque no tengan nada pagado (pagó en efectivo y no
/// se cargó, lo autorizó el jefe). Se guardan como excepciones y no como la
/// lista final a propósito: si con el diálogo abierto alguien paga, sale solo de
/// la lista, y si aparece uno nuevo sin pagar, queda afuera por defecto.
ExclusionSorteo exclusionSorteo({
  required CandidatosPorPago candidatos,
  required bool soloPagado,
  Set<String> incluirBase = const {},
  Set<String> incluirExtras = const {},
}) {
  if (!soloPagado) return ExclusionSorteo.ninguna;
  final sinMesa = {
    for (final a in candidatos.sinPagoBase)
      if (!incluirBase.contains(a.id)) a.id,
  };
  final soloBase = {
    for (final a in candidatos.sinPagoMesasExtra)
      if (!incluirExtras.contains(a.id)) a.id,
    // Sorteado igual por la base, pero con las extra sin pagar: solo la base.
    for (final id in candidatos.sinPagoBaseConExtras)
      if (incluirBase.contains(id)) id,
  };
  return ExclusionSorteo(sinMesa: sinMesa, soloBase: soloBase);
}

/// Huella de lo que pagó cada alumno para el sorteo. Si cambia entre que se abrió
/// el diálogo y se tocó SORTEAR (entró un pago), se vuelve a mostrar.
String firmaPagos(
  Iterable<ContratoAlumno> alumnos,
  Map<String, PagoAlumno> pagos,
) {
  final filas = [
    for (final a in alumnos)
      () {
        final p = pagos[a.id] ?? PagoAlumno.nada;
        return '${a.id}|${p.pagoBase}|${p.pagoMesas}|${p.pagoSillas}';
      }(),
  ]..sort();
  return filas.join('\n');
}
