import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pc_despierta.dart';
import '../../barra/central/buscar_central.dart' show RespondeBusqueda;
import '../../tele/red_de_la_tele.dart';
import '../../../models/evento.dart';
import '../../../models/invitado.dart';
import '../../../models/silla_puerta.dart';
import '../../../models/totem_config.dart';
import '../../totem/providers/tiempos_a_mano_provider.dart';
import '../../totem/services/tiempos_a_mano.dart';
import '../chat/chat_del_puesto.dart';
import '../chat/mensaje_de_puesto.dart';
import '../providers/acciones_puerta_provider.dart' show quienOperaEnEstaPc;
import '../providers/recepcion_provider.dart';
import '../providers/salon_de_la_puerta_provider.dart';
import '../services/plano_de_la_puerta.dart';
import '../repositories/invitados_repository.dart';
import '../repositories/sillas_puerta_repository.dart';
import '../services/puerta_del_evento.dart';
import 'central_puerta.dart';
import 'pedidos_de_la_puerta.dart';
import 'codigo_central.dart';
import 'direcciones_red.dart';

/// La central marca con la base de esta PC, por el mismo repositorio que
/// Recepción.
class PuertaDeEstaPcConBase implements PuertaDeEstaPc {
  PuertaDeEstaPcConBase(
    this._invitados,
    this._sillas, {
    required Future<void> Function(String eventoId, TiemposAMano t, int? tele)
        ponerTiempos,
  }) : _ponerTiempos = ponerTiempos;
  final InvitadosRepository _invitados;
  final SillasPuertaRepository _sillas;
  final Future<void> Function(String eventoId, TiemposAMano t, int? tele)
      _ponerTiempos;

  @override
  Future<Invitado?> fila(String id) => _invitados.getLocal(id);

  /// Por `ingresarDesdeLaPuerta`, que crea la fila si falta (un masivo antes del
  /// sorteo) y si no la marca como siempre.
  @override
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  }) =>
      _invitados.ingresarDesdeLaPuerta(
        eventoId: eventoId,
        id: persona.id,
        nombre: persona.nombre,
        mesa: persona.mesa,
        saludar: saludar,
      );

  @override
  Future<void> deshacer(String id) => _invitados.deshacerIngreso(id);

  @override
  Future<List<SillaPuerta>> sillasDelEvento(String eventoId) =>
      _sillas.delEvento(eventoId);

  @override
  Future<void> sumarSilla({
    required String eventoId,
    required String contratoId,
    required int mesa,
    required String vale,
    required String anotadoPor,
    String? nota,
  }) =>
      _sillas.anotar(
        eventoId: eventoId,
        contratoAlumnoId: contratoId,
        mesa: mesa,
        vale: vale,
        anotadoPor: anotadoPor,
        nota: nota,
      );

  @override
  Future<void> quitarSilla(
    String sillaId, {
    required String por,
    required String motivo,
  }) =>
      _sillas.quitar(sillaId, por: por, motivo: motivo);

  @override
  Future<void> ponerTiempos(
    String eventoId,
    TiemposAMano tiempos, {
    int? tele,
  }) =>
      _ponerTiempos(eventoId, tiempos, tele);
}

/// Por dónde escucha la central: todas las conexiones de la PC. Las pruebas
/// la ponen solo en esta PC, así Windows no pregunta por el cortafuegos.
final escuchaCentralProvider =
    Provider<InternetAddress>((ref) => InternetAddress.anyIPv4);

/// En qué puerto prueba primero. Las pruebas ponen 0: el que esté libre.
final puertoCentralProvider = Provider<int>((ref) => kPuertoCentral);

/// Las direcciones de esta PC que sirven para los celulares.
final direccionesDeEstaPcProvider =
    Provider<Future<List<String>> Function()>((ref) => direccionesDeEstaPc);

/// El código del evento, guardado en esta PC (`CodigoCentral`).
final codigoCentralProvider =
    Provider<Future<String> Function(String eventoId)>(
  (ref) => CodigoCentral.delEvento,
);

/// El código del evento si la central se usó esta noche, sin sacar uno nuevo.
final codigoVigenteCentralProvider =
    Provider<Future<String?> Function(String eventoId)>(
  (ref) => CodigoCentral.vigente,
);

final cambiarCodigoCentralProvider =
    Provider<Future<String> Function(String eventoId, String anterior)>(
  (ref) => (eventoId, anterior) =>
      CodigoCentral.cambiar(eventoId, anterior: anterior),
);

/// La carpeta con la página del celular: `puesto` al lado del programa. La
/// deja el instalador. En una tele o una tablet (24-nov-2026) viene adentro del
/// APK y la tele la copia a su carpeta al abrir (`PaginaDelCelularEnAndroid`).
final paginaDelCelularProvider = Provider<Directory?>((ref) {
  try {
    if (Platform.isAndroid) return PaginaDelCelularEnAndroid.carpeta;
    final carpeta = Directory(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}puesto',
    );
    return carpeta.existsSync() ? carpeta : null;
  } catch (_) {
    return null;
  }
});

/// Cómo está la central de la puerta en esta PC.
class EstadoCentral {
  final String? eventoId;
  final String? codigo;
  final int? puerto;

  /// De la más probable a la menos ([direccionesParaCelulares]).
  final List<String> direcciones;
  final List<PuestoConectado> puestos;

  /// Lo que salió mal al prenderla, en palabras.
  final String? error;

  /// La central es la Tele 1 (24-nov-2026).
  final bool esTele;

  /// La Tele 2: si está conectada.
  final List<TeleConectada> teles;

  const EstadoCentral({
    this.eventoId,
    this.codigo,
    this.puerto,
    this.direcciones = const [],
    this.puestos = const [],
    this.error,
    this.esTele = false,
    this.teles = const [],
  });

  /// Los celulares conectados que eligieron la tele [n] (o las dos).
  List<String> manejan(int n) => [
        for (final p in puestos)
          if (p.conectado && (p.tele == n || p.tele == kLasDosTeles)) p.nombre,
      ];

  bool get prendida => puerto != null;

  /// "192.168.0.10:8787", lo que se escribe en el navegador del celular. Null
  /// si la PC no está conectada a ningún router.
  String? get direccion => !prendida || direcciones.isEmpty
      ? null
      : '${direcciones.first}:$puerto';

  /// Lo que va en el QR: la dirección con el código adentro.
  String? get enlace {
    final d = direccion;
    return d == null ? null : 'http://$d/?c=$codigo';
  }

  int get conectados => puestos.where((p) => p.conectado).length;

  EstadoCentral _con({
    String? codigo,
    List<String>? direcciones,
    List<PuestoConectado>? puestos,
    List<TeleConectada>? teles,
  }) =>
      EstadoCentral(
        eventoId: eventoId,
        codigo: codigo ?? this.codigo,
        puerto: puerto,
        direcciones: direcciones ?? this.direcciones,
        puestos: puestos ?? this.puestos,
        error: error,
        esTele: esTele,
        teles: teles ?? this.teles,
      );
}

/// La central de la puerta de esta PC (`CentralPuerta`).
///
/// Se prende con "Sumar un celular" en Recepción ([prender]) y queda prendida
/// mientras el programa esté abierto: salir de Recepción no deja a los
/// celulares sin lista. Atiende un evento por vez; prenderla para otro apaga la
/// del anterior.
class CentralDeLaPuerta extends Notifier<EstadoCentral> {
  CentralPuerta? _central;
  ProviderSubscription<AsyncValue<PuertaDelEvento>>? _lista;
  ProviderSubscription<AsyncValue<List<Evento>>>? _evento;
  ProviderSubscription<TotemConfig>? _tiempos;
  ProviderSubscription<SalonParaLaPuerta?>? _salon;

  /// El chat de la puerta de esta PC (6.5.0): existe con la central prendida.
  ChatDelPuesto? _chat;
  ChatDelPuesto? get chat => _chat;
  StreamSubscription<List<PuestoConectado>>? _puestos;

  /// La fila de los pedidos del evento: la de la central si está prendida, y
  /// la misma para lo que se pide desde esta PC aunque esté apagada.
  ResolvedorDePedidos? _resolvedor;

  ResolvedorDePedidos _resolvedorDe(String eventoId) {
    final r = _resolvedor;
    if (r != null && r.eventoId == eventoId) return r;
    return _resolvedor = ResolvedorDePedidos(eventoId: eventoId, pc: _pc());
  }

  PuertaDeEstaPc _pc() => PuertaDeEstaPcConBase(
        ref.read(invitadosRepositoryProvider),
        ref.read(sillasPuertaRepositoryProvider),
        // Cada recepcionista controla su tele (24-nov-2026): los segundos de
        // la Tele 2 van a la Tele 2; los de la Tele 1 (o de la notebook), acá.
        // "Las dos": a las dos.
        ponerTiempos: (id, t, tele) async {
          final central = _central;
          if (central != null && central.esTele && tele != null && tele != 1) {
            if (tele == kLasDosTeles) {
              for (final otra in central.teles) {
                central.ponerTiemposDeTele(otra.numero, t);
              }
            } else {
              central.ponerTiemposDeTele(tele, t);
              return;
            }
          }
          await ref.read(tiemposAManoProvider(id).notifier).poner(t);
        },
      );

  /// Cómo se saluda a [personaId] en las teles, si entró por la central esta
  /// noche (la tele es el tótem, 24-nov-2026).
  BienvenidaDeLaNoche? bienvenidaDe(String eventoId, String personaId) {
    final r = _resolvedor;
    if (r == null || r.eventoId != eventoId) return null;
    return r.marcas.bienvenida(personaId);
  }

  /// Lo que se pide desde esta PC (sumar o quitar una silla): por la misma
  /// fila que los celulares, con la central prendida o no. [puerta] es la
  /// lista que ve Recepción.
  ///
  /// Devuelve la respuesta, como la recibe un celular.
  Future<Map<String, Object?>> resolverDeEstaPc(
    String eventoId,
    PedidoPuerta pedido, {
    required String puesto,
    required PuertaDelEvento puerta,
  }) =>
      _resolvedorDe(eventoId).resolver(pedido, puesto, conLista: puerta);

  /// Con la central prendida, la notebook no se duerme: los celulares dependen
  /// de ella aunque nadie la toque en toda la noche ([PcDespierta]).
  PcDespierta? _despierta;

  @override
  EstadoCentral build() {
    // Se arma acá: al cerrarse, Riverpod no deja leer otros providers.
    _despierta = PcDespierta(avisar: ref.read(avisarUsoAlSistemaProvider));
    ref.onDispose(() => unawaited(_soltar()));
    return const EstadoCentral();
  }

  /// La lista de la puerta fila por fila, para la Tele 2.
  ProviderSubscription<AsyncValue<List<Invitado>>>? _filas;
  StreamSubscription<List<TeleConectada>>? _teles;

  /// Para que la Tele 2 la encuentre por el wifi ([RespondeBusqueda]).
  RespondeBusqueda? _responde;

  /// La central de [eventoId]. Si ya estaba prendida para ese evento, solo
  /// vuelve a mirar las direcciones (la PC pudo haberse conectado al router
  /// recién).
  ///
  /// [comoTele]: la prende la Tele 1 (24-nov-2026). Los celulares eligen "Tu
  /// tele", la Tele 2 la encuentra por el wifi y se copia la lista.
  Future<void> prender(String eventoId, {bool comoTele = false}) async {
    if (_central != null &&
        state.eventoId == eventoId &&
        _central!.esTele == comoTele) {
      final direcciones = await ref.read(direccionesDeEstaPcProvider)();
      state = state._con(direcciones: direcciones);
      return;
    }
    await _soltar();

    final codigo = await ref.read(codigoCentralProvider)(eventoId);
    final resolvedor = _resolvedorDe(eventoId);
    final central = CentralPuerta(
      eventoId: eventoId,
      codigo: codigo,
      pc: _pc(),
      resolvedor: resolvedor,
      paginaDelCelular: ref.read(paginaDelCelularProvider),
      esTele: comoTele,
    );
    try {
      await central.arrancar(
        desde: ref.read(puertoCentralProvider),
        en: ref.read(escuchaCentralProvider),
      );
    } catch (_) {
      state = EstadoCentral(
        eventoId: eventoId,
        error: 'No se pudo abrir la central en esta PC. Cerrá el programa, '
            'volvé a abrirlo y probá de nuevo.',
      );
      return;
    }
    _central = central;
    _despierta?.mantener(true);
    // Desde el contenedor y no con `ref.listen`: Riverpod pausa lo que escucha
    // un provider cuando nadie lo mira, y la central tiene que seguir mandando
    // la lista aunque Recepción esté cerrada.
    _evento = ref.container.listen<AsyncValue<List<Evento>>>(
      eventosActivosProvider,
      (_, eventos) {
        final e = eventos.value?.where((e) => e.id == eventoId).firstOrNull;
        central.ponerTitulo(e == null ? null : etiquetaEventoRecepcion(e));
      },
      fireImmediately: true,
    );
    _lista = ref.container.listen<AsyncValue<PuertaDelEvento>>(
      puertaDelEventoProvider(eventoId),
      (_, lista) {
        final puerta = lista.value;
        if (puerta != null) central.ponerPuerta(puerta);
      },
      fireImmediately: true,
    );
    // Los segundos de la llegada de esa noche: el celular los muestra y los
    // puede cambiar.
    _tiempos = ref.container.listen<TotemConfig>(
      totemConfigDeLaNocheProvider(eventoId),
      (_, cfg) => central.ponerTiempos(TiemposAMano.de(cfg)),
      fireImmediately: true,
    );
    // El salón, para VER EN EL PLANO del celular (6.5.0): sin la foto ni el
    // fondo, que están en internet.
    _salon = ref.container.listen<SalonParaLaPuerta?>(
      salonDeLaPuertaProvider(eventoId),
      (_, salon) => central.ponerSalon(
        salon?.armado.toJson(),
        salon == null ? null : SalonParaLaPuerta.cfgParaElCelular(salon.cfg),
      ),
      fireImmediately: true,
    );
    // El chat de la puerta: la PC habla con la central sin red de por medio.
    final nombre = quienOperaEnEstaPc(ref);
    final chat = ChatDelPuesto(
      yo: kPuestoDeLaPc,
      nombre: nombre,
      enviar: central.mandarDesdeLaPc,
    );
    central
      ..nombreDeLaPc = nombre
      ..alLlegarALaPc = chat.recibir;
    chat.ponerPuestos(central.puestosDelChat);
    _chat = chat;
    _puestos = central.cambiosDePuestos.listen((puestos) {
      _chat?.ponerPuestos(central.puestosDelChat);
      if (identical(_central, central)) state = state._con(puestos: puestos);
    });
    if (comoTele) {
      // La Tele 2 copia la lista de esta: fila por fila, con cómo se saluda.
      _filas = ref.container.listen<AsyncValue<List<Invitado>>>(
        invitadosStreamProvider(eventoId),
        (_, filas) {
          final f = filas.value;
          if (f != null) central.ponerFilas(f);
        },
        fireImmediately: true,
      );
      _teles = central.cambiosDeTeles.listen((teles) {
        if (identical(_central, central)) state = state._con(teles: teles);
      });
      final responde = RespondeBusqueda(
        eventoId: eventoId,
        puertoCentral: central.puerto!,
      );
      _responde = responde;
      // Android oye la pregunta de la Tele 2 solo con el permiso del
      // multicast prendido (`RedDeLaTele`).
      await RedDeLaTele.oirLaRed(true);
      await responde.escuchar(
        puerto: kPuertoBusquedaTele,
        en: ref.read(escuchaCentralProvider),
      );
    }
    final direcciones = await ref.read(direccionesDeEstaPcProvider)();
    if (!identical(_central, central)) return;
    state = EstadoCentral(
      eventoId: eventoId,
      codigo: codigo,
      puerto: central.puerto,
      direcciones: direcciones,
      puestos: central.puestos,
      esTele: comoTele,
      teles: central.teles,
    );
  }

  /// Si la central de [eventoId] se usó esta noche y no está prendida (la
  /// notebook se reinició, o se cerró el programa), la vuelve a prender con el
  /// mismo código: los celulares se reconectan solos, sin volver a escanear.
  /// La llama Recepción al abrir el evento.
  Future<void> reanudar(String eventoId) async {
    if (_central != null) return;
    final codigo = await ref.read(codigoVigenteCentralProvider)(eventoId);
    if (codigo == null || _central != null) return;
    await prender(eventoId);
  }

  /// Otro código: los celulares conectados tienen que volver a escanear.
  Future<void> cambiarCodigo() async {
    final central = _central;
    final eventoId = state.eventoId;
    if (central == null || eventoId == null) return;
    final nuevo =
        await ref.read(cambiarCodigoCentralProvider)(eventoId, central.codigo);
    await central.cambiarCodigo(nuevo);
    if (identical(_central, central)) state = state._con(codigo: nuevo);
  }

  Future<void> apagar() async {
    await _soltar();
    state = const EstadoCentral();
  }

  /// Quién marcó a [personaId] esta noche desde un celular.
  String? quienMarco(String personaId) => _central?.marcas.quien(personaId);

  Future<void> _soltar() async {
    final central = _central;
    _central = null;
    _despierta?.mantener(false);
    _lista?.close();
    _lista = null;
    _evento?.close();
    _evento = null;
    _tiempos?.close();
    _tiempos = null;
    _salon?.close();
    _salon = null;
    _filas?.close();
    _filas = null;
    await _teles?.cancel();
    _teles = null;
    final responde = _responde;
    _responde = null;
    if (responde != null) {
      responde.cerrar();
      await RedDeLaTele.oirLaRed(false);
    }
    final chat = _chat;
    _chat = null;
    chat?.dispose();
    await _puestos?.cancel();
    _puestos = null;
    await central?.cerrar();
  }
}

final centralDeLaPuertaProvider =
    NotifierProvider<CentralDeLaPuerta, EstadoCentral>(CentralDeLaPuerta.new);
