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

/// Cómo está pagado algo extra de un alumno: sus mesas agregadas o sus sillas.
enum EstadoPagoExtra {
  /// No tiene ninguna cargada (o está cargada sin precio, que no cuenta).
  sinCargar,

  /// La tiene cargada y no pagó nada.
  sinPagar,

  /// Pagó una parte.
  enCuotas,

  /// La pagó entera.
  pagado,
}

/// Lo cargado y lo pagado de un extra, para mostrarlo sin lugar a dudas.
class ExtraPagado {
  /// Cuántas tiene cargadas, con precio.
  final int cantidad;

  /// El precio total cargado.
  final double precio;

  /// Lo pagado según sus pagos (antes de descuentos, igual que el saldo).
  final double pagado;

  const ExtraPagado({this.cantidad = 0, this.precio = 0, this.pagado = 0});

  EstadoPagoExtra get estado {
    if (cantidad <= 0) return EstadoPagoExtra.sinCargar;
    if (pagado <= 0.01) return EstadoPagoExtra.sinPagar;
    return pagado >= precio - 0.01
        ? EstadoPagoExtra.pagado
        : EstadoPagoExtra.enCuotas;
  }
}

/// Las mesas y sillas de un alumno, con lo que pagó de cada cosa y lo que le
/// da hoy el sorteo.
///
/// Sale de los **pagos**, como todo lo que decide con plata. La grilla, su
/// filtro y [candidatosPorPago] comen de acá, para no decir cosas distintas.
class ExtrasSegunPago {
  /// Pagó algo de la cuota base.
  final bool pagoBase;

  /// Las mesas agregadas (además de la del contrato).
  final ExtraPagado mesas;
  final ExtraPagado sillas;

  /// Mesas que ya tiene con número.
  final int asignadas;

  const ExtrasSegunPago({
    required this.pagoBase,
    this.mesas = const ExtraPagado(),
    this.sillas = const ExtraPagado(),
    this.asignadas = 0,
  });

  factory ExtrasSegunPago.de(ContratoAlumno a, PagoAlumno pago) =>
      ExtrasSegunPago(
        pagoBase: pago.pagoBase,
        mesas: ExtraPagado(
          cantidad: SalonMesas.mesasExtra(a),
          precio: a.mesaExtraPrecio,
          pagado: pago.mesas,
        ),
        sillas: ExtraPagado(
          cantidad: SalonMesas.sillasExtra(a),
          precio: a.sillasExtraPrecioTotal,
          pagado: pago.sillas,
        ),
        asignadas: MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length,
      );

  /// La del contrato más las agregadas.
  int get mesasCargadas => 1 + mesas.cantidad;

  /// $0 de base y todavía sin mesa: el sorteo no le da ninguna.
  bool get sinMesaPorBase => asignadas == 0 && !pagoBase;

  /// Tiene mesas agregadas y no pagó nada de ellas.
  bool get agregadasSinPago =>
      mesas.cantidad > 0 && mesas.estado == EstadoPagoExtra.sinPagar;

  /// Tiene (o va a tener) su mesa del contrato, pero las agregadas que le
  /// faltan no las pagó: el sorteo le da solo la del contrato.
  bool get soloLaDelContrato =>
      !sinMesaPorBase && agregadasSinPago && asignadas < mesasCargadas;

  /// Cuántas mesas tendría en total si se sorteara hoy, sin excepciones.
  int get mesasConElSorteoDeHoy {
    if (sinMesaPorBase) return 0;
    if (soloLaDelContrato) return asignadas > 1 ? asignadas : 1;
    return asignadas > mesasCargadas ? asignadas : mesasCargadas;
  }

  /// El sorteo de hoy le daría menos mesas de las que tiene cargadas.
  bool get recibeMenos => mesasConElSorteoDeHoy < mesasCargadas;
}

/// Las mesas y sillas de cada alumno, a partir de lo que pagó cada uno.
Map<String, ExtrasSegunPago> extrasPorAlumno(
  Iterable<ContratoAlumno> alumnos,
  Map<String, PagoAlumno> pagos,
) => {
  for (final a in alumnos)
    a.id: ExtrasSegunPago.de(a, pagos[a.id] ?? PagoAlumno.nada),
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
    final extras = ExtrasSegunPago.de(a, pagos[a.id] ?? PagoAlumno.nada);
    if (extras.sinMesaPorBase) {
      sinBase.add(a);
      if (extras.agregadasSinPago) sinBaseConExtras.add(a.id);
      continue;
    }
    // Tiene su base (asignada o por sortear) y le faltarían las extra.
    if (extras.soloLaDelContrato) sinExtras.add(a);
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
