// Ventana de prueba de la venta de entradas (6.9.0, etapa 7): **la tablet de Carla a
// la izquierda y la PC del jefe a la derecha, cada una con su base, sobre la misma
// fiesta**, sin tocar la base de la PC ni la nube. Carla vende, mira sus ventas y cierra
// su caja; el jefe pone los precios, mira VENTAS (verifica, anula, imprime), la entrega
// sin cargo con lo vendido a la vista y ENTRADAS en el cierre de caja. Lo que hace uno le
// llega al otro como en la app: lo que un equipo guarda sube a los 2 s y el otro lo baja.
// Al cerrar la ventana se olvida todo.
//
//   flutter run -d windows -t tool/venta_entradas_prueba.dart
//
// No corre `main.dart`: no abre la base (`LocalDatabase.cerrarParaLaPrueba`) ni inicia
// sesión. Arriba de cada lado, su barra:
// - Carla: VER COMO CELULAR / TABLET (el ancho de su lado), lo que tiene sin subir y
//   CORTAR INTERNET, que vale para los dos: sin internet nada cruza, lo de cada equipo
//   queda en su cola y el otro no lo ve; al volver, sube y le llega;
// - el jefe: MODO JEFE SÍ / NO (para ver lo apagado con su motivo), ENTRADAS DE LA FIESTA
//   (la entrega de la oficina, con PRECIOS, VENTAS y VENDER) y CIERRE DE CAJA (COBROS ·
//   BARRA · ENTRADAS).
//
// La noche arranca así: PUERTO VIEJO con precio (la entrada $ 10.000, la anticipada
// $ 8.000 hasta el 28-nov, los lugares al 50 %); Carla todavía sin caja; la caja de Maxi
// (otra tablet) ya cerrada, con $ 500 de menos; PÉREZ, JUAN con 8 lugares al 50 % y
// ninguna comprada; GÓMEZ, ANA ya retiró las suyas (1001 a 1007). Con
// `--dart-define=ventas=muchas`, la caja de Maxi trae 700 ventas más (para ver el
// cartel Todo junto · Por hojas de IMPRIMIR HISTORIAL).
//
// Lo que no es como en la app:
// - las entregas sin cargo se comparten al instante entre los dos lados (con o sin
//   internet); lo que va y viene con la subida es la venta de entradas;
// - los papeles de la venta (el comprobante, el historial y el cierre) son los de la
//   app, pero quedan en build/venta_entradas_prueba y se abren con el visor, sin el menú
//   de la app (que los dejaría en la carpeta del programa);
// - COBROS, en el cierre de caja, muestra un día fijo;
// - no usar el ícono de la impresora de la entrega ni los PDF de COBROS: salen por el
//   camino de la app, a la carpeta del programa.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/cierre_caja/cierre_caja_screen.dart';
import 'package:arguello_events/features/cierre_caja/providers/cierre_caja_provider.dart';
import 'package:arguello_events/features/common/providers/admin_provider.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/common/utils/subir_ya.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';
import 'package:arguello_events/features/entradas/cuentas/cierre_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/pdf/cierre_caja_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/cierre_en_memoria.dart' show CierreDePrueba, ModoJefeDelCierre;
import '../test/helpers/entradas_en_memoria.dart';
import '../test/helpers/entrega_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart' show ConexionFija;
import '../test/helpers/puerta_en_memoria.dart' show MotorDePrueba;
import '../test/helpers/tema_de_la_app.dart';
import 'raiz_del_proyecto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  // Las preferencias, en memoria: no las del programa instalado.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  GoogleFonts.config.allowRuntimeFetching = false;
  final lados = await armarLados(
    papeles: PapelesDeLaPrueba(
      carpeta: carpetaEnBuild('venta_entradas_prueba'),
      abrirConElVisor: true,
    ),
  );
  runApp(PruebaDeLaVenta(lados));
  unawaited(_agrandarCuandoSeVea());
}

/// Como la de la barra: se agranda cuando ya se ve.
Future<void> _agrandarCuandoSeVea() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle('Prueba de la venta de entradas · Carla y el jefe');
    await windowManager.maximize();
  } catch (_) {}
}

// ── Los dos equipos y la nube ───────────────────────────────────────────────

/// La base de un equipo de la prueba. Lo que escribe queda en su cola ([pendientes])
/// y, con internet, sube: llega a la base del otro equipo y el otro "baja".
class EntradasDeUnEquipo extends EntradasEnMemoria {
  EntradasDeUnEquipo({required super.equipo});

  /// null mientras se arma la noche: lo de antes no va a ninguna cola.
  NubeDeLaPrueba? nube;

  /// Lo escrito en este equipo que todavía no subió, en orden.
  final pendientes = <({String tabla, Object fila})>[];

  /// Las horas de verdad (la venta en memoria trae una fija).
  @override
  DateTime reloj() => DateTime.now().toUtc();

  Future<T> _sube<T extends Object>(String tabla, Future<T> Function() escribir) async {
    final antes = escrituras;
    final fila = await escribir();
    // Sin escritura (guardar sin cambios, anular dos veces) no hay nada que subir.
    if (escrituras != antes && nube != null) {
      pendientes.add((tabla: tabla, fila: fila));
      nube!.escribio(this);
    }
    return fila;
  }

  @override
  Future<CajaEntradas> abrirCaja({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    double cambioInicial = 0,
  }) =>
      _sube(
        'entradas_cajas',
        () => super.abrirCaja(
          eventoId: eventoId,
          operadorId: operadorId,
          operadorNombre: operadorNombre,
          cambioInicial: cambioInicial,
        ),
      );

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
  }) =>
      _sube(
        'entradas_ventas',
        () => super.vender(
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
        ),
      );

  @override
  Future<CajaEntradas> cerrarCaja(
    CajaEntradas caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) =>
      _sube(
        'entradas_cajas',
        () => super.cerrarCaja(
          caja,
          efectivoContado: efectivoContado,
          diferencia: diferencia,
          nota: nota,
          quien: quien,
        ),
      );

  @override
  Future<CajaEntradas> anotarCierre(CajaEntradas caja, {String? nota, required String quien}) =>
      _sube('entradas_cajas', () => super.anotarCierre(caja, nota: nota, quien: quien));

  @override
  Future<AnulacionEntradas> anular(
    VentaEntradas venta, {
    required String motivo,
    required bool devueltas,
    required String quien,
  }) =>
      _sube(
        'entradas_anulaciones',
        () => super.anular(venta, motivo: motivo, devueltas: devueltas, quien: quien),
      );

  @override
  Future<VerificacionEntradas> verificar(
    VentaEntradas venta, {
    required bool verificado,
    required String quien,
  }) =>
      _sube(
        'entradas_verificaciones',
        () => super.verificar(venta, verificado: verificado, quien: quien),
      );

  @override
  Future<ConfigEntradas> guardarConfig(ConfigEntradas config, {required String quien}) =>
      _sube('entradas_config', () => super.guardarConfig(config, quien: quien));

  /// Lo que bajó del otro equipo. Como `BarraLocal.guardarDeOtroEquipo`: no va a la
  /// cola ni cuenta como escrito acá.
  void ponerDeOtroEquipo(Object fila) {
    void poner<T>(List<T> lista, T nueva, bool Function(T) igual) {
      final i = lista.indexWhere(igual);
      if (i < 0) {
        lista.add(nueva);
      } else {
        lista[i] = nueva;
      }
    }

    switch (fila) {
      case ConfigEntradas c:
        configs[c.eventoId] = c;
      case CajaEntradas c:
        poner(listaCajas, c, (x) => x.id == c.id);
      case VentaEntradas v:
        poner(listaVentas, v, (x) => x.id == v.id);
      case AnulacionEntradas a:
        poner(listaAnulaciones, a, (x) => x.id == a.id);
      case VerificacionEntradas v:
        poner(listaVerificaciones, v, (x) => x.ventaId == v.ventaId);
    }
  }
}

/// Un lado de la ventana: su base, su motor de mentira y sus providers.
class LadoDeLaVenta {
  LadoDeLaVenta(this.nombre, this.entradas, this.motor);

  final String nombre;
  final EntradasDeUnEquipo entradas;
  final MotorDePrueba motor;
  late final ProviderContainer c;

  /// Lo que en la app hace el motor al bajar algo nuevo: avisa por
  /// `cambiosBajadosStream` (VENDER, VENTAS y la entrega releen) y el coordinador sube
  /// la revisión (el cierre de caja, el inicio de Entradas).
  void bajo(Set<String> tablas) {
    motor.bajo.add(tablas);
    c.read(operationalSyncRevisionProvider.notifier).bump();
  }
}

/// La nube de la prueba: lo que un equipo guarda sube a los [demora] (como el motor,
/// que sube a los 2 s de guardar) y el otro lo baja. Sin internet, nada cruza.
class NubeDeLaPrueba {
  NubeDeLaPrueba(this.conexion, {required this.demora});

  final ConexionFija conexion;
  final Duration demora;
  late final LadoDeLaVenta tablet;
  late final LadoDeLaVenta pc;

  /// Para las barras de arriba: cambia cada vez que algo se escribe o sube.
  final cambios = ValueNotifier<int>(0);

  bool get hayInternet => conexion.currentStatus == AppConnectivity.online;

  LadoDeLaVenta _ladoDe(EntradasDeUnEquipo e) => identical(e, tablet.entradas) ? tablet : pc;
  LadoDeLaVenta _otro(LadoDeLaVenta lado) => identical(lado, tablet) ? pc : tablet;

  void escribio(EntradasDeUnEquipo desde) {
    cambios.value++;
    // Sin internet, la subida no hace nada y queda en la cola (lo dice [_subir]).
    final lado = _ladoDe(desde);
    // En los tests sube en el momento (con el reloj de las pruebas, una espera
    // quedaría colgada).
    if (demora == Duration.zero) {
      _subir(lado);
    } else {
      unawaited(Future<void>.delayed(demora, () => _subir(lado)));
    }
  }

  /// Sube la cola de [lado]: la copia a la base del otro, que la baja. Quien escribió no
  /// baja nada (como en la app: el aviso del motor sale al bajar, no al subir).
  Set<String> _subir(LadoDeLaVenta lado) {
    final e = lado.entradas;
    if (!hayInternet || e.pendientes.isEmpty) return const {};
    final otro = _otro(lado);
    final tablas = {for (final p in e.pendientes) p.tabla};
    for (final p in e.pendientes) {
      otro.entradas.ponerDeOtroEquipo(p.fila);
    }
    e.pendientes.clear();
    e.sinSubir = 0;
    // Como el motor después de subir: avisa lo que queda en la cola (VENDER vuelve a
    // contar su línea).
    lado.motor.pendiente.add(0);
    otro.bajo(tablas);
    cambios.value++;
    return tablas;
  }

  /// Una entrega sin cargo que subió: el otro la baja. Las entregas viven en memoria y
  /// se comparten, así que lo único que cruza es el aviso.
  bool entregaSubio(LadoDeLaVenta desde, String tabla) {
    if (!hayInternet) return false;
    _otro(desde).bajo({tabla});
    return true;
  }

  /// VOLVER EL INTERNET: suben las dos colas. Como `SyncEngine` al volver la red:
  /// después de subir baja lo del cobro, y lo propio vuelve con la hora de la nube, así
  /// que también quien subió relee.
  void volvio() {
    for (final lado in [tablet, pc]) {
      final subio = _subir(lado);
      if (subio.isNotEmpty) lado.bajo(subio);
    }
  }
}

/// La subida inmediata de las entregas: sube (o no, sin internet) y avisa al otro.
class SubidaQueAvisa extends SubidaInmediata {
  SubidaQueAvisa(super.motor, this.subio);

  final bool Function(String tabla) subio;

  @override
  Future<bool> subir({
    required String tabla,
    required String registroId,
    required DateTime desde,
  }) async =>
      subio(tabla);
}

/// Los papeles de la venta: los mismos PDF de la app, guardados en [carpeta] y abiertos
/// con el visor de Windows (sin el menú de la app, que los dejaría en la carpeta del
/// programa). Sin [carpeta] (los tests), solo se anotan.
class PapelesDeLaPrueba {
  PapelesDeLaPrueba({this.carpeta, this.abrirConElVisor = false});

  final Directory? carpeta;
  final bool abrirConElVisor;
  final comprobantes = <DatosDelComprobante>[];
  final cierres = <DatosDelCierreDeEntradas>[];
  final historiales = <DatosDelHistorial>[];
  final archivos = <String>[];

  Future<void> _guardar(String lado, String nombre, Future<List<int>> Function() armar) async {
    final carpeta = this.carpeta;
    if (carpeta == null) return;
    final bytes = await armar();
    carpeta.createSync(recursive: true);
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    final hora = '${dos(ahora.hour)}${dos(ahora.minute)}${dos(ahora.second)}';
    final conPdf = nombre.toLowerCase().endsWith('.pdf') ? nombre : '$nombre.pdf';
    final archivo = File('${carpeta.path}${Platform.pathSeparator}${hora}_${lado}_$conPdf')
      ..writeAsBytesSync(bytes);
    archivos.add(archivo.path);
    if (abrirConElVisor) await Process.run('cmd', ['/c', 'start', '', archivo.path]);
  }

  List<Override> reemplazos(String lado) => [
        abrirComprobanteDeEntradasProvider.overrideWithValue((d, {context}) async {
          comprobantes.add(d);
          await _guardar(
            lado,
            ComprobanteEntradasPdf.nombreDelArchivo(d),
            () async => ComprobanteEntradasPdf.armar(
              d,
              fuentes: await PdfService.fuentesOutfit(),
              logo: await isotipoDeLosPapeles(),
            ),
          );
        }),
        abrirCierreDeEntradasProvider.overrideWithValue((d, {context}) async {
          cierres.add(d);
          await _guardar(
            lado,
            CierreCajaEntradasPdf.nombreDelArchivo(d),
            () async => CierreCajaEntradasPdf.armar(
              d,
              fuentes: await PdfService.fuentesOutfit(),
              logo: await isotipoDeLosPapeles(),
            ),
          );
        }),
        abrirHistorialDeEntradasProvider.overrideWithValue((d, {context}) async {
          historiales.add(d);
          await _guardar(
            lado,
            HistorialEntradasPdf.nombreDelArchivo(d),
            () async => HistorialEntradasPdf.armar(
              d,
              fuentes: await PdfService.fuentesOutfit(),
              logo: await isotipoDeLosPapeles(),
            ),
          );
        }),
      ];
}

/// Los dos lados de la ventana, cada uno con sus providers y su base.
class LadosDeLaVenta {
  LadosDeLaVenta._({
    required this.carla,
    required this.jefe,
    required this.tablet,
    required this.pc,
    required this.nube,
    required this.entrega,
    required this.papeles,
    required this.operadora,
    required this.cajaDeMaxi,
  });

  /// Los providers de la tablet de Carla y los de la PC del jefe.
  final ProviderContainer carla;
  final ProviderContainer jefe;

  /// La base de cada equipo.
  final EntradasDeUnEquipo tablet;
  final EntradasDeUnEquipo pc;
  final NubeDeLaPrueba nube;
  final EntregaEnMemoria entrega;
  final PapelesDeLaPrueba papeles;
  final OperadorCaja operadora;

  /// La caja de Maxi, la otra tablet: ya cerrada, con $ 500 de menos.
  final CajaEntradas cajaDeMaxi;

  bool get hayInternet => nube.hayInternet;

  /// CORTAR INTERNET y VOLVER EL INTERNET, para los dos lados.
  void cambiarInternet() {
    final vuelve = !hayInternet;
    entrega.conexion.cambiar(vuelve ? AppConnectivity.online : AppConnectivity.offline);
    if (vuelve) nube.volvio();
    nube.cambios.value++;
  }

  /// Carla vuelve a entrar con su PIN (después de SALIR).
  Future<void> entrarCarla() => carla.read(appRoleProvider.notifier).entrarComoEntradas(
        operadora,
        const PermisosEfectivos(entradas: true, vendeEntradas: true),
      );

  void dispose() {
    carla.dispose();
    jefe.dispose();
    nube.cambios.dispose();
  }
}

/// Arma la noche y los dos lados. [demoraDeSubida]: lo que tarda en subir lo guardado
/// (en los tests, nada). [hoy] y [relojDelJefe]: el día de la venta y el del cierre de
/// caja (en la ventana, los de verdad; los tests los fijan).
Future<LadosDeLaVenta> armarLados({
  Duration demoraDeSubida = const Duration(seconds: 2),
  DateTime Function()? hoy,
  DateTime Function()? relojDelJefe,
  PapelesDeLaPrueba? papeles,
}) async {
  final entrega = EntregaEnMemoria();
  final carla = entrega.operador(vende: true);
  final losPapeles = papeles ?? PapelesDeLaPrueba();
  final tablet = EntradasDeUnEquipo(equipo: 'tablet-carla');
  final pc = EntradasDeUnEquipo(equipo: 'pc-oficina');
  final cajaDeMaxi = await _armarLaNoche(pc: pc, tablet: tablet);

  final nube = NubeDeLaPrueba(entrega.conexion, demora: demoraDeSubida);
  nube.tablet = LadoDeLaVenta('tablet', tablet, entrega.motor);
  nube.pc = LadoDeLaVenta('pc', pc, MotorDePrueba());
  tablet.nube = nube;
  pc.nube = nube;

  // La fiesta, para el inicio de Entradas y para el cierre de caja (BARRA y ENTRADAS).
  final fiestas = [fiestaDeLaEntrega];
  final barra = BarraEnPrueba()..eventos.addAll(fiestas);

  List<Override> comunes(LadoDeLaVenta lado) => [
        ...entrega.operadores.reemplazos,
        supabaseProvider.overrideWithValue(entrega.supabase),
        contratosRepositoryProvider.overrideWithValue(entrega.contratos),
        entradasRetiroRepositoryProvider.overrideWithValue(entrega.entregas),
        syncEngineProvider.overrideWithValue(lado.motor),
        subidaInmediataProvider.overrideWithValue(
          SubidaQueAvisa(lado.motor, (tabla) => nube.entregaSubio(lado, tabla)),
        ),
        ...lado.entradas.reemplazos,
        enLaWebProvider.overrideWithValue(false),
        if (hoy != null) hoyEnArgentinaProvider.overrideWithValue(hoy),
      ];

  nube.tablet.c = ProviderContainer(overrides: [
    ...comunes(nube.tablet),
    userRoleProvider.overrideWith((ref) async => const UserRoleState(isLoading: false)),
    fiestasQueVienenProvider.overrideWith((ref) async {
      ref.watch(operationalSyncRevisionProvider);
      return fiestas;
    }),
    ...losPapeles.reemplazos('carla'),
  ]);

  nube.pc.c = ProviderContainer(overrides: [
    ...comunes(nube.pc),
    userRoleProvider.overrideWith(
      (ref) async => const UserRoleState(isLoading: false, nombre: 'Jefe'),
    ),
    // Una sola llave para todo el lado del jefe: `esRolJefeProvider` la lee (PRECIOS,
    // VENTAS, anular, verificar, VENDER) y el cierre de caja también (sus pestañas).
    adminAuthProvider.overrideWith(() => ModoJefeDelCierre(true)),
    // COBROS con un día fijo: no lee la base ni sube nada.
    cierreCajaProvider.overrideWith(CierreDePrueba.new),
    // BARRA, en memoria y sin cajas; y la fiesta para el cierre.
    ...barra.reemplazos,
    barraDelJefeProvider.overrideWithValue(barra.barra),
    if (relojDelJefe != null) relojDelJefeProvider.overrideWithValue(relojDelJefe),
    ...losPapeles.reemplazos('jefe'),
  ]);
  // autoDispose: sin alguien escuchando, quien anula figura "Sin identificar".
  nube.pc.c.listen(userRoleProvider, (_, _) {});

  await nube.tablet.c.read(appRoleProvider.notifier).entrarComoEntradas(
        carla,
        const PermisosEfectivos(entradas: true, vendeEntradas: true),
      );

  return LadosDeLaVenta._(
    carla: nube.tablet.c,
    jefe: nube.pc.c,
    tablet: tablet,
    pc: pc,
    nube: nube,
    entrega: entrega,
    papeles: losPapeles,
    operadora: carla,
    cajaDeMaxi: cajaDeMaxi,
  );
}

/// `--dart-define=ventas=muchas`: la caja de Maxi con 700 ventas más, para que el
/// historial pase las 10 hojas y IMPRIMIR HISTORIAL pregunte cómo imprimir.
const _conMuchasVentas = String.fromEnvironment('ventas') == 'muchas';

/// El precio de PUERTO VIEJO y la caja de Maxi (otra tablet), ya cerrada: en las dos
/// bases, como si ya hubiera subido y bajado. Devuelve la caja de Maxi.
Future<CajaEntradas> _armarLaNoche({
  required EntradasDeUnEquipo pc,
  required EntradasDeUnEquipo tablet,
}) async {
  final precio = pc.conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-28');
  tablet.ponerDeOtroEquipo(precio);

  final maxi = EntradasEnMemoria(
    equipo: 'tablet-maxi',
    ahora: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
  )..configs[idFiestaEntrega] = precio;
  final caja = await maxi.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: 'a0000000-0000-4000-8000-000000000202',
    operadorNombre: 'Maxi',
    cambioInicial: 2000,
  );
  RenglonEntradas anticipadas(int n) =>
      RenglonEntradas.suelta(nombre: 'Entrada anticipada', precioLista: 8000, cantidad: n);
  await maxi.vender(
    caja: caja,
    compradorNombre: 'GOMEZ, LUIS',
    renglones: [anticipadas(2)],
    medio: MedioBarra.efectivo,
    efectivo: 16000,
    numeros: '3001-3002',
    quien: 'Maxi',
  );
  final ruiz = await maxi.vender(
    caja: caja,
    compradorNombre: 'RUIZ, ANA',
    renglones: [anticipadas(1)],
    medio: MedioBarra.transferencia,
    transferencia: 8000,
    numeros: '3003',
    quien: 'Maxi',
  );
  final sosa = await maxi.vender(
    caja: caja,
    compradorNombre: 'SOSA, DIEGO',
    renglones: [anticipadas(1)],
    medio: MedioBarra.efectivo,
    efectivo: 8000,
    numeros: '3004',
    quien: 'Maxi',
  );
  if (_conMuchasVentas) {
    // Para ver el cartel de IMPRIMIR HISTORIAL (Todo junto · Por hojas): pasa las
    // 10 hojas. Nombres inventados.
    for (var i = 0; i < 700; i++) {
      await maxi.vender(
        caja: caja,
        compradorNombre: 'COMPRADOR DE PRUEBA ${i + 1}',
        renglones: [anticipadas(1)],
        medio: MedioBarra.efectivo,
        efectivo: 8000,
        numeros: '${4001 + i}',
        quien: 'Maxi',
      );
    }
  }
  await maxi.anular(sosa, motivo: 'se cargó dos veces', devueltas: true, quien: 'Jefe');
  await maxi.verificar(ruiz, verificado: true, quien: 'Jefe');
  // Contó $ 500 menos de lo que tenía que haber.
  final ventas = await maxi.ventasDeLaCaja(caja.id);
  final anulaciones = await maxi.anulacionesDeLaCaja(caja.id);
  final esperado = CierreDeEntradas.de(caja, ventas, anulaciones).efectivoEsperado;
  final contado = esperado - 500;
  final cerrada = await maxi.cerrarCaja(
    caja,
    efectivoContado: contado,
    diferencia: CierreDeEntradas.de(caja, ventas, anulaciones).diferenciaCon(contado),
    nota: 'faltó un billete de 500',
    quien: 'Maxi',
  );
  for (final base in [pc, tablet]) {
    for (final fila in <Object>[
      ...maxi.listaCajas,
      ...maxi.listaVentas,
      ...maxi.listaAnulaciones,
      ...maxi.listaVerificaciones,
    ]) {
      base.ponerDeOtroEquipo(fila);
    }
  }
  return cerrada;
}

// ── La ventana ──────────────────────────────────────────────────────────────

/// La ventana: Carla a la izquierda y el jefe a la derecha. **Cada lado es su propia
/// app** (su `MaterialApp`, sus diálogos y su ancho), como en la de la barra.
class PruebaDeLaVenta extends StatefulWidget {
  final LadosDeLaVenta lados;

  const PruebaDeLaVenta(this.lados, {super.key});

  @override
  State<PruebaDeLaVenta> createState() => _PruebaDeLaVentaState();
}

/// Lo que mira el jefe: la entrega de la fiesta (con PRECIOS, VENTAS y VENDER) o el
/// cierre de caja.
enum PestanaDelJefe { entradas, cierre }

class _PruebaDeLaVentaState extends State<PruebaDeLaVenta> {
  static const anchoTablet = 800.0;
  static const anchoCelular = 390.0;

  var _anchoCarla = anchoTablet;
  final _navCarla = GlobalKey<NavigatorState>();
  final _navJefe = GlobalKey<NavigatorState>();
  final _pestana = ValueNotifier(PestanaDelJefe.entradas);

  @override
  void dispose() {
    _pestana.dispose();
    super.dispose();
  }

  void _irA(PestanaDelJefe p) {
    _navJefe.currentState?.popUntil((r) => r.isFirst);
    _pestana.value = p;
  }

  Widget _barraCarla() {
    final l = widget.lados;
    final celular = _anchoCarla == anchoCelular;
    return ValueListenableBuilder<int>(
      valueListenable: l.nube.cambios,
      builder: (context, _, _) {
        final cola = l.tablet.pendientes.length;
        return _BarraDeArriba(
          color: const Color(0xFFFFF3CD),
          texto: 'CARLA · ${celular ? 'celular' : 'tablet'} · '
              '${cola == 0 ? 'todo subido' : 'sin subir: $cola'}',
          botones: [
            TextButton(
              key: const Key('prueba_ancho_carla'),
              onPressed: () =>
                  setState(() => _anchoCarla = celular ? anchoTablet : anchoCelular),
              child: Text(celular ? 'VER COMO TABLET' : 'VER COMO CELULAR'),
            ),
            TextButton(
              key: const Key('prueba_internet'),
              onPressed: () => setState(l.cambiarInternet),
              child: Text(l.hayInternet ? 'CORTAR INTERNET' : 'VOLVER EL INTERNET'),
            ),
          ],
        );
      },
    );
  }

  Widget _barraJefe() {
    final l = widget.lados;
    return ValueListenableBuilder<int>(
      valueListenable: l.nube.cambios,
      builder: (context, _, _) {
        final cola = l.pc.pendientes.length;
        return _BarraDeArriba(
          color: l.hayInternet ? const Color(0xFFDCEBFF) : const Color(0xFFFFD9D2),
          texto: l.hayInternet
              ? 'JEFE · la PC de la oficina${cola == 0 ? '' : ' · sin subir: $cola'}'
              : 'JEFE · sin internet: no ve lo que la tablet no subió',
          botones: [
            Consumer(
              builder: (context, ref, _) {
                final prendido = ref.watch(adminAuthProvider).esModoJefe;
                return TextButton(
                  key: const Key('prueba_modo_jefe'),
                  onPressed: () =>
                      (ref.read(adminAuthProvider.notifier) as ModoJefeDelCierre).poner(!prendido),
                  child: Text(prendido ? 'MODO JEFE: SÍ' : 'MODO JEFE: NO'),
                );
              },
            ),
            TextButton(
              key: const Key('prueba_jefe_entradas'),
              onPressed: () => _irA(PestanaDelJefe.entradas),
              child: const Text('ENTRADAS DE LA FIESTA'),
            ),
            TextButton(
              key: const Key('prueba_jefe_cierre'),
              onPressed: () => _irA(PestanaDelJefe.cierre),
              child: const Text('CIERRE DE CAJA'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lados;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: LayoutBuilder(
          builder: (context, c) {
            // Al jefe le quedan por lo menos 360: en una pantalla chica, la tablet se achica.
            final ancho = math.min(_anchoCarla, math.max(320.0, c.maxWidth - 366));
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: ancho,
                  child: UncontrolledProviderScope(
                    container: l.carla,
                    child: MaterialApp(
                      navigatorKey: _navCarla,
                      debugShowCheckedModeBanner: false,
                      theme: temaClaroDeLaApp(),
                      builder: (context, nav) => _Lado(arriba: _barraCarla(), child: nav!),
                      home: _Carla(entrar: l.entrarCarla),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: UncontrolledProviderScope(
                    container: l.jefe,
                    child: MaterialApp(
                      navigatorKey: _navJefe,
                      debugShowCheckedModeBanner: false,
                      theme: temaClaroDeLaApp(),
                      builder: (context, nav) => _Lado(arriba: _barraJefe(), child: nav!),
                      home: ValueListenableBuilder<PestanaDelJefe>(
                        valueListenable: _pestana,
                        // Se arma de nuevo en cada cambio: escondida, la entrega seguiría
                        // releyendo cada 15 s.
                        builder: (context, p, _) => switch (p) {
                          PestanaDelJefe.entradas => RetiroEntradasScreen(
                              key: const ValueKey('prueba_jefe_entrega'),
                              evento: fiestaDeLaEntrega,
                              onCobrar: (a) => _avisar(
                                context,
                                'Acá se abre el cobro de ${a.nombreAlumno}: '
                                'los cobros se prueban en la app.',
                              ),
                              onEditarAlumno: (a) => _avisar(
                                context,
                                'Acá se abre Editar alumno de ${a.nombreAlumno}.',
                              ),
                            ),
                          PestanaDelJefe.cierre => const CierreCajaScreen(),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<void> _avisar(BuildContext context, String texto) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(texto),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR'))],
        ),
      );
}

/// El lado de Carla: Entradas con "Vende entradas" (ENTREGAR · VENDER de verdad).
class _Carla extends ConsumerWidget {
  final Future<void> Function() entrar;

  const _Carla({required this.entrar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    if (app.esEntradas) return const EntradasHomeScreen();
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('prueba_carla_entrar'),
          onPressed: entrar,
          child: const Text('Carla salió. ENTRAR DE NUEVO'),
        ),
      ),
    );
  }
}

/// Un lado: su barra de prueba arriba y la app abajo, que mide solo su lado.
class _Lado extends StatelessWidget {
  final Widget arriba;
  final Widget child;

  const _Lado({required this.arriba, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        arriba,
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: c.biggest),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarraDeArriba extends StatelessWidget {
  final Color color;
  final String texto;
  final List<Widget> botones;

  const _BarraDeArriba({required this.color, required this.texto, required this.botones});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(texto, key: const Key('prueba_barra_texto')),
              ),
              ...botones,
            ],
          ),
        ),
      ),
    );
  }
}
