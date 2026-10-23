import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/kiosk_launcher.dart';
import '../../../main.dart' show kWebBaseUrl;
import '../../../models/invitado.dart';
import '../../../models/totem_config.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../recepcion/providers/recepcion_provider.dart'
    show eventosActivosProvider;
import '../estilos/escena_totem.dart';
import '../estilos/fuentes_totem.dart';
import '../estilos/totem_estilo.dart';
import '../estilos/tu_fondo.dart';
import '../providers/clave_totem_provider.dart';
import '../providers/totem_config_provider.dart';
import '../repositories/totem_config_repository.dart';
import '../services/bienvenidas_totem.dart';
import '../services/contenido_bienvenida.dart';
import '../services/ficha_totem.dart';
import '../services/foto_guardada.dart';
import '../services/lectura_del_fondo.dart';
import '../totem_orientation.dart';
import 'link_totem_navegador.dart';

const _gold = TotemConfig.acentoPorDefecto;
const _colorDelPanel = Color(0xFF141414);

/// Paleta curada.
///
/// Se eligieron a mano en vez de sumar un color picker: el acento no se mira en
/// un monitor sino **proyectado** en un salón, y los fondos del tótem derivan
/// del tono elegido. Una rueda libre deja pasar combinaciones que quedan
/// ilegibles a cinco metros. Para el color exacto de una marca está el campo de
/// hex.
const List<({String nombre, Color color})> _paleta = [
  (nombre: 'Dorado', color: _gold),
  (nombre: 'Perla', color: Color(0xFFE8E3D3)),
  (nombre: 'Rosa', color: Color(0xFFFF8FB1)),
  (nombre: 'Fucsia', color: Color(0xFFE0218A)),
  (nombre: 'Violeta', color: Color(0xFF9B5DE5)),
  (nombre: 'Azul', color: Color(0xFF4EA8DE)),
  (nombre: 'Esmeralda', color: Color(0xFF2EC4B6)),
  (nombre: 'Verde', color: Color(0xFF7BC950)),
  (nombre: 'Rojo', color: Color(0xFFE63946)),
  (nombre: 'Naranja', color: Color(0xFFFF9F1C)),
];

/// Personalizar el tótem de un evento: la apariencia, la foto, los textos y el
/// color, mirando el tótem de verdad.
///
/// En la PC (más de [CortesPantalla.pc]) abre como ventana al centro, con la
/// vista grande a la izquierda; en tablet y celular, como hoja a pantalla
/// completa, con la vista arriba.
Future<void> showTotemConfigSheet({
  required BuildContext context,
  required String eventoId,
}) async {
  if (CortesPantalla.esPc(MediaQuery.sizeOf(context).width)) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => PersonalizarTotem(eventoId: eventoId, enVentana: true),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PersonalizarTotem(eventoId: eventoId, enVentana: false),
  );
}

/// Lo que se ve al tocar "Ver una llegada": una llegada inventada, armada con
/// lo mismo que arma la del salón ([ContenidoBienvenida.armar]), así que dice
/// el saludo, la mesa, las sillas y la música como las diría el tótem.
abstract final class LlegadaDeEjemplo {
  /// Lo que dura en la vista: lo de una bienvenida sin cola.
  static const dura = kBienvenidaSola;

  /// En un masivo, una familia (el alumno y dos acompañantes) con su mesa, sus
  /// sillas y la música si está prendida. En un particular, una persona con
  /// su mesa.
  static ContenidoBienvenida para({
    required bool masivo,
    required TotemConfig cfg,
  }) {
    Invitado fila(String id, String nombre, String mesa) => Invitado(
          id: id,
          eventoId: cfg.eventoId,
          nombreCompleto: nombre,
          dni: '',
          numeroMesa: mesa,
          estadoIngreso: EstadoIngreso.ingresado,
        );
    final empezo = DateTime(2026, 12, 12, 22);

    if (!masivo) {
      return ContenidoBienvenida.armar(
        BienvenidaTotem(
          familia: 'ejemplo',
          personas: [fila('ejemplo', 'GONZÁLEZ, MARÍA', '4')],
          empezo: empezo,
        ),
        ficha: FichaTotem.particular(cfg.eventoId),
        cfg: cfg,
      );
    }

    const alumno = 'ejemplo-alumno';
    const titular = 'PÉREZ, JUAN MARTÍN';
    PersonaFicha persona(String id, String nombre, {bool esAlumno = false}) =>
        PersonaFicha(
          id: id,
          nombre: nombre,
          familia: alumno,
          esAlumno: esAlumno,
          mesa: '12',
          sillas: '10 sillas (8 + 2 extra)',
          musica: esAlumno ? 'Tusa · Karol G' : null,
          titular: esAlumno ? null : titular,
        );
    final personas = [
      persona(alumno, titular, esAlumno: true),
      persona('ejemplo-1', 'GÓMEZ, ANA'),
      persona('ejemplo-2', 'PÉREZ, LUIS'),
    ];
    return ContenidoBienvenida.armar(
      BienvenidaTotem(
        familia: alumno,
        personas: [for (final p in personas) fila(p.id, p.nombre, '12')],
        empezo: empezo,
      ),
      ficha: FichaTotem(
        eventoId: cfg.eventoId,
        masivo: true,
        personas: {for (final p in personas) p.id: p},
      ),
      cfg: cfg,
    );
  }
}

/// Lo que abre [showTotemConfigSheet].
class PersonalizarTotem extends ConsumerStatefulWidget {
  final String eventoId;

  /// En la PC: ventana al centro, con la vista a la izquierda. Si no, hoja a
  /// pantalla completa, con la vista arriba.
  final bool enVentana;

  const PersonalizarTotem({
    super.key,
    required this.eventoId,
    required this.enVentana,
  });

  /// Lo que se dice si no se pudo guardar. Sin el texto de la excepción.
  static const errorAlGuardar =
      'No se pudo guardar. Revisá la conexión e intentá de nuevo.';

  /// Cómo se elige la foto. Solo los tests lo cambian.
  @visibleForTesting
  static Future<FilePickerResult?> Function() elegirFoto = _conElSelector;

  /// Cómo se elige el fondo de "Tu fondo". Solo los tests lo cambian.
  @visibleForTesting
  static Future<FilePickerResult?> Function() elegirFondo = _fondoConElSelector;

  static Future<FilePickerResult?> _conElSelector() =>
      _selector('Elegí la foto del evento');

  static Future<FilePickerResult?> _fondoConElSelector() =>
      _selector('Elegí el fondo del tótem');

  static Future<FilePickerResult?> _selector(String titulo) =>
      // `withData: true` es obligatorio: en web `PlatformFile.path` siempre es
      // null. El resto del repo usa `.path` y por eso no anda del lado web.
      FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: TotemConfigRepository.tiposPermitidos.keys.toList(),
        withData: true,
        dialogTitle: titulo,
      );

  @override
  ConsumerState<PersonalizarTotem> createState() => _PersonalizarTotemState();
}

class _PersonalizarTotemState extends ConsumerState<PersonalizarTotem> {
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _bienvenida;
  late final TextEditingController _mensajeQr;
  late final TextEditingController _hex;

  late Color _acento;
  late bool _mostrarMusica;

  /// La apariencia: la guardada, o la que se tocó. Si no se toca ninguna se
  /// conserva tal cual, también vacía: la config se arma campo por campo, y un
  /// campo que falte acá se borra en la nube.
  String? _estilo;
  String? _imagenUrl;

  /// La config como llegó.
  late final TotemConfig _guardada;

  /// Foto elegida y todavía no subida. Se sube recién al guardar para no dejar
  /// archivos huérfanos en el bucket si el usuario cancela. Mientras tanto se
  /// ve en la vista y en las tarjetas.
  Uint8List? _imagenNueva;
  String? _extensionNueva;
  bool _quitarImagen = false;

  // ── "Tu fondo" ──
  //
  // Lo del fondo (la receta, los colores, el foco) viaja en [_fondo], una
  // config de la que solo importa lo del fondo: Personalizar arma la config
  // campo por campo, y un campo que falte se borra en la nube.

  late TotemConfig _fondo;

  /// El fondo elegido y todavía no subido, como la foto.
  Uint8List? _fondoNuevo;
  String? _extensionFondo;
  bool _quitarFondo = false;

  /// Lo que se leyó de la imagen (la nueva, o la guardada cuando se termina de
  /// leer). Con ella se rehacen los colores al cambiar el oscurecido.
  LecturaDelFondo? _lectura;
  bool _leyendo = false;

  bool _guardando = false;
  String? _error;

  /// La vista apaisada. Arranca como quedó el tótem de este evento en esta PC;
  /// no se guarda.
  bool _apaisada = false;
  bool _seGiro = false;

  /// "Ver una llegada": la llegada de ejemplo en la vista grande.
  bool _conLlegada = false;
  bool _llegadaSaliendo = false;
  Object _claveLlegada = Object();
  DateTime? _llegadaEmpezo;
  DateTime? _llegadaFin;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    // `totemConfigValueProvider` nunca falla: si el evento no tiene fila,
    // devuelve los valores de siempre.
    final cfg = ref.read(totemConfigValueProvider(widget.eventoId));
    _guardada = cfg;
    _titulo = TextEditingController(text: cfg.titulo);
    _subtitulo = TextEditingController(text: cfg.subtitulo);
    _bienvenida = TextEditingController(text: cfg.mensajeBienvenida);
    _mensajeQr = TextEditingController(text: cfg.mensajeQr);
    _hex = TextEditingController(text: cfg.colorAcentoHex);
    _acento = cfg.colorAcento;
    _mostrarMusica = cfg.mostrarMusica;
    _estilo = cfg.estilo;
    _imagenUrl = cfg.imagenUrl;
    _fondo = cfg;
    if (cfg.fondoUrl != null) _leerGuardado();

    TotemOrientationStore.load(widget.eventoId).then((o) {
      if (mounted && !_seGiro && o == TotemOrientation.horizontal) {
        setState(() => _apaisada = true);
      }
    });
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _titulo.dispose();
    _subtitulo.dispose();
    _bienvenida.dispose();
    _mensajeQr.dispose();
    _hex.dispose();
    super.dispose();
  }

  /// Config tal como quedaría, para la vista y para guardar.
  TotemConfig get _preview => TotemConfig(
        eventoId: widget.eventoId,
        titulo: _titulo.text.trim().isEmpty ? 'JUNIOR EVENTOS' : _titulo.text.trim(),
        subtitulo: _subtitulo.text.trim(),
        mensajeBienvenida: _bienvenida.text.trim().isEmpty
            ? TotemConfig.saludoPorDefecto
            : _bienvenida.text.trim(),
        mensajeQr: _mensajeQr.text.trim().isEmpty
            ? 'ESCANEÁ PARA INGRESAR'
            : _mensajeQr.text.trim(),
        imagenUrl: _quitarImagen ? null : _imagenUrl,
        colorAcento: _acento,
        mostrarMusica: _mostrarMusica,
        estilo: _estilo,
      ).conFondoDe(
        _quitarFondo ? _fondo.copyWith(limpiarFondo: true) : _fondo,
      );

  /// Si hay un fondo para "Tu fondo": el guardado o uno recién elegido.
  bool get _hayFondo =>
      !_quitarFondo && (_fondoNuevo != null || _guardada.fondoUrl != null);

  /// La foto recién elegida, que manda sobre la guardada.
  ImageProvider? get _foto =>
      _imagenNueva == null ? null : MemoryImage(_imagenNueva!);

  /// El fondo recién elegido, que manda sobre el guardado. Se guarda el
  /// proveedor: uno nuevo en cada cuadro haría leer la imagen de nuevo.
  MemoryImage? _fondoImagen;
  MemoryImage? get _fondoParaVer {
    final bytes = _fondoNuevo;
    if (bytes == null) return null;
    if (!identical(_fondoImagen?.bytes, bytes)) _fondoImagen = MemoryImage(bytes);
    return _fondoImagen;
  }

  /// El QR de la espera: solo en un particular, como en el salón.
  String? _qrUrl(bool masivo) =>
      masivo ? null : '$kWebBaseUrl/lista?evento=${widget.eventoId}';

  /// La que se ve: la elegida, o la del tipo de evento si nadie eligió.
  EstiloTotem _estiloQueSeVe(bool masivo) =>
      EstiloTotem.elegida(_estilo, fondoUrl: _hayFondo ? 'hay' : null) ??
      EstiloTotem.porDefecto(masivo: masivo);

  // ── Ver una llegada ───────────────────────────────────────────────────────

  void _verLlegada() {
    _temporizador?.cancel();
    final ahora = DateTime.now();
    setState(() {
      _conLlegada = true;
      _llegadaSaliendo = false;
      _claveLlegada = Object();
      _llegadaEmpezo = ahora;
      _llegadaFin = ahora.add(LlegadaDeEjemplo.dura);
    });
    _temporizador = Timer(LlegadaDeEjemplo.dura, () {
      if (!mounted) return;
      setState(() => _llegadaSaliendo = true);
      _temporizador = Timer(EscenaTotem.salida, () {
        if (!mounted) return;
        setState(() {
          _conLlegada = false;
          _llegadaSaliendo = false;
        });
      });
    });
  }

  // ── Imagen ────────────────────────────────────────────────────────────────

  /// Los bytes y la extensión del archivo elegido, o null (y el error dicho)
  /// si no sirve. Las mismas reglas para la foto y el fondo: las del bucket.
  (Uint8List, String)? _archivoValido(FilePickerResult? resultado) {
    if (!mounted || resultado == null || resultado.files.isEmpty) return null;
    final archivo = resultado.files.single;
    final bytes = archivo.bytes;

    if (bytes == null) {
      setState(() => _error = 'No se pudo leer el archivo.');
      return null;
    }

    final ext = archivo.extension ?? '';
    if (TotemConfigRepository.mimeDe(ext) == null) {
      setState(() => _error = 'Solo se aceptan JPG, PNG o WEBP.');
      return null;
    }
    if (bytes.length > TotemConfigRepository.maxBytes) {
      setState(() => _error = 'La imagen pesa más de 5 MB. Elegí una más liviana.');
      return null;
    }
    return (bytes, ext);
  }

  Future<void> _elegirImagen() async {
    final valido = _archivoValido(await PersonalizarTotem.elegirFoto());
    if (valido == null) return;
    setState(() {
      _imagenNueva = valido.$1;
      _extensionNueva = valido.$2;
      _quitarImagen = false;
      _error = null;
    });
  }

  // ── "Tu fondo" ────────────────────────────────────────────────────────────

  /// Elige el fondo: queda elegida "Tu fondo" y se lee la imagen. Con
  /// "Automático" prendido, la receta sale de ella.
  Future<void> _elegirFondo() async {
    final valido = _archivoValido(await PersonalizarTotem.elegirFondo());
    if (valido == null) return;
    final (bytes, ext) = valido;
    setState(() {
      _fondoNuevo = bytes;
      _extensionFondo = ext;
      _quitarFondo = false;
      _estilo = EstiloTotem.tuFondo.clave;
      _lectura = null;
      _leyendo = true;
      _error = null;
    });
    try {
      final lectura = await LecturaDelFondo.deBytes(bytes);
      if (!mounted || !identical(_fondoNuevo, bytes)) return;
      setState(() {
        _lectura = lectura;
        _fondo = conLaLectura(
          _fondo,
          lectura,
          automatico: _fondo.fondoAutomatico,
        );
      });
    } catch (e) {
      debugPrint('Personalizar: no se pudo leer el fondo: $e');
      if (mounted && identical(_fondoNuevo, bytes)) {
        setState(() => _error = 'No se pudo leer la imagen. Probá con otra.');
      }
    } finally {
      if (mounted && identical(_fondoNuevo, bytes)) {
        setState(() => _leyendo = false);
      }
    }
  }

  /// Lee el fondo guardado, en chico: hace falta para rehacer los colores si
  /// se cambia el oscurecido. Si no se puede (sin internet y sin el fondo en
  /// la PC), quedan los colores guardados.
  void _leerGuardado() {
    final proveedor = fondoDelEvento(_guardada);
    if (proveedor == null) return;
    final stream = ResizeImage(
      proveedor,
      width: LecturaDelFondo.anchoDeLectura,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener oyente;
    oyente = ImageStreamListener(
      (info, _) async {
        stream.removeListener(oyente);
        try {
          final lectura = await LecturaDelFondo.deImagen(info.image);
          if (mounted && _fondoNuevo == null && !_quitarFondo) {
            setState(() => _lectura = lectura);
          }
        } catch (e) {
          debugPrint('Personalizar: no se pudo leer el fondo guardado: $e');
        } finally {
          info.dispose();
        }
      },
      onError: (e, _) {
        stream.removeListener(oyente);
        debugPrint('Personalizar: el fondo guardado no se pudo leer; quedan '
            'sus colores: $e');
      },
    );
    stream.addListener(oyente);
  }

  void _quitarElFondo() {
    setState(() {
      _fondoNuevo = null;
      _extensionFondo = null;
      _quitarFondo = true;
      _lectura = null;
      _leyendo = false;
      // Sin fondo, "Tu fondo" no se puede elegir: vuelve a la del tipo.
      if (_estilo == EstiloTotem.tuFondo.clave) _estilo = null;
      _error = null;
    });
  }

  void _alternarAutomatico(bool automatico) {
    setState(() {
      final lectura = _lectura;
      _fondo = automatico && lectura != null
          ? conLaLectura(_fondo, lectura, automatico: true)
          : _fondo.copyWith(fondoAutomatico: automatico);
    });
  }

  /// Un cambio a mano: apaga "Automático" y queda lo elegido. Los colores se
  /// rehacen (dependen del oscurecido).
  void _aMano(TotemConfig Function(TotemConfig) cambio) {
    setState(() {
      final nuevo = cambio(_fondo).copyWith(fondoAutomatico: false);
      final lectura = _lectura;
      _fondo = lectura == null
          ? nuevo
          : conLaLectura(nuevo, lectura, automatico: false);
    });
  }

  void _quitarFoto() {
    setState(() {
      _imagenNueva = null;
      _extensionNueva = null;
      _quitarImagen = true;
      _error = null;
    });
  }

  // ── Guardado ──────────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (_guardando) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(totemConfigRepositoryProvider);

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      var url = _imagenUrl;

      if (_quitarImagen) {
        await repo.borrarImagen(widget.eventoId);
        url = null;
      } else if (_imagenNueva != null) {
        url = await repo.subirImagen(
          eventoId: widget.eventoId,
          bytes: _imagenNueva!,
          extension: _extensionNueva!,
        );
      }

      // El fondo, igual: se sube o se borra recién ahora.
      var fondoUrl = _guardada.fondoUrl;
      if (_quitarFondo) {
        if (fondoUrl != null) await repo.borrarFondo(widget.eventoId);
        fondoUrl = null;
      } else if (_fondoNuevo != null) {
        fondoUrl = await repo.subirFondo(
          eventoId: widget.eventoId,
          bytes: _fondoNuevo!,
          extension: _extensionFondo!,
        );
      }

      final cfg = TotemConfig(
        eventoId: widget.eventoId,
        titulo: _preview.titulo,
        subtitulo: _preview.subtitulo,
        mensajeBienvenida: _preview.mensajeBienvenida,
        mensajeQr: _preview.mensajeQr,
        imagenUrl: url,
        colorAcento: _acento,
        mostrarMusica: _mostrarMusica,
        estilo: _estilo,
      ).conFondoDe(
        fondoUrl == null
            ? _fondo.copyWith(limpiarFondo: true)
            : _fondo.copyWith(fondoUrl: fondoUrl),
      );

      final guardada = await repo.guardar(cfg);

      // Puente local: sin esto la ventana del salón depende del stream, o sea de
      // que haya red. Con esto se repinta al instante aunque el wifi esté caído.
      if (KioskLauncher.isTotemActive) {
        KioskLauncher.notifyConfigUpdated(guardada.toJson());
      }
      ref.invalidate(totemConfigProvider(widget.eventoId));

      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Tótem actualizado.')),
      );
    } catch (e) {
      debugPrint('Personalizar tótem: no se pudo guardar: $e');
      if (!mounted) return;
      setState(() => _error = PersonalizarTotem.errorAlGuardar);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cfg = _preview;
    // En un masivo el tótem no muestra QR (su texto no se usa) y puede mostrar
    // la música de cada alumno.
    final masivo = ref
            .watch(eventosActivosProvider)
            .value
            ?.where((e) => e.id == widget.eventoId)
            .firstOrNull
            ?.modalidad ==
        'masivo';
    final estilo = _estiloQueSeVe(masivo);
    return widget.enVentana
        ? _ventana(cfg, estilo, masivo)
        : _hoja(cfg, estilo, masivo);
  }

  /// En la PC: ventana al centro, la vista a la izquierda y lo que se elige a
  /// la derecha.
  Widget _ventana(TotemConfig cfg, EstiloTotem estilo, bool masivo) {
    final alto = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1180,
          maxHeight: math.min(820, alto - 48),
        ),
        child: _marco(
          redondeo: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _encabezado(),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 400,
                        child: _vista(cfg, estilo, masivo, llenar: true),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ajustes(cfg, estilo, masivo),
                              ),
                            ),
                            ..._pie(),
                          ],
                        ),
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

  /// En tablet y celular: hoja a pantalla completa, la vista arriba.
  Widget _hoja(TotemConfig cfg, EstiloTotem estilo, bool masivo) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, c) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: c.maxHeight,
          child: _marco(
            redondeo: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _encabezado(),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _vista(cfg, estilo, masivo, llenar: false),
                            const SizedBox(height: 24),
                            _ajustes(cfg, estilo, masivo),
                          ],
                        ),
                      ),
                    ),
                    ..._pie(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _marco({required BorderRadius redondeo, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _colorDelPanel,
        borderRadius: redondeo,
        border: Border.all(color: _gold.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _encabezado() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _gold.withValues(alpha: 0.22),
                _gold.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.35)),
          ),
          child: Icon(
            Icons.palette_rounded,
            color: _gold.withValues(alpha: 0.95),
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERSONALIZAR TÓTEM',
                style: TextStyle(
                  fontFamily: FuentesTotem.cartelera,
                  fontSize: 14,
                  color: _gold,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Lo que ven los invitados en la pantalla del salón.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white54),
        ),
      ],
    );
  }

  /// La vista grande del tótem, animada, con la llave vertical/horizontal y
  /// "Ver una llegada". [llenar]: ocupa el alto que tenga (la ventana).
  Widget _vista(
    TotemConfig cfg,
    EstiloTotem estilo,
    bool masivo, {
    required bool llenar,
  }) {
    final escena = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: EscenaTotem(
        key: const ValueKey('vista_totem'),
        estilo: estilo,
        respaldo: EstiloTotem.porDefecto(masivo: masivo),
        cfg: cfg,
        foto: _foto,
        fondo: _fondoParaVer,
        qrUrl: _qrUrl(masivo),
        llegada: _conLlegada
            ? LlegadaDeEjemplo.para(masivo: masivo, cfg: cfg)
            : null,
        claveLlegada: _claveLlegada,
        saliendo: _llegadaSaliendo,
        empezo: _llegadaEmpezo,
        fin: _llegadaFin,
      ),
    );

    final Widget pantalla;
    if (llenar) {
      pantalla = Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: _apaisada ? 16 / 9 : 9 / 16,
            child: escena,
          ),
        ),
      );
    } else if (_apaisada) {
      pantalla = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AspectRatio(aspectRatio: 16 / 9, child: escena),
        ),
      );
    } else {
      final alto =
          (MediaQuery.sizeOf(context).height * 0.45).clamp(220.0, 460.0);
      pantalla = Center(
        child: SizedBox(height: alto, width: alto * 9 / 16, child: escena),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'VISTA DEL TÓTEM · ${estilo.nombre.toUpperCase()}',
          textAlign: TextAlign.center,
          style: _estiloRotulo,
        ),
        const SizedBox(height: 10),
        pantalla,
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            _LlaveOrientacion(
              apaisada: _apaisada,
              onChanged: (v) => setState(() {
                _apaisada = v;
                _seGiro = true;
              }),
            ),
            OutlinedButton.icon(
              key: const ValueKey('ver_una_llegada'),
              onPressed: _verLlegada,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                minimumSize: const Size(0, 44),
                side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Ver una llegada'),
            ),
          ],
        ),
      ],
    );
  }

  /// Las tarjetas, la foto, los textos y el color.
  Widget _ajustes(TotemConfig cfg, EstiloTotem estilo, bool masivo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('APARIENCIA', style: _estiloRotulo),
        const SizedBox(height: 4),
        const Text(
          'Tocá una para verla en grande. Se usa en este evento.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),
        _tarjetas(cfg, estilo, masivo),
        const SizedBox(height: 24),
        _seccionFoto(cfg),
        const SizedBox(height: 24),
        _seccionFondo(),
        const SizedBox(height: 20),
        _campo(_titulo, 'Título', 'PROMOCIÓN 2026'),
        const SizedBox(height: 12),
        _campo(_subtitulo, 'Subtítulo', 'Los 15 de Sofía'),
        const SizedBox(height: 12),
        _campo(_bienvenida, 'Saludo al ingresar', TotemConfig.saludoPorDefecto),
        const SizedBox(height: 12),
        if (masivo)
          CasillaMusicaTotem(
            valor: _mostrarMusica,
            onChanged: _guardando
                ? null
                : (v) => setState(() => _mostrarMusica = v),
          )
        else
          _campo(_mensajeQr, 'Texto del QR', 'ESCANEÁ PARA INGRESAR'),
        const SizedBox(height: 20),
        _seccionColor(),
        const SizedBox(height: 20),
        LinkTotemNavegador(
          eventoId: widget.eventoId,
          base: kWebBaseUrl,
          pedirClave: () => ref.read(claveTotemProvider).de(widget.eventoId),
        ),
      ],
    );
  }

  Widget _tarjetas(TotemConfig cfg, EstiloTotem visto, bool masivo) {
    final nadieEligio =
        EstiloTotem.elegida(_estilo, fondoUrl: _hayFondo ? 'hay' : null) == null;
    final porDefecto = EstiloTotem.porDefecto(masivo: masivo);
    // "Tu fondo" se puede elegir solo con un fondo cargado.
    final estilos = [
      ...EstiloTotem.deLaCasa,
      if (_hayFondo) EstiloTotem.tuFondo,
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const espacio = 10.0;
        final n = estilos.length;
        final ancho = math.min(128.0, (c.maxWidth - espacio * (n - 1)) / n);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in estilos) ...[
              if (e != estilos.first) const SizedBox(width: espacio),
              TarjetaApariencia(
                key: ValueKey('apariencia_${e.clave}'),
                estilo: e,
                respaldo: porDefecto,
                cfg: cfg,
                foto: _foto,
                fondo: _fondoParaVer,
                qrUrl: _qrUrl(masivo),
                ancho: ancho,
                elegida: e == visto,
                vaSiNoElegis: nadieEligio && e == porDefecto,
                onTap: _guardando
                    ? null
                    : () => setState(() => _estilo = e.clave),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _pie() => [
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _guardando ? 'GUARDANDO…' : 'GUARDAR',
            style: const TextStyle(
              fontFamily: FuentesTotem.cartelera,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ];

  static const _estiloRotulo = TextStyle(
    fontFamily: FuentesTotem.cartelera,
    fontSize: 12,
    color: Colors.white70,
    letterSpacing: 1.6,
  );

  Widget _seccionFoto(TotemConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FOTO DEL EVENTO', style: _estiloRotulo),
        const SizedBox(height: 4),
        const Text(
          'Para un quince, la foto de la quinceañera. '
          'Si no cargás ninguna se usa el logo.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _guardando ? null : _elegirImagen,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                minimumSize: const Size(0, 44),
                side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Elegir foto'),
            ),
            if (cfg.imagenUrl != null || _imagenNueva != null)
              TextButton.icon(
                onPressed: _guardando ? null : _quitarFoto,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar foto'),
              ),
            Text(
              'JPG, PNG o WEBP · hasta 5 MB',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "Tu fondo": la imagen para toda la pantalla, lo que se leyó de ella y su
  /// receta, automática o a mano. Es lo del diseño del 23-oct (Claude Design).
  Widget _seccionFondo() {
    final cfg = _fondo;
    final receta = RecetaDibujada.de(cfg);
    final hay = _hayFondo;
    final libre = !_guardando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FONDO', style: _estiloRotulo),
        const SizedBox(height: 4),
        const Text(
          'Una imagen para toda la pantalla, por ejemplo una story. La foto '
          'del círculo es aparte. De la imagen salen la animación, los efectos '
          'y los colores de "Tu fondo".',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('elegir_fondo'),
              onPressed: libre ? _elegirFondo : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                minimumSize: const Size(0, 44),
                side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.wallpaper_rounded, size: 18),
              label: Text(hay ? 'Cambiar fondo' : 'Elegir fondo'),
            ),
            if (hay)
              TextButton.icon(
                onPressed: libre ? _quitarElFondo : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar fondo'),
              ),
            Text(
              'JPG, PNG o WEBP · hasta 5 MB',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ],
        ),
        if (_leyendo) ...[
          const SizedBox(height: 8),
          const Text(
            'Leyendo la imagen…',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        if (hay) ...[
          const SizedBox(height: 14),
          _automatico(cfg, receta),
          const SizedBox(height: 18),
          Text('ANIMACIÓN DE LA IMAGEN', style: _estiloRotulo),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in AnimacionFondo.values)
                _Pastilla(
                  key: ValueKey('animacion_${a.clave}'),
                  texto: a.nombre,
                  ayuda: a.explicacion,
                  elegida: receta.animacion == a,
                  onTap: libre
                      ? () => _aMano((c) => c.copyWith(fondoAnimacion: a.clave))
                      : null,
                ),
            ],
          ),
          _barra(
            'Intensidad',
            cfg.fondoIntensidad,
            100,
            key: const ValueKey('intensidad_animacion'),
            receta.animacion == AnimacionFondo.quieta || !libre
                ? null
                : (v) => _aMano((c) => c.copyWith(fondoIntensidad: v)),
          ),
          const SizedBox(height: 14),
          Text('EFECTOS · VAN ENCIMA, SE COMBINAN', style: _estiloRotulo),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in EfectoFondo.values)
                _Pastilla(
                  key: ValueKey('efecto_${e.clave}'),
                  texto: e.nombre,
                  ayuda: e.explicacion,
                  elegida: receta.tiene(e),
                  onTap: libre ? () => _aMano((c) => _conEfecto(c, e)) : null,
                ),
            ],
          ),
          _barra(
            'Intensidad',
            cfg.fondoIntensidadEfectos,
            100,
            key: const ValueKey('intensidad_efectos'),
            receta.efectos.isEmpty || !libre
                ? null
                : (v) => _aMano((c) => c.copyWith(fondoIntensidadEfectos: v)),
          ),
          const SizedBox(height: 14),
          Text('OSCURECER', style: _estiloRotulo),
          _barra(
            'Para que se lea',
            cfg.fondoOscurecer,
            TotemConfig.oscurecerMaximo,
            key: const ValueKey('oscurecer'),
            libre
                ? (v) => _aMano((c) => c.copyWith(fondoOscurecer: v))
                : null,
          ),
        ],
      ],
    );
  }

  /// Prende o apaga un efecto. Los que esta versión no conoce quedan.
  static TotemConfig _conEfecto(TotemConfig c, EfectoFondo e) {
    final claves = [
      ...(c.fondoEfectos ?? [for (final p in EfectoFondo.porDefecto) p.clave]),
    ];
    if (!claves.remove(e.clave)) claves.add(e.clave);
    return c.copyWith(fondoEfectos: claves);
  }

  /// "Automático · según la imagen", lo que se leyó y lo que quedó.
  Widget _automatico(TotemConfig cfg, RecetaDibujada receta) {
    final lectura = _lectura;
    final efectos = receta.efectos.map((e) => e.nombre).toList();
    final resumen = '${cfg.fondoAutomatico ? 'Eligió' : 'Queda'}: '
        '${receta.animacion.nombre} · '
        '${efectos.isEmpty ? 'sin efectos' : efectos.join(', ')} · '
        'oscurecer ${cfg.fondoOscurecer} %'
        '${receta.textoOscuro ? ' · el texto va oscuro' : ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _gold.withValues(alpha: 0.9)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Automático · según la imagen',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cfg.fondoAutomatico
                          ? 'La animación, los efectos y el oscurecido salen de '
                              'la imagen.'
                          : 'Lo elegiste vos. Prendelo para volver a lo de la '
                              'imagen.',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('fondo_automatico'),
                value: cfg.fondoAutomatico,
                onChanged: _guardando ? null : _alternarAutomatico,
                activeThumbColor: Colors.black,
                activeTrackColor: _gold,
              ),
            ],
          ),
          if (lectura != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Se lee:',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                for (final p in lectura.palabras)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Colores:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 8),
              for (final (nombre, color) in [
                ('Brillo', receta.colores.brillo),
                ('Saludo', receta.colores.saludo),
                ('Tarjeta', receta.colores.tarjeta),
              ]) ...[
                Tooltip(
                  message: '$nombre ${TotemConfig.hexDe(color)}',
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            resumen,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Una barra de 0 a [maximo], de a 10. Sin [alCambiar], apagada.
  Widget _barra(
    String rotulo,
    int valor,
    int maximo,
    ValueChanged<int>? alCambiar, {
    Key? key,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(
            rotulo,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            key: key,
            value: valor.clamp(0, maximo).toDouble(),
            max: maximo.toDouble(),
            divisions: maximo ~/ 10,
            label: '$valor %',
            activeColor: _gold,
            inactiveColor: Colors.white24,
            onChanged: alCambiar == null ? null : (v) => alCambiar(v.round()),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            alCambiar == null ? '—' : '$valor %',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _campo(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      enabled: !_guardando,
      onChanged: (_) => setState(() {}), // la vista sigue lo que se tipea
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.6)),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _seccionColor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COLOR DE ACENTO', style: _estiloRotulo),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _paleta.map((entrada) {
            final elegido =
                entrada.color.toARGB32() == _acento.toARGB32();
            return Tooltip(
              message: entrada.nombre +
                  (entrada.color.toARGB32() == _gold.toARGB32()
                      ? ' (por defecto)'
                      : ''),
              child: GestureDetector(
                onTap: _guardando
                    ? null
                    : () => setState(() {
                          _acento = entrada.color;
                          _hex.text = TotemConfig(
                            eventoId: widget.eventoId,
                            colorAcento: entrada.color,
                          ).colorAcentoHex;
                        }),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: entrada.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: elegido ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: elegido
                      ? const Icon(Icons.check, size: 18, color: Colors.black87)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hex,
          enabled: !_guardando,
          // `parseHex` ya cae al dorado ante cualquier basura, así que no hace
          // falta validar a mano ni bloquear el guardado.
          onChanged: (v) => setState(() => _acento = TotemConfig.parseHex(v)),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'O pegá el hex de la marca',
            hintText: '#D4AF37',
            labelStyle: const TextStyle(color: Colors.white54),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: _acento,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _gold.withValues(alpha: 0.6)),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

/// Una de las cuatro apariencias en Personalizar: la espera, quieta, con la
/// foto, el título y el color de este evento, y su nombre debajo.
///
/// Es la escena de verdad ([EscenaTotem]), así que no puede mentir. Va quieta:
/// cinco fondos animados a la vez cargan una PC de oficina, y la vista grande
/// ya muestra el movimiento.
class TarjetaApariencia extends StatelessWidget {
  final EstiloTotem estilo;

  /// La del tipo de evento, si es "Tu fondo" y la imagen no se puede leer.
  final EstiloTotem respaldo;
  final TotemConfig cfg;
  final ImageProvider? foto;

  /// El fondo de "Tu fondo" recién elegido, como [foto].
  final ImageProvider? fondo;
  final String? qrUrl;
  final double ancho;
  final bool elegida;

  /// Nadie eligió y es la del tipo de evento: la que va si no se elige otra.
  final bool vaSiNoElegis;

  /// Null mientras se guarda.
  final VoidCallback? onTap;

  const TarjetaApariencia({
    super.key,
    required this.estilo,
    this.respaldo = EstiloTotem.cristal,
    required this.cfg,
    required this.foto,
    this.fondo,
    required this.qrUrl,
    required this.ancho,
    required this.elegida,
    required this.vaSiNoElegis,
    required this.onTap,
  });

  static const rotuloPorDefecto = 'va esta si no elegís';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegida,
      label: 'Apariencia ${estilo.nombre}',
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: ancho,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: ancho,
                  height: ancho * 16 / 9,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: elegida
                          ? _gold
                          : Colors.white.withValues(alpha: 0.14),
                      width: elegida ? 2.5 : 1,
                    ),
                  ),
                  child: IgnorePointer(
                    child: EscenaTotem(
                      estilo: estilo,
                      respaldo: respaldo,
                      cfg: cfg,
                      foto: foto,
                      fondo: fondo,
                      qrUrl: qrUrl,
                      quieta: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (elegida) ...[
                      const Icon(Icons.check_circle_rounded,
                          size: 15, color: _gold),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        estilo.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FuentesTotem.linea,
                          fontSize: 13,
                          fontWeight:
                              elegida ? FontWeight.w700 : FontWeight.w400,
                          color: elegida ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                if (vaSiNoElegis)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      rotuloPorDefecto,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una opción de "Tu fondo" (una animación, un efecto), que se prende y se
/// apaga.
class _Pastilla extends StatelessWidget {
  final String texto;
  final String ayuda;
  final bool elegida;
  final VoidCallback? onTap;

  const _Pastilla({
    super.key,
    required this.texto,
    required this.ayuda,
    required this.elegida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ayuda,
      child: Semantics(
        button: true,
        selected: elegida,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: elegida
                  ? _gold.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: elegida ? _gold : Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (elegida) ...[
                  const Icon(Icons.check_rounded, size: 15, color: _gold),
                  const SizedBox(width: 4),
                ],
                Text(
                  texto,
                  style: TextStyle(
                    fontSize: 13,
                    color: elegida ? const Color(0xFFF3D77A) : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical u horizontal, para la vista de Personalizar. No guarda nada.
class _LlaveOrientacion extends StatelessWidget {
  final bool apaisada;
  final ValueChanged<bool> onChanged;

  const _LlaveOrientacion({required this.apaisada, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget opcion(bool valor, IconData icono, String texto) {
      final activa = apaisada == valor;
      return Semantics(
        button: true,
        selected: activa,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => onChanged(valor),
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: activa ? _gold.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono,
                    size: 16, color: activa ? _gold : Colors.white54),
                const SizedBox(width: 6),
                Text(
                  texto,
                  style: TextStyle(
                    fontSize: 13,
                    color: activa ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion(false, Icons.stay_current_portrait_rounded, 'Vertical'),
          opcion(true, Icons.stay_current_landscape_rounded, 'Horizontal'),
        ],
      ),
    );
  }
}

/// La casilla de la música, en Personalizar de un evento masivo.
///
/// Prendida, la bienvenida del tótem muestra la canción que eligió cada
/// alumno, si está cargada (con el Excel del delegado o en su ficha).
class CasillaMusicaTotem extends StatelessWidget {
  final bool valor;

  /// Null mientras se guarda.
  final ValueChanged<bool>? onChanged;

  const CasillaMusicaTotem({
    super.key,
    required this.valor,
    required this.onChanged,
  });

  static const titulo = 'Mostrar la música de cada alumno';
  static const explicacion =
      'Al saludar, el tótem muestra la canción que eligió, si está cargada.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.music_note_rounded, color: _gold.withValues(alpha: 0.9)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text(
                  explicacion,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: valor,
            onChanged: onChanged,
            activeThumbColor: Colors.black,
            activeTrackColor: _gold,
          ),
        ],
      ),
    );
  }
}
