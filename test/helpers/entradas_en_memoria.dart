// La venta de entradas en memoria, para montar sus pantallas sin base ni nube.
// Hace lo mismo que `EntradasLocal`: guardar sin cambiar nada no escribe, el
// número del comprobante es por caja, una caja cerrada no se vuelve a cerrar y
// anular dos veces devuelve la que ya había. Las entradas para rendir (v82,
// 20-nov-2026), igual: rendir vuelve a contar lo que le queda al bloque y
// guarda todo o nada, y un bloque se anula solo sin movimientos en pie.
import 'dart:math' show max;

import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;
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
  final listaParaRendir = <MovimientoParaRendir>[];

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

  /// Con esto prendido, después de la próxima rendición leer las entradas para
  /// rendir tira: la rendición se guarda y la relectura de VENDER no anda.
  bool fallaLeerDespuesDeRendir = false;
  bool _leerParaRendirFalla = false;

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
  Future<List<MovimientoParaRendir>> paraRendir(String eventoId) async {
    if (_leerParaRendirFalla) throw StateError('no se pudo leer (prueba)');
    return [for (final m in listaParaRendir) if (m.eventoId == eventoId) m];
  }

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
    final venta = _ventaNueva(
      caja: caja,
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
      quien: quien,
    );
    _escribir();
    listaVentas.add(venta);
    sinSubir++;
    return venta;
  }

  /// La venta armada, con su número, **sin guardarla**: la usan [vender] y
  /// [rendir] (que guarda la venta junto con sus renglones, o nada).
  VentaEntradas _ventaNueva({
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
  }) {
    final i = _donde(caja);
    if (!listaCajas[i].abierta) {
      throw StateError('la caja de entradas está cerrada');
    }
    final ultimo = listaVentas
        .where((v) => v.cajaEntradasId == caja.id)
        .fold(0, (m, v) => v.numero > m ? v.numero : m);
    return VentaEntradas.nueva(
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
  }

  // ── Las entradas para rendir ───────────────────────────────────────────────

  MovimientoParaRendir _bloqueGuardado(MovimientoParaRendir bloque) {
    for (final m in listaParaRendir) {
      if (m.id == bloque.id) {
        if (!m.esDio) {
          throw StateError('lo que se quiere rendir no es un bloque dado');
        }
        return m;
      }
    }
    throw StateError('el bloque para rendir no está en este equipo');
  }

  Set<String> get _ventasAnuladas => {for (final a in listaAnulaciones) a.ventaId};

  List<MovimientoParaRendir> _vigentes(MovimientoParaRendir bloque) =>
      MovimientoParaRendir.vigentesDe(
        bloque,
        listaParaRendir,
        ventasAnuladas: _ventasAnuladas,
      );

  int _quedan(MovimientoParaRendir bloque) => MovimientoParaRendir.quedanSinRendir(
        bloque,
        listaParaRendir,
        ventasAnuladas: _ventasAnuladas,
      );

  /// Como en `EntradasLocal`: un número que ya volvió o se dio por perdido.
  int? _yaNoLoTiene(MovimientoParaRendir bloque, List<TramoTalonario> tramos) {
    for (final m in _vigentes(bloque)) {
      if (!m.esDevolvio && !m.esNoVolvieron) continue;
      for (final suyo in m.tramos) {
        for (final t in tramos) {
          if (t.seCruzaCon(suyo)) return max(t.desde, suyo.desde);
        }
      }
    }
    return null;
  }

  @override
  Future<MovimientoParaRendir> darParaRendir({
    required String eventoId,
    required String personaNombre,
    String? personaContacto,
    String? contratoAlumnoId,
    required int cantidad,
    required List<TramoTalonario> numeros,
    required double precio,
    required String nombrePrecio,
    String? nota,
    required String quien,
  }) async {
    final dio = MovimientoParaRendir.dio(
      eventoId: eventoId,
      personaNombre: personaNombre,
      personaContacto: personaContacto,
      contratoAlumnoId: contratoAlumnoId,
      cantidad: cantidad,
      tramos: numeros,
      precio: precio,
      nombrePrecio: nombrePrecio,
      nota: nota,
      hechoPor: quien,
      deviceId: equipo,
      ahora: reloj(),
    );
    _escribir();
    listaParaRendir.add(dio);
    return dio;
  }

  @override
  Future<RendicionDeEntradas> rendir({
    CajaEntradas? caja,
    required MovimientoParaRendir bloque,
    required int vendidas,
    int devueltas = 0,
    List<TramoTalonario> numerosDevueltos = const [],
    MedioBarra medio = MedioBarra.efectivo,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  }) async {
    Never no(String por) => throw ArgumentError('la rendición no cierra: $por');
    if (vendidas < 0 || devueltas < 0) no('las cantidades van de 0 en adelante');
    if (vendidas + devueltas < 1) no('no vendió ni devolvió nada');
    final numeros = numerosDevueltos.fold<int>(0, (s, t) => s + t.cantidad);
    if (numeros != devueltas) no('devuelve $devueltas y vienen $numeros números');
    if (vendidas > 0 && caja == null) no('lo vendido se cobra con la caja abierta');
    if (vendidas == 0 && (efectivo != 0 || transferencia != 0 || recargo != 0)) {
      no('si solo devuelve, no entra plata');
    }
    // Todo se arma antes de guardar nada: si algo no cierra, no queda nada.
    final guardado = _bloqueGuardado(bloque);
    // Como en `EntradasLocal`: la caja y la fiesta, como están guardadas. Si
    // solo devuelve, el renglón lleva la caja solo si está acá y abierta.
    CajaEntradas? guardada;
    if (caja != null) {
      for (final c in listaCajas) {
        if (c.id == caja.id) guardada = c;
      }
    }
    if (guardada != null && guardada.eventoId != guardado.eventoId) {
      no('la caja es de otra fiesta');
    }
    final cajaQueRecibe = guardada != null && guardada.abierta ? guardada.id : null;
    final devolvio = devueltas == 0
        ? null
        : MovimientoParaRendir.devolvio(
            guardado,
            tramos: numerosDevueltos,
            cajaEntradasId: cajaQueRecibe,
            hechoPor: quien,
            deviceId: equipo,
            ahora: reloj(),
          );
    final quedan = _quedan(guardado);
    if (vendidas + devueltas > quedan) {
      throw StateError('cambió algo: le quedan $quedan sin rendir');
    }
    final yaNo = _yaNoLoTiene(guardado, numerosDevueltos);
    if (yaNo != null) throw StateError('cambió algo: el $yaNo ya no lo tiene');
    VentaEntradas? venta;
    MovimientoParaRendir? vendio;
    if (vendidas > 0) {
      final precio = guardado.precio;
      if (precio == null || precio <= 0) {
        throw StateError('el bloque para rendir no tiene precio');
      }
      venta = _ventaNueva(
        caja: guardada ?? caja!,
        compradorNombre: guardado.personaNombre ?? '',
        renglones: [
          RenglonEntradas.suelta(
            nombre: '${guardado.nombrePrecio ?? 'Entrada'}'
                '${MovimientoParaRendir.sufijoDelRenglon}',
            precioLista: precio,
            descuentoPct: 0,
            cantidad: vendidas,
          ),
        ],
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        recibe: recibe,
        recargo: recargo,
        recargoPct: recargoPct,
        quien: quien,
      );
      vendio = MovimientoParaRendir.vendio(
        guardado,
        cantidad: vendidas,
        ventaId: venta.id,
        cajaEntradasId: venta.cajaEntradasId,
        hechoPor: quien,
        deviceId: equipo,
        ahora: reloj(),
      );
    }
    _escribir();
    if (venta != null) {
      listaVentas.add(venta);
      sinSubir++;
    }
    if (vendio != null) listaParaRendir.add(vendio);
    if (devolvio != null) listaParaRendir.add(devolvio);
    if (fallaLeerDespuesDeRendir) _leerParaRendirFalla = true;
    return RendicionDeEntradas(venta: venta, vendio: vendio, devolvio: devolvio);
  }

  @override
  Future<MovimientoParaRendir> noVolvieron(
    MovimientoParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> numeros = const [],
    required String motivo,
    required String quien,
  }) async {
    final guardado = _bloqueGuardado(bloque);
    final perdidas = MovimientoParaRendir.noVolvieron(
      guardado,
      cantidad: cantidad,
      tramos: numeros,
      motivo: motivo,
      hechoPor: quien,
      deviceId: equipo,
      ahora: reloj(),
    );
    final quedan = _quedan(guardado);
    if (cantidad > quedan) {
      throw StateError('cambió algo: le quedan $quedan sin rendir');
    }
    final yaNo = _yaNoLoTiene(guardado, numeros);
    if (yaNo != null) throw StateError('cambió algo: el $yaNo ya no lo tiene');
    _escribir();
    listaParaRendir.add(perdidas);
    return perdidas;
  }

  @override
  Future<MovimientoParaRendir> anularDeParaRendir(
    MovimientoParaRendir movimiento, {
    required String motivo,
    required String quien,
  }) async {
    final ahora = reloj();
    final nueva = MovimientoParaRendir.anulo(
      movimiento,
      motivo: motivo,
      hechoPor: quien,
      deviceId: equipo,
      ahora: ahora,
    );
    for (final m in listaParaRendir) {
      if (m.id == nueva.id) return m;
    }
    final i = listaParaRendir.indexWhere((m) => m.id == movimiento.id);
    if (i < 0) throw StateError('lo que se quiere anular no está en este equipo');
    final guardado = listaParaRendir[i];
    if (guardado.esDio && _vigentes(guardado).isNotEmpty) {
      throw StateError('el bloque tiene movimientos: anulá primero lo que tiene');
    }
    final anulo = MovimientoParaRendir.anulo(
      guardado,
      motivo: motivo,
      hechoPor: quien,
      deviceId: equipo,
      ahora: ahora,
    );
    _escribir();
    listaParaRendir.add(anulo);
    return anulo;
  }
}
