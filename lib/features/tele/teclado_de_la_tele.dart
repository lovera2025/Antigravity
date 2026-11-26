import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const _oro = Color(0xFFD4AF37);
const _perla = Color(0xFFE8E6F0);
const _ambar = Color(0xFFFBBF24);

/// **El teclado de la tele** (25-nov-2026): números (y, para una dirección,
/// "." y ":") que se eligen con las flechas del control y OK.
///
/// El teclado de Google TV no gira con la app: con la tele parada salía
/// acostado. Este va adentro de la pantalla, así que gira con todo
/// (`TeleGirada`). Con un teclado de verdad (la ventana de prueba, el
/// emulador) también se escribe.
class TecladoDeLaTele extends StatefulWidget {
  const TecladoDeLaTele({
    super.key,
    required this.alListo,
    required this.alCancelar,
    this.oculto = false,
    this.conPuntos = false,
    this.inicial = '',
    this.error,
    this.alEscribir,
    this.maximo = 21,
  });

  /// LISTO, con lo escrito.
  final void Function(String texto) alListo;
  final VoidCallback alCancelar;

  /// Un PIN: se ven puntos.
  final bool oculto;

  /// Una dirección (192.168.0.10:8787): con "." y ":", y VACIAR.
  final bool conPuntos;
  final String inicial;

  /// Lo que salió mal (el PIN que no es): se muestra y se borra lo escrito.
  final String? error;

  /// Cada vez que se toca una tecla.
  final VoidCallback? alEscribir;

  final int maximo;

  @override
  State<TecladoDeLaTele> createState() => _TecladoDeLaTeleState();
}

class _TecladoDeLaTeleState extends State<TecladoDeLaTele> {
  late String _texto = widget.inicial;

  @override
  void didUpdateWidget(TecladoDeLaTele old) {
    super.didUpdateWidget(old);
    // El PIN equivocado: a escribirlo de nuevo.
    if (widget.error != null && old.error != widget.error) _texto = '';
  }

  String get _permitidas => widget.conPuntos ? '0123456789.:' : '0123456789';

  void _poner(String letra) {
    if (_texto.length >= widget.maximo) return;
    setState(() => _texto += letra);
    widget.alEscribir?.call();
  }

  void _borrar() {
    if (_texto.isEmpty) return;
    setState(() => _texto = _texto.substring(0, _texto.length - 1));
    widget.alEscribir?.call();
  }

  void _vaciar() {
    setState(() => _texto = '');
    widget.alEscribir?.call();
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _borrar();
      return KeyEventResult.handled;
    }
    final c = e.character;
    if (c != null && c.length == 1 && _permitidas.contains(c)) {
      _poner(c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final escrito = widget.oculto ? '•' * _texto.length : _texto;
    Widget fila(List<Widget> teclas) => Row(
          children: [
            for (final (i, t) in teclas.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: t),
            ],
          ],
        );
    _Tecla numero(String n, {bool primera = false}) => _Tecla(
          key: ValueKey('tecla_$n'),
          texto: n,
          autofocus: primera,
          alElegir: () => _poner(n),
        );
    final borrar = _Tecla(
      key: const ValueKey('tecla_borrar'),
      icono: Icons.backspace_outlined,
      alElegir: _borrar,
    );
    final listo = _Tecla(
      key: const ValueKey('tecla_listo'),
      texto: 'LISTO',
      destacada: true,
      alElegir: () => widget.alListo(_texto),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _tecla,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('tecla_escrito'),
            height: 58,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _oro.withValues(alpha: 0.5)),
            ),
            child: Text(
              escrito.isEmpty && widget.conPuntos ? 'Vacía: la busca sola' : escrito,
              style: GoogleFonts.outfit(
                fontSize: widget.oculto ? 30 : 24,
                letterSpacing: widget.oculto ? 6 : 0,
                color: escrito.isEmpty ? Colors.white38 : _perla,
              ),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Text(widget.error!, style: GoogleFonts.outfit(fontSize: 17, color: _ambar)),
          ],
          const SizedBox(height: 12),
          fila([numero('1', primera: true), numero('2'), numero('3')]),
          const SizedBox(height: 8),
          fila([numero('4'), numero('5'), numero('6')]),
          const SizedBox(height: 8),
          fila([numero('7'), numero('8'), numero('9')]),
          const SizedBox(height: 8),
          if (widget.conPuntos) ...[
            fila([
              _Tecla(key: const ValueKey('tecla_punto'), texto: '.', alElegir: () => _poner('.')),
              numero('0'),
              _Tecla(key: const ValueKey('tecla_dos_puntos'), texto: ':', alElegir: () => _poner(':')),
            ]),
            const SizedBox(height: 8),
            fila([
              _Tecla(key: const ValueKey('tecla_vaciar'), texto: 'VACIAR', alElegir: _vaciar),
              borrar,
              listo,
            ]),
          ] else
            fila([borrar, numero('0'), listo]),
          const SizedBox(height: 8),
          _Tecla(
            key: const ValueKey('tecla_cancelar'),
            texto: 'CANCELAR',
            alElegir: widget.alCancelar,
          ),
        ],
      ),
    );
  }
}

/// Una tecla: con un borde dorado cuando el control la tiene elegida.
class _Tecla extends StatelessWidget {
  const _Tecla({
    super.key,
    this.texto,
    this.icono,
    required this.alElegir,
    this.autofocus = false,
    this.destacada = false,
  });

  final String? texto;
  final IconData? icono;
  final VoidCallback alElegir;
  final bool autofocus;
  final bool destacada;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: TextButton(
          autofocus: autofocus,
          onPressed: alElegir,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
            shape: WidgetStateProperty.resolveWith(
              (s) => RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: s.contains(WidgetState.focused)
                    ? const BorderSide(color: _oro, width: 3)
                    : BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? _oro.withValues(alpha: 0.22)
                  : destacada
                      ? _oro.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.04),
            ),
            foregroundColor: const WidgetStatePropertyAll(_perla),
          ),
          child: icono != null
              ? Icon(icono, size: 24)
              : Text(
                  texto ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: texto != null && texto!.length > 1 ? 17 : 24,
                    fontWeight: destacada ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
        ),
      );
}
