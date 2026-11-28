import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/evento.dart';
import '../../totem/widgets/totem_local.dart' show eventoMasivoProvider;
import '../central/central_provider.dart';
import '../central/central_puerta.dart';
import '../providers/recepcion_provider.dart';
import '../services/puerta_del_evento.dart';

/// "CELULARES · 2" en la barra de Recepción de la PC: abre la ventana para
/// sumar un celular a la puerta ([VentanaSumarCelular]) y dice cuántos hay
/// conectados a esta notebook.
class BotonCelulares extends ConsumerWidget {
  const BotonCelulares({super.key, required this.eventoId});
  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(centralDeLaPuertaProvider);
    final deEste = estado.prendida && estado.eventoId == eventoId;
    final conectados = deEste ? estado.conectados : 0;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: () => VentanaSumarCelular.abrir(context, eventoId),
        icon: const Icon(Icons.phone_android_rounded, size: 18),
        label: Text(
          conectados > 0 ? 'CELULARES · $conectados' : 'CELULARES',
          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _perla,
          side: BorderSide(
            color: conectados > 0
                ? _verde.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.3),
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

const _perla = Color(0xFFE2E2E2);
const _verde = Color(0xFF4ADE80);
const _ambar = Color(0xFFFBBF24);

TextStyle _letra({double size = 14, bool negrita = false, Color? color}) =>
    GoogleFonts.outfit(
      fontSize: size,
      fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
      color: color ?? _perla,
    );

/// La ventana "Sumar un celular": prende la central de la puerta en esta
/// notebook y muestra el QR que abre la lista en el celular, la dirección y el
/// código por si el QR no anda, y quiénes están conectados.
class VentanaSumarCelular extends ConsumerStatefulWidget {
  const VentanaSumarCelular({super.key, required this.eventoId});
  final String eventoId;

  static Future<void> abrir(BuildContext context, String eventoId) =>
      showDialog<void>(
        context: context,
        builder: (_) => VentanaSumarCelular(eventoId: eventoId),
      );

  @override
  ConsumerState<VentanaSumarCelular> createState() =>
      _VentanaSumarCelularState();
}

class _VentanaSumarCelularState extends ConsumerState<VentanaSumarCelular> {
  var _prendiendo = true;

  /// SUMAR AL LOCUTOR abierto (28-nov-2026).
  var _locutor = false;

  @override
  void initState() {
    super.initState();
    // Después de dibujar: prenderla cambia la central, y eso no se puede
    // mientras se arma la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prender();
    });
  }

  Future<void> _prender() async {
    // La central es una sola: prenderla para esta fiesta apaga la de la otra, y
    // sus celulares quedan afuera hasta escanear de nuevo. Hasta la 6.8.0 pasaba
    // con solo abrir esta ventana con otro evento elegido (revisión del 13-nov).
    final estado = ref.read(centralDeLaPuertaProvider);
    if (estado.prendida &&
        estado.eventoId != null &&
        estado.eventoId != widget.eventoId) {
      final pasarla = await _preguntarPorLaOtra(estado);
      if (!mounted) return;
      if (pasarla != true) {
        Navigator.pop(context);
        return;
      }
    }
    setState(() => _prendiendo = true);
    await ref.read(centralDeLaPuertaProvider.notifier).prender(widget.eventoId);
    if (mounted) setState(() => _prendiendo = false);
  }

  String _nombreDe(String eventoId) {
    final eventos = ref.read(eventosActivosProvider).value ?? const <Evento>[];
    for (final e in eventos) {
      if (e.id == eventoId) return etiquetaEventoRecepcion(e);
    }
    return 'otra fiesta';
  }

  Future<bool?> _preguntarPorLaOtra(EstadoCentral estado) {
    final n = estado.conectados;
    final conectados = switch (n) {
      0 => 'Ahora no tiene ningún celular conectado.',
      1 => 'Tiene 1 celular conectado.',
      _ => 'Tiene $n celulares conectados.',
    };
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const Key('celulares_de_otra_fiesta'),
        title: const Text('Los celulares están con otra fiesta'),
        content: Text(
          'La central de los celulares está prendida para:\n'
          '${_nombreDe(estado.eventoId!)}\n'
          '$conectados\n\n'
          'Si la pasás a:\n'
          '${_nombreDe(widget.eventoId)}\n'
          'los celulares de la otra se desconectan y tienen que escanear el '
          'QR de nuevo.',
        ),
        actions: [
          TextButton(
            key: const Key('celulares_dejarla'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('DEJARLA COMO ESTÁ'),
          ),
          FilledButton(
            key: const Key('celulares_pasarla'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PASARLA A ESTA'),
          ),
        ],
      ),
    );
  }

  Future<void> _cambiarCodigo() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar el código'),
        content: const Text(
          'Los celulares conectados se desconectan y tienen que volver a '
          'escanear el QR. Sirve si se perdió un celular o alguien que no '
          'tenía que entrar tiene el código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CAMBIAR'),
          ),
        ],
      ),
    );
    if (si == true) {
      await ref.read(centralDeLaPuertaProvider.notifier).cambiarCodigo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(centralDeLaPuertaProvider);
    return Dialog(
      backgroundColor: const Color(0xFF1B1B20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Oswald, la que viene con la app (la del tótem): anda sin
              // internet.
              const Text(
                'SUMAR UN CELULAR',
                style: TextStyle(
                  fontFamily: 'TotemCartelera',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _perla,
                ),
              ),
              const SizedBox(height: 14),
              _contenido(estado),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Solo con el QR a la vista: sin router no hay código que
                  // cambiar.
                  if (estado.eventoId == widget.eventoId &&
                      estado.enlace != null)
                    TextButton(
                      onPressed: _cambiarCodigo,
                      child: Text(
                        'Cambiar el código (desconecta a todos)',
                        style: _letra(size: 12, color: Colors.white54),
                      ),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _perla,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text('CERRAR', style: _letra(size: 12, negrita: true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenido(EstadoCentral estado) {
    if (_prendiendo && !(estado.prendida && estado.eventoId == widget.eventoId)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _perla)),
      );
    }
    if (estado.error != null) {
      return _aviso(estado.error!, reintentar: true);
    }
    if (estado.enlace == null) {
      return _aviso(
        'Esta PC no está conectada a ningún router. Conectala al wifi del '
        'router (o con un cable) y tocá PROBAR DE NUEVO.',
        reintentar: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: QrImageView(
                data: estado.enlace!,
                version: QrVersions.auto,
                size: 190,
                padding: EdgeInsets.zero,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _instrucciones(estado),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
        const SizedBox(height: 10),
        _conectados(estado.puestos),
        // El locutor (28-nov-2026): solo en un evento masivo, con su propio QR.
        if (ref.watch(eventoMasivoProvider(widget.eventoId)) == true && estado.enlaceLocutor != null) ...[
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 6),
          _elLocutor(estado),
        ],
      ],
    );
  }

  Widget _elLocutor(EstadoCentral estado) {
    if (!_locutor) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('sumar_al_locutor'),
          onPressed: () => setState(() => _locutor = true),
          icon: const Icon(Icons.mic_none, color: _perla),
          label: Text(
            estado.locutores > 0 ? 'SUMAR AL LOCUTOR · conectado' : 'SUMAR AL LOCUTOR',
            style: _letra(size: 13, negrita: true),
          ),
        ),
      );
    }
    return Column(
      key: const Key('locutor_qr'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('EL LOCUTOR', style: _letra(size: 14, negrita: true)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: QrImageView(
                data: estado.enlaceLocutor!,
                version: QrVersions.auto,
                size: 150,
                padding: EdgeInsets.zero,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ve la lista de la noche con cómo nombrar a cada uno, y lo que cambien en '
                    'CÓMO LO NOMBRAN le llega solo. No puede ingresar a nadie ni cambiar nada.',
                    key: const Key('locutor_solo_mira'),
                    style: _letra(size: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Su celular: en el wifi del router; el bloqueo automático en "Nunca"; sin pestaña '
                    'privada; con "Cambiar a datos móviles" (o "Asistencia para Wi-Fi") apagado.',
                    style: _letra(size: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: _letra(size: 13, color: Colors.white60),
                      children: [
                        const TextSpan(text: 'Sin QR: '),
                        TextSpan(text: '${estado.direccion}/?locutor', style: _letra(size: 14, negrita: true)),
                        const TextSpan(text: ' y el código '),
                        TextSpan(text: estado.codigoLocutor, style: _letra(size: 16, negrita: true)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    estado.locutores > 0 ? 'El locutor está conectado.' : 'Todavía no se conectó.',
                    key: const Key('locutor_conectado'),
                    style: _letra(size: 13, negrita: estado.locutores > 0),
                  ),
                  TextButton(
                    key: const Key('locutor_cambiar_codigo'),
                    onPressed: () => ref.read(centralDeLaPuertaProvider.notifier).cambiarCodigoLocutor(),
                    child: Text(
                      'Cambiar el código del locutor (lo desconecta)',
                      style: _letra(size: 12, color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _instrucciones(EstadoCentral estado) {
    final otras = estado.direcciones.skip(1).map((d) => '$d:${estado.puerto}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: _letra(size: 14),
            children: [
              const TextSpan(text: '1. El celular, en el '),
              TextSpan(
                text: 'wifi del router',
                style: _letra(size: 14, negrita: true),
              ),
              const TextSpan(text: ', el mismo de esta PC.'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('2. Abrí la cámara y apuntá al QR.', style: _letra(size: 14)),
        const SizedBox(height: 12),
        Text(
          '¿No lee el QR? En el navegador escribí',
          style: _letra(size: 13, color: Colors.white60),
        ),
        SelectableText(
          estado.direccion!,
          style: _letra(size: 20, negrita: true),
        ),
        Text.rich(
          TextSpan(
            style: _letra(size: 13, color: Colors.white60),
            children: [
              const TextSpan(text: 'y el código '),
              TextSpan(
                text: estado.codigo,
                style: _letra(size: 18, negrita: true),
              ),
            ],
          ),
        ),
        if (otras.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Si no conecta, probá con ${otras.join(' o ')}',
            style: _letra(size: 12, color: Colors.white54),
          ),
        ],
      ],
    );
  }

  Widget _conectados(List<PuestoConectado> puestos) {
    if (puestos.isEmpty) {
      return Text(
        'Todavía no hay celulares conectados.',
        style: _letra(size: 13, color: Colors.white54),
      );
    }
    final ahora = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conectados ahora', style: _letra(size: 12, color: Colors.white54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            for (final p in puestos)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.conectado ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: p.conectado ? _verde : Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    p.conectado
                        ? '${p.nombre} · ${_marcados(p.marcados)}'
                        : '${p.nombre} · sin señal ${_hace(ahora.difference(p.ultimaVez))}',
                    style: _letra(
                      size: 13,
                      color: p.conectado ? _perla : Colors.white54,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static String _marcados(int n) => n == 1 ? '1 marcado' : '$n marcados';

  /// "hace un rato", "hace 3 min", "hace 1 h".
  static String _hace(Duration d) {
    if (d.inMinutes < 1) return 'hace un rato';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    return 'hace ${d.inHours} h';
  }

  Widget _aviso(String texto, {bool reintentar = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: _ambar, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(texto, style: _letra(size: 14))),
              ],
            ),
            if (reintentar) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _prender,
                  style: FilledButton.styleFrom(
                    backgroundColor: _perla,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    'PROBAR DE NUEVO',
                    style: _letra(size: 12, negrita: true, color: Colors.black),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}
