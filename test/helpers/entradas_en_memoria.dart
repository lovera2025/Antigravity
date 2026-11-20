// La venta de entradas en memoria, para montar sus pantallas sin base ni nube.
// Hace lo mismo que `EntradasLocal`: guardar sin cambiar nada no escribe, el
// número del comprobante es por caja, una caja cerrada no se vuelve a cerrar y
// anular dos veces devuelve la que ya había.
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

class EntradasEnMemoria implements EntradasDeLaCaja, EntradasDelJefe {
  EntradasEnMemoria({this.equipo = 'pc-1', DateTime? ahora})
      : _ahora = ahora ?? DateTime.utc(2026, 11, 20, 15);

  /// El equipo donde "corre": una caja vive donde se abrió.
  final String equipo;
  DateTime _ahora;

  /// Cada cosa que pasa, un segundo después de la anterior.
  DateTime reloj() => _ahora = _ahora.add(const Duration(seconds: 1));

  /// Para saltar en el tiempo (anular "al otro día").
  void adelantar(Duration d) => _ahora = _ahora.add(d);

  final configs = <String, ConfigEntradas>{};
  final listaCajas = <CajaEntradas>[];
  final listaVentas = <VentaEntradas>[];
  final listaAnulaciones = <AnulacionEntradas>[];
  final listaVerificaciones = <VerificacionEntradas>[];

  /// Cuántas veces se escribió de verdad (lo que iría a la cola de subida).
  int escrituras = 0;

  /// Las ventas de este equipo que "esperan subir".
  int sinSubir = 0;

  /// Lo demás de la venta que "espera subir" (cajas, anulaciones).
  int cambiosPendientes = 0;

  /// Con esto prendido, todo lo que escribe tira: la base no anda.
  bool falla = false;

  void _escribir() {
    if (falla) throw StateError('la base no anda (prueba)');
    escrituras++;
  }

  /// Los providers de la app, apuntando acá.
  List<Override> get reemplazos => [
        entradasDeLaFiestaProvider.overrideWithValue(this),
        entradasDeLaCajaProvider.overrideWithValue(this),
        entradasDelJefeProvider.overrideWithValue(this),
        entradasEnEsteEquipoProvider.overrideWithValue(true),
      ];

  /// Deja cargado el precio de una fiesta, como si el jefe ya lo hubiera puesto.
  ConfigEntradas conPrecio(
    String eventoId, {
    double? valor = 10000,
    double? anticipada,
    String? hasta,
    double lugaresPct = 50,
    double recargo = 0,
    bool aMano = false,
  }) =>
      configs[eventoId] = ConfigEntradas.vacia(eventoId, ahora: reloj())
          .conPrecios(
            valorEntrada: valor,
            precioAnticipada: anticipada,
            anticipadaHasta: hasta,
            descuentoLugaresPct: lugaresPct,
            recargoPct: recargo,
            descuentoAMano: aMano,
          )
          .sellada(hechoPor: 'Jefe', deviceId: equipo, ahora: reloj());

  // ── Leer ───────────────────────────────────────────────────────────────────

  @override
  Future<ConfigEntradas?> config(String eventoId) async => configs[eventoId];

  @override
  Future<List<CajaEntradas>> cajas(String eventoId) async =>
      [for (final c in listaCajas) if (c.eventoId == eventoId) c];

  @override
  Future<List<VentaEntradas>> ventas(String eventoId) async =>
      [for (final v in listaVentas) if (v.eventoId == eventoId) v];

  @override
  Future<List<AnulacionEntradas>> anulaciones(String eventoId) async =>
      [for (final a in listaAnulaciones) if (a.eventoId == eventoId) a];

  @override
  Future<List<VerificacionEntradas>> verificaciones(String eventoId) async =>
      [for (final v in listaVerificaciones) if (v.eventoId == eventoId) v];

  @override
  Future<List<VentaEntradas>> ventasDeLaCaja(String cajaId) async => [
        for (final v in listaVentas) if (v.cajaEntradasId == cajaId) v,
      ]..sort((a, b) => a.numero.compareTo(b.numero));

  @override
  Future<List<AnulacionEntradas>> anulacionesDeLaCaja(String cajaId) async =>
      [for (final a in listaAnulaciones) if (a.cajaEntradasId == cajaId) a];

  @override
  Future<int> ventasSinSubir() async => sinSubir;

  @override
  Future<int> cambiosSinSubir() async => cambiosPendientes;

  // ── El jefe ────────────────────────────────────────────────────────────────

  @override
  Future<ConfigEntradas> guardarConfig(
    ConfigEntradas config, {
    required String quien,
  }) async {
    final ya = configs[config.eventoId];
    if (ya != null && ya.mismosPreciosQue(config)) return ya;
    _escribir();
    return configs[config.eventoId] = config.sellada(
      hechoPor: quien,
      deviceId: equipo,
      createdAt: ya?.createdAt,
      ahora: reloj(),
    );
  }

  @override
  Future<AnulacionEntradas> anular(
    VentaEntradas venta, {
    required String motivo,
    required bool devueltas,
    required String quien,
  }) async {
    for (final a in listaAnulaciones) {
      if (a.ventaId == venta.id) return a;
    }
    final nueva = AnulacionEntradas.de(
      venta,
      motivo: motivo,
      devueltas: devueltas,
      hechoPor: quien,
      deviceId: equipo,
      ahora: reloj(),
    );
    _escribir();
    listaAnulaciones.add(nueva);
    return nueva;
  }

  @override
  Future<VerificacionEntradas> verificar(
    VentaEntradas venta, {
    required bool verificado,
    required String quien,
  }) async {
    final i = listaVerificaciones.indexWhere((v) => v.ventaId == venta.id);
    final nueva = VerificacionEntradas.de(
      venta,
      verificado: verificado,
      hechoPor: quien,
      deviceId: equipo,
      createdAt: i < 0 ? null : listaVerificaciones[i].createdAt,
      ahora: reloj(),
    );
    _escribir();
    if (i < 0) {
      listaVerificaciones.add(nueva);
    } else {
      listaVerificaciones[i] = nueva;
    }
    return nueva;
  }

  // ── La caja ────────────────────────────────────────────────────────────────

  @override
  Future<CajaEntradas?> cajaAbierta({
    required String eventoId,
    String? operadorId,
  }) async {
    for (final c in listaCajas.reversed) {
      if (c.eventoId == eventoId &&
          c.abierta &&
          c.operadorId == operadorId &&
          c.deviceId == equipo) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<CajaEntradas> abrirCaja({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    double cambioInicial = 0,
  }) async {
    final ya = await cajaAbierta(eventoId: eventoId, operadorId: operadorId);
    if (ya != null) return ya;
    final ahora = reloj();
    final caja = CajaEntradas.abrir(
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: operadorNombre,
      cambioInicial: cambioInicial,
      ahora: ahora,
    ).sellada(hechoPor: operadorNombre, deviceId: equipo, ahora: ahora);
    _escribir();
    listaCajas.add(caja);
    return caja;
  }

  int _donde(CajaEntradas caja) {
    final i = listaCajas.indexWhere((c) => c.id == caja.id);
    if (i < 0) throw StateError('la caja de entradas no está en este equipo');
    return i;
  }

  @override
  Future<CajaEntradas> cerrarCaja(
    CajaEntradas caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    final i = _donde(caja);
    if (!listaCajas[i].abierta) return listaCajas[i];
    final ahora = reloj();
    final cerrada = listaCajas[i]
        .cerrada(
          efectivoContado: efectivoContado,
          diferencia: diferencia,
          nota: nota,
          ahora: ahora,
        )
        .sellada(hechoPor: quien, deviceId: equipo, ahora: ahora);
    _escribir();
    return listaCajas[i] = cerrada;
  }

  @override
  Future<CajaEntradas> anotarCierre(
    CajaEntradas caja, {
    String? nota,
    required String quien,
  }) async {
    final i = _donde(caja);
    if (listaCajas[i].abierta) return listaCajas[i];
    _escribir();
    return listaCajas[i] = listaCajas[i]
        .conNota(nota)
        .sellada(hechoPor: quien, deviceId: equipo, ahora: reloj());
  }

  @override
  Future<VentaEntradas> vender({
    required CajaEntradas caja,
    String? contratoAlumnoId,
    required String compradorNombre,
    String? compradorDni,
    required List<RenglonEntradas> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    String? numeros,
    required String quien,
  }) async {
    final i = _donde(caja);
    if (!listaCajas[i].abierta) {
      throw StateError('la caja de entradas está cerrada');
    }
    final ultimo = listaVentas
        .where((v) => v.cajaEntradasId == caja.id)
        .fold(0, (m, v) => v.numero > m ? v.numero : m);
    final venta = VentaEntradas.nueva(
      cajaEntradasId: caja.id,
      eventoId: caja.eventoId,
      numero: ultimo + 1,
      contratoAlumnoId: contratoAlumnoId,
      compradorNombre: compradorNombre,
      compradorDni: compradorDni,
      renglones: renglones,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      recargo: recargo,
      recargoPct: recargoPct,
      numeros: numeros,
      hechoPor: quien,
      deviceId: equipo,
      ahora: reloj(),
    );
    _escribir();
    listaVentas.add(venta);
    sinSubir++;
    return venta;
  }
}
