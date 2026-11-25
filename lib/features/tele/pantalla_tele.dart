import 'dart:async';

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
import '../totem/widgets/totem_local.dart';
import 'cliente_de_la_tele.dart';
import 'fluidez.dart';
import 'modo_tele.dart';
import 'red_de_la_tele.dart';
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
  const PantallaTele({super.key, this.ahora = DateTime.now});

  /// El reloj: las pruebas lo fijan.
  final DateTime Function() ahora;

  @override
  ConsumerState<PantallaTele> createState() => _PantallaTeleState();
}

enum _Vista { menu, celulares, fiestas }

class _PantallaTeleState extends ConsumerState<PantallaTele> {
  final _foco = FocusNode(debugLabel: 'tele');
  final _fluidez = Fluidez();
  _Vista? _vista;
  String? _elegida;
  String? _prendidaPara;
  StreamSubscription<Set<String>>? _bajadas;
  Timer? _relectura;
  Timer? _ayuda;
  bool _mostrarAyuda = true;

  /// Quién la maneja, para avisarlo un rato cuando cambia.
  List<String> _manejanAntes = const [];
  Timer? _borrarManejan;
  bool _mostrarManejan = false;

  @override
  void initState() {
    super.initState();
    unawaited(PantallaDespierta.mantener(true));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    _fluidez.arrancar();
    unawaited(ModoTeleGuardado.fiestaElegida().then((id) {
      if (mounted && id != null) setState(() => _elegida = id);
    }));
    // Lo que se bajó en la oficina con internet: una fiesta nueva aparece sola.
    _bajadas = ref.read(syncEngineProvider).cambiosBajadosStream.listen((t) {
      if (t.contains('eventos')) ref.invalidate(eventosActivosProvider);
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
    unawaited(_bajadas?.cancel());
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
      case _Vista.celulares:
      case _Vista.fiestas:
        _abrir(_Vista.menu);
    }
  }

  // ── La pantalla ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final modo = ref.watch(modoTeleProvider);
    if (modo == null) return const SizedBox.shrink();
    final eventos = ref.watch(eventosActivosProvider);
    final fiesta = FiestaDeLaTele.de(
      eventos.value ?? const [],
      widget.ahora(),
      elegida: _elegida,
    );
    final evento = fiesta.fiesta;
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
                    fondoQuieto: modo.fondoQuieto,
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
    };
    return Container(
      width: 560,
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
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
          key: const ValueKey('tele_fondo'),
          icono: modo.fondoQuieto ? Icons.pause_circle_outline : Icons.play_circle_outline,
          texto: modo.fondoQuieto ? 'Fondo quieto · tocá para animarlo' : 'Fondo animado · tocá para dejarlo quieto',
          alElegir: () => ref
              .read(modoTeleProvider.notifier)
              .poner(modo.con(fondoQuieto: !modo.fondoQuieto)),
        ),
        if (!principal) ...[
          _Opcion(
            key: const ValueKey('tele_direccion'),
            icono: Icons.edit_outlined,
            texto: modo.direccionAMano == null
                ? 'Escribir la dirección de la Tele 1'
                : 'Tele 1 en ${modo.direccionAMano} · cambiar',
            alElegir: () => _escribirDireccion(modo),
          ),
          _Opcion(
            key: const ValueKey('tele_pasar_a_principal'),
            icono: Icons.swap_horiz_rounded,
            texto: 'Pasar a principal (si la Tele 1 se apagó)',
            alElegir: () => _pasarAPrincipal(modo),
          ),
        ],
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: _fluidez,
          builder: (context, _) => Text(
            'Cómo anda: ${Fluidez.texto(_fluidez.porSegundo)}',
            style: _letra(15, color: Colors.white54),
          ),
        ),
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

  Future<bool> _pinDelJefe(String para) async {
    final controlador = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1A2A),
        title: Text(para, style: _letra(20, negrita: true)),
        content: TextField(
          controller: controlador,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: _letra(22),
          decoration: const InputDecoration(labelText: 'PIN del jefe'),
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('LISTO'),
          ),
        ],
      ),
    );
    final pin = controlador.text.trim();
    controlador.dispose();
    if (ok != true || pin.isEmpty) return false;
    final bien = await ref.read(adminAuthProvider.notifier).esPinMaestro(pin);
    if (!bien && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese no es el PIN del jefe.')),
      );
    }
    return bien;
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

  Future<void> _escribirDireccion(ModoTele modo) async {
    final controlador = TextEditingController(text: modo.direccionAMano ?? '');
    final texto = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1A2A),
        title: Text('La dirección de la Tele 1', style: _letra(20, negrita: true)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La que muestra la Tele 1 en "Sumar un celular", por ejemplo '
              '192.168.0.10:8787. Vacía: la busca sola.',
              style: _letra(15, color: Colors.white70),
            ),
            TextField(
              controller: controlador,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: _letra(22),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controlador.text),
            child: const Text('LISTO'),
          ),
        ],
      ),
    );
    controlador.dispose();
    if (texto == null) return;
    final t = texto.trim();
    await ref
        .read(modoTeleProvider.notifier)
        .poner(t.isEmpty ? modo.con(sinDireccion: true) : modo.con(direccionAMano: t));
  }
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
  });

  final IconData icono;
  final String texto;
  final VoidCallback? alElegir;
  final bool autofocus;

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
              Expanded(child: Text(texto, style: GoogleFonts.outfit(fontSize: 19))),
            ],
          ),
        ),
      );
}
