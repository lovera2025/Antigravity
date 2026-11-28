import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/red/servir_archivos.dart';
import '../../../models/invitado.dart';
import '../../totem/services/tiempos_a_mano.dart';
import '../chat/mensaje_de_puesto.dart';
import '../services/lista_del_locutor.dart';
import '../services/puerta_del_evento.dart';
import 'pedidos_de_la_puerta.dart';
import 'resolvedor_de_pedidos.dart';

export 'resolvedor_de_pedidos.dart' show PuertaDeEstaPc, ResolvedorDePedidos;

/// El puerto de la central. Si está ocupado se prueban los siguientes nueve.
const kPuertoCentral = 8787;

/// Cuántos códigos mal puestos seguidos se aceptan de un mismo celular antes de
/// frenarlo un minuto.
const kErroresDeCodigo = 5;
const kFrenoPorErrores = Duration(minutes: 1);

/// Cuánto espera la pregunta "La Tele 1 cambió a ESCUELA B · MANTENER ·
/// CAMBIAR" (25-nov-2026). Sin respuesta, se mantiene.
const kEsperaDeLaPregunta = Duration(minutes: 3);

/// Un celular que se conectó a la central esta noche.
class PuestoConectado {
  /// Lo inventa el celular la primera vez y lo guarda: así se lo reconoce al
  /// volver.
  final String celular;

  /// El nombre que puso quien lo usa: "Juli".
  final String nombre;
  final bool conectado;

  /// Cuándo se supo de él por última vez.
  final DateTime ultimaVez;

  /// Cuántos ingresó esta noche que siguen adentro.
  final int marcados;

  /// La tele que eligió ("Tu tele", 24-nov-2026). Null: un celular de antes,
  /// o una noche con una sola tele.
  final int? tele;

  const PuestoConectado({
    required this.celular,
    required this.nombre,
    required this.conectado,
    required this.ultimaVez,
    required this.marcados,
    this.tele,
  });
}

/// La Tele 2, conectada a la central de la Tele 1 (24-nov-2026).
class TeleConectada {
  final int numero;
  final bool conectada;

  /// La escuela que muestra (25-nov-2026). Null: no se sabe todavía.
  final String? evento;
  const TeleConectada(this.numero, {required this.conectada, this.evento});
}

/// Una escuela que se puede elegir para una tele desde el celular
/// (25-nov-2026): las que vienen, como las ve la tele en LA FIESTA.
class EscuelaParaElegir {
  final String id;
  final String titulo;
  const EscuelaParaElegir(this.id, this.titulo);

  Map<String, Object?> toJson() => {'id': id, 'titulo': titulo};
}

/// La central de la puerta: una notebook del salón a la que los celulares de
/// la puerta le piden ingresar o deshacer por el wifi del router, con o sin
/// internet.
///
/// - **A cada celular le manda la lista** (la misma [PuertaDelEvento] que ve
///   Recepción) apenas se conecta y cada vez que cambia ([ponerPuerta]).
/// - **Lo que le piden lo marca en la base de esta PC** ([PuertaDeEstaPc]),
///   como si lo hubieran tocado en su Recepción: la cola de subida y el aviso
///   al tótem quedan iguales. Los pedidos se atienden de a uno, mirando la base
///   en ese momento ([ResolvedorDePedidos]): si dos celulares ingresan a la misma
///   persona, el segundo recibe "ya ingresó". Las sillas de la noche y los
///   segundos del tótem van por la misma fila, que también usa la PC.
/// - **Solo atiende a quien trae el código** del QR (`CodigoCentral`).
/// - También sirve la página del celular ([paginaDelCelular]): sin internet,
///   el celular no tiene de dónde más bajarla.
///
/// **En la tele ([esTele], 25-nov-2026) atiende las dos escuelas de la noche a
/// la vez**: cada una con su fila de pedidos, sus marcas y su lista
/// ([_Escuela]). Cada tele muestra la suya, y cada celular ve la de su tele
/// ("Tu tele"). Cambiar la escuela de una tele no reinicia nada: sus celulares
/// pasan solos ([cambiarEscuelaDeTele]). En la notebook, una sola, como
/// siempre.
///
/// Habla por WebSocket en `/vivo?c=<código>&id=<celular>&p=<nombre>`, con
/// mensajes JSON que llevan su tipo en `t`.
class CentralPuerta {
  CentralPuerta({
    required String eventoId,
    required String codigo,
    String? codigoLocutor,
    required PuertaDeEstaPc pc,
    ResolvedorDePedidos? resolvedor,
    ResolvedorDePedidos Function(String eventoId)? resolvedorDe,
    this.paginaDelCelular,
    DateTime Function()? ahora,
    this.esTele = false,
  })  : _codigo = codigo,
        _codigoLocutor = codigoLocutor,
        _pc = pc,
        _resolvedorDe = resolvedorDe,
        // El mismo reloj para la central y sus marcas: cuánto hace que se
        // marcó a alguien se cuenta con uno solo.
        _ahora = ahora ?? DateTime.now {
    _escuelas[eventoId] = _Escuela(eventoId, resolvedor ?? _nuevoResolvedor(eventoId));
    _deLaTele[1] = eventoId;
  }

  /// La escuela de la central: la de la notebook o la que muestra la Tele 1.
  String get eventoId => _deLaTele[1]!;

  /// La central es la Tele 1 (la tele es el tótem, 24-nov-2026): los celulares
  /// eligen "Tu tele" y se le puede conectar la Tele 2. En la notebook, false:
  /// como siempre.
  final bool esTele;

  final PuertaDeEstaPc _pc;
  final ResolvedorDePedidos Function(String eventoId)? _resolvedorDe;

  ResolvedorDePedidos _nuevoResolvedor(String id) =>
      _resolvedorDe?.call(id) ?? ResolvedorDePedidos(eventoId: id, pc: _pc, ahora: _ahora);

  /// Las escuelas que atiende: en la notebook, una.
  final _escuelas = <String, _Escuela>{};

  /// La escuela de cada tele: la 1 es la de la central.
  final _deLaTele = <int, String>{};

  _Escuela get _principal => _escuelas[eventoId]!;

  /// La carpeta con la página que abre el celular, o null si no hay (en las
  /// pruebas).
  final Directory? paginaDelCelular;
  final DateTime Function() _ahora;

  String _codigo;
  HttpServer? _servidor;
  var _version = 0;
  final _conexiones = <_Conexion>{};
  final _puestos = <String, PuestoConectado>{};
  final _errores = <String, List<DateTime>>{};
  final _cambiosDePuestos = StreamController<List<PuestoConectado>>.broadcast();

  // ── Las escuelas de la tele (25-nov-2026) ─────────────────────────────────

  /// Las que atiende, la de la Tele 1 primero.
  List<String> get atiende => [eventoId, ..._escuelas.keys.where((e) => e != eventoId)];

  /// La escuela de la tele [n], si se sabe.
  String? escuelaDeTele(int n) => _deLaTele[n];

  /// Si [id] es una escuela de esta tele: la que muestra, una que ya atiende
  /// o una de las que vienen ([ponerEscuelasParaElegir]). **El id del evento es
  /// lo que trae la Tele 2 para conectarse** (como antes del 25-nov, cuando
  /// tenía que ser el de la Tele 1): con un id inventado no entra, no se
  /// atiende nada y nadie se lleva el código ni la lista.
  bool conoce(String id) =>
      id.length == 36 &&
      (id == eventoId || _escuelas.containsKey(id) || _paraElegir.any((e) => e.id == id));

  /// Empieza a atender la escuela [id] (si no la atendía y es de esta tele,
  /// [conoce]): se le avisa a quien la arma ([alAtender]) para que le pase su
  /// lista, su salón y lo demás.
  void atender(String id) {
    if (!esTele || _escuelas.containsKey(id) || !conoce(id)) return;
    _escuelas[id] = _Escuela(id, _nuevoResolvedor(id));
    alAtender?.call(id);
  }

  /// Hay que armarle lo suyo a una escuela nueva.
  void Function(String eventoId)? alAtender;

  /// Ya no hace falta lo de esa escuela: ninguna tele la muestra.
  void Function(String eventoId)? alSoltar;

  /// Suelta las escuelas que ninguna tele muestra (la Tele 2 desconectada
  /// sigue con la suya: vuelve). Sin esto, con la tele prendida varios días,
  /// se juntaban escuelas, sus oyentes y las filas que copia la Tele 2. Un
  /// pedido que quedó sin mandar de una escuela soltada la vuelve a atender
  /// ([atender]); sus marcas siguen en su fila de pedidos.
  void _soltarSinTele() {
    final enUso = {..._deLaTele.values};
    for (final id in _escuelas.keys.toList()) {
      if (enUso.contains(id)) continue;
      _escuelas.remove(id);
      alSoltar?.call(id);
    }
    _mandarLocutor();
  }

  /// La Tele 1 tiene que mostrar otra escuela: la pidió un celular, o la
  /// respuesta a "MANTENER · CAMBIAR". [por]: quién (null: con el control).
  void Function(String eventoId, String? por)? alCambiarTele1;

  /// Girar la Tele 1, pedido desde un celular: "horizontal", "vertical" o
  /// "dar_vuelta" (el celular no sabe cómo está girada).
  void Function(String como)? alGirarTele1;

  static const _girosQueSePiden = {'horizontal', 'vertical', 'dar_vuelta'};

  /// Cambió la escuela de alguna tele, o se le cambió la escuela a la tele
  /// desde un celular ([aviso]: lo que se dice).
  void Function(String? aviso)? alCambiarLasEscuelas;

  /// Las que se pueden elegir desde el celular.
  var _paraElegir = const <EscuelaParaElegir>[];

  void ponerEscuelasParaElegir(List<EscuelaParaElegir> escuelas) {
    _paraElegir = List.unmodifiable(escuelas);
    _avisarTeles();
  }

  String _tituloDe(String id) =>
      _escuelas[id]?.titulo ??
      _paraElegir.where((e) => e.id == id).firstOrNull?.titulo ??
      'otra escuela';

  /// Si las teles conectadas muestran la misma escuela: "Las dos" vale solo
  /// así.
  bool get _mismaEscuela {
    final una = _deLaTele[1];
    for (final t in _teles.values) {
      if (t.escuela != una) return false;
    }
    return true;
  }

  // ── Las teles (24-nov-2026) ───────────────────────────────────────────────

  /// La Tele 2 conectada, si está.
  final _teles = <int, _ConexionTele>{};

  /// Los segundos de la llegada de cada otra tele (la 2): cada recepcionista
  /// controla los de su tele. Los de la Tele 1 son los de su escuela.
  final _tiemposDeTele = <int, TiemposAMano>{};

  final _cambiosDeTeles = StreamController<List<TeleConectada>>.broadcast();

  /// Se avisa cada vez que la Tele 2 se conecta o se va.
  Stream<List<TeleConectada>> get cambiosDeTeles => _cambiosDeTeles.stream;

  List<TeleConectada> get teles => [
    for (var n = 2; n <= kTelesDeLaNoche; n++)
      TeleConectada(n, conectada: _teles.containsKey(n), evento: _deLaTele[n]),
  ];

  /// Lo que cambia la Tele 2 en sus segundos lo avisa acá.
  void Function(int tele, TiemposAMano t)? alCambiarTiemposDeTele;

  String get codigo => _codigo;
  int? get puerto => _servidor?.port;

  // ── El locutor (28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`) ───────────

  /// **El código del locutor**: otro que el de los celulares. Con él solo se mira la
  /// lista ([ListaDelLocutor]); no abre la puerta. Null: sin locutor.
  String? get codigoLocutor => _codigoLocutor;
  String? _codigoLocutor;

  /// Los locutores conectados: van aparte de los puestos (no marcan, no están en el
  /// chat ni reciben la lista de la puerta).
  final _locutores = <_Conexion>{};
  ListaDelLocutor? _listaLocutor;
  String? _firmaLocutor;
  var _versionLocutor = 0;
  final _cambiosDeLocutores = StreamController<int>.broadcast();

  int get locutoresConectados => _locutores.length;

  /// Cuántos locutores hay conectados, cada vez que cambia.
  Stream<int> get cambiosDeLocutores => _cambiosDeLocutores.stream;

  /// La lista del locutor de todas las escuelas que atiende; **se le manda solo si cambió
  /// lo que dice** (un ingreso no la cambia).
  void _mandarLocutor() {
    final puertas = [for (final e in _escuelas.values) ?e.puerta];
    if (puertas.isEmpty) return;
    final lista = ListaDelLocutor.de(puertas);
    final firma = jsonEncode([_principal.titulo, lista.toJson()]);
    if (firma == _firmaLocutor) return;
    _firmaLocutor = firma;
    _listaLocutor = lista;
    _versionLocutor++;
    final texto = _textoLocutor();
    for (final c in _locutores) {
      c.mandar(texto);
    }
  }

  String _textoLocutor() => jsonEncode({
        't': 'locutor',
        'v': _versionLocutor,
        'titulo': _principal.titulo,
        // La hora de la central: el NUEVO no depende de la del celular.
        'ahora': _ahora().toUtc().toIso8601String(),
        'lista': _listaLocutor!.toJson(),
      });

  void _avisarLocutores() {
    if (!_cambiosDeLocutores.isClosed) _cambiosDeLocutores.add(_locutores.length);
  }

  void _conectarLocutor(WebSocket ws, String celular) {
    for (final vieja in _locutores.where((c) => c.celular == celular).toList()) {
      _locutores.remove(vieja);
      unawaited(vieja.cerrar(4003, 'reemplazada'));
    }
    ws.pingInterval = const Duration(seconds: 5);
    final c = _Conexion(ws, celular, 'Locutor');
    _locutores.add(c);
    _avisarLocutores();
    c.mandar(_listaLocutor == null ? jsonEncode({'t': 'esperando'}) : _textoLocutor());
    ws.listen(
      (m) => _mensajeDelLocutor(c, m),
      onDone: () => _seFueLocutor(c),
      onError: (Object _) => _seFueLocutor(c),
      cancelOnError: true,
    );
  }

  /// Del locutor solo se atiende el latido: un pedido o un chat no hacen nada.
  void _mensajeDelLocutor(_Conexion c, dynamic mensaje) {
    if (mensaje is! String || mensaje.length > 512) return;
    try {
      final j = jsonDecode(mensaje);
      if (j is Map && j['t'] == 'hola') {
        c.mandar(jsonEncode({'t': 'hola', 'ahora': _ahora().toUtc().toIso8601String()}));
      }
    } catch (_) {}
  }

  void _seFueLocutor(_Conexion c) {
    if (_locutores.remove(c)) _avisarLocutores();
  }

  /// Otro código del locutor: el que está conectado queda afuera (los celulares de la
  /// puerta siguen).
  Future<void> cambiarCodigoLocutor(String nuevo) async {
    _codigoLocutor = nuevo;
    final viejos = _locutores.toList();
    _locutores.clear();
    for (final c in viejos) {
      c.mandar(jsonEncode({'t': 'codigo'}));
      await c.cerrar(4001, 'codigo');
    }
    _avisarLocutores();
  }

  /// Las marcas de la escuela de la central (en la notebook, las de la
  /// noche).
  MarcasDeLaNoche get marcas => _principal.resolvedor.marcas;

  /// Las marcas de la escuela [eventoId], si la atiende.
  MarcasDeLaNoche? marcasDe(String eventoId) => _escuelas[eventoId]?.resolvedor.marcas;

  /// Cuántos marcó [puesto] esta noche que siguen adentro, en todas.
  int _marcados(String puesto) =>
      _escuelas.values.fold(0, (n, e) => n + e.resolvedor.marcas.cuantos(puesto));

  /// Los celulares de esta noche: primero los conectados, por nombre.
  List<PuestoConectado> get puestos {
    final lista = _puestos.values.toList()
      ..sort((a, b) {
        if (a.conectado != b.conectado) return a.conectado ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return lista;
  }

  Stream<List<PuestoConectado>> get cambiosDePuestos =>
      _cambiosDePuestos.stream;

  /// Abre la central y devuelve en qué puerto quedó. [en] es por dónde se
  /// escucha: en la app, todas las conexiones de la PC; en las pruebas, solo
  /// esta PC (así Windows no pregunta por el cortafuegos).
  Future<int> arrancar({
    int desde = kPuertoCentral,
    InternetAddress? en,
  }) async {
    final donde = en ?? InternetAddress.anyIPv4;
    final intentos = desde == 0 ? 1 : 10;
    SocketException? ultimo;
    for (var i = 0; i < intentos && _servidor == null; i++) {
      try {
        _servidor = await HttpServer.bind(donde, desde == 0 ? 0 : desde + i);
      } on SocketException catch (e) {
        ultimo = e;
      }
    }
    final servidor = _servidor;
    if (servidor == null) throw ultimo!;
    servidor.listen(
      (pedido) => unawaited(_atender(pedido)),
      onError: (Object e) => debugPrint('Central de la puerta: $e'),
    );
    return servidor.port;
  }

  _Escuela? _escuela(String? de) => _escuelas[de ?? eventoId];

  /// La lista cambió (alguien entró, se sorteó, se cargó un acompañante): se
  /// les manda a todos los celulares. [de]: la escuela (null: la de la
  /// central).
  void ponerPuerta(PuertaDelEvento puerta, {String? de}) {
    final e = _escuela(de);
    if (e == null) return;
    e.puerta = puerta;
    e.resolvedor.puerta = puerta;
    _mandarLista(e);
    _mandarLocutor();
  }

  /// Los segundos de la llegada de esa noche, para que el celular los muestre
  /// y los pueda cambiar.
  void ponerTiempos(TiemposAMano? tiempos, {String? de}) {
    final e = _escuela(de);
    if (e == null || tiempos == e.tiempos) return;
    e.tiempos = tiempos;
    if (e.puerta != null) _mandarLista(e);
  }

  void ponerTitulo(String? titulo, {String? de}) {
    final e = _escuela(de);
    if (e == null || titulo == e.titulo) return;
    e.titulo = titulo;
    if (e.puerta != null) _mandarLista(e);
    if (esTele) _avisarTeles();
  }

  /// Los segundos de la llegada de la Tele [tele] (la 2), cambiados desde un
  /// celular: se los manda a esa tele, que los pone en su pantalla.
  void ponerTiemposDeTele(int tele, TiemposAMano tiempos) {
    _tiemposDeTele[tele] = tiempos;
    _teles[tele]?.mandar(jsonEncode({'t': 'tiempos', 'tiempos': tiempos.toJson()}));
    for (final e in _escuelas.values) {
      if (e.puerta != null) _mandarLista(e);
    }
  }

  /// La lista de la puerta fila por fila (la de la base de esta tele): lo que
  /// cambió se le manda a la Tele 2, que lo copia en la suya. Con cada ingreso
  /// va cómo se saluda ([MarcasDeLaNoche.bienvenida]). La Tele 2 copia las de
  /// todas las escuelas que se atienden: si la Tele 1 se apaga, tiene todo.
  void ponerFilas(List<Invitado> filas, {String? de}) {
    final e = _escuela(de);
    if (e == null) return;
    e.filas
      ..clear()
      ..addEntries(filas.map((f) => MapEntry(f.id, f)));
    for (final t in _teles.values) {
      _mandarFilas(t);
    }
  }

  /// Lo que la Tele 2 todavía no tiene: todo al conectarse; después, lo que
  /// cambió.
  void _mandarFilas(_ConexionTele t) {
    final ahora = _ahora();
    final cambiadas = <Invitado>[];
    final bienvenidas = <String, Object?>{};
    final por = <String, String>{};
    for (final e in _escuelas.values) {
      por.addAll(e.resolvedor.marcas.todas);
      for (final f in e.filas.values) {
        final firma = _firma(f);
        if (t.enviadas[f.id] == firma) continue;
        t.enviadas[f.id] = firma;
        cambiadas.add(f);
        final b = f.estadoIngreso == EstadoIngreso.ingresado
            ? e.resolvedor.marcas.bienvenida(f.id)
            : null;
        if (b != null) bienvenidas[f.id] = b.toJson(ahora);
      }
    }
    if (cambiadas.isEmpty) return;
    t.mandar(jsonEncode({
      't': 'filas',
      'filas': [for (final f in cambiadas) Invitado.sinDatosPrivados(f.toJson())],
      'bienvenidas': bienvenidas,
      'por': por,
    }));
  }

  static String _firma(Invitado f) =>
      '${f.estadoIngreso.name}|${f.updatedAt?.toIso8601String()}|'
      '${f.numeroMesa}|${f.nombreCompleto}';

  /// Lo que la Tele 2 tiene que saber de los celulares: quién la maneja.
  void _mandarManejan() {
    for (final t in _teles.values) {
      t.mandar(jsonEncode({
        't': 'maneja',
        'nombres': _quienesManejan(t.numero),
      }));
    }
    _avisarTeles();
  }

  /// Los nombres de los celulares conectados que eligieron la tele [n].
  List<String> _quienesManejan(int n) => [
    for (final c in _conexiones)
      if (c.tele == n || c.tele == kLasDosTeles) c.nombre,
  ];

  /// Las teles para el celular: cuáles hay, quién maneja cada una, qué escuela
  /// muestra, y las escuelas que se pueden elegir.
  String _textoDeTeles() => jsonEncode({
    't': 'teles',
    'lista': [
      {
        'n': 1,
        'conectada': true,
        'maneja': _quienesManejan(1),
        'evento': eventoId,
        'titulo': _tituloDe(eventoId),
      },
      for (final t in teles)
        {
          'n': t.numero,
          'conectada': t.conectada,
          'maneja': _quienesManejan(t.numero),
          if (t.evento != null) 'evento': t.evento,
          if (t.evento != null) 'titulo': _tituloDe(t.evento!),
        },
    ],
    'escuelas': [for (final e in _paraElegir) e.toJson()],
    'lasDos': _mismaEscuela,
  });

  void _avisarTeles() {
    if (!esTele) return;
    final texto = _textoDeTeles();
    for (final c in _conexiones) {
      c.mandar(texto);
    }
    // La Tele 2 sabe qué escuelas se atienden: si pasa a principal, atiende la
    // de la Tele 1 y sube solo lo copiado de esas.
    final escuelas = jsonEncode({'t': 'escuelas', 'escuelas': atiende});
    for (final t in _teles.values) {
      t.mandar(escuelas);
    }
    if (!_cambiosDeTeles.isClosed) _cambiosDeTeles.add(teles);
  }

  // ── El chat de la puerta (6.5.0) ─────────────────────────────────────────

  /// Los mensajes de la noche, solo en la memoria de la central.
  final _chat = ChatDeLaNoche();

  /// Lo que le llega a la PC (los de todos y los que le mandan).
  void Function(MensajeDePuesto)? alLlegarALaPc;

  /// Cómo se llama la PC en el chat: quien la opera.
  String _nombreDeLaPc = 'PC';

  set nombreDeLaPc(String nombre) {
    final n = nombre.trim();
    if (n.isEmpty || n == _nombreDeLaPc) return;
    _nombreDeLaPc = n;
    _mandarPuestos();
  }

  /// Los puestos con los que se puede hablar: la PC y los celulares.
  List<PuestoDelChat> get puestosDelChat => [
    PuestoDelChat(id: kPuestoDeLaPc, nombre: _nombreDeLaPc, conectado: true),
    for (final p in puestos)
      PuestoDelChat(id: p.celular, nombre: p.nombre, conectado: p.conectado),
  ];

  /// Lo que manda la PC.
  void mandarDesdeLaPc(MensajeDePuesto m) => _repartir(m);

  /// Lo guarda y se lo da solo a quien le toca: a todos, o al otro puesto y a
  /// quien lo mandó. Si llega dos veces, la segunda no hace nada.
  void _repartir(MensajeDePuesto m) {
    if (!_chat.agregar(m)) return;
    final texto = jsonEncode({'t': 'chat', 'm': m.toJson()});
    for (final c in _conexiones) {
      if (m.loVe(c.celular)) c.mandar(texto);
    }
    if (m.loVe(kPuestoDeLaPc)) alLlegarALaPc?.call(m);
  }

  /// La última lista de puestos que se mandó: el latido de cada celular avisa
  /// los puestos cada 5 s, y la lista se manda solo si cambió.
  String? _ultimosPuestos;

  String _textoDePuestos() => jsonEncode({
    't': 'puestos',
    'lista': [for (final p in puestosDelChat) p.toJson()],
  });

  /// A [salvo] no: es el que recién llega, y a ese se le manda aparte.
  void _mandarPuestos({_Conexion? salvo}) {
    final texto = _textoDePuestos();
    if (texto == _ultimosPuestos) return;
    _ultimosPuestos = texto;
    for (final c in _conexiones) {
      if (identical(c, salvo)) continue;
      c.mandar(texto);
    }
  }

  /// Pone el salón y se lo manda a todos. [armado] y [cfg] ya en JSON (el de
  /// `ArmadoSalon.toJson` y `SalonParaLaPuerta.cfgParaElCelular`); null: sin
  /// salón. El salón de la fiesta para VER EN EL PLANO del celular (6.5.0) va
  /// en un mensaje aparte de la lista, que se manda muchas veces por noche: el
  /// armado pesa.
  void ponerSalon(Map<String, dynamic>? armado, Map<String, dynamic>? cfg, {String? de}) {
    final e = _escuela(de);
    if (e == null) return;
    final nuevo = jsonEncode({
      't': 'salon',
      'armado': armado,
      'cfg': armado == null ? null : cfg,
      // De qué escuela es: el celular no lo confunde con el de otra
      // (revisión del 26-nov).
      if (esTele) 'evento': e.eventoId,
    });
    if (nuevo == e.salon) return;
    e.salon = nuevo;
    for (final c in _conexiones) {
      if (_escuelaDe(c) == e.eventoId) c.mandar(nuevo);
    }
  }

  /// La escuela que ve un celular: la de su tele. "Las dos" va solo con la
  /// misma escuela; un celular sin tele (o en la notebook), la de la central.
  String _escuelaDe(_Conexion c) {
    if (!esTele) return eventoId;
    final t = c.tele;
    if (t == null || t == kLasDosTeles) return eventoId;
    return _deLaTele[t] ?? eventoId;
  }

  void _mandarLista(_Escuela e) {
    _version++;
    e.lista = jsonEncode({
      't': 'puerta',
      'v': _version,
      'evento': e.eventoId,
      'titulo': e.titulo,
      'puerta': e.puerta!.toJson(),
      'por': e.resolvedor.marcas.todas,
      if (e.tiempos != null) 'tiempos': e.tiempos!.toJson(),
      // La tele es el tótem (24-nov-2026): el celular dice "Conectado a la
      // Tele 1" y, con dos teles, muestra los segundos de la suya.
      if (esTele) 'central': 'Tele 1',
      if (_tiemposDeTele.isNotEmpty)
        'tiemposTeles': {
          for (final x in _tiemposDeTele.entries) '${x.key}': x.value.toJson(),
        },
    });
    for (final c in _conexiones) {
      if (_escuelaDe(c) == e.eventoId) c.mandar(e.lista!);
    }
  }

  /// A [c], lo de su escuela: la lista y el salón. Si esa escuela todavía no
  /// tiene lista (recién se empezó a atender), "esperando" con la escuela: el
  /// celular deja la de antes y no marca en ella (revisión del 26-nov).
  void _mandarEscuelaA(_Conexion c) {
    final id = _escuelaDe(c);
    final e = _escuelas[id];
    c.mandar(e?.lista ?? jsonEncode({'t': 'esperando', if (esTele) 'evento': id}));
    // Sin salón también: que no quede el de la escuela de antes.
    c.mandar(e?.salon ??
        jsonEncode({'t': 'salon', 'armado': null, 'cfg': null, if (esTele) 'evento': id}));
  }

  /// **La tele [n] pasa a mostrar la escuela [evento]** (25-nov-2026), sin
  /// reiniciar nada: la central la atiende (si no la atendía), los celulares
  /// de esa tele pasan solos con un aviso ("Caro pasó la Tele 1 a ESCUELA B"),
  /// y si la otra tele tenía la misma escuela, a sus celulares se les pregunta
  /// MANTENER · CAMBIAR. [por]: quién la cambió (null: con el control de la
  /// tele). [yaCambio]: la tele ya la cambió (la Tele 2 con su control): no se
  /// le vuelve a pedir.
  ///
  /// Devuelve si cambió. No cambia (revisión del 26-nov):
  /// - una escuela que esta tele no conoce ([conoce]): la tele no la podría
  ///   mostrar y la central quedaría en otra;
  /// - la Tele 2 desconectada, salvo que ella misma avise ([yaCambio]): no se
  ///   enteraría, y al volver con la suya la central la volvería atrás.
  bool cambiarEscuelaDeTele(int n, String evento, {String? por, bool yaCambio = false}) {
    if (!esTele || n < 1 || n > kTelesDeLaNoche || !conoce(evento)) return false;
    if (n >= 2 && !yaCambio && !_teles.containsKey(n)) return false;
    final antes = _deLaTele[n];
    if (antes == evento) return false;
    atender(evento);
    // Las preguntas que hablaban de esta tele ya no valen: volvió a cambiar.
    for (final e in _preguntas.entries.toList()) {
      if (e.value.deTele == n || e.value.tele == n) {
        _cerrarPregunta(e.key, 'La ${nombreDeLaTele(n)} volvió a cambiar: la pregunta ya no vale.');
      }
    }
    // A quién preguntar: la otra tele con la misma escuela, si está conectada
    // (desconectada, no se enteraría del CAMBIAR).
    final conLaMisma = [
      for (final e in _deLaTele.entries)
        if (e.key != n && e.value == antes && (e.key == 1 || _teles.containsKey(e.key))) e.key,
    ];
    _deLaTele[n] = evento;
    if (n == 1) {
      if (!yaCambio) alCambiarTele1?.call(evento, por);
    } else {
      final t = _teles[n];
      if (t != null) {
        t.escuela = evento;
        if (!yaCambio) {
          t.mandar(jsonEncode({'t': 'escuela', 'evento': evento, 'por': ?por}));
        }
      }
    }
    final titulo = _tituloDe(evento);
    final tele = nombreDeLaTele(n);
    final aviso = por == null ? 'La $tele pasó a $titulo' : '$por pasó la $tele a $titulo';
    // Sus celulares pasan solos. Los de "Las dos" ya no ven las dos: quedan en
    // esta tele.
    for (final c in _conexiones) {
      if (c.tele == kLasDosTeles) {
        c.tele = n;
        c.mandar(jsonEncode({'t': 'tu_tele', 'n': n}));
      }
      if (_escuelaDe(c) == evento && (c.tele == n || (c.tele == null && n == 1))) {
        _mandarEscuelaA(c);
        c.mandar(jsonEncode({'t': 'aviso', 'texto': aviso}));
      }
    }
    // La otra tele tenía la misma: que lo decidan sus celulares.
    for (final m in conLaMisma) {
      _preguntar(m, evento, 'La $tele cambió a $titulo', deTele: n);
    }
    _soltarSinTele();
    _mandarManejan();
    for (final c in _conexiones) {
      _anotarPuesto(c, conectado: true, avisar: false);
    }
    _avisarPuestos();
    alCambiarLasEscuelas?.call(por == null ? null : aviso);
    return true;
  }

  /// **"Pasar a principal" con la Tele 1 apagada** (25-nov-2026): esta tele
  /// atiende también la escuela que mostraba la que se apagó, en el lugar de
  /// la Tele 2 (que ya no está). Sus celulares escanean el QR de "la otra
  /// escuela" (`&t=2`) y marcan en ella; ninguna tele la saluda.
  void atenderSinTele(String evento) {
    if (!esTele || evento == eventoId || !conoce(evento) || _teles.containsKey(2)) return;
    atender(evento);
    _deLaTele[2] = evento;
    for (final c in _conexiones) {
      if (c.tele == 2) _mandarEscuelaA(c);
    }
    _mandarManejan();
    alCambiarLasEscuelas?.call(null);
  }

  // ── "La Tele 1 cambió a ESCUELA B · MANTENER · CAMBIAR" ───────────────────

  final _preguntas = <String, _Pregunta>{};
  var _numeroDePregunta = 0;

  /// Les pregunta a los celulares de la tele [tele] si cambian a [evento] (la
  /// tele [deTele] ya cambió). Vale la primera respuesta; sin respuesta, se
  /// mantiene.
  void _preguntar(int tele, String evento, String texto, {required int deTele}) {
    final id = 'p${++_numeroDePregunta}';
    final mensaje = jsonEncode({
      't': 'pregunta',
      'id': id,
      'tele': tele,
      'evento': evento,
      'texto': texto,
    });
    var alguien = false;
    for (final c in _conexiones) {
      if (c.tele == tele) {
        c.mandar(mensaje);
        alguien = true;
      }
    }
    // Sin nadie que conteste, se mantiene: no hace falta esperar.
    if (!alguien) return;
    final p = _Pregunta(tele, evento, deTele);
    _preguntas[id] = p;
    p.vence = Timer(kEsperaDeLaPregunta, () => _cerrarPregunta(id, 'Nadie contestó: se mantiene.'));
  }

  void _cerrarPregunta(String id, String texto) {
    final p = _preguntas.remove(id);
    p?.vence?.cancel();
    final mensaje = jsonEncode({'t': 'pregunta_cerrada', 'id': id, 'texto': texto});
    for (final c in _conexiones) {
      if (p == null || c.tele == p.tele) c.mandar(mensaje);
    }
  }

  void _contestar(_Conexion c, String id, bool cambiar) {
    final p = _preguntas[id];
    if (p == null) {
      // Ya la contestó otro, o venció.
      c.mandar(jsonEncode({'t': 'pregunta_cerrada', 'id': id}));
      return;
    }
    if (c.tele != p.tele) return;
    _cerrarPregunta(id, '${c.nombre} eligió ${cambiar ? 'CAMBIAR' : 'MANTENER'}.');
    if (cambiar) cambiarEscuelaDeTele(p.tele, p.evento, por: c.nombre);
  }

  /// Otro código: los celulares conectados quedan afuera y tienen que volver a
  /// escanear.
  Future<void> cambiarCodigo(String nuevo) async {
    _codigo = nuevo;
    // La Tele 2 muestra el QR con el código: el nuevo (revisión del 26-nov).
    for (final t in _teles.values) {
      t.mandar(jsonEncode({'t': 'central', 'codigo': nuevo, 'evento': eventoId, 'escuelas': atiende}));
    }
    final viejas = _conexiones.toList();
    _conexiones.clear();
    _puestos.clear();
    for (final c in viejas) {
      c.mandar(jsonEncode({'t': 'codigo'}));
      await c.cerrar(4001, 'codigo');
    }
    _avisarPuestos();
  }

  Future<void> cerrar() async {
    for (final p in _preguntas.values) {
      p.vence?.cancel();
    }
    _preguntas.clear();
    final todas = _conexiones.toList();
    _conexiones.clear();
    for (final c in todas) {
      await c.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    final teles = _teles.values.toList();
    _teles.clear();
    for (final t in teles) {
      await t.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    // Los locutores también: la página dice que se cortó y vuelve sola.
    final locutores = _locutores.toList();
    _locutores.clear();
    for (final c in locutores) {
      await c.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    await _servidor?.close(force: true);
    _servidor = null;
    await _cambiosDePuestos.close();
    await _cambiosDeTeles.close();
    await _cambiosDeLocutores.close();
  }

  // ── Lo que llega por la red ───────────────────────────────────────────────

  Future<void> _atender(HttpRequest pedido) async {
    try {
      if (pedido.uri.path == '/vivo') {
        await _conectar(pedido);
        return;
      }
      if (pedido.uri.path == '/tele') {
        await _conectarTele(pedido);
        return;
      }
      if (pedido.method != 'GET' && pedido.method != 'HEAD') {
        pedido.response.statusCode = HttpStatus.methodNotAllowed;
        await pedido.response.close();
        return;
      }
      await _servirArchivo(pedido);
    } catch (e) {
      debugPrint('Central de la puerta, pedido ${pedido.uri.path}: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  bool _frenado(String ip) {
    final ahora = _ahora();
    final lista = _errores[ip];
    if (lista == null) return false;
    lista.removeWhere((t) => ahora.difference(t) >= kFrenoPorErrores);
    return lista.length >= kErroresDeCodigo;
  }

  Future<void> _conectar(HttpRequest pedido) async {
    if (!WebSocketTransformer.isUpgradeRequest(pedido)) {
      pedido.response.statusCode = HttpStatus.badRequest;
      await pedido.response.close();
      return;
    }
    final ip = pedido.connectionInfo?.remoteAddress.address ?? '';
    final datos = pedido.uri.queryParameters;
    final ws = await WebSocketTransformer.upgrade(pedido);

    // Se acepta la conexión antes de mirar el código: un navegador no deja
    // leer por qué se rechazó, así el celular puede decir qué pasó.
    if (_frenado(ip)) {
      ws.add(jsonEncode({'t': 'espera'}));
      await ws.close(4029, 'espera');
      return;
    }
    // El locutor entra solo con su código, y su código no abre la puerta.
    final esLocutor = datos['r'] == 'locutor';
    final esperado = esLocutor ? _codigoLocutor : _codigo;
    if (esperado == null || datos['c'] != esperado) {
      (_errores[ip] ??= []).add(_ahora());
      ws.add(jsonEncode({'t': 'codigo'}));
      await ws.close(4001, 'codigo');
      return;
    }
    _errores.remove(ip);
    final celular = datos['id']?.trim() ?? '';
    final nombre = datos['p']?.trim() ?? '';
    if (celular.isEmpty ||
        celular.length > 64 ||
        nombre.isEmpty ||
        nombre.length > 40) {
      ws.add(jsonEncode({'t': 'nombre'}));
      await ws.close(4002, 'nombre');
      return;
    }

    if (esLocutor) {
      _conectarLocutor(ws, celular);
      return;
    }

    // Si el mismo celular vuelve (se cortó el wifi y se reconectó), la conexión
    // vieja puede seguir colgada un rato: se cierra.
    for (final vieja
        in _conexiones.where((c) => c.celular == celular).toList()) {
      _conexiones.remove(vieja);
      unawaited(vieja.cerrar(4003, 'reemplazada'));
    }

    // El ping lo contesta solo el navegador: una conexión que no contesta en
    // ese tiempo se da por caída.
    ws.pingInterval = const Duration(seconds: 5);
    final tele = int.tryParse(datos['t'] ?? '');
    final conexion = _Conexion(
      ws,
      celular,
      nombre,
      tele: esTele && tele != null && esTeleValida(tele) ? tele : null,
    );
    // "Las dos" va solo con la misma escuela en las dos teles.
    if (conexion.tele == kLasDosTeles && !_mismaEscuela) conexion.tele = 1;
    _conexiones.add(conexion);
    _anotarPuesto(conexion, conectado: true, salvo: conexion);
    final escuela = _escuelas[_escuelaDe(conexion)];
    conexion.mandar(escuela?.lista ??
        jsonEncode({'t': 'esperando', if (esTele) 'evento': _escuelaDe(conexion)}));
    if (escuela?.salon != null) conexion.mandar(escuela!.salon!);
    // El chat: lo que ya hubo esta noche para ese celular, y con quién hablar.
    conexion.mandar(
      jsonEncode({
        't': 'chat',
        'todos': [for (final m in _chat.paraElPuesto(celular)) m.toJson()],
      }),
    );
    // Al que llega, siempre (aunque la lista no haya cambiado: vuelve el
    // mismo celular).
    conexion.mandar(_textoDePuestos());
    // Con la central en una tele: qué teles hay y quién maneja cada una.
    if (esTele) {
      if (tele == kLasDosTeles && conexion.tele != kLasDosTeles) {
        conexion.mandar(jsonEncode({'t': 'tu_tele', 'n': conexion.tele}));
      }
      _mandarManejan();
    }

    ws.listen(
      (mensaje) => _mensaje(conexion, mensaje),
      onDone: () => _seFue(conexion),
      onError: (Object _) => _seFue(conexion),
      cancelOnError: true,
    );
  }

  void _seFue(_Conexion conexion) {
    if (!_conexiones.remove(conexion)) return;
    _anotarPuesto(conexion, conectado: false);
    if (esTele) _mandarManejan();
  }

  void _anotarPuesto(
    _Conexion c, {
    required bool conectado,
    _Conexion? salvo,
    bool avisar = true,
  }) {
    _puestos[c.celular] = PuestoConectado(
      celular: c.celular,
      nombre: c.nombre,
      conectado: conectado,
      ultimaVez: _ahora(),
      marcados: _marcados(c.nombre),
      tele: c.tele,
    );
    if (avisar) _avisarPuestos(salvo: salvo);
  }

  void _avisarPuestos({_Conexion? salvo}) {
    for (final entrada in _puestos.entries.toList()) {
      final p = entrada.value;
      _puestos[entrada.key] = PuestoConectado(
        celular: p.celular,
        nombre: p.nombre,
        conectado: p.conectado,
        ultimaVez: p.ultimaVez,
        marcados: _marcados(p.nombre),
        tele: p.tele,
      );
    }
    if (!_cambiosDePuestos.isClosed) _cambiosDePuestos.add(puestos);
    _mandarPuestos(salvo: salvo);
  }

  void _mensaje(_Conexion conexion, dynamic mensaje) {
    if (mensaje is! String || mensaje.length > 4096) return;
    final Object? json;
    try {
      json = jsonDecode(mensaje);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'hola':
        conexion.mandar(jsonEncode({'t': 'hola'}));
        final antes = _puestos[conexion.celular];
        if (antes != null && _conexiones.contains(conexion)) {
          _anotarPuesto(conexion, conectado: true);
        }
      case 'chat':
        final m = MensajeDePuesto.fromJson(json['m']);
        if (m == null) return;
        // De quién es lo dice la conexión, no el mensaje: nadie escribe con el
        // nombre de otro.
        _repartir(
          MensajeDePuesto(
            id: m.id,
            de: conexion.celular,
            deNombre: conexion.nombre,
            para: m.para,
            texto: m.texto,
            hora: _ahora(),
          ),
        );
      case 'tele':
        // "Tu tele" (24-nov-2026): el celular cambió de tele.
        final n = json['n'];
        if (!esTele || n is! int || !esTeleValida(n)) return;
        if (n == kLasDosTeles && !_mismaEscuela) {
          conexion.mandar(jsonEncode({
            't': 'aviso',
            'texto': '"Las dos" va solo con la misma escuela en las dos teles.',
          }));
          conexion.mandar(jsonEncode({'t': 'tu_tele', 'n': conexion.tele}));
          return;
        }
        final antes = _escuelaDe(conexion);
        conexion.tele = n;
        // Otra tele con otra escuela: lo de esa escuela.
        if (_escuelaDe(conexion) != antes) _mandarEscuelaA(conexion);
        _anotarPuesto(conexion, conectado: true);
        _mandarManejan();
      case 'escuela':
        // CAMBIAR LA ESCUELA de una tele, desde el celular (sin PIN).
        final n = json['tele'];
        final evento = json['evento'];
        if (!esTele || n is! int || evento is! String) return;
        if (_deLaTele[n] == evento) return;
        if (!cambiarEscuelaDeTele(n, evento, por: conexion.nombre)) {
          conexion.mandar(jsonEncode({
            't': 'aviso',
            'texto': n >= 2 && !_teles.containsKey(n)
                ? 'La ${nombreDeLaTele(n)} no está conectada: cambiale la escuela cuando vuelva.'
                : 'Esa escuela no está en esta tele.',
          }));
        }
      case 'girar':
        // GIRAR desde el celular, sin PIN: Horizontal · Vertical · Dar vuelta.
        final n = json['tele'];
        final como = json['como'];
        if (!esTele || n is! int || como is! String || !_girosQueSePiden.contains(como)) return;
        if (n == 1) {
          alGirarTele1?.call(como);
        } else {
          _teles[n]?.mandar(jsonEncode({'t': 'girar', 'como': como}));
        }
        final aviso = '${conexion.nombre} giró la ${nombreDeLaTele(n)}';
        for (final c in _conexiones) {
          if (!identical(c, conexion) && (c.tele == n || c.tele == kLasDosTeles)) {
            c.mandar(jsonEncode({'t': 'aviso', 'texto': aviso}));
          }
        }
      case 'contesta':
        final id = json['id'];
        final cambiar = json['cambiar'];
        if (!esTele || id is! String || cambiar is! bool) return;
        _contestar(conexion, id, cambiar);
      case 'pedido':
        final leido = PedidoPuerta.fromJson(json);
        if (leido == null) return;
        // Sin tele en el pedido, la que eligió el celular. Con la central en
        // la notebook no hay teles: como siempre.
        final pedido = esTele
            ? leido.conTele(leido.tele ?? conexion.tele)
            : leido.conTele(null);
        // La escuela del pedido: la que miraba el celular al tocarlo (en la
        // tele), o la de su tele.
        final evento = esTele ? leido.evento : null;
        if (evento != null) atender(evento);
        final escuela = _escuelas[evento] ?? _escuelas[_escuelaDe(conexion)]!;
        // De a uno, con la PC: cada pedido mira la base después del anterior.
        unawaited(
          escuela.resolvedor.resolver(pedido, conexion.nombre).then((respuesta) {
            conexion.mandar(jsonEncode(respuesta));
            if (respuesta['ok'] == true && respuesta['hizo'] != 'nada') {
              _avisarPuestos();
            }
          }),
        );
    }
  }

  // ── La Tele 2 (24-nov-2026) ───────────────────────────────────────────────

  /// La Tele 2 se conecta con el número del evento, como las cajas de la barra:
  /// es la misma app, con la misma fiesta bajada en la oficina. Desde el
  /// 25-nov-2026 puede tener otra escuela: la Tele 1 la atiende también.
  Future<void> _conectarTele(HttpRequest pedido) async {
    if (!WebSocketTransformer.isUpgradeRequest(pedido)) {
      pedido.response.statusCode = HttpStatus.badRequest;
      await pedido.response.close();
      return;
    }
    final datos = pedido.uri.queryParameters;
    final ws = await WebSocketTransformer.upgrade(pedido);
    final numero = int.tryParse(datos['n'] ?? '');
    final evento = datos['evento'] ?? '';
    if (!esTele ||
        !conoce(evento) ||
        numero == null ||
        numero < 2 ||
        numero > kTelesDeLaNoche) {
      ws.add(jsonEncode({'t': 'evento'}));
      await ws.close(4001, 'evento');
      return;
    }
    final vieja = _teles.remove(numero);
    if (vieja != null) unawaited(vieja.cerrar(4003, 'reemplazada'));
    ws.pingInterval = const Duration(seconds: 5);
    atender(evento);
    final antes = _deLaTele[numero];
    final t = _ConexionTele(ws, numero, evento);
    _teles[numero] = t;
    _deLaTele[numero] = evento;
    t.mandar(jsonEncode({
      't': 'central',
      'codigo': _codigo,
      'evento': eventoId,
      'escuelas': atiende,
    }));
    final tiempos = _tiemposDeTele[numero];
    if (tiempos != null) {
      t.mandar(jsonEncode({'t': 'tiempos', 'tiempos': tiempos.toJson()}));
    }
    _mandarFilas(t);
    // Sus celulares, con lo de su escuela si volvió con otra; y los de "Las
    // dos", a la Tele 1 si ya no tienen la misma escuela.
    if (antes != evento) {
      for (final c in _conexiones) {
        if (c.tele == kLasDosTeles && !_mismaEscuela) {
          c.tele = 1;
          c.mandar(jsonEncode({'t': 'tu_tele', 'n': 1}));
        }
        if (c.tele == numero) _mandarEscuelaA(c);
      }
      _soltarSinTele();
    }
    _mandarManejan();
    ws.listen(
      (mensaje) => _mensajeDeTele(t, mensaje),
      onDone: () => _seFueTele(t),
      onError: (Object _) => _seFueTele(t),
      cancelOnError: true,
    );
  }

  void _seFueTele(_ConexionTele t) {
    if (!identical(_teles[t.numero], t)) return;
    _teles.remove(t.numero);
    _avisarTeles();
  }

  void _mensajeDeTele(_ConexionTele t, dynamic mensaje) {
    if (mensaje is! String || mensaje.length > 4096) return;
    final Object? json;
    try {
      json = jsonDecode(mensaje);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'hola':
        t.mandar(jsonEncode({'t': 'hola'}));
      case 'tiempos':
        // Los segundos con que la Tele 2 arrancó: los celulares de esa tele
        // los ven y los cambian desde ahí.
        final tiempos = TiemposAMano.fromJson(json['tiempos']);
        if (tiempos == null || _tiemposDeTele[t.numero] == tiempos) return;
        _tiemposDeTele[t.numero] = tiempos;
        alCambiarTiemposDeTele?.call(t.numero, tiempos);
        for (final e in _escuelas.values) {
          if (e.puerta != null) _mandarLista(e);
        }
      case 'escuela':
        // La Tele 2 cambió de escuela con su control (25-nov-2026).
        final evento = json['evento'];
        if (evento is! String) return;
        final por = json['por'];
        final cambio = cambiarEscuelaDeTele(
          t.numero,
          evento,
          por: por is String && por.isNotEmpty && por.length <= 40 ? por : null,
          yaCambio: true,
        );
        // Una escuela que esta tele no conoce: la Tele 2 se queda donde estaba
        // para la central (sus celulares, con lo de antes).
        if (!cambio && _deLaTele[t.numero] != evento) {
          t.mandar(jsonEncode({'t': 'aviso', 'texto': 'La Tele 1 no tiene esa escuela.'}));
        }
        t.mandar(jsonEncode({'t': 'escuelas', 'escuelas': atiende}));
    }
  }

  // ── La página del celular ─────────────────────────────────────────────────

  /// La sirve la misma función que la página de la barra ([ServirArchivos]).
  Future<void> _servirArchivo(HttpRequest pedido) => ServirArchivos.servir(pedido, paginaDelCelular);
}

/// Lo de cada escuela que atiende la central (25-nov-2026): su fila de
/// pedidos con sus marcas, su lista, sus segundos, su salón y sus filas.
class _Escuela {
  _Escuela(this.eventoId, this.resolvedor);

  final String eventoId;
  final ResolvedorDePedidos resolvedor;
  PuertaDelEvento? puerta;

  /// El último mensaje con la lista.
  String? lista;
  TiemposAMano? tiempos;

  /// Cómo se llama el evento, para el encabezado del celular: "ESCUELA NORMAL —
  /// Egresados (12/12) · masivo".
  String? titulo;

  /// El mensaje del salón, o null.
  String? salon;

  /// La lista de la puerta fila por fila, para copiarla en la Tele 2.
  final filas = <String, Invitado>{};
}

/// "La Tele 1 cambió a ESCUELA B": a qué tele se le pregunta y a qué escuela.
class _Pregunta {
  _Pregunta(this.tele, this.evento, this.deTele);
  final int tele;
  final String evento;

  /// La tele que cambió y por eso se pregunta.
  final int deTele;
  Timer? vence;
}

class _Conexion {
  _Conexion(this.ws, this.celular, this.nombre, {this.tele});

  final WebSocket ws;
  final String celular;
  final String nombre;

  /// "Tu tele": la que eligió el celular.
  int? tele;

  void mandar(String mensaje) {
    try {
      ws.add(mensaje);
    } catch (_) {
      // Ya se cerró: el aviso de que se fue llega por su lado.
    }
  }

  Future<void> cerrar(int codigo, String motivo) async {
    try {
      await ws.close(codigo, motivo).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}

/// La Tele 2, del lado de la Tele 1: qué filas ya tiene y qué escuela muestra.
class _ConexionTele extends _Conexion {
  _ConexionTele(WebSocket ws, this.numero, this.escuela)
      : super(ws, 'tele-$numero', 'Tele $numero');

  final int numero;
  String escuela;

  /// La firma de cada fila que ya se le mandó.
  final enviadas = <String, String>{};
}
