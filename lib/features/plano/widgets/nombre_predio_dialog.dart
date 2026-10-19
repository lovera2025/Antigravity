import 'package:flutter/material.dart';

import '../../../models/predio.dart';
import '../services/predios_del_salon.dart';

/// GUARDAR COMO PREDIO… y Renombrar (6.1.0): pide el nombre del predio.
/// Devuelve el nombre escrito, o null si se cancela.
///
/// Al guardar, los chips de los ya guardados ponen su nombre: guardar con un
/// nombre que ya está lo reemplaza, y se avisa antes. Al renombrar no hay
/// chips, y un nombre de otro predio no se acepta.
///
/// No lee ni guarda nada: así se prueba sin base.
Future<String?> pedirNombreDePredio({
  required BuildContext context,
  required List<Predio> guardados,
  String sugerido = '',
  Predio? renombrando,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => NombrePredioDialog(
        guardados: guardados,
        sugerido: sugerido,
        renombrando: renombrando,
      ),
    );

class NombrePredioDialog extends StatefulWidget {
  final List<Predio> guardados;
  final String sugerido;

  /// El que se renombra. Null: se guarda uno, nuevo o reemplazando.
  final Predio? renombrando;

  const NombrePredioDialog({
    super.key,
    required this.guardados,
    this.sugerido = '',
    this.renombrando,
  });

  @override
  State<NombrePredioDialog> createState() => _NombrePredioDialogState();
}

class _NombrePredioDialogState extends State<NombrePredioDialog> {
  late final _nombre = TextEditingController(
    text: widget.renombrando?.nombre ?? widget.sugerido,
  );

  bool get _renombrando => widget.renombrando != null;

  /// Hasta que se escribe algo, no se dice que falta el nombre.
  bool _tocado = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  String? get _problema => PrediosDelSalon.problemaDelNombre(
        _nombre.text,
        widget.guardados,
        exceptoId: widget.renombrando?.id,
        renombrando: _renombrando,
      );

  Predio? get _reemplaza => _renombrando
      ? null
      : PrediosDelSalon.conElNombre(_nombre.text, widget.guardados);

  void _listo() {
    if (_problema != null) {
      setState(() => _tocado = true);
      return;
    }
    Navigator.of(context).pop(PrediosDelSalon.limpiar(_nombre.text));
  }

  @override
  Widget build(BuildContext context) {
    final problema = _problema;
    final reemplaza = _reemplaza;
    final gris = TextStyle(color: Colors.grey.shade700, fontSize: 13);
    final guardados = [
      for (final p in widget.guardados)
        if (!p.borrado) p,
    ];
    final (texto, color) = problema != null
        ? (_tocado || _nombre.text.trim().isNotEmpty ? problema : null,
            Colors.red.shade700)
        : reemplaza != null
            ? ('Ya hay un predio "${reemplaza.nombre}": se reemplaza por este. '
                    'Las fiestas que lo usaron no cambian.',
                Colors.orange.shade900)
            : (null, Colors.grey.shade700);
    return AlertDialog(
      title: Text(_renombrando ? 'Renombrar el predio' : 'Guardar como predio'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _renombrando
                  ? 'Cambia el nombre en la lista. Las fiestas que lo usaron no '
                      'cambian.'
                  : 'Se guarda el espacio: el playón con sus medidas, el '
                      'escenario, la pista, las barras y el Ingreso. Las mesas, '
                      'los colores y los títulos no: son de cada fiesta.',
              style: gris,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('nombre_predio'),
              controller: _nombre,
              autofocus: true,
              maxLength: PrediosDelSalon.largoMaximo,
              decoration: const InputDecoration(
                labelText: 'Nombre del predio',
                hintText: 'Buena Vista',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => setState(() => _tocado = true),
              onSubmitted: (_) => _listo(),
            ),
            if (!_renombrando && guardados.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('O reemplazá uno guardado:', style: gris),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in guardados)
                    ActionChip(
                      key: Key('chip_predio_${p.id}'),
                      label: Text(p.nombre),
                      onPressed: () => setState(() {
                        _nombre.text = p.nombre;
                        _tocado = true;
                      }),
                    ),
                ],
              ),
            ],
            if (texto != null) ...[
              const SizedBox(height: 10),
              Text(
                texto,
                key: const Key('aviso_nombre_predio'),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelar_predio'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('listo_predio'),
          onPressed: problema == null ? _listo : null,
          child: Text(
            _renombrando
                ? 'RENOMBRAR'
                : reemplaza != null
                    ? 'REEMPLAZAR'
                    : 'GUARDAR',
          ),
        ),
      ],
    );
  }
}
