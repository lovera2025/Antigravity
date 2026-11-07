import 'package:flutter/material.dart';

import 'ticket_esc_pos.dart';

/// Un papel de la barra dibujado en la pantalla, como sale de la térmica: una tira
/// blanca con lo grande en grande, los renglones a dos columnas y las rayas. Es la misma
/// lista de líneas que va a la impresora y al PDF (`PapelPdf`), así que lo que se lee es
/// lo que sale.
///
/// Siempre blanco con letra oscura, también en el diseño Noche dorada: es papel.
class PapelEnPantalla extends StatelessWidget {
  final List<LineaTicket> lineas;

  /// El ancho de la tira. El papel de 58 mm, en una tablet, se lee bien a unos 340.
  final double ancho;

  const PapelEnPantalla(this.lineas, {super.key, this.ancho = 340});

  static const _tinta = Color(0xFF1D1B20);
  static const _chica = 14.0;
  static const _grande = 24.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x22000000)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            // Merge: conserva la letra de la app y cambia solo el color y el tamaño.
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: _tinta, fontSize: _chica, height: 1.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final l in lineas) _linea(l)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _linea(LineaTicket l) => switch (l) {
        TituloTicket() => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              l.texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: _grande, fontWeight: FontWeight.bold),
            ),
          ),
        TextoTicket() => Text(
            l.texto,
            textAlign: l.centrado ? TextAlign.center : TextAlign.left,
            style: TextStyle(fontWeight: l.negrita ? FontWeight.bold : FontWeight.normal),
          ),
        GrandeTicket() => Text(
            l.texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: l.soloAlto ? _chica * 1.5 : _grande,
              fontWeight: FontWeight.bold,
            ),
          ),
        RenglonTicket() => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l.izquierda,
                  style: TextStyle(fontWeight: l.negrita ? FontWeight.bold : FontWeight.normal),
                ),
              ),
              if (l.derecha.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    l.derecha,
                    style: TextStyle(fontWeight: l.negrita ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
            ],
          ),
        SeparadorTicket() => const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: _Raya(),
          ),
        QrTicket() => const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Icon(Icons.qr_code_2, size: 72, color: _tinta),
          ),
        LogoTicket() => const SizedBox.shrink(),
      };
}

/// La raya de guiones del papel.
class _Raya extends StatelessWidget {
  const _Raya();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) {
          const guion = 6.0, hueco = 4.0;
          final n = (c.maxWidth / (guion + hueco)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < n; i++)
                const SizedBox(
                  width: guion,
                  height: 1,
                  child: ColoredBox(color: Color(0x991D1B20)),
                ),
            ],
          );
        },
      );
}
