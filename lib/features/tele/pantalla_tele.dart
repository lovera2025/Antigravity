import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/sync_engine.dart';
import '../../models/evento.dart';
import '../barra/services/pantalla_despierta.dart';
import '../common/providers/admin_provider.dart';
import '../recepcion/central/central_provider.dart';
import '../recepcion/central/pedidos_de_la_puerta.dart';
import '../recepcion/providers/recepcion_provider.dart';
import '../recepcion/providers/sin_internet_provider.dart';
import '../recepcion/services/puerta_del_evento.dart';
import '../recepcion/widgets/linea_sin_internet.dart';
import '../totem/providers/totem_config_provider.dart';
import '../totem/widgets/totem_local.dart';
import 'aparato_de_la_tele.dart';
import 'calidad_de_la_tele.dart';
import 'cliente_de_la_tele.dart';
import 'fluidez.dart';
import 'giro_de_la_tele.dart';
import 'modo_tele.dart';
import 'preparar_las_fiestas.dart';
import 'red_de_la_tele.dart';
import 'teclado_de_la_tele.dart';
import 'tele_segunda_provider.dart';

const _oro = Color(0xFFD4AF37);
const _perla = Color(0xFFE8E6F0);
const _panel = Color(0xF0141220);
const _ambar = Color(0xFFFBBF24);
const _verde = Color(0xFF4ADE80);

TextStyle _letra(double size, {Color color = _perla, bool negrita = false}) =>
    GoogleFonts.outfit(
      fontSize: size,
      color: color,
      fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
    );

/// **La pantalla de la tele** (la tele es el tótem, 24-nov-2026): el tótem de
/// la fiesta a pantalla completa y, con el OK del control, un menú chico.
///
/// - La **Tele 1** prende la central de la puerta: los celulares escanean el
///   QR del menú y marcan en la base de esta tele. La Tele 2 se le engancha.
/// - La **Tele 2** busca a la Tele 1 por el wifi y copia su lista.
/// - Cada tele **saluda solo lo de su recepcionista** ([seSaludaEnLaTele]):
///   el plano, la mesa que se enciende y la flecha del camino, como siempre.
///
/// **Desde acá no hay camino al panel ni a cobrar**: lo único que sale de la
/// tele es "Salir del modo tele", con el PIN del jefe
/// (`test/modo_tele_cerrado_test.dart`).
class PantallaTele extends ConsumerStatefulWidget {
  const PantallaTele({
    super.key,
    this.ahora = DateTime.now,
    this.conDiagnostico = false,
    this.fluida = true,
  });

  /// Lo quieto en foto y el fondo en chico ([TotemLocal.enLaTele]). Siempre
  /// prendido; solo la app de prueba lo apaga (`--dart-define=fluida=no`) para
  /// medir el antes y el después en el mismo aparato.
  final bool fluida;

  /// El reloj: las pruebas lo fijan.
  final DateTime Function() ahora;

  /// "Cómo anda" en el menú, con los números (imágenes por segundo, lo que
  /// tarda cada una, el aparato). **Solo la app de prueba**
  /// (`tool/tele_prueba.dart`): en la app de verdad no se ve ningún número
  /// (pedido del usuario, 25-nov-2026; `test/pantalla_tele_test.dart`).
  final bool conDiagnostico;

  @override
  ConsumerState<PantallaTele> createState() => _PantallaTeleState();
}

enum _Vista { menu, celulares, fiestas, girar, pin, direccion }

class _PantallaTeleState extends ConsumerState<PantallaTele> {
  final _foco = FocusNode(debugLabel: 'tele');
  final _fluidez = Fluidez();
  _Vista? _vista;
  String? _elegida;
  String? _prendidaPara;
  StreamSubscription<Set<String>>? _bajadas;
  StreamSubscription<Set<String>>? _apariencias;
  Timer? _relectura;
  Timer? _ayuda;
  bool _mostrarAyuda = true;

  /// Quién la maneja, para avisarlo un rato cuando cambia.
  List<String> _manejanAntes = const [];
  Timer? _borrarManejan;
  bool _mostrarManejan = false;

  /// De cuánto va el fondo: arranca a la mitad y, si la tele no llega, baja
  /// sola (`AjusteDeLaTele`), callada.
  final _ajuste = AjusteDeLaTele();
  Timer? _mirarFluidez;
  bool _hayTotem = false;

  /// Solo con [PantallaTele.conDiagnostico].
  AparatoDeLaTele? _aparato;

  /// Las medidas del último minuto, con su hora.
  final _ultimas = <(DateTime, MedidaDeFluidez)>[];

  /// La peor del último minuto (en la app de prueba: hacer entrar a alguien,
  /// abrir el menú y mirar esto).
  MedidaDeFluidez? get _peor => _ultimas.isEmpty
      ? null
      : _ultimas
          .map((x) => x.$2)
          .reduce((a, b) => a.porSegundo <= b.porSegundo ? a : b);

  /// Las imágenes por segundo de la pantalla.
  double get _hz {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return hz.isFinite && hz >= 20 ? hz : 60;
  }

  /// Cuándo arrancó: los primeros segundos (preparar las fotos, girar la
  /// pantalla) no cuentan para decidir.
  final _arranco = DateTime.now();
  static const _sinMirarAlArrancar = Duration(seconds: 15);

  void _mirar() {
    if (!mounted || !_hayTotem || _vista != null) return;
    _fluidez.tope = _hz;
    final m = _fluidez.medida;
    // Lo de cada 5 s del último minuto: lo peor es lo de la última bienvenida.
    if (m != null) {
      final ahora = DateTime.now();
      _ultimas
        ..add((ahora, m))
        ..removeWhere((x) => ahora.difference(x.$1) > const Duration(minutes: 1));
    }
    // En la app de prueba, cada medida al registro (`adb logcat -s flutter`).
    if (widget.conDiagnostico) {
      debugPrint('fluidez: ${Fluidez.detalle(m)} · '
          '${widget.fluida ? _ajuste.fondo.nombre : 'como antes'}');
    }
    if (!widget.fluida) return;
    if (DateTime.now().difference(_arranco) < _sinMirarAlArrancar) return;
    if (_ajuste.mirar(m, hz: _hz)) {
      setState(() {});
      unawaited(AjusteDeLaTele.guardar(_ajuste.fondo));
      _fluidez.olvidar();
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(PantallaDespierta.mantener(true));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    _fluidez.arrancar();
    unawaited(AjusteDeLaTele.leer().then((f) {
      if (mounted && f != _ajuste.fondo) setState(() => _ajuste.fondo = f);
    }));
    _mirarFluidez = Timer.periodic(const Duration(seconds: 5), (_) => _mirar());
    if (widget.conDiagnostico) {
      unawaited(AparatoDeLaTele.leer().then((a) {
        if (mounted) setState(() => _aparato = a);
      }));
    }
    unawaited(ModoTeleGuardado.fiestaElegida().then((id) {
      if (mounted && id != null) setState(() => _elegida = id);
    }));
    // Lo que se bajó en la oficina con internet: una fiesta nueva aparece sola.
    _bajadas = ref.read(syncEngineProvider).cambiosBajadosStream.listen((t) {
      if (t.contains('eventos')) ref.invalidate(eventosActivosProvider);
    });
    // Lo que se guardó en Personalizar, en otra PC: la tele lo vuelve a leer
    // al momento (25-nov-2026).
    _apariencias = ref.read(syncEngineProvider).aparienciasCambiadasStream.listen((ids) {
      for (final id in ids) {
        ref.invalidate(totemConfigProvider(id));
      }
    });
    _relectura = Timer.periodic(const Duration(minutes: 10), (_) {
      ref.invalidate(eventosActivosProvider);
    });
    _ayuda = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _mostrarAyuda = false);
    });
  }

  @override
  void dispose() {
    unawaited(PantallaDespierta.mantener(false));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _fluidez.dispose();
    _mirarFluidez?.cancel();
    unawaited(_bajadas?.cancel());
    unawaited(_apariencias?.cancel());
    _relectura?.cancel();
    _ayuda?.cancel();
    _borrarManejan?.cancel();
    _foco.dispose();
    super.dispose();
  }

  /// Prende la central (Tele 1) o se engancha a la Tele 1 (Tele 2) para la
  /// fiesta de esta noche, una vez por fiesta y papel.
  void _asegurar(String eventoId, ModoTele modo) {
    final clave = '$eventoId|${modo.papel.name}|${modo.direccionAMano}';
    if (_prendidaPara == clave) return;
    _prendidaPara = clave;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (modo.papel == PapelDeLaTele.principal) {
        ref.read(teleSegundaProvider.notifier).soltar();
        await PaginaDelCelularEnAndroid.preparar();
        if (!mounted) return;
        ref.invalidate(paginaDelCelularProvider);
        await ref
            .read(centralDeLaPuertaProvider.notifier)
            .prender(eventoId, comoTele: true);
      } else {
        final central = ref.read(centralDeLaPuertaProvider);
        if (central.prendida) {
          await ref.read(centralDeLaPuertaProvider.notifier).apagar();
        }
        if (!mounted) return;
        ref
            .read(teleSegundaProvider.notifier)
            .conectar(eventoId, direccionAMano: modo.direccionAMano);
      }
    });
  }

  bool _seSaluda(String eventoId, ModoTele modo, String personaId) {
    final ahora = widget.ahora();
    final b = modo.papel == PapelDeLaTele.principal
        ? ref.read(centralDeLaPuertaProvider.notifier).bienvenidaDe(eventoId, personaId)
        : ref.read(teleSegundaProvider.notifier).bienvenida(personaId);
    return seSaludaEnLaTele(b, miTele: modo.numero, ahora: ahora);
  }

  // ── El control de la tele ─────────────────────────────────────────────────

  static final _abren = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonSelect,
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.mediaPlayPause,
  };

  static final _vuelven = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
  };

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // Atrás del control (o Esc del teclado): cierra lo abierto, o abre el menú.
    if (_vuelven.contains(e.logicalKey)) {
      _atras();
      return KeyEventResult.handled;
    }
    if (_vista != null) return KeyEventResult.ignored;
    if (_abren.contains(e.logicalKey)) {
      _abrir(_Vista.menu);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _abrir(_Vista? v) {
    setState(() => _vista = v);
    if (v == null) _foco.requestFocus();
  }

  /// Atrás: cierra lo abierto, o abre el menú. La app no se cierra con el
  /// control: el tótem tiene que quedar.
  void _atras() {
    switch (_vista) {
      case null:
        _abrir(_Vista.menu);
      case _Vista.menu:
        _abrir(null);
      case _Vista.pin:
        _soltarPin(false);
        _abrir(_Vista.menu);
      case _Vista.celulares:
      case _Vista.fiestas:
      case _Vista.girar:
      case _Vista.direccion:
        _abrir(_Vista.menu);
    }
  }

  // ── La pantalla ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final modo = ref.watch(modoTeleProvider);
    if (modo == null) return const SizedBox.shrink();
    // Todas las fiestas que vienen, listas sin internet (25-nov-2026).
    ref.watch(prepararLasFiestasProvider);
    final eventos = ref.watch(eventosActivosProvider);
    final fiesta = FiestaDeLaTele.de(
      eventos.value ?? const [],
      widget.ahora(),
      elegida: _elegida,
    );
    final evento = fiesta.fiesta;
    _hayTotem = evento != null;
    if (evento != null) _asegurar(evento.id, modo);
    if (fiesta.hayQueElegir && _vista == null && eventos.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vista == null) _abrir(_Vista.fiestas);
      });
    }

    final central = ref.watch(centralDeLaPuertaProvider);
    final segunda = ref.watch(teleSegundaProvider);
    final manejan = modo.papel == PapelDeLaTele.principal
        ? central.manejan(1)
        : (segunda?.manejan ?? const <String>[]);
    _avisarSiCambianLosQueManejan(manejan);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _atras(),
      child: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _tecla,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Con el mouse o el dedo (la tablet, la ventana de prueba).
            onTap: _vista == null ? () => _abrir(_Vista.menu) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (evento == null)
                  _sinFiesta(eventos.isLoading && !eventos.hasValue, fiesta)
                else
                  TotemLocal(
                    key: ValueKey('tele-${evento.id}-${modo.papel.name}'),
                    eventoId: evento.id,
                    seSaluda: (id) => _seSaluda(evento.id, modo, id),
                    fondoQuieto:
                        modo.fondoQuieto || _ajuste.fondo == FondoDeLaTele.quieto,
                    // Lo quieto en foto y el fondo en chico: se ve igual y la
                    // placa de la tele llega (25-nov-2026).
                    enLaTele: widget.fluida,
                    escalaDelFondo: widget.fluida ? _ajuste.fondo.escala : 1,
                    ensayar: widget.fluida,
                  ),
                if (evento != null) _Vigia(eventoId: evento.id),
                Positioned(
                  left: 24,
                  bottom: 18,
                  child: _estadoAbajo(modo, central, segunda),
                ),
                if (_mostrarManejan && manejan.isNotEmpty && _vista == null)
                  Positioned(
                    top: 18,
                    right: 24,
                    child: _Pastilla(
                      texto: '${modo.papel.nombre} · la maneja ${manejan.join(', ')}',
                      color: _verde,
                    ),
                  ),
                if (_vista != null)
                  Positioned.fill(
                    child: Stack(
                      children: [
                        // Tocar afuera del menú lo cierra (con el mouse o el dedo).
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _abrir(null),
                            child: const ColoredBox(color: Colors.black54),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _panelDe(_vista!, modo, evento, fiesta, central, segunda, manejan),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _avisarSiCambianLosQueManejan(List<String> manejan) {
    final iguales = manejan.length == _manejanAntes.length &&
        manejan.every(_manejanAntes.contains);
    if (iguales) return;
    _manejanAntes = List.of(manejan);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _mostrarManejan = true);
      _borrarManejan?.cancel();
      _borrarManejan = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _mostrarManejan = false);
      });
    });
  }

  Widget _sinFiesta(bool cargando, FiestaDeLaTele fiesta) => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_rounded, color: _oro, size: 56),
              const SizedBox(height: 16),
              Text(
                cargando
                    ? 'Abriendo…'
                    : fiesta.hayQueElegir
                        ? 'Esta noche hay más de una fiesta: elegí cuál con el control.'
                        : 'No hay ninguna fiesta que venga en esta tele.',
                textAlign: TextAlign.center,
                style: _letra(26, negrita: true),
              ),
              if (!cargando && fiesta.ninguna) ...[
                const SizedBox(height: 10),
                Text(
                  'Con internet, en la oficina, las fiestas se bajan solas.',
                  textAlign: TextAlign.center,
                  style: _letra(18, color: Colors.white60),
                ),
              ],
            ],
          ),
        ),
      );

  /// Abajo a la izquierda, chico: solo lo que necesita atención (la ayuda del
  /// principio, la Tele 2 sin la Tele 1, la central que no abrió).
  Widget _estadoAbajo(ModoTele modo, EstadoCentral central, ClienteDeLaTele? segunda) {
    String? texto;
    var color = _ambar;
    if (modo.papel == PapelDeLaTele.segunda && segunda != null) {
      texto = switch (segunda.estado) {
        EstadoDeLaSegunda.buscando => 'Tele 2 · buscando la Tele 1 en el wifi…',
        EstadoDeLaSegunda.conectando => 'Tele 2 · conectando con la Tele 1…',
        EstadoDeLaSegunda.cortada =>
          'Tele 2 · sin la Tele 1: sigue con la lista que tenía',
        EstadoDeLaSegunda.otraFiesta => 'Tele 2 · la Tele 1 tiene otra fiesta',
        EstadoDeLaSegunda.conectada => null,
      };
    } else if (central.error != null) {
      texto = central.error;
    }
    if (texto == null && _mostrarAyuda && _vista == null) {
      texto = '${modo.papel.nombre} · apretá OK en el control para el menú';
      color = Colors.white70;
    }
    if (texto == null) return const SizedBox.shrink();
    return _Pastilla(texto: texto, color: color);
  }

  // ── Los paneles ───────────────────────────────────────────────────────────

  Widget _panelDe(
    _Vista vista,
    ModoTele modo,
    Evento? evento,
    FiestaDeLaTele fiesta,
    EstadoCentral central,
    ClienteDeLaTele? segunda,
    List<String> manejan,
  ) {
    final Widget hijo = switch (vista) {
      _Vista.menu => _menu(modo, evento, central, segunda, manejan),
      _Vista.celulares => _celulares(modo, central, segunda),
      _Vista.fiestas => _fiestas(fiesta, evento),
      _Vista.girar => _girar(),
      _Vista.pin => _pin(),
      _Vista.direccion => _direccion(modo),
    };
    // Con la tele parada (540 de ancho) el panel entra entero.
    final ancho = MediaQuery.sizeOf(context).width;
    final angosta = ancho < 640;
    return Container(
      width: math.min(560, ancho - (angosta ? 24 : 48)),
      margin: EdgeInsets.all(angosta ? 12 : 24),
      padding: angosta
          ? const EdgeInsets.fromLTRB(20, 20, 20, 16)
          : const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _oro.withValues(alpha: 0.35)),
      ),
      child: FocusScope(
        autofocus: true,
        child: SingleChildScrollView(child: hijo),
      ),
    );
  }

  Widget _menu(
    ModoTele modo,
    Evento? evento,
    EstadoCentral central,
    ClienteDeLaTele? segunda,
    List<String> manejan,
  ) {
    final principal = modo.papel == PapelDeLaTele.principal;
    final quieto = modo.fondoQuieto || _ajuste.fondo == FondoDeLaTele.quieto;
    final otra = principal
        ? (central.teles.any((t) => t.conectada)
            ? 'La Tele 2 está conectada'
            : 'La Tele 2 no está conectada')
        : switch (segunda?.estado) {
            EstadoDeLaSegunda.conectada =>
              'Conectada a la Tele 1 (${segunda!.donde?.texto ?? ''})',
            EstadoDeLaSegunda.buscando || null => 'Buscando la Tele 1…',
            EstadoDeLaSegunda.conectando => 'Conectando con la Tele 1…',
            EstadoDeLaSegunda.cortada => 'Sin la Tele 1: sigue con la lista que tenía',
            EstadoDeLaSegunda.otraFiesta => 'La Tele 1 tiene otra fiesta',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(modo.papel.nombre.toUpperCase(), style: _letra(28, color: _oro, negrita: true)),
        const SizedBox(height: 4),
        Text(
          evento == null ? 'Sin fiesta' : etiquetaEventoRecepcion(evento),
          style: _letra(17, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        Text(
          manejan.isEmpty ? 'Ningún celular la maneja todavía' : 'La maneja: ${manejan.join(', ')}',
          style: _letra(16, color: manejan.isEmpty ? Colors.white54 : _verde),
        ),
        Text(otra, style: _letra(16, color: Colors.white54)),
        const SizedBox(height: 18),
        _Opcion(
          key: const ValueKey('tele_sumar_celular'),
          icono: Icons.qr_code_2_rounded,
          texto: 'Sumar un celular',
          autofocus: true,
          alElegir: evento == null ? null : () => _abrir(_Vista.celulares),
        ),
        _Opcion(
          key: const ValueKey('tele_fiesta'),
          icono: Icons.celebration_outlined,
          texto: 'La fiesta',
          alElegir: () => _abrir(_Vista.fiestas),
        ),
        _Opcion(
          key: const ValueKey('tele_girar'),
          icono: Icons.screen_rotation_rounded,
          texto: 'Girar la pantalla · ${Giro.nombre(ref.watch(giroDeLaTeleProvider))}',
          alElegir: () => _abrir(_Vista.girar),
        ),
        _Opcion(
          key: const ValueKey('tele_fondo'),
          icono: quieto ? Icons.pause_circle_outline : Icons.play_circle_outline,
          texto: quieto ? 'Fondo quieto · tocá para animarlo' : 'Fondo animado · tocá para dejarlo quieto',
          alElegir: () {
            if (quieto && _ajuste.fondo == FondoDeLaTele.quieto) {
              // Lo había dejado quieto la tele sola: lo animado, en chico.
              setState(() => _ajuste.fondo = FondoDeLaTele.tercio);
              unawaited(AjusteDeLaTele.guardar(_ajuste.fondo));
            }
            ref.read(modoTeleProvider.notifier).poner(modo.con(fondoQuieto: !quieto));
          },
        ),
        if (!principal) ...[
          _Opcion(
            key: const ValueKey('tele_direccion'),
            icono: Icons.edit_outlined,
            texto: modo.direccionAMano == null
                ? 'Escribir la dirección de la Tele 1'
                : 'Tele 1 en ${modo.direccionAMano} · cambiar',
            alElegir: () => _abrir(_Vista.direccion),
          ),
          _Opcion(
            key: const ValueKey('tele_pasar_a_principal'),
            icono: Icons.swap_horiz_rounded,
            texto: 'Pasar a principal (si la Tele 1 se apagó)',
            alElegir: () => _pasarAPrincipal(modo),
          ),
        ],
        // Los números, solo en la app de prueba.
        if (widget.conDiagnostico) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            key: const ValueKey('tele_como_anda'),
            listenable: _fluidez,
            builder: (context, _) {
              final pantalla = MediaQuery.sizeOf(context) *
                  MediaQuery.devicePixelRatioOf(context);
              final peor = _peor;
              return Text(
                'Cómo anda: ${Fluidez.detalle(_fluidez.medida)}\n'
                '${peor == null ? '' : 'Lo peor del último minuto: ${Fluidez.detalle(peor)}\n'}'
                '${pantalla.width.round()}×${pantalla.height.round()} · '
                '${_hz.round()} Hz · ${_ajuste.fondo.nombre}'
                '${_aparato == null || _aparato!.texto.isEmpty ? '' : ' · ${_aparato!.texto}'}',
                style: _letra(15, color: Colors.white54),
              );
            },
          ),
        ],
        if (evento != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _LineaDeLaFiesta(eventoId: evento.id),
          ),
        const SizedBox(height: 10),
        _Opcion(
          key: const ValueKey('tele_salir'),
          icono: Icons.logout_rounded,
          texto: 'Salir del modo tele (PIN del jefe)',
          alElegir: _salirDelModoTele,
        ),
        _Opcion(
          key: const ValueKey('tele_cerrar'),
          icono: Icons.close_rounded,
          texto: 'Volver al tótem',
          alElegir: () => _abrir(null),
        ),
      ],
    );
  }

  Widget _celulares(ModoTele modo, EstadoCentral central, ClienteDeLaTele? segunda) {
    final principal = modo.papel == PapelDeLaTele.principal;
    final enlace = principal
        ? (central.enlace == null ? null : '${central.enlace}&t=1')
        : segunda?.enlaceParaCelulares;
    final direccion = principal ? central.direccion : segunda?.donde?.texto;
    final codigo = principal ? central.codigo : segunda?.codigo;
    final sinPagina = principal && ref.read(paginaDelCelularProvider) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SUMAR UN CELULAR', style: _letra(26, color: _oro, negrita: true)),
        const SizedBox(height: 6),
        Text(
          'Escaneá con la cámara del celular (iPhone o Android). Se abre la '
          'recepción de la ${modo.papel.nombre}, sin internet.',
          style: _letra(16, color: Colors.white70),
        ),
        const SizedBox(height: 16),
        if (enlace == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text(
              principal
                  ? (central.error ??
                      (central.prendida
                          ? 'Esta tele no está en ningún wifi: conectala al router.'
                          : 'Abriendo la central…'))
                  : 'Primero la Tele 2 tiene que encontrar a la Tele 1.',
              textAlign: TextAlign.center,
              style: _letra(18, color: _ambar),
            ),
          )
        else
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                key: const ValueKey('tele_qr'),
                data: enlace,
                version: QrVersions.auto,
                size: 260,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        if (direccion != null && codigo != null) ...[
          const SizedBox(height: 14),
          Text(
            'O en el navegador: $direccion · código $codigo',
            textAlign: TextAlign.center,
            style: _letra(17),
          ),
        ],
        if (sinPagina) ...[
          const SizedBox(height: 10),
          Text(
            'A esta app le falta la página del celular: el celular no va a '
            'abrir. Hay que instalar de nuevo la app.',
            textAlign: TextAlign.center,
            style: _letra(15, color: _ambar),
          ),
        ],
        const SizedBox(height: 16),
        _Opcion(
          key: const ValueKey('tele_qr_volver'),
          icono: Icons.arrow_back_rounded,
          texto: 'Volver',
          autofocus: true,
          alElegir: () => _abrir(_Vista.menu),
        ),
      ],
    );
  }

  Widget _fiestas(FiestaDeLaTele fiesta, Evento? evento) {
    final lista = fiesta.todas;
    final preparar = ref.watch(prepararLasFiestasProvider);
    return ListenableBuilder(
      listenable: preparar,
      builder: (context, _) => _listaDeFiestas(lista, evento, preparar.como),
    );
  }

  Widget _listaDeFiestas(
    List<Evento> lista,
    Evento? evento,
    Map<String, ComoQuedoLaFiesta> como,
  ) {
    final ahora = widget.ahora();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('LA FIESTA', style: _letra(26, color: _oro, negrita: true)),
        const SizedBox(height: 6),
        Text(
          lista.isEmpty
              ? 'No hay ninguna fiesta que venga en esta tele.'
              : 'La que muestra esta tele. Con dos teles, las dos van con la misma.',
          style: _letra(16, color: Colors.white70),
        ),
        const SizedBox(height: 14),
        for (final (i, e) in lista.indexed)
          _Opcion(
            key: ValueKey('tele_fiesta_${e.id}'),
            icono: e.id == evento?.id ? Icons.check_circle_rounded : Icons.circle_outlined,
            texto: etiquetaEventoRecepcion(e),
            // Cómo quedó para trabajar sin internet.
            detalle: como[e.id]?.texto(ahora),
            detalleBien: como[e.id]?.completa ?? false,
            autofocus: e.id == evento?.id || (evento == null && i == 0),
            alElegir: () async {
              await ModoTeleGuardado.elegirFiesta(e.id);
              if (!mounted) return;
              setState(() => _elegida = e.id);
              _abrir(null);
            },
          ),
        const SizedBox(height: 8),
        _Opcion(
          key: const ValueKey('tele_fiestas_volver'),
          icono: Icons.arrow_back_rounded,
          texto: 'Volver',
          autofocus: lista.isEmpty,
          alElegir: () => _abrir(_Vista.menu),
        ),
      ],
    );
  }

  // ── Lo que pide el PIN ────────────────────────────────────────────────────

  /// El PIN que se está pidiendo: para qué, y quién espera la respuesta.
  Completer<bool>? _esperaPin;
  String _paraQuePin = '';
  String? _errorDelPin;

  /// El PIN del jefe, **con el teclado de la tele** (el de Google TV no gira:
  /// con la tele parada salía acostado). Contesta true solo con el PIN bien;
  /// Atrás o CANCELAR, false.
  Future<bool> _pinDelJefe(String para) {
    _soltarPin(false);
    final espera = _esperaPin = Completer<bool>();
    setState(() {
      _paraQuePin = para;
      _errorDelPin = null;
    });
    _abrir(_Vista.pin);
    return espera.future;
  }

  void _soltarPin(bool bien) {
    final espera = _esperaPin;
    _esperaPin = null;
    if (espera != null && !espera.isCompleted) espera.complete(bien);
  }

  Future<void> _probarPin(String pin) async {
    if (pin.isEmpty) return;
    final bien = await ref.read(adminAuthProvider.notifier).esPinMaestro(pin);
    if (!mounted) return;
    if (!bien) {
      setState(() => _errorDelPin = 'Ese no es el PIN del jefe.');
      return;
    }
    _abrir(_Vista.menu);
    _soltarPin(true);
  }

  Widget _pin() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_paraQuePin.toUpperCase(), style: _letra(24, color: _oro, negrita: true)),
          const SizedBox(height: 6),
          Text('PIN del jefe', style: _letra(16, color: Colors.white70)),
          const SizedBox(height: 12),
          TecladoDeLaTele(
            key: ValueKey('tele_pin_$_paraQuePin'),
            oculto: true,
            error: _errorDelPin,
            alEscribir: () {
              if (_errorDelPin != null) setState(() => _errorDelPin = null);
            },
            alListo: _probarPin,
            alCancelar: () {
              _soltarPin(false);
              _abrir(_Vista.menu);
            },
          ),
        ],
      );

  // ── Girar ─────────────────────────────────────────────────────────────────

  /// Horizontal · Vertical · Dar vuelta, **sin PIN**: cada tele recuerda la
  /// suya ([GiroGuardado]).
  Widget _girar() {
    final giro = ref.watch(giroDeLaTeleProvider);
    final parada = Giro.esParada(giro);
    void poner(int cuartos) =>
        unawaited(ref.read(giroDeLaTeleProvider.notifier).poner(cuartos));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('GIRAR LA PANTALLA', style: _letra(26, color: _oro, negrita: true)),
        const SizedBox(height: 6),
        Text(
          'Vertical: para la tele colgada parada. Si se ve cabeza abajo, '
          '"Dar vuelta". Cada tele recuerda la suya.',
          style: _letra(16, color: Colors.white70),
        ),
        const SizedBox(height: 14),
        _Opcion(
          key: const ValueKey('tele_giro_horizontal'),
          icono: parada ? Icons.circle_outlined : Icons.check_circle_rounded,
          texto: 'Horizontal',
          autofocus: !parada,
          alElegir: () => poner(Giro.horizontal(giro)),
        ),
        _Opcion(
          key: const ValueKey('tele_giro_vertical'),
          icono: parada ? Icons.check_circle_rounded : Icons.circle_outlined,
          texto: 'Vertical',
          autofocus: parada,
          alElegir: () => poner(Giro.vertical(giro)),
        ),
        _Opcion(
          key: const ValueKey('tele_giro_dar_vuelta'),
          icono: Icons.flip_camera_android_rounded,
          texto: 'Dar vuelta (se ve cabeza abajo)',
          alElegir: () => poner(Giro.darVuelta(giro)),
        ),
        const SizedBox(height: 8),
        _Opcion(
          key: const ValueKey('tele_girar_volver'),
          icono: Icons.arrow_back_rounded,
          texto: 'Volver',
          alElegir: () => _abrir(_Vista.menu),
        ),
      ],
    );
  }

  Future<void> _salirDelModoTele() async {
    if (!await _pinDelJefe('Salir del modo tele')) return;
    ref.read(teleSegundaProvider.notifier).soltar();
    await ref.read(centralDeLaPuertaProvider.notifier).apagar();
    await ref.read(modoTeleProvider.notifier).poner(null);
  }

  Future<void> _pasarAPrincipal(ModoTele modo) async {
    if (!await _pinDelJefe('Pasar a principal')) return;
    await ref.read(teleSegundaProvider.notifier).soltarParaSerPrincipal();
    await ref
        .read(modoTeleProvider.notifier)
        .poner(ModoTele(PapelDeLaTele.principal, fondoQuieto: modo.fondoQuieto));
    if (mounted) _abrir(_Vista.celulares);
  }

  /// La dirección de la Tele 1, **con el teclado de la tele** (el de Google TV
  /// no gira). Vacía: la busca sola.
  Widget _direccion(ModoTele modo) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('LA DIRECCIÓN DE LA TELE 1', style: _letra(24, color: _oro, negrita: true)),
          const SizedBox(height: 6),
          Text(
            'La que muestra la Tele 1 en "Sumar un celular", por ejemplo '
            '192.168.0.10:8787. Vacía: la busca sola.',
            style: _letra(16, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          TecladoDeLaTele(
            key: const ValueKey('tele_teclado_direccion'),
            inicial: modo.direccionAMano ?? '',
            conPuntos: true,
            alListo: (t) async {
              final texto = t.trim();
              _abrir(_Vista.menu);
              await ref.read(modoTeleProvider.notifier).poner(
                  texto.isEmpty ? modo.con(sinDireccion: true) : modo.con(direccionAMano: texto));
            },
            alCancelar: () => _abrir(_Vista.menu),
          ),
        ],
      );
}

/// "Lista para trabajar sin internet" de la fiesta: la misma línea de
/// Recepción, con lo de esta tele.
class _LineaDeLaFiesta extends ConsumerWidget {
  const _LineaDeLaFiesta({required this.eventoId});
  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puerta = ref.watch(puertaDelEventoProvider(eventoId)).value;
    return Theme(
      data: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      child: LineaSinInternet(
        eventoId: eventoId,
        personas: puerta?.total ?? 0,
        adentro: puerta?.adentro ?? 0,
      ),
    );
  }
}

/// Mantiene viva la puesta al día de la fiesta (la lista, los alumnos y la foto
/// se bajan solos con internet) mientras la tele la muestra.
class _Vigia extends ConsumerWidget {
  const _Vigia({required this.eventoId});
  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(puestaAlDiaProvider(eventoId));
    return const SizedBox.shrink();
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.texto, required this.color});
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(texto, style: _letra(15, color: color)),
      );
}

/// Una opción del menú: grande, y con un borde dorado cuando el control la
/// tiene elegida.
class _Opcion extends StatelessWidget {
  const _Opcion({
    super.key,
    required this.icono,
    required this.texto,
    required this.alElegir,
    this.autofocus = false,
    this.detalle,
    this.detalleBien = false,
  });

  final IconData icono;
  final String texto;
  final VoidCallback? alElegir;
  final bool autofocus;

  /// Una segunda línea, más chica (cómo quedó la fiesta sin internet).
  final String? detalle;
  final bool detalleBien;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextButton(
          autofocus: autofocus,
          onPressed: alElegir,
          style: ButtonStyle(
            alignment: Alignment.centerLeft,
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            shape: WidgetStateProperty.resolveWith(
              (s) => RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: s.contains(WidgetState.focused)
                    ? const BorderSide(color: _oro, width: 3)
                    : BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? _oro.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? Colors.white38 : _perla,
            ),
          ),
          child: Row(
            children: [
              Icon(icono, size: 26),
              const SizedBox(width: 14),
              // Sin color propio: el del botón (apagado si no se puede).
              Expanded(
                child: detalle == null
                    ? Text(texto, style: GoogleFonts.outfit(fontSize: 19))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(texto, style: GoogleFonts.outfit(fontSize: 19)),
                          Text(
                            detalle!,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: detalleBien ? _verde : _ambar,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
}
