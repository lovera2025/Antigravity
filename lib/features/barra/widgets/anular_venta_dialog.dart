import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Lo que contesta quien anula una venta de la barra: el motivo (escrito, sin marca) y
/// si el vale volvió a su mano.
typedef AnulacionPedida = ({String motivo, bool valeVolvio});

/// **Anular una venta de la barra** (28-nov-2026): el motivo, obligatorio, y **"¿Volvió
/// el vale?"** (decidido por el usuario): SÍ, LO TENGO · NO, YA SE ENTREGÓ, sin ninguna
/// marcada: hay que elegir. Con SÍ el stock vuelve (lo de siempre); con NO la plata se
/// anula igual y el stock no vuelve (`AnulacionBarra.valeVolvio`).
///
/// Sin [preguntaPorElVale] (una venta de solo sillas de la noche,
/// `AnulacionBarra.preguntaPorElVale`) no pregunta y contesta "volvió". No guarda nada:
/// guarda quien la abrió, con su llave. Null si se canceló.
Future<AnulacionPedida?> pedirAnulacion(
  BuildContext context, {
  required String titulo,
  required String explicacion,
  required bool preguntaPorElVale,
}) =>
    showDialog<AnulacionPedida>(
      context: context,
      builder: (_) => AnularVentaDialog(
        titulo: titulo,
        explicacion: explicacion,
        preguntaPorElVale: preguntaPorElVale,
      ),
    );

class AnularVentaDialog extends StatefulWidget {
  final String titulo;
  final String explicacion;
  final bool preguntaPorElVale;

  const AnularVentaDialog({
    super.key,
    required this.titulo,
    required this.explicacion,
    required this.preguntaPorElVale,
  });

  @override
  State<AnularVentaDialog> createState() => _AnularVentaDialogState();
}

class _AnularVentaDialogState extends State<AnularVentaDialog> {
  final _ctrl = TextEditingController();
  final _foco = FocusNode();

  /// Null: todavía no contestó.
  bool? _volvio;

  @override
  void dispose() {
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  bool get _hayMotivo => _ctrl.text.trim().isNotEmpty;
  bool get _contesto => !widget.preguntaPorElVale || _volvio != null;

  /// Lo que falta para poder anular, dicho en palabras (null si no falta nada).
  String? get _falta {
    if (!_hayMotivo && !_contesto) return 'Falta el motivo y decir si volvió el vale.';
    if (!_hayMotivo) return 'Falta el motivo.';
    if (!_contesto) return 'Falta decir si volvió el vale.';
    return null;
  }

  void _elegir(bool volvio) => setState(() => _volvio = volvio);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final gris = tema.hintColor;
    final falta = _falta;
    return AlertDialog(
      // "$ 10.000" no se parte en dos renglones en un celular.
      title: Text(widget.titulo.replaceAll(r'$ ', '\$ ')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.explicacion),
              const SizedBox(height: 12),
              TextField(
                key: const Key('motivo_texto'),
                controller: _ctrl,
                focusNode: _foco,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  helperText: 'Por qué: se cobró dos veces, se equivocó de bebida…',
                ),
                onChanged: (_) => setState(() {}),
                // En la web de un celular, soltar el teclado al apoyar el dedo afuera se
                // come el toque (como en `pedirMotivo`): se suelta al levantarlo.
                onTapOutside: kIsWeb ? (_) {} : null,
                onTapUpOutside: kIsWeb ? (_) => _foco.unfocus() : null,
              ),
              if (widget.preguntaPorElVale) ...[
                const SizedBox(height: 16),
                const Text(
                  '¿Volvió el vale?',
                  key: Key('anular_pregunta_vale'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  'Si lo tenés en la mano, la bebida no se entregó.',
                  style: TextStyle(fontSize: 12.5, color: gris),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('anular_vale_volvio'),
                      label: const Text('SÍ, LO TENGO'),
                      selected: _volvio == true,
                      onSelected: (_) => _elegir(true),
                    ),
                    ChoiceChip(
                      key: const Key('anular_vale_no_volvio'),
                      label: const Text('NO, YA SE ENTREGÓ'),
                      selected: _volvio == false,
                      onSelected: (_) => _elegir(false),
                    ),
                  ],
                ),
                if (_volvio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _volvio!
                          ? 'El stock vuelve: la bebida no salió.'
                          : 'La plata se anula igual, pero el stock no vuelve: lo entregado '
                              'cuenta como perdido y queda anotado con tu nombre.',
                      key: const Key('anular_que_pasa'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _volvio! ? gris : Colors.orange.shade700,
                      ),
                    ),
                  ),
              ],
              if (falta != null && (_hayMotivo || _volvio != null))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    falta,
                    key: const Key('anular_falta'),
                    style: TextStyle(fontSize: 12.5, color: gris),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(
          key: const Key('motivo_anular'),
          style: FilledButton.styleFrom(backgroundColor: colores.error, foregroundColor: colores.onError),
          onPressed: falta == null
              ? () => Navigator.pop<AnulacionPedida>(
                    context,
                    (motivo: _ctrl.text.trim(), valeVolvio: _volvio ?? true),
                  )
              : null,
          child: const Text('ANULAR'),
        ),
      ],
    );
  }
}
