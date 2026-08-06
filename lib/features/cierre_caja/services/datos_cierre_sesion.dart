import '../../../models/egreso.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../models/medio_pago_caja.dart';
import '../models/turno_caja.dart';

/// Movimientos y totales de un alcance de caja (una sesión, varias, o el día
/// sin sesiones), ya clasificados por medio de pago.
///
/// Existe para que el aviso previo al cierre y los papeles puedan calcular lo
/// mismo que la pantalla **sin depender del provider**: al cerrar, el operario se
/// desloguea y `CierreCajaState` queda vacío, así que un papel que leyera el
/// estado saldría en cero.
class DatosCierreSesion {
  final List<IngresoDetallado> ingresos;

  /// Todos los egresos del alcance (retiros formales + otros gastos).
  final List<Egreso> egresos;

  /// Solo los de categoría [kCategoriaRetiroCaja].
  final List<Egreso> retiros;

  /// Los que **no** son retiro de caja.
  final List<Egreso> otrosEgresos;

  final double efectivoBruto;
  final double transferenciaBruta;
  final double egresosEfectivo;
  final double egresosTransferencia;
  final double retirosEfectivo;
  final double retirosTransferencia;

  const DatosCierreSesion({
    this.ingresos = const [],
    this.egresos = const [],
    this.retiros = const [],
    this.otrosEgresos = const [],
    this.efectivoBruto = 0,
    this.transferenciaBruta = 0,
    this.egresosEfectivo = 0,
    this.egresosTransferencia = 0,
    this.retirosEfectivo = 0,
    this.retirosTransferencia = 0,
  });

  double get efectivoNeto => efectivoBruto - egresosEfectivo;
  double get transferenciaNeta => transferenciaBruta - egresosTransferencia;
  double get totalNeto => efectivoNeto + transferenciaNeta;

  /// Lo que tiene que haber en el cajón: el cambio con el que se abrió más lo
  /// cobrado en efectivo, menos lo que salió.
  ///
  /// Es la cifra contra la que se compara el arqueo, la misma fórmula que usa
  /// `_ticketCajaBloqueCierreSesion`. El aviso previo al cierre muestra **esta** y
  /// no el bruto cobrado: contra el bruto, el arqueo daría diferencia siempre.
  double efectivoEsperado(double cambioInicial) => cambioInicial + efectivoNeto;

  bool get vacio => ingresos.isEmpty && egresos.isEmpty;
}

/// Carga y clasifica los movimientos de un alcance de caja.
///
/// Con [sesionIds] pide **solo esas sesiones al SQL**. Con [rangoSinSesion] entra
/// al modo contraste del jefe —cobros de builds viejos, sin `sesion_caja_id`—, que
/// necesita traer todo y filtrar por hora porque justamente no hay id por el que
/// filtrar; ese camino no lo pisa nunca un operario.
Future<DatosCierreSesion> cargarDatosCierreSesion({
  required Set<String> sesionIds,
  RangoHorarioAr? rangoSinSesion,
  required FinanzasRepository finanzasRepo,
  required EgresosRepository egresosRepo,
}) async {
  final sinSesiones = rangoSinSesion != null;
  if (!sinSesiones && sesionIds.isEmpty) return const DatosCierreSesion();

  final results = await Future.wait([
    sinSesiones
        ? finanzasRepo.obtenerIngresosDetallados()
        : finanzasRepo.obtenerIngresosDeSesiones(sesionIds),
    sinSesiones
        ? egresosRepo.getEgresosConEvento()
        : egresosRepo.getEgresosDeSesiones(sesionIds),
  ]);
  final ingresosFull = results[0] as List<IngresoDetallado>;
  final egresosFull = (results[1] as List<dynamic>)
      .map((e) => Egreso.fromJson(e))
      .toList();

  double efectivoBruto = 0;
  double transferenciaBruta = 0;
  final ingresos = <IngresoDetallado>[];
  for (final i in ingresosFull) {
    if (sinSesiones) {
      final sid = i.sesionCajaId?.trim();
      if (sid != null && sid.isNotEmpty) continue;
      if (!rangoSinSesion.contiene(i.fecha)) continue;
    }
    ingresos.add(i);
    if (esTransferenciaCaja(i.medioPago)) {
      transferenciaBruta += i.monto;
    } else {
      efectivoBruto += i.monto;
    }
  }
  ingresos.sort((a, b) => b.fecha.compareTo(a.fecha));

  final egresos = <Egreso>[];
  final retiros = <Egreso>[];
  double egresosEfectivo = 0;
  double egresosTransferencia = 0;
  double retirosEfectivo = 0;
  double retirosTransferencia = 0;
  for (final e in egresosFull) {
    if (sinSesiones) {
      final sid = e.sesionCajaId?.trim();
      if (sid != null && sid.isNotEmpty) continue;
      final fe = e.fecha;
      if (fe == null || !rangoSinSesion.contiene(fe)) continue;
    }
    egresos.add(e);
    final esTransf = esTransferenciaCaja(e.medioPago);
    if (esTransf) {
      egresosTransferencia += e.monto;
    } else {
      egresosEfectivo += e.monto;
    }
    if ((e.categoria ?? '').trim() == kCategoriaRetiroCaja) {
      retiros.add(e);
      if (esTransf) {
        retirosTransferencia += e.monto;
      } else {
        retirosEfectivo += e.monto;
      }
    }
  }
  egresos.sort(_porFechaDesc);
  retiros.sort(_porFechaDesc);

  return DatosCierreSesion(
    ingresos: ingresos,
    egresos: egresos,
    retiros: retiros,
    otrosEgresos: egresos
        .where((e) => (e.categoria ?? '').trim() != kCategoriaRetiroCaja)
        .toList(),
    efectivoBruto: efectivoBruto,
    transferenciaBruta: transferenciaBruta,
    egresosEfectivo: egresosEfectivo,
    egresosTransferencia: egresosTransferencia,
    retirosEfectivo: retirosEfectivo,
    retirosTransferencia: retirosTransferencia,
  );
}

int _porFechaDesc(Egreso a, Egreso b) {
  final fa = a.fecha;
  final fb = b.fecha;
  if (fa == null && fb == null) return 0;
  if (fa == null) return 1;
  if (fb == null) return -1;
  return fb.compareTo(fa);
}
