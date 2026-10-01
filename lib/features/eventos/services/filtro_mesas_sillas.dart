import '../../../models/contrato_alumno.dart';
import 'filtro_mora_masivos.dart';
import 'pago_para_sorteo.dart';

/// De qué habla cada opción del filtro (para agruparlas en el menú).
enum GrupoFiltroExtras { mesas, sillas, revisar }

/// Cómo se filtra la grilla de masivos por las mesas y sillas de cada uno.
///
/// Es para llegar al sorteo sabiendo, sin lugar a dudas, quién tiene qué y
/// quién lo pagó: que nadie pueda decir "yo te había pedido tantas mesas y
/// tantas sillas". Todo sale de los pagos ([ExtrasSegunPago]).
enum FiltroExtras {
  todos('Todos', 'Sin filtro de mesas ni sillas', null),
  conMesaAgregada(
    'Con mesa agregada',
    'Tienen mesas además de la de su contrato',
    GrupoFiltroExtras.mesas,
  ),
  mesaPagada(
    'Mesa agregada pagada',
    'La pagaron entera',
    GrupoFiltroExtras.mesas,
  ),
  mesaEnCuotas(
    'Mesa agregada en cuotas',
    'Pagaron una parte: entra al sorteo',
    GrupoFiltroExtras.mesas,
  ),
  mesaSinPagar(
    'Mesa agregada sin pagar',
    'El sorteo les da solo la de su contrato',
    GrupoFiltroExtras.mesas,
  ),
  sinPagoBase(
    'Sin pago de la base',
    'No pagaron nada de la cuota: el sorteo no les da mesa',
    GrupoFiltroExtras.mesas,
  ),
  conSillas(
    'Con sillas extra',
    'Tienen sillas extra cargadas',
    GrupoFiltroExtras.sillas,
  ),
  sillasPagadas(
    'Sillas pagadas',
    'Las pagaron enteras',
    GrupoFiltroExtras.sillas,
  ),
  sillasEnCuotas(
    'Sillas en cuotas',
    'Pagaron una parte',
    GrupoFiltroExtras.sillas,
  ),
  sillasSinPagar(
    'Sillas sin pagar',
    'Las tienen cargadas y no pagaron nada',
    GrupoFiltroExtras.sillas,
  ),
  revisar(
    'Para revisar',
    'Algo no cierra: un precio distinto, sillas de más, gente que no entra',
    GrupoFiltroExtras.revisar,
  );

  const FiltroExtras(this.label, this.ayuda, this.grupo);

  final String label;
  final String ayuda;
  final GrupoFiltroExtras? grupo;

  bool get activo => this != FiltroExtras.todos;
}

/// ¿Este alumno entra en [filtro]?
///
/// [extras] es lo suyo según sus pagos y [tieneAvisos], si `SalonMesas.avisos`
/// marcó algo de él. Las bajas temporales nunca entran, igual que en el
/// sorteo: están suspendidas y no se les reserva nada.
bool cumpleFiltroExtras(
  ContratoAlumno a,
  ExtrasSegunPago? extras,
  FiltroExtras filtro, {
  bool tieneAvisos = false,
}) {
  if (filtro == FiltroExtras.todos) return true;
  if (esBajaTemporal(a)) return false;
  if (filtro == FiltroExtras.revisar) return tieneAvisos;
  if (extras == null) return false;
  final mesas = extras.mesas.estado;
  final sillas = extras.sillas.estado;
  switch (filtro) {
    case FiltroExtras.conMesaAgregada:
      return mesas != EstadoPagoExtra.sinCargar;
    case FiltroExtras.mesaPagada:
      return mesas == EstadoPagoExtra.pagado;
    case FiltroExtras.mesaEnCuotas:
      return mesas == EstadoPagoExtra.enCuotas;
    case FiltroExtras.mesaSinPagar:
      return mesas == EstadoPagoExtra.sinPagar;
    case FiltroExtras.sinPagoBase:
      return !extras.pagoBase;
    case FiltroExtras.conSillas:
      return sillas != EstadoPagoExtra.sinCargar;
    case FiltroExtras.sillasPagadas:
      return sillas == EstadoPagoExtra.pagado;
    case FiltroExtras.sillasEnCuotas:
      return sillas == EstadoPagoExtra.enCuotas;
    case FiltroExtras.sillasSinPagar:
      return sillas == EstadoPagoExtra.sinPagar;
    case FiltroExtras.todos:
    case FiltroExtras.revisar:
      return true;
  }
}

/// Tiene algo para mirar antes del sorteo: no pagó la base, tiene una mesa o
/// sillas sin pagar, o un aviso. Es lo que cuenta el chip de la barra.
bool tieneAlgoPendienteDeExtras(
  ContratoAlumno a,
  ExtrasSegunPago? extras, {
  bool tieneAvisos = false,
}) {
  if (esBajaTemporal(a)) return false;
  if (tieneAvisos) return true;
  if (extras == null) return false;
  return !extras.pagoBase ||
      extras.mesas.estado == EstadoPagoExtra.sinPagar ||
      extras.sillas.estado == EstadoPagoExtra.sinPagar;
}

/// Cuántos alumnos entran en cada opción del filtro, para mostrarlo en el
/// menú. [conAvisos] son los ids de quienes `SalonMesas.avisos` marcó.
Map<FiltroExtras, int> contarPorFiltro(
  Iterable<ContratoAlumno> alumnos,
  Map<String, ExtrasSegunPago> extras,
  Set<String> conAvisos,
) {
  final cuenta = {
    for (final f in FiltroExtras.values)
      if (f.activo) f: 0,
  };
  for (final a in alumnos) {
    for (final f in cuenta.keys) {
      if (cumpleFiltroExtras(
        a,
        extras[a.id],
        f,
        tieneAvisos: conAvisos.contains(a.id),
      )) {
        cuenta[f] = cuenta[f]! + 1;
      }
    }
  }
  return cuenta;
}

/// Los totales del evento, para el chip: lo cargado y lo que daría hoy el
/// sorteo. Sin las bajas.
({int mesas, int agregadas, int conLoPagado, int sillas}) totalesDeExtras(
  Iterable<ContratoAlumno> alumnos,
  Map<String, ExtrasSegunPago> extras,
) {
  var mesas = 0;
  var agregadas = 0;
  var conLoPagado = 0;
  var sillas = 0;
  for (final a in alumnos) {
    if (esBajaTemporal(a)) continue;
    final e = extras[a.id];
    if (e == null) continue;
    mesas += e.mesasCargadas;
    agregadas += e.mesas.cantidad;
    conLoPagado += e.mesasConElSorteoDeHoy;
    sillas += e.sillas.cantidad;
  }
  return (
    mesas: mesas,
    agregadas: agregadas,
    conLoPagado: conLoPagado,
    sillas: sillas,
  );
}
