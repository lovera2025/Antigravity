import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/silla_puerta.dart';
import '../central/pedidos_de_la_puerta.dart' show DatosSilla;
import '../services/puerta_del_evento.dart';
import '../services/sillas_de_la_puerta.dart';

const _perla = Color(0xFFE2E2E2);
const _verde = Color(0xFF4ADE80);

TextStyle _letra(
  BuildContext context, {
  double size = 14,
  bool negrita = false,
  Color? color,
  TextDecoration? tachado,
}) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  return GoogleFonts.outfit(
    fontSize: size,
    fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
    color: color ?? (oscuro ? _perla : Colors.black87),
    decoration: tachado,
  );
}

/// Los botones, en Outfit como el panel. Sin color: el del botón.
TextStyle _boton(BuildContext context, {Color? color = _perla}) =>
    GoogleFonts.outfit(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).brightness == Brightness.dark ? color : null,
    );

/// Un campo, con la letra del panel.
InputDecoration _campo(
  BuildContext context, {
  required String etiqueta,
  String? pista,
  String? ayuda,
}) =>
    InputDecoration(
      labelText: etiqueta,
      labelStyle: _letra(context, size: 14, color: _suave(context)),
      hintText: pista,
      hintStyle: _letra(context, size: 14, color: _suave(context)),
      helperText: ayuda,
      helperStyle: _letra(context, size: 12, color: _suave(context)),
      helperMaxLines: 2,
      counterStyle: _letra(context, size: 11, color: _suave(context)),
      border: const OutlineInputBorder(),
    );

Color _suave(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : Colors.black54;

/// Sumar una silla de la noche a una familia (6.4.0): a qué mesa, el número del
/// vale de la barra (obligatorio) y una nota. La recepcionista no cobra: la
/// silla se paga en la caja de la barra, que da el vale. La misma hoja en la PC
/// y en el celular de la puerta.
class HojaSumarSilla extends StatefulWidget {
  final GrupoPuerta grupo;

  /// A nombre de quién queda: el celular o quien opera la PC.
  final String quienSoy;

  const HojaSumarSilla({super.key, required this.grupo, required this.quienSoy});

  /// Abre la hoja. Null si se canceló.
  static Future<DatosSilla?> abrir(
    BuildContext context, {
    required GrupoPuerta grupo,
    required String quienSoy,
  }) =>
      showDialog<DatosSilla>(
        context: context,
        builder: (_) => HojaSumarSilla(grupo: grupo, quienSoy: quienSoy),
      );

  @override
  State<HojaSumarSilla> createState() => _HojaSumarSillaState();
}

class _HojaSumarSillaState extends State<HojaSumarSilla> {
  final _vale = TextEditingController();
  final _nota = TextEditingController();
  final _focoVale = FocusNode();
  final _focoNota = FocusNode();
  int? _mesa;

  @override
  void initState() {
    super.initState();
    _mesa = widget.grupo.sillasPorMesa.mesaConLugar()?.numero;
  }

  @override
  void dispose() {
    _vale.dispose();
    _nota.dispose();
    _focoVale.dispose();
    _focoNota.dispose();
    super.dispose();
  }

  bool get _listo => _mesa != null && valeNormalizado(_vale.text) != null;

  void _confirmar() {
    if (!_listo) return;
    final nota = _nota.text.trim();
    Navigator.of(context).pop(DatosSilla(
      mesa: _mesa,
      vale: _vale.text.trim(),
      nota: nota.isEmpty ? null : nota,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mesas = [
      for (final m in widget.grupo.sillasPorMesa.mesas)
        if (m.puedeAgregar) m,
    ];
    final elegida = mesas.where((m) => m.numero == _mesa).firstOrNull;
    return AlertDialog(
      title: Text(
        'Sumar una silla a ${widget.grupo.titular.nombre}',
        style: _letra(context, size: 17, negrita: true),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿A qué mesa?', style: _letra(context, size: 13, negrita: true)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in mesas)
                    ChoiceChip(
                      key: ValueKey('mesa_${m.numero}'),
                      label: Text(m.esPrincipal
                          ? 'Mesa ${m.numero}'
                          : 'Mesa ${m.numero} (adicional)'),
                      labelStyle: _letra(
                        context,
                        size: 13,
                        negrita: m.numero == _mesa,
                        color: m.numero == _mesa ? Colors.black : null,
                      ),
                      selected: m.numero == _mesa,
                      selectedColor: _perla,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _mesa = m.numero),
                    ),
                ],
              ),
              if (elegida != null) ...[
                const SizedBox(height: 6),
                Text(
                  elegida.lugar == 1
                      ? 'Le queda 1 en esa mesa.'
                      : 'Le quedan ${elegida.lugar} en esa mesa.',
                  style: _letra(context, size: 12, color: _suave(context)),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('vale'),
                controller: _vale,
                focusNode: _focoVale,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                textInputAction: TextInputAction.next,
                style: _letra(context, size: 16),
                decoration: _campo(
                  context,
                  etiqueta: 'Número del vale',
                  pista: 'Caja y número: 2 0017',
                  ayuda:
                      'La silla se cobra en la caja de la barra: pedí el vale.',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _focoNota.requestFocus(),
                onTapOutside: kIsWeb ? (_) {} : null,
                onTapUpOutside: kIsWeb ? (_) => _focoVale.unfocus() : null,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('nota'),
                controller: _nota,
                focusNode: _focoNota,
                maxLength: 120,
                style: _letra(context, size: 14),
                decoration: _campo(context, etiqueta: 'Nota (si hace falta)'),
                onSubmitted: (_) => _confirmar(),
                onTapOutside: kIsWeb ? (_) {} : null,
                onTapUpOutside: kIsWeb ? (_) => _focoNota.unfocus() : null,
              ),
              Text(
                'Queda anotada a nombre de ${widget.quienSoy}.',
                style: _letra(context, size: 12, color: _suave(context)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCELAR', style: _boton(context)),
        ),
        FilledButton(
          key: const ValueKey('confirmar_silla'),
          onPressed: _listo ? _confirmar : null,
          style: FilledButton.styleFrom(
            backgroundColor: _verde,
            foregroundColor: Colors.black,
          ),
          child: Text('CONFIRMAR', style: _boton(context, color: null)),
        ),
      ],
    );
  }
}

/// Quitar una silla sumada esa noche: el motivo es obligatorio, y la línea queda
/// tachada con quién y por qué. Devuelve el motivo, o null si se canceló.
class HojaQuitarSilla extends StatefulWidget {
  final SillaPuerta silla;
  final String nombre;

  const HojaQuitarSilla({super.key, required this.silla, required this.nombre});

  static Future<String?> abrir(
    BuildContext context, {
    required SillaPuerta silla,
    required String nombre,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => HojaQuitarSilla(silla: silla, nombre: nombre),
      );

  @override
  State<HojaQuitarSilla> createState() => _HojaQuitarSillaState();
}

class _HojaQuitarSillaState extends State<HojaQuitarSilla> {
  final _motivo = TextEditingController();
  final _foco = FocusNode();

  @override
  void dispose() {
    _motivo.dispose();
    _foco.dispose();
    super.dispose();
  }

  bool get _listo => _motivo.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          'Quitar una silla de ${widget.nombre}',
          style: _letra(context, size: 17, negrita: true),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                textoSillaSumada(widget.silla),
                style: _letra(context, size: 13, color: _suave(context)),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('motivo'),
                controller: _motivo,
                focusNode: _foco,
                autofocus: true,
                maxLength: 120,
                style: _letra(context, size: 15),
                decoration: _campo(
                  context,
                  etiqueta: '¿Por qué se quita?',
                  ayuda: 'La silla queda en la lista, tachada, con quién y por '
                      'qué.',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_listo) Navigator.of(context).pop(_motivo.text.trim());
                },
                onTapOutside: kIsWeb ? (_) {} : null,
                onTapUpOutside: kIsWeb ? (_) => _foco.unfocus() : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCELAR', style: _boton(context)),
          ),
          FilledButton(
            key: const ValueKey('confirmar_quitar'),
            onPressed:
                _listo ? () => Navigator.of(context).pop(_motivo.text.trim()) : null,
            child: Text('QUITAR', style: _boton(context, color: null)),
          ),
        ],
      );
}
