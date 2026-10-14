import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/sin_internet_provider.dart';
import '../services/lista_sin_internet.dart';

/// La línea de Recepción debajo de "312 de 1.100 adentro": si esta PC está
/// lista para trabajar sin internet, qué le falta o, sin internet, con qué se
/// está trabajando y cuántos ingresos esperan subir. Tocándola se ve el
/// detalle (sección 5 de la 6.0.0, la opción A de la maqueta).
///
/// Lo que dice lo decide [EstadoSinInternet]; cuándo se pone al día,
/// [PuestaAlDiaPuerta].
class LineaSinInternet extends ConsumerStatefulWidget {
  final String eventoId;

  /// Cuántas personas tiene la lista del evento en esta PC.
  final int personas;

  /// Cuántos entraron: cuando cambia, se cuenta de nuevo lo que espera subir.
  final int adentro;

  const LineaSinInternet({
    super.key,
    required this.eventoId,
    required this.personas,
    required this.adentro,
  });

  @override
  ConsumerState<LineaSinInternet> createState() => _LineaSinInternetState();
}

class _LineaSinInternetState extends ConsumerState<LineaSinInternet> {
  static const _verde = Color(0xFF4ADE80);
  static const _ambar = Color(0xFFFBBF24);

  bool _abierta = false;

  @override
  void didUpdateWidget(covariant LineaSinInternet old) {
    super.didUpdateWidget(old);
    if (old.adentro != widget.adentro) {
      ref.read(puestaAlDiaProvider(widget.eventoId)).recontar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final puesta = ref.watch(puestaAlDiaProvider(widget.eventoId));
    return ListenableBuilder(
      listenable: puesta,
      builder: (context, _) {
        final e = EstadoSinInternet.de(
          puesta.datos,
          personas: widget.personas,
          ahora: puesta.accesos.ahora(),
        );
        return _linea(e);
      },
    );
  }

  Widget _linea(EstadoSinInternet e) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final (color, icono) = switch (e.tipo) {
      TipoSinInternet.lista => (
          oscuro ? _verde : const Color(0xFF15803D),
          Icons.check_circle_outline_rounded,
        ),
      TipoSinInternet.falta => (
          oscuro ? _ambar : const Color(0xFF92400E),
          Icons.warning_amber_rounded,
        ),
      TipoSinInternet.sinInternet => (
          oscuro ? Colors.white70 : Colors.black87,
          Icons.wifi_off_rounded,
        ),
      TipoSinInternet.sinLista => (
          oscuro ? _ambar : const Color(0xFF92400E),
          Icons.wifi_off_rounded,
        ),
    };
    final fondo = e.tipo == TipoSinInternet.sinInternet
        ? (oscuro ? Colors.white : Colors.black).withValues(alpha: 0.06)
        : (e.tipo == TipoSinInternet.lista ? _verde : _ambar)
            .withValues(alpha: 0.12);
    TextStyle letra(double size, {Color? c}) =>
        GoogleFonts.outfit(fontSize: size, color: c ?? color);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: fondo,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _abierta = !_abierta),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(icono, size: 17, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.texto, style: letra(13))),
                    Icon(
                      _abierta
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: color.withValues(alpha: color.a * 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_abierta)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: oscuro ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Column(
                children: [
                  for (final (clave, valor) in e.detalle)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              clave,
                              style: letra(12,
                                  c: oscuro ? Colors.white54 : Colors.black54),
                            ),
                          ),
                          Text(
                            valor,
                            style: letra(12,
                                c: oscuro ? Colors.white : Colors.black87),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
