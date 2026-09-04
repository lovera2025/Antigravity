import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/kiosk_launcher.dart';
import '../../../models/totem_config.dart';
import '../providers/totem_config_provider.dart';
import '../repositories/totem_config_repository.dart';

const _gold = TotemConfig.acentoPorDefecto;

/// Paleta curada.
///
/// Se eligieron a mano en vez de sumar un color picker: el acento no se mira en
/// un monitor sino **proyectado** en un salón, y `gradientePanel` /
/// `gradienteCard` derivan el fondo del tono elegido. Una rueda libre deja pasar
/// combinaciones que quedan ilegibles a cinco metros. Para el color exacto de
/// una marca está el campo de hex.
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

/// Editor de la identidad visual del tótem para un evento.
Future<void> showTotemConfigSheet({
  required BuildContext context,
  required String eventoId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TotemConfigSheetBody(eventoId: eventoId),
  );
}

class _TotemConfigSheetBody extends ConsumerStatefulWidget {
  final String eventoId;

  const _TotemConfigSheetBody({required this.eventoId});

  @override
  ConsumerState<_TotemConfigSheetBody> createState() =>
      _TotemConfigSheetBodyState();
}

class _TotemConfigSheetBodyState extends ConsumerState<_TotemConfigSheetBody> {
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _bienvenida;
  late final TextEditingController _mensajeQr;
  late final TextEditingController _hex;

  late Color _acento;
  String? _imagenUrl;

  /// Foto elegida y todavía no subida. Se sube recién al guardar para no dejar
  /// archivos huérfanos en el bucket si el usuario cancela.
  Uint8List? _imagenNueva;
  String? _extensionNueva;
  bool _quitarImagen = false;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // `totemConfigValueProvider` nunca falla: si el evento no tiene fila,
    // devuelve los valores de siempre.
    final cfg = ref.read(totemConfigValueProvider(widget.eventoId));
    _titulo = TextEditingController(text: cfg.titulo);
    _subtitulo = TextEditingController(text: cfg.subtitulo);
    _bienvenida = TextEditingController(text: cfg.mensajeBienvenida);
    _mensajeQr = TextEditingController(text: cfg.mensajeQr);
    _hex = TextEditingController(text: cfg.colorAcentoHex);
    _acento = cfg.colorAcento;
    _imagenUrl = cfg.imagenUrl;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _subtitulo.dispose();
    _bienvenida.dispose();
    _mensajeQr.dispose();
    _hex.dispose();
    super.dispose();
  }

  /// Config tal como quedaría, para el preview y para guardar.
  TotemConfig get _preview => TotemConfig(
        eventoId: widget.eventoId,
        titulo: _titulo.text.trim().isEmpty ? 'JUNIOR EVENTOS' : _titulo.text.trim(),
        subtitulo: _subtitulo.text.trim(),
        mensajeBienvenida: _bienvenida.text.trim().isEmpty
            ? '¡Bienvenido!'
            : _bienvenida.text.trim(),
        mensajeQr: _mensajeQr.text.trim().isEmpty
            ? 'ESCANEÁ PARA INGRESAR'
            : _mensajeQr.text.trim(),
        imagenUrl: _quitarImagen ? null : _imagenUrl,
        colorAcento: _acento,
      );

  // ── Imagen ────────────────────────────────────────────────────────────────

  Future<void> _elegirImagen() async {
    // `withData: true` es obligatorio: en web `PlatformFile.path` siempre es
    // null. El resto del repo usa `.path` y por eso no anda del lado web.
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: TotemConfigRepository.tiposPermitidos.keys.toList(),
      withData: true,
      dialogTitle: 'Elegí la foto del evento',
    );

    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.single;
    final bytes = archivo.bytes;

    if (bytes == null) {
      setState(() => _error = 'No se pudo leer el archivo.');
      return;
    }

    final ext = archivo.extension ?? '';
    if (TotemConfigRepository.mimeDe(ext) == null) {
      setState(() => _error = 'Solo se aceptan JPG, PNG o WEBP.');
      return;
    }
    if (bytes.length > TotemConfigRepository.maxBytes) {
      setState(() => _error = 'La imagen pesa más de 5 MB. Elegí una más liviana.');
      return;
    }

    setState(() {
      _imagenNueva = bytes;
      _extensionNueva = ext;
      _quitarImagen = false;
      _error = null;
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

      final cfg = TotemConfig(
        eventoId: widget.eventoId,
        titulo: _preview.titulo,
        subtitulo: _preview.subtitulo,
        mensajeBienvenida: _preview.mensajeBienvenida,
        mensajeQr: _preview.mensajeQr,
        imagenUrl: url,
        colorAcento: _acento,
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
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final bottom = MediaQuery.of(context).padding.bottom;
    final cfg = _preview;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: _gold.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 18),
                _encabezado(),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _seccionFotoYPreview(cfg),
                        const SizedBox(height: 20),
                        _campo(_titulo, 'Título', 'JUNIOR EVENTOS'),
                        const SizedBox(height: 12),
                        _campo(_subtitulo, 'Subtítulo', 'Los 15 de Sofía'),
                        const SizedBox(height: 12),
                        _campo(_bienvenida, 'Saludo al ingresar', '¡Bienvenido!'),
                        const SizedBox(height: 12),
                        _campo(_mensajeQr, 'Texto del QR', 'ESCANEÁ PARA INGRESAR'),
                        const SizedBox(height: 20),
                        _seccionColor(),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
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
                    style: GoogleFonts.oswald(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _gold.withValues(alpha: 0.22),
                _gold.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.35)),
          ),
          child: Icon(
            Icons.palette_rounded,
            color: _gold.withValues(alpha: 0.95),
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERSONALIZAR TÓTEM',
                style: GoogleFonts.oswald(
                  fontSize: 13,
                  color: _gold,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Lo que ven los invitados en la pantalla del salón.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccionFotoYPreview(TotemConfig cfg) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _previewPantalla(cfg),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'FOTO DEL EVENTO',
                style: GoogleFonts.oswald(
                  fontSize: 12,
                  color: Colors.white70,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Para un quince, la foto de la quinceañera. '
                'Si no cargás ninguna se usa el logo.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _guardando ? null : _elegirImagen,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Elegir foto'),
              ),
              if (cfg.imagenUrl != null || _imagenNueva != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _guardando ? null : _quitarFoto,
                  style: TextButton.styleFrom(foregroundColor: Colors.white38),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Quitar foto'),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'JPG, PNG o WEBP · hasta 5 MB',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Maqueta chica de la pantalla del salón.
  ///
  /// Reusa `gradienteCard` y `acentoConAlpha` del propio modelo, así que el
  /// preview no puede desincronizarse de lo que dibuja el tótem. **No** se
  /// embebe un `TotemDisplay` real: rearrancaría streams, canales y animaciones.
  Widget _previewPantalla(TotemConfig cfg) {
    return Container(
      width: 108,
      height: 192,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: cfg.gradienteCard,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.acentoConAlpha(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cfg.acentoConAlpha(0.6), width: 2),
              ),
              child: _miniatura(cfg),
            ),
            const SizedBox(height: 8),
            Text(
              cfg.titulo,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.oswald(
                color: cfg.colorAcento,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (cfg.subtitulo.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                cfg.subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 8),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: cfg.acentoConAlpha(0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                cfg.mensajeQr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cfg.colorAcento, fontSize: 7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniatura(TotemConfig cfg) {
    if (_imagenNueva != null) {
      return Image.memory(_imagenNueva!, fit: BoxFit.cover);
    }
    if (cfg.imagenUrl != null) {
      return Image.network(
        cfg.imagenUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholderFoto(cfg),
      );
    }
    return _placeholderFoto(cfg);
  }

  Widget _placeholderFoto(TotemConfig cfg) => ColoredBox(
        color: cfg.acentoConAlpha(0.12),
        child: Icon(
          Icons.celebration_rounded,
          color: cfg.acentoConAlpha(0.7),
          size: 22,
        ),
      );

  Widget _campo(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      enabled: !_guardando,
      onChanged: (_) => setState(() {}), // el preview sigue lo que se tipea
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
        Text(
          'COLOR DE ACENTO',
          style: GoogleFonts.oswald(
            fontSize: 12,
            color: Colors.white70,
            letterSpacing: 1.6,
          ),
        ),
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
