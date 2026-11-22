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
//   (la entrega de la oficina, con PRECIOS, VENTAS, VENDER y PARA RENDIR) y CIERRE DE
//   CAJA (COBROS · BARRA · ENTRADAS).
//
// Las entradas para rendir (21-nov-2026): el jefe, en PARA RENDIR, le da 20 a alguien
// (por ejemplo a PÉREZ, JUAN, de afuera, del 1201 al 1220); en la tablet, VENDER de
// Carla dice "Entradas para rendir: 1 persona" y con RENDIR le cobra lo vendido y le
// recibe lo que devuelve. Una rendición se anula en VENTAS del jefe. Rendir lo mismo
// en los dos equipos con CORTAR INTERNET da "rindió de más" al volver.
//
// PRECIOS, al guardar, pregunta si se ponen los mismos precios en otras fiestas: ofrece
// BAHÍA SERENA ([otraFiestaDeLosPrecios]), inventada, sin alumnos.
//
// **Ningún papel sale solo** (22-nov-2026): el comprobante, la constancia y el cierre
// salen con su botón (IMPRIMIR EL COMPROBANTE, IMPRIMIR LA CONSTANCIA, IMPRIMIR EL
// CIERRE).
//
// Desde el 20-nov-2026 Carla, que tiene "Vende entradas", ve **un solo botón por fiesta,
// VENDER**: adentro entrega lo sin cargo en dos partes (las pulseras VIP con cena y las
// generales, solo a quien pagó todo su contrato) y vende A PAGAR (cada mesa adicional y
// silla extra que ya está paga entera) y al público, del talonario de las anticipadas.
//
// La noche arranca así: PUERTO VIEJO con precio (la General $ 10.000, la ANTICIPADA
// $ 8.000 hasta el 28-nov, los lugares al 50 %), ya sorteada y con lo que cada familia
// tenía anotado; Carla todavía sin caja; la caja de Maxi (otra tablet) ya cerrada, con
// $ 500 de menos. Las familias, una de cada caso ([sumarLaNoche]):
// - ACOSTA, LUCÍA pagó todo: 2 acompañantes y una mesa adicional paga (8 con 50 %);
// - BENÍTEZ, TOMÁS debe una cuota, pero su mesa adicional está paga: no retira lo sin
//   cargo y sí compra lo de su mesa;
// - DÍAZ, NICOLÁS debe solo la mora;
// - PÉREZ, JUAN debe su mesa adicional: "a confirmar";
// - FERREYRA, MÍA agregó una silla después del sorteo y la pagó: 1 sin descuento, al
//   precio del día;
// - HERRERA, LUCAS tiene 3 acompañantes (el aviso del máximo);
// - IBARRA, CAMILA tiene 2 acompañantes, uno sin nombre;
// - LÓPEZ, SOFÍA, sin mesa adicional ni sillas;
// - GÓMEZ, ANA ya retiró las suyas con la 6.9.x (las 8 juntas, 1001 a 1007).
// Con `--dart-define=ventas=muchas`, la caja de Maxi trae 700 ventas más (para ver el
// cartel Todo junto · Por hojas de IMPRIMIR HISTORIAL).
//
// Lo que no es como en la app:
// - las entregas sin cargo se comparten al instante entre los dos lados (con o sin
//   internet); lo que va y viene con la subida es la venta de entradas;
// - la caja de cuotas: LA CAJA COBRA, arriba del jefe (o COBRAR en su entrega), le
//   cobra a una familia todo lo que debe, como si pagara en la caja de otra PC, y les
//   llega a los dos lados (con o sin internet);
// - los papeles de la venta (el comprobante, el historial, el cierre y la constancia de
//   las entradas para rendir), el de la caja de entregas (IMPRIMIR en el cierre de
//   caja → ENTRADAS) y la planilla de entrega
//   (PLANILLA de VENDER y la impresora de la entrega) son los de la app, pero quedan en
//   build/venta_entradas_prueba y se abren con el visor, sin el menú de la app (que los
//   dejaría en la carpeta del programa);
// - COBROS, en el cierre de caja, muestra un día fijo;
// - no usar los PDF de COBROS: salen por el camino de la app, a la carpeta del programa.

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
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/cierre_caja/cierre_caja_screen.dart';
import 'package:arguello_events/features/cierre_caja/providers/caja_de_entregas_provider.dart';
import 'package:arguello_events/features/cierre_caja/providers/cierre_caja_provider.dart';
import 'package:arguello_events/features/common/providers/admin_provider.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/common/services/entregas_sin_cargo_pdf.dart';
import 'package:arguello_events/features/common/services/imprimir_planilla_de_entrega.dart';
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
import 'package:arguello_events/features/entradas/pdf/para_rendir_pdf.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_entregas_repository.dart';
import 'package:arguello_events/features/eventos/repositories/entregar_parte_de_la_app.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_retiro_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/retiro_entradas_screen.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/entregar_parte.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;
import 'package:arguello_events/models/entrega_entradas.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

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

  /// Lo que no es una venta y espera subir (la caja, una anulación, los precios):
  /// la línea de VENDER lo cuenta como "cambios".
  @override
  Future<int> cambiosSinSubir() async =>
      pendientes.where((p) => p.tabla != 'entradas_ventas').length;

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

  // Las entradas para rendir (v82, 20-nov-2026): cada renglón sube por su tabla,
  // y la rendición sube su venta y sus renglones juntos.

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
  }) =>
      _sube(
        'entradas_para_rendir',
        () => super.darParaRendir(
          eventoId: eventoId,
          personaNombre: personaNombre,
          personaContacto: personaContacto,
          contratoAlumnoId: contratoAlumnoId,
          cantidad: cantidad,
          numeros: numeros,
          precio: precio,
          nombrePrecio: nombrePrecio,
          nota: nota,
          quien: quien,
        ),
      );

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
    final antes = escrituras;
    final r = await super.rendir(
      caja: caja,
      bloque: bloque,
      vendidas: vendidas,
      devueltas: devueltas,
      numerosDevueltos: numerosDevueltos,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      recargo: recargo,
      recargoPct: recargoPct,
      quien: quien,
    );
    if (escrituras != antes && nube != null) {
      if (r.venta != null) pendientes.add((tabla: 'entradas_ventas', fila: r.venta!));
      for (final m in r.movimientos) {
        pendientes.add((tabla: 'entradas_para_rendir', fila: m));
      }
      nube!.escribio(this);
    }
    return r;
  }

  @override
  Future<MovimientoParaRendir> noVolvieron(
    MovimientoParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> numeros = const [],
    required String motivo,
    required String quien,
  }) =>
      _sube(
        'entradas_para_rendir',
        () => super.noVolvieron(
          bloque,
          cantidad: cantidad,
          numeros: numeros,
          motivo: motivo,
          quien: quien,
        ),
      );

  @override
  Future<MovimientoParaRendir> anularDeParaRendir(
    MovimientoParaRendir movimiento, {
    required String motivo,
    required String quien,
  }) =>
      _sube(
        'entradas_para_rendir',
        () => super.anularDeParaRendir(movimiento, motivo: motivo, quien: quien),
      );

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
      case MovimientoParaRendir m:
        poner(listaParaRendir, m, (x) => x.id == m.id);
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

  /// Las familias con una entrega hecha en este equipo sin internet: la línea de
  /// VENDER las cuenta ("1 entrega por subir") hasta VOLVER EL INTERNET.
  final entregasSinSubir = <String>{};

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
    if (!hayInternet) {
      // Lo que se acaba de guardar es el último renglón: esa familia queda por subir.
      final renglones = desde.c.read(entradasEntregasRepositoryProvider) as _PartesDeUnLado;
      final ultimo = renglones.ultimo;
      if (tabla == EntradasEntregasRepository.tabla && ultimo != null) {
        desde.entregasSinSubir.add(ultimo.contratoAlumnoId);
        desde.motor.pendiente.add(desde.entregasSinSubir.length);
        cambios.value++;
      }
      return false;
    }
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
      // Las entregas que quedaron sin subir: suben y el otro las baja.
      if (lado.entregasSinSubir.isNotEmpty) {
        lado.entregasSinSubir.clear();
        lado.motor.pendiente.add(0);
        _otro(lado).bajo({EntradasEntregasRepository.tabla});
        cambios.value++;
      }
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

  /// Cada constancia de las entradas para rendir (al DAR y con CONSTANCIA).
  final constancias = <DatosDeLaConstancia>[];

  /// Cada IMPRIMIR de la caja de entregas: de quién (null, todo).
  final entregasSinCargo = <String?>[];

  /// Cada planilla de entrega, por material.
  final planillas = <ParteEntrega>[];
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
        // La constancia de las entradas para rendir (PARA RENDIR del jefe): al
        // DAR y con CONSTANCIA. Sin [carpeta], solo se anota.
        abrirConstanciaParaRendirProvider.overrideWithValue((d, {context}) async {
          constancias.add(d);
          await _guardar(
            lado,
            ConstanciaParaRendirPdf.nombreDelArchivo(d),
            () async => ConstanciaParaRendirPdf.armar(
              d,
              fuentes: await PdfService.fuentesOutfit(),
              logo: await isotipoDeLosPapeles(),
            ),
          );
        }),
        // IMPRIMIR de la caja de entregas, en el cierre de caja → ENTRADAS.
        imprimirEntregasSinCargoProvider.overrideWithValue(
          (caja, {required fiesta, fechaFiesta, soloDe}) async {
            entregasSinCargo.add(soloDe);
            final quien = soloDe == null
                ? ''
                : '_${soloDe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}';
            await _guardar(lado, 'Entregas_sin_cargo$quien', () async {
              final letras = await PdfService.fuentesOutfit();
              return EntregasSinCargoPdf.construir(
                caja: caja,
                fiesta: fiesta,
                fechaFiesta: fechaFiesta,
                soloDe: soloDe,
                regular: letras?.$1,
                negrita: letras?.$2,
              );
            });
          },
        ),
        // PLANILLA de VENDER y la impresora de la entrega.
        imprimirPlanillaDeEntregaProvider.overrideWithValue(
          (evento, alumnos,
              {required material,
              required retiros,
              renglones = const [],
              required deudas,
              blancoYNegro = false}) async {
            planillas.add(material);
            await _guardar(
              lado,
              'Planilla_de_entrega_${material.clave}',
              () => PdfService.construirPlanillaEntregaPdf(
                evento,
                alumnos,
                material: material,
                retiros: retiros,
                renglones: renglones,
                deudas: deudas,
                blancoYNegro: blancoYNegro,
              ),
            );
          },
        ),
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

  List<Map<String, dynamic>> _pagosDe(String alumnoId) => [
        for (final p in entrega.contratos.pagos)
          if (p['contrato_alumno_id'] == alumnoId) p,
      ];

  /// Lo que debe [alumnoId] de su contrato, con la misma cuenta que la entrega
  /// (`RetiroEntradas.deudaDe`).
  DeudaAlumno deudaDe(String alumnoId) => RetiroEntradas.deudaDe(
        entrega.contratos.alumnos.firstWhere((a) => a.id == alumnoId),
        pagos: _pagosDe(alumnoId),
        moraCobradaHistorial: 0,
      );

  /// Las familias que deben algo de su contrato: las que LA CAJA COBRA ofrece.
  List<ContratoAlumno> get familiasQueDeben => [
        for (final a in entrega.contratos.alumnos)
          if (!deudaDe(a.id).pagoTodo) a,
      ];

  /// LA CAJA COBRA: la caja de cuotas (otra PC) le cobra a [alumnoId] todo lo
  /// que debe, como lo haría el cobro de la app: un pago por lo que falta de la
  /// base, de la mesa adicional y de las sillas, y la mora; la ficha queda en
  /// cero. Los dos lados lo bajan (como el pulso), así VENDER destraba lo sin
  /// cargo y habilita lo de A PAGAR solo, y en "En caja" salta "pagó todo".
  /// Devuelve lo cobrado.
  double cobrarTodo(String alumnoId) {
    final alumnos = entrega.contratos.alumnos;
    final i = alumnos.indexWhere((a) => a.id == alumnoId);
    final a = alumnos[i];
    final pagos = _pagosDe(alumnoId);
    final base = a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal;
    final faltan = <String, double>{
      'Cuota Base (9/9)': base - grossHistoricoClaseCobro(pagos, CobroConceptoClase.base),
      'Mesa Extra 1':
          a.mesaExtraPrecio - grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
      'Sillas extra (1/1)': a.sillasExtraPrecioTotal -
          grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
    };
    var cobrado = a.moraPendienteTracked;
    for (final MapEntry(key: concepto, value: monto) in faltan.entries) {
      if (monto <= RetiroEntradas.margen) continue;
      entrega.contratos.pagos.add(pagoDeLaEntrega(alumnoId, monto, concepto));
      cobrado += monto;
    }
    alumnos[i] = a.copyWith(
      saldoDeudor: 0,
      cuotasPagadas: a.totalCuotas,
      mesaExtraCuotasPagadas: a.mesaExtraCuotas,
      sillasExtraCuotasPagadas: a.sillasExtraCuotas,
      moraPendienteTracked: 0,
    );
    for (final lado in [nube.tablet, nube.pc]) {
      lado.bajo({'pagos_contrato_alumno', 'contratos_alumnos'});
    }
    nube.cambios.value++;
    return cobrado;
  }

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
  sumarLaNoche(entrega);
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
        // La entrega por partes (pulseras y generales), en memoria y compartida:
        // al subir, avisa al otro lado como las demás entregas. Lo que cada lado
        // tiene sin subir es suyo (la línea de VENDER lo cuenta).
        entradasEntregasRepositoryProvider.overrideWithValue(
          _PartesDeUnLado(entrega.partes, lado),
        ),
        entregarParteProvider.overrideWithValue(
          EntregarParte(
            PuertosEnMemoria(entrega, alSubir: (tabla) => nube.entregaSubio(lado, tabla)),
          ),
        ),
        // El registro de sorteos: de ahí sale a qué lugares les va el descuento.
        sorteosMesasRepositoryProvider.overrideWithValue(entrega.sorteos),
        syncEngineProvider.overrideWithValue(lado.motor),
        subidaInmediataProvider.overrideWithValue(
          SubidaQueAvisa(lado.motor, (tabla) => nube.entregaSubio(lado, tabla)),
        ),
        ...lado.entradas.reemplazos,
        enLaWebProvider.overrideWithValue(false),
        if (hoy != null) hoyEnArgentinaProvider.overrideWithValue(hoy),
        // PRECIOS → "¿Poner estos precios también en otras fiestas?" (22-nov-2026):
        // PUERTO VIEJO (PRECIOS la saca sola) y una inventada. Sin esto leería los
        // eventos de la base de la PC.
        fiestasParaLosPreciosProvider.overrideWithValue(
          () async => [fiestaDeLaEntrega, otraFiestaDeLosPrecios],
        ),
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

/// La otra fiesta que ofrece PRECIOS después de GUARDAR ("¿Poner estos precios
/// también en otras fiestas?", 22-nov-2026). Inventada, sin precio y sin alumnos:
/// está para ver el cartel. No está en la lista de Carla ni en el cierre de caja.
final Evento otraFiestaDeLosPrecios = fiestaDePrueba(
  'e0000000-0000-4000-8000-000000000002',
  'BAHÍA SERENA',
  DateTime(2026, 12, 12),
);

// ── Las familias de la noche ────────────────────────────────────────────────

/// Las familias que [sumarLaNoche] agrega a las tres de `EntregaEnMemoria`
/// (PÉREZ, LÓPEZ y GÓMEZ): una de cada caso. Nombres inventados.
abstract final class NocheDeLaVenta {
  /// Pagó todo: 2 acompañantes con nombre y una mesa adicional paga.
  static const acosta = 'a0000000-0000-4000-8000-000000000401';

  /// Debe una cuota de la base ($ 33.333), con la mesa adicional paga.
  static const benitez = 'a0000000-0000-4000-8000-000000000402';

  /// Debe solo la mora ($ 12.500).
  static const diaz = 'a0000000-0000-4000-8000-000000000403';

  /// Agregó una silla extra después del sorteo, y la pagó.
  static const ferreyra = 'a0000000-0000-4000-8000-000000000404';

  /// 3 acompañantes (el máximo es 2).
  static const herrera = 'a0000000-0000-4000-8000-000000000405';

  /// 2 acompañantes, uno sin nombre.
  static const ibarra = 'a0000000-0000-4000-8000-000000000406';

  /// Cuándo se sorteó PUERTO VIEJO.
  static final sorteoEl = DateTime.utc(2026, 11, 11, 0, 30);
}

/// Una familia más de PUERTO VIEJO: la base de $ 300.000 ([basePagada] de eso
/// pagado), [extras] mesas adicionales de $ 70.000 y [sillas] sillas extra de
/// $ 8.000, las dos pagas enteras, y [mora] de mora. La ficha dice lo mismo que
/// los pagos.
ContratoAlumno _familia(
  EntregaEnMemoria e, {
  required String id,
  required String nombre,
  required List<int> mesas,
  String division = '5° B',
  int extras = 0,
  int sillas = 0,
  int acompanantes = 0,
  List<String> nombres = const [],
  double basePagada = 300000,
  double mora = 0,
}) {
  final total = 300000 + 70000.0 * extras + 8000.0 * sillas;
  final pagado = basePagada + 70000.0 * extras + 8000.0 * sillas;
  final a = ContratoAlumno(
    id: id,
    eventoId: idFiestaEntrega,
    nombreAlumno: nombre,
    cantidadAcompanantes: acompanantes,
    nombresAcompanantes: nombres,
    montoTotalPactado: total,
    saldoDeudor: total - pagado,
    // Como en las pruebas de VENDER: con las 9 marcadas la deuda de la base no
    // genera mora, así "debe una cuota" y "debe solo mora" quedan separados.
    totalCuotas: 9,
    cuotasPagadas: 9,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    mesaExtraCuotas: 1,
    mesaExtraCuotasPagadas: extras > 0 ? 1 : 0,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: 8000.0 * sillas,
    sillasExtraCuotas: 1,
    sillasExtraCuotasPagadas: sillas > 0 ? 1 : 0,
    moraPendienteTracked: mora,
    numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
    cursoDivision: division,
    createdAt: DateTime(2026, 2, 1),
  );
  e.contratos.alumnos.add(a);
  e.contratos.pagos.add(pagoDeLaEntrega(id, basePagada, 'Cuota Base (9/9)'));
  if (extras > 0) {
    e.contratos.pagos.add(pagoDeLaEntrega(id, 70000.0 * extras, 'Mesa Extra 1'));
  }
  if (sillas > 0) {
    e.contratos.pagos.add(pagoDeLaEntrega(id, 8000.0 * sillas, 'Sillas extra (1/1)'));
  }
  return a;
}

/// La noche de la ventana (y de las muestras): a las tres familias de
/// `EntregaEnMemoria` les suma una de cada caso ([NocheDeLaVenta]) y el sorteo de
/// PUERTO VIEJO, con lo que cada familia tenía cargado: de ahí sale qué va con
/// el descuento de PRECIOS y qué al precio del día.
void sumarLaNoche(EntregaEnMemoria e) {
  _familia(
    e,
    id: NocheDeLaVenta.acosta,
    nombre: 'ACOSTA, LUCÍA',
    mesas: const [16, 17],
    extras: 1,
    acompanantes: 2,
    nombres: const ['ACOSTA, MARTA', 'ACOSTA, RUBÉN'],
  );
  _familia(
    e,
    id: NocheDeLaVenta.benitez,
    nombre: 'BENÍTEZ, TOMÁS',
    mesas: const [18, 19],
    extras: 1,
    acompanantes: 1,
    nombres: const ['BENÍTEZ, CLARA'],
    basePagada: 266667,
  );
  _familia(
    e,
    id: NocheDeLaVenta.diaz,
    nombre: 'DÍAZ, NICOLÁS',
    mesas: const [20],
    mora: 12500,
  );
  _familia(
    e,
    id: NocheDeLaVenta.ferreyra,
    nombre: 'FERREYRA, MÍA',
    mesas: const [21],
    sillas: 1,
  );
  _familia(
    e,
    id: NocheDeLaVenta.herrera,
    nombre: 'HERRERA, LUCAS',
    mesas: const [22],
    division: '5° C',
    acompanantes: 3,
    nombres: const ['HERRERA, ANA', 'HERRERA, LUIS', 'HERRERA, PEDRO'],
  );
  _familia(
    e,
    id: NocheDeLaVenta.ibarra,
    nombre: 'IBARRA, CAMILA',
    mesas: const [23],
    division: '5° C',
    acompanantes: 2,
    nombres: const ['IBARRA, JOSÉ'],
  );
  // El sorteo: las mesas de cada familia y lo que tenía cargado (PÉREZ, ACOSTA y
  // BENÍTEZ ya tenían su mesa adicional; FERREYRA todavía no tenía la silla).
  e.sorteos.registros.add(SorteoMesasRegistro(
    id: 'f0000000-0000-4000-8000-000000000001',
    eventoId: idFiestaEntrega,
    tipo: TipoRegistroSorteo.sorteo,
    resultado: {
      for (final a in e.contratos.alumnos) a.id: a.numeroMesa ?? '',
    },
    lugares: const {
      EntregaEnMemoria.idPerez: '2,0',
      NocheDeLaVenta.acosta: '2,0',
      NocheDeLaVenta.benitez: '2,0',
    },
    hechoPor: 'Jefe',
    createdAt: NocheDeLaVenta.sorteoEl,
  ));
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
              key: const Key('prueba_caja_cobra'),
              onPressed: _laCajaCobra,
              child: const Text('LA CAJA COBRA'),
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
                              onCobrar: (a) => _cobrarDesdeLaEntrega(context, a),
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

  /// LA CAJA COBRA: las familias que deben algo, cada una con COBRAR TODO. Es la
  /// caja de cuotas de otra PC: lo cobrado les llega a los dos lados.
  Future<void> _laCajaCobra() async {
    final contexto = _navJefe.currentContext;
    if (contexto == null) return;
    final l = widget.lados;
    await showDialog<void>(
      context: contexto,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redibujar) {
          final deben = l.familiasQueDeben;
          return AlertDialog(
            title: const Text('La caja de cuotas (otra PC)'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cobra todo lo que debe la familia (cuotas, extras y mora), como si '
                      'pagara en la caja. Les llega a la tablet de Carla y a esta PC.',
                    ),
                    const SizedBox(height: 8),
                    if (deben.isEmpty) const Text('Nadie debe nada.'),
                    for (final a in deben)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(a.nombreAlumno),
                        subtitle: Text('Debe ${pesos(l.deudaDe(a.id).total)}'),
                        trailing: FilledButton(
                          key: Key('prueba_cobrar_${a.id}'),
                          onPressed: () => redibujar(() => l.cobrarTodo(a.id)),
                          child: const Text('COBRAR TODO'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                key: const Key('prueba_caja_cerrar'),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CERRAR'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// COBRAR, en la entrega del jefe: en la app abre el cobro; acá, la caja le
  /// cobra todo lo que debe (como LA CAJA COBRA).
  Future<void> _cobrarDesdeLaEntrega(BuildContext context, ContratoAlumno a) async {
    final l = widget.lados;
    final debe = l.deudaDe(a.id).total;
    final cobrar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('La caja de cuotas'),
        content: Text(
          'Acá se abre el cobro de ${a.nombreAlumno}. En esta prueba, la caja le cobra '
          'todo lo que debe: ${pesos(debe)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          FilledButton(
            key: const Key('prueba_cobrar_todo'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('COBRAR TODO'),
          ),
        ],
      ),
    );
    if (cobrar == true) l.cobrarTodo(a.id);
  }

  static Future<void> _avisar(BuildContext context, String texto) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(texto),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR'))],
        ),
      );
}

/// El lado de Carla: Entradas con "Vende entradas", con un solo botón, VENDER, de
/// verdad (20-nov-2026): adentro entrega lo sin cargo en dos partes y vende.
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

/// Los renglones de la entrega, compartidos entre los dos lados, con lo que **este
/// lado** tiene sin subir: la línea de VENDER dice "1 entrega por subir" mientras no
/// vuelve el internet (revisión del 20-nov-2026: en la ventana de prueba no se veía).
class _PartesDeUnLado extends EntradasEntregasRepository {
  _PartesDeUnLado(this.partes, this.lado)
      : super(null, abrir: () => throw StateError('la prueba no abre la base'));

  final PartesEnMemoria partes;
  final LadoDeLaVenta lado;

  EntregaEntradas? get ultimo => partes.renglones.isEmpty ? null : partes.renglones.last;

  @override
  Future<int> familiasSinSubir() async => lado.entregasSinSubir.length;

  @override
  Future<Map<String, List<EntregaEntradas>>> deContratos(List<String> ids) =>
      partes.deContratos(ids);

  @override
  Future<List<EntregaEntradas>> delEvento(String eventoId) => partes.delEvento(eventoId);

  @override
  Future<List<EntregaEntradas>> traerDeLaNube(String contratoAlumnoId) =>
      partes.traerDeLaNube(contratoAlumnoId);
}
