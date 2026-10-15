import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/clave_totem.dart';

/// "En otra pantalla, por el navegador", al pie de Personalizar tótem
/// (sección 8 de la 6.0.0).
///
/// El tótem por el navegador (`?totem`, para una tele con navegador) lee la
/// lista con la clave del tótem, que va en el link. Hasta la 6.0.0 ese link no
/// se ofrecía en ningún lado; ahora se copia de acá. La clave sale de la nube:
/// sin internet y sin haberla pedido antes, no hay link.
class LinkTotemNavegador extends StatefulWidget {
  final String eventoId;

  /// La dirección de la web (`kWebBaseUrl`).
  final String base;

  /// La clave del tótem del evento (`ClaveTotem.de`). Null si no se pudo.
  final Future<String?> Function() pedirClave;

  const LinkTotemNavegador({
    super.key,
    required this.eventoId,
    required this.base,
    required this.pedirClave,
  });

  static const titulo = 'En otra pantalla, por el navegador';
  static const explicacion =
      'Necesita internet. Sin el link con la clave, el tótem del navegador no '
      'muestra a nadie.';
  static const sinInternet = 'Para armar el link hace falta internet.';
  static const copiar = 'COPIAR LINK';
  static const copiado = 'COPIADO';
  static const reintentar = 'PROBAR DE NUEVO';

  @override
  State<LinkTotemNavegador> createState() => _LinkTotemNavegadorState();
}

class _LinkTotemNavegadorState extends State<LinkTotemNavegador> {
  static const _gold = Color(0xFFD4AF37);

  String? _link;
  bool _buscando = true;
  bool _copiado = false;
  Timer? _volver;

  @override
  void initState() {
    super.initState();
    _armar();
  }

  @override
  void dispose() {
    _volver?.cancel();
    super.dispose();
  }

  Future<void> _armar() async {
    setState(() => _buscando = true);
    String? clave;
    try {
      clave = await widget.pedirClave();
    } catch (e) {
      debugPrint('No se pudo armar el link del tótem: $e');
    }
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _link = clave == null || clave.isEmpty
          ? null
          : linkDelTotemWeb(
              base: widget.base,
              eventoId: widget.eventoId,
              clave: clave,
            );
    });
  }

  Future<void> _copiar() async {
    final link = _link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _copiado = true);
    _volver?.cancel();
    _volver = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    final debajo = _buscando
        ? '…'
        : link ?? LinkTotemNavegador.sinInternet;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tv_rounded, color: _gold.withValues(alpha: 0.9)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      LinkTotemNavegador.titulo,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      debajo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_buscando)
                TextButton.icon(
                  onPressed: link == null ? _armar : _copiar,
                  style: TextButton.styleFrom(foregroundColor: _gold),
                  icon: Icon(
                    link == null
                        ? Icons.refresh_rounded
                        : _copiado
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    link == null
                        ? LinkTotemNavegador.reintentar
                        : _copiado
                            ? LinkTotemNavegador.copiado
                            : LinkTotemNavegador.copiar,
                    style: const TextStyle(fontSize: 12, letterSpacing: 1),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            LinkTotemNavegador.explicacion,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
