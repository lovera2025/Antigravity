// Recepción sin base ni red: los alumnos de una institución, la lista de la
// puerta y quién entró, en memoria. Lo usan `test/panel_puerta_test.dart`,
// `test/totem_local_test.dart`, `test/recepcion_pantalla_test.dart` y
// `tool/recepcion_muestra_test.dart`, puestos por los mismos providers que usa
// la app.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sillas_reparto_repository.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/repositories/planos_evento_repository.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/providers/sin_internet_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/repositories/sillas_puerta_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart'
    show PlanListaPuerta;
import 'package:arguello_events/features/recepcion/services/lista_sin_internet.dart';
import 'package:arguello_events/features/recepcion/widgets/panel_puerta.dart';
import 'package:arguello_events/features/tele/preparar_las_fiestas.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'barra_en_memoria.dart';

const eventoMasivo = 'e0000000-0000-4000-8000-00000000000a';
const eventoParticular = 'e0000000-0000-4000-8000-00000000000b';

/// La hora con que se marca un ingreso en memoria: 22:41 en Argentina.
final horaDeIngreso = DateTime.utc(2026, 12, 13, 1, 41);

ContratoAlumno alumnoDePrueba(
  String id,
  String nombre, {
  List<int> mesas = const [],
  int extras = 0,
  int sillas = 0,
  List<String> acomp = const [],
  String? musica,
  String division = '5° B',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: eventoMasivo,
      nombreAlumno: nombre,
      cantidadAcompanantes: acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
      musicaElegida: musica,
    );

Evento eventoDePrueba(String id, String modalidad) => Evento(
      id: id,
      clienteId: 'c0000000-0000-4000-8000-000000000001',
      tipo: 'Egresados',
      fechaEvento: DateTime(2026, 12, 12),
      estado: EstadoEvento.confirmado,
      modalidad: modalidad,
    );

class ConexionApagada extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
}

/// Una conexión que la prueba corta o vuelve a poner ([poner]).
class ConexionDePrueba extends ConnectivityService {
  ConexionDePrueba([this.estado = AppConnectivity.online]);
  AppConnectivity estado;
  final _cambios = StreamController<AppConnectivity>.broadcast();

  @override
  AppConnectivity get currentStatus => estado;

  @override
  Stream<AppConnectivity> get stream => _cambios.stream;

  void poner(AppConnectivity nuevo) {
    estado = nuevo;
    _cambios.add(nuevo);
  }
}

/// La hora de las pruebas de "Lista para trabajar sin internet".
final ahoraDePrueba = DateTime(2026, 12, 12, 21, 40);

/// Con qué se pone al día el evento, en memoria: qué bajó, qué foto hay y
/// cuántos ingresos esperan subir.
class SinInternetEnMemoria {
  var bajaLista = true;
  var bajanAlumnos = true;
  var bajaFoto = true;
  final fotosGuardadas = <String>{};
  var bajaFondo = true;
  final fondosGuardados = <String>{};
  var sinSubir = 0;

  /// Las sillas de la noche que esperan subir (6.9.0: "Todo subido" las cuenta).
  var sillasSinSubir = 0;
  final alDia = <String, DateTime>{};
  var listasBajadas = 0;
  var alumnosBajados = 0;
  DateTime ahora = ahoraDePrueba;

  AccesosPuerta get accesos => AccesosPuerta(
        bajarLista: (_) async {
          listasBajadas++;
          return bajaLista;
        },
        bajarAlumnos: () async {
          alumnosBajados++;
          return bajanAlumnos;
        },
        guardarFoto: (url, _) async {
          if (bajaFoto) fotosGuardadas.add(url);
          return fotosGuardadas.contains(url);
        },
        fotoGuardada: (url, _) async => fotosGuardadas.contains(url),
        guardarFondo: (url, _) async {
          if (bajaFondo) fondosGuardados.add(url);
          return fondosGuardados.contains(url);
        },
        fondoGuardado: (url, _) async => fondosGuardados.contains(url),
        contarSinSubir: (_) async => sinSubir,
        contarSillasSinSubir: (_) async => sillasSinSubir,
        leerAlDia: (id) async => alDia[id],
        anotarAlDia: (id, cuando) async => alDia[id] = cuando,
        ahora: () => ahora,
      );

  // ── Las fiestas de la tele (25-nov-2026): todas listas sin internet ──────

  /// La apariencia de cada fiesta en la nube, y la guardada en el equipo.
  final aparienciasEnLaNube = <String, TotemConfig>{};
  final aparienciasGuardadas = <String, TotemConfig>{};
  var leeApariencias = true;
  var aparienciasLeidas = 0;
  var listasDeFiestas = <String>[];

  AccesosDeLasFiestas get fiestas => AccesosDeLasFiestas(
        bajarLista: (id) async {
          listasBajadas++;
          listasDeFiestas.add(id);
          return bajaLista;
        },
        bajarParaLaPuerta: () async {
          alumnosBajados++;
          return bajanAlumnos;
        },
        leerApariencias: (ids) async {
          aparienciasLeidas++;
          if (!leeApariencias) throw StateError('sin internet');
          return {
            for (final id in ids)
              if (aparienciasEnLaNube[id] != null) id: aparienciasEnLaNube[id]!,
          };
        },
        guardarApariencia: (cfg) async => aparienciasGuardadas[cfg.eventoId] = cfg,
        aparienciaGuardada: (id) async => aparienciasGuardadas[id],
        guardarFoto: (url, _) async {
          if (bajaFoto) fotosGuardadas.add(url);
          return fotosGuardadas.contains(url);
        },
        fotoGuardada: (url, _) async => fotosGuardadas.contains(url),
        guardarFondo: (url, _) async {
          if (bajaFondo) fondosGuardados.add(url);
          return fondosGuardados.contains(url);
        },
        fondoGuardado: (url, _) async => fondosGuardados.contains(url),
        leerAlDia: (id) async => alDia[id],
        anotarAlDia: (id, cuando) async => alDia[id] = cuando,
        ahora: () => ahora,
      );
}

/// La lista de la puerta de esta PC, en memoria, y lo que se pidió marcar.
///
/// **Ningún método llega a la base de la PC** (6.9.0, etapa 7): todo lo que en
/// [InvitadosRepository] abre `LocalDatabase.instance` está reemplazado acá. En
/// las ventanas de prueba (`tool/central_puerta_prueba.dart`,
/// `tool/totem_salon_prueba.dart`) "Actualizar la lista" abría, y migraba, la
/// base de verdad. `test/arneses_sin_base_test.dart` lee el repositorio y falla
/// si aparece un método nuevo que la abra y no esté reemplazado acá.
class InvitadosEnMemoria extends InvitadosRepository {
  InvitadosEnMemoria(SupabaseClient supabase, this.filas)
      : super(supabase, ConexionApagada());

  final List<Invitado> filas;
  final _cambios = StreamController<void>.broadcast();
  final marcados = <String>[];
  final creados = <String>[];
  final desmarcados = <String>[];
  final eliminados = <String>[];

  /// La hora con que se marca: la fija de las pruebas, o la de verdad en el
  /// arnés.
  DateTime Function() hora = () => horaDeIngreso;

  List<Invitado> _del(String eventoId) =>
      filas.where((i) => i.eventoId == eventoId).toList();

  @override
  Stream<List<Invitado>> watchByEvento(String eventoId) {
    late final StreamController<List<Invitado>> c;
    StreamSubscription<void>? sub;
    c = StreamController<List<Invitado>>(
      onListen: () {
        c.add(_del(eventoId));
        sub = _cambios.stream.listen((_) => c.add(_del(eventoId)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  void _poner(String id, EstadoIngreso estado) {
    final i = filas.indexWhere((f) => f.id == id);
    filas[i] = filas[i].copyWith(estadoIngreso: estado, updatedAt: hora());
    _cambios.add(null);
  }

  /// Los ingresos que se marcaron sin saludar en el tótem.
  final sinSaludo = <String>[];

  @override
  Future<Invitado?> getLocal(String id) async =>
      filas.where((f) => f.id == id).firstOrNull;

  @override
  Future<void> marcarIngreso(String invitadoId, {bool saludar = true}) async {
    marcados.add(invitadoId);
    if (!saludar) sinSaludo.add(invitadoId);
    _poner(invitadoId, EstadoIngreso.ingresado);
  }

  @override
  Future<void> ingresarDesdeLaPuerta({
    required String eventoId,
    required String id,
    required String nombre,
    String? mesa,
    bool saludar = true,
  }) async {
    if (filas.any((f) => f.id == id)) {
      return marcarIngreso(id, saludar: saludar);
    }
    if (!saludar) sinSaludo.add(id);
    creados.add(id);
    filas.add(Invitado(
      id: id,
      eventoId: eventoId,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: hora(),
    ));
    _cambios.add(null);
  }

  @override
  Future<void> deshacerIngreso(String invitadoId) async {
    desmarcados.add(invitadoId);
    _poner(invitadoId, EstadoIngreso.pendiente);
  }

  @override
  Future<void> eliminar(String id) async {
    eliminados.add(id);
    filas.removeWhere((f) => f.id == id);
    _cambios.add(null);
  }

  /// "Actualizar la lista": acá no hay nube. Con `false` (lo de siempre) dice
  /// que no pudo; con `true`, "Lista actualizada".
  bool bajaDeLaNube = false;
  var actualizaciones = 0;
  var _otroId = 0;

  // Cada reemplazo de la base en un renglón: la rotura a propósito borra uno.
  @override Future<bool> forceRefresh(String eventoId) async { actualizaciones++; return bajaDeLaNube; }
  @override Future<bool> bajarListaDelEvento(String eventoId) async => false;
  @override Future<List<Invitado>> getByEvento(String eventoId) async => _del(eventoId);
  @override Future<List<Invitado>> getLocalesByEvento(String eventoId) async => _del(eventoId);
  @override Future<Set<String>> idsSinSubir(String eventoId) async => const {};
  @override Future<void> registrarIntentoFallido(String invitadoId) async {}
  @override Future<void> resetearIntentos(String invitadoId) async {}

  @override
  Future<Map<String, int>> getEstadisticas(String eventoId) async {
    final todos = _del(eventoId);
    final adentro =
        todos.where((i) => i.estadoIngreso == EstadoIngreso.ingresado).length;
    return {
      'total': todos.length,
      'ingresados': adentro,
      'pendientes': todos.length - adentro,
    };
  }

  @override
  Future<void> vaciarEvento(String eventoId) async {
    filas.removeWhere((f) => f.eventoId == eventoId);
    _cambios.add(null);
  }

  @override
  Future<String> agregar({
    required String eventoId,
    required String nombreCompleto,
    String? dni,
    String? numeroMesa,
  }) async {
    final id = 'agregado-${++_otroId}';
    filas.add(Invitado(
      id: id,
      eventoId: eventoId,
      nombreCompleto: nombreCompleto,
      dni: dni ?? '',
      numeroMesa: numeroMesa,
      estadoIngreso: EstadoIngreso.pendiente,
      updatedAt: hora(),
    ));
    _cambios.add(null);
    return id;
  }

  @override
  Future<int> agregarBatch({
    required String eventoId,
    required List<Map<String, String>> invitados,
  }) async {
    var n = 0;
    for (final i in invitados) {
      final nombre = i['nombre_completo']?.trim() ?? '';
      if (nombre.isEmpty) continue;
      await agregar(
        eventoId: eventoId,
        nombreCompleto: nombre,
        dni: i['dni'],
        numeroMesa: i['numero_mesa'],
      );
      n++;
    }
    return n;
  }

  /// Lo que la Tele 1 le mandó a esta tele (la tele es el tótem, 24-nov-2026):
  /// se copia sin encolar, como en la base.
  final copiadasDeOtraTele = <String>[];

  /// Lo que se encoló al pasar a principal.
  final subidasDeOtraTele = <String>[];

  @override
  Future<Set<String>> guardarDeOtraTele(
    String eventoId,
    List<Map<String, dynamic>> llegadas,
  ) async {
    final escritas = <String>{};
    for (final f in llegadas) {
      final id = f['id'];
      if (id is! String || f['evento_id'] != eventoId) continue;
      final nueva = Invitado.fromJson({
        'dni': '',
        'intentos_fallidos': 0,
        ...f,
      });
      final i = filas.indexWhere((x) => x.id == id);
      if (i < 0) {
        filas.add(nueva);
      } else {
        filas[i] = filas[i].copyWith(
          nombreCompleto: nueva.nombreCompleto,
          numeroMesa: nueva.numeroMesa,
          estadoIngreso: nueva.estadoIngreso,
          updatedAt: nueva.updatedAt,
        );
      }
      escritas.add(id);
      copiadasDeOtraTele.add(id);
    }
    if (escritas.isNotEmpty) _cambios.add(null);
    return escritas;
  }

  @override
  Future<void> subirLoDeOtraTele(String eventoId, Set<String> ids) async =>
      subidasDeOtraTele.addAll(ids);

  /// Armar la lista desde los alumnos es de la oficina (las pantallas del
  /// salón), no de Recepción.
  @override
  Future<void> aplicarListaPuerta(String eventoId, PlanListaPuerta plan) async =>
      throw StateError('En la prueba no: armar la lista es de la oficina');
}

class ContratosEnMemoria extends ContratosRepository {
  ContratosEnMemoria(SupabaseClient supabase, this.alumnos, {this.pagos})
      : super(supabase, ConexionApagada());
  List<ContratoAlumno> alumnos;

  /// Los pagos de cada familia, por id de contrato (6.9.2: de ahí sale la mesa
  /// adicional "a confirmar"). **Null: como si no se pudieran leer**, así en
  /// las pruebas que no hablan de pagos ninguna mesa queda "a confirmar".
  Map<String, List<Map<String, dynamic>>>? pagos;

  @override
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async =>
      eventoId == eventoMasivo ? alumnos : const [];

  /// Nunca va a la base de la PC: sin esto la puerta se quedaba esperando.
  @override
  Future<List<Map<String, dynamic>>> getPagosForContratoIds(
    List<String> contratoIds,
  ) async {
    final p = pagos;
    if (p == null) throw StateError('La prueba no cargó pagos');
    return [
      for (final id in contratoIds)
        for (final pago in p[id] ?? const <Map<String, dynamic>>[])
          {...pago, 'contrato_alumno_id': id},
    ];
  }
}

class SillasEnMemoria extends SillasRepartoRepository {
  SillasEnMemoria([this.repartos = const {}]);
  final Map<String, SillasReparto> repartos;

  @override
  Future<Map<String, SillasReparto>> obtenerPorContratoIds(
    List<String> ids,
  ) async =>
      repartos;
}

/// Las sillas que se suman la noche de la fiesta, en memoria: nunca se borra
/// nada, igual que en la base.
class SillasPuertaEnMemoria extends SillasPuertaRepository {
  SillasPuertaEnMemoria([List<SillaPuerta> filas = const []])
      : filas = [...filas];

  final List<SillaPuerta> filas;
  final _avisos = StreamController<String>.broadcast();
  var _siguiente = 0;

  /// La hora con que se anota: la fija de las pruebas, o la de verdad.
  DateTime Function() hora = () => horaDeIngreso;

  @override
  Stream<String> get cambios => _avisos.stream;

  @override
  Future<List<SillaPuerta>> delEvento(String eventoId) async =>
      [for (final s in filas) if (s.eventoId == eventoId) s];

  @override
  Future<List<SillaPuerta>> vigentesDe(String contratoAlumnoId) async => [
        for (final s in filas)
          if (s.contratoAlumnoId == contratoAlumnoId && s.vigente) s,
      ];

  @override
  Future<SillaPuerta> anotar({
    required String eventoId,
    required String contratoAlumnoId,
    required int mesa,
    required String vale,
    String? anotadoPor,
    String? nota,
  }) async {
    _siguiente++;
    final fila = SillaPuerta(
      id: 'silla-$_siguiente',
      eventoId: eventoId,
      contratoAlumnoId: contratoAlumnoId,
      mesa: mesa,
      vale: vale.trim(),
      anotadoPor: anotadoPor,
      nota: nota,
      createdAt: hora().add(Duration(seconds: _siguiente)),
      updatedAt: hora().add(Duration(seconds: _siguiente)),
    );
    filas.add(fila);
    _avisos.add(eventoId);
    return fila;
  }

  @override
  Future<SillaPuerta?> quitar(
    String id, {
    required String por,
    required String motivo,
  }) async {
    final i = filas.indexWhere((s) => s.id == id);
    if (i < 0 || !filas[i].vigente) return null;
    filas[i] = filas[i].quitada(por: por, motivo: motivo, ahora: hora());
    _avisos.add(filas[i].eventoId);
    return filas[i];
  }
}

/// El plano de la fiesta masiva en esta PC: su salón ([armado]), o ninguno.
class PlanosEnMemoria implements PlanosEventoRepository {
  PlanosEnMemoria([this.armado]);
  ArmadoSalon? armado;

  /// Lo configurado del plano: las mesas libres y las reservadas para quien no
  /// es alumno (los profes).
  ConfigPlano config = ConfigPlano.vacia;
  var lecturas = 0;

  @override
  Future<PlanoEvento?> obtener(String eventoId) async {
    lecturas++;
    final a = armado;
    if (a == null || eventoId != eventoMasivo) return null;
    return PlanoEvento.nuevo(
      eventoId: eventoId,
      armado: a,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.entera,
      ahora: DateTime(2026, 11, 1),
    ).copyWith(config: config, ahora: DateTime(2026, 11, 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Del motor, Recepción solo escucha el aviso de "bajó algo de la otra PC".
class MotorDePrueba implements SyncEngine {
  final bajo = StreamController<Set<String>>.broadcast();

  @override
  Stream<Set<String>> get cambiosBajadosStream => bajo.stream;

  /// Lo que queda en la cola, como avisa el motor después de subir.
  final pendiente = StreamController<int>.broadcast();

  @override
  Stream<int> get pendingStream => pendiente.stream;

  /// La apariencia que se guardó en otra PC (el pulso, 25-nov-2026).
  final apariencias = StreamController<Set<String>>.broadcast();

  @override
  Stream<Set<String>> get aparienciasCambiadasStream => apariencias.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Todo lo que rodea al panel en una prueba.
class PuertaEnMemoria {
  PuertaEnMemoria(
    SupabaseClient supabase, {
    required List<ContratoAlumno> alumnos,
    List<Invitado>? filas,
    Map<String, SillasReparto> repartos = const {},
    List<SillaPuerta> sillasDeLaNoche = const [],
    ArmadoSalon? plano,
    Map<String, List<Map<String, dynamic>>>? pagos,
  })  : contratos = ContratosEnMemoria(supabase, alumnos, pagos: pagos),
        invitados = InvitadosEnMemoria(supabase, filas ?? []),
        sillas = SillasEnMemoria(repartos),
        sillasPuerta = SillasPuertaEnMemoria(sillasDeLaNoche),
        planos = PlanosEnMemoria(plano);

  final ContratosEnMemoria contratos;
  final InvitadosEnMemoria invitados;
  final SillasEnMemoria sillas;

  /// Las sillas sumadas esa noche en la puerta.
  final SillasPuertaEnMemoria sillasPuerta;

  /// La barra de la fiesta como la ve esta PC: de ahí salen los vales anulados.
  final barra = BarraEnMemoria();

  /// El plano de la fiesta masiva: siempre puesto, así nadie lee la base real.
  final PlanosEnMemoria planos;
  final motor = MotorDePrueba();

  /// La conexión de la PC: con internet, salvo que la prueba la corte.
  final conexion = ConexionDePrueba();

  /// "Lista para trabajar sin internet", sin base, nube ni carpeta de fotos.
  final sinInternet = SinInternetEnMemoria();
  var actualizado = 0;
  var agregar = 0;
  var vaciar = 0;

  /// El código de la central de la puerta si se usó esta noche, o null.
  String? codigoCentral;

  /// Las direcciones de la PC para los celulares: vacía, sin router.
  List<String> direcciones = const ['192.168.0.10'];

  /// Dónde escucha la central si se prende: solo en esta PC, en un puerto
  /// libre, sin página del celular. El arnés `tool/central_puerta_prueba.dart`
  /// la abre al wifi de verdad.
  ///
  /// `late`: se lee recién si alguien prende la central. Así el mismo mundo
  /// corre en el navegador (`tool/totem_salon_prueba.dart`), donde no hay
  /// direcciones de red.
  late InternetAddress escuchaCentral = InternetAddress.loopbackIPv4;
  int puertoCentral = 0;
  Future<List<String>> Function()? leerDirecciones;
  Directory? paginaDelCelular;

  /// El panel del evento, con los reemplazos puestos.
  Widget panel(
    String eventoId, {
    ThemeData? tema,
    Map<String, TotemConfig> config = const {},
    bool animarElPlano = true,
  }) =>
      recepcion(
        Scaffold(
          body: PanelPuerta(
            eventoId: eventoId,
            onActualizar: () => actualizado++,
            onAgregar: () => agregar++,
            onImportar: () {},
            onExportar: () {},
            onVaciar: () => vaciar++,
            animarElPlano: animarElPlano,
          ),
        ),
        tema: tema,
        config: config,
      );

  /// [home] con los reemplazos puestos: los eventos, la lista de la puerta,
  /// los alumnos, sus sillas y el motor; la personalización del tótem de cada
  /// evento ([config], o la de siempre); el permiso del tótem ([puedeTotem]);
  /// y en el selector de Recepción, [elegido].
  Widget recepcion(
    Widget home, {
    ThemeData? tema,
    String? elegido,
    Map<String, TotemConfig> config = const {},
    bool puedeTotem = true,
    List<Override> extra = const [],
    List<Evento>? eventos,
    TransitionBuilder? builder,
  }) =>
      ProviderScope(
        overrides: [
          eventosActivosProvider.overrideWith(
            (ref) async =>
                eventos ??
                [
                  eventoDePrueba(eventoMasivo, 'masivo'),
                  eventoDePrueba(eventoParticular, 'particular'),
                ],
          ),
          invitadosRepositoryProvider.overrideWithValue(invitados),
          contratosRepositoryProvider.overrideWithValue(contratos),
          sillasRepartoRepositoryProvider.overrideWithValue(sillas),
          sillasPuertaRepositoryProvider.overrideWithValue(sillasPuerta),
          barraDelJefeProvider.overrideWithValue(barra),
          planosEventoRepositoryProvider.overrideWithValue(planos),
          syncEngineProvider.overrideWithValue(motor),
          connectivityServiceProvider.overrideWithValue(conexion),
          accesosPuertaProvider.overrideWithValue(sinInternet.accesos),
          // Las fiestas de la tele, preparadas en memoria (sin la carpeta de
          // fotos ni la nube).
          accesosDeLasFiestasProvider.overrideWithValue(sinInternet.fiestas),
          // La central de la puerta no se usó esta noche ([codigoCentral]
          // dice lo contrario), y si se prende, escucha solo en esta PC.
          codigoVigenteCentralProvider
              .overrideWithValue((_) async => codigoCentral),
          codigoCentralProvider.overrideWithValue((_) async => '4821'),
          escuchaCentralProvider.overrideWith((ref) => escuchaCentral),
          puertoCentralProvider.overrideWithValue(puertoCentral),
          direccionesDeEstaPcProvider.overrideWithValue(
            leerDirecciones ?? () async => direcciones,
          ),
          paginaDelCelularProvider.overrideWithValue(paginaDelCelular),
          for (final evento in [eventoMasivo, eventoParticular])
            totemConfigProvider(evento).overrideWith(
              (ref) => Stream.value(
                config[evento] ?? TotemConfig.defaults(evento),
              ),
            ),
          userRoleProvider.overrideWith(
            (ref) async => UserRoleState(
              isLoading: false,
              permisos: UserPermissions(puedeTotem: puedeTotem),
            ),
          ),
          selectedEventProvider.overrideWith(() => _EventoElegido(elegido)),
          ...extra,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tema ??
              ThemeData(brightness: Brightness.dark, useMaterial3: true),
          // La tele: girada como en la app (`GiroDeLaApp`).
          builder: builder,
          home: home,
        ),
      );
}

/// El evento ya elegido en el selector de Recepción.
class _EventoElegido extends SelectedEventNotifier {
  _EventoElegido(this.elegido);
  final String? elegido;

  @override
  String? build() => elegido;
}
