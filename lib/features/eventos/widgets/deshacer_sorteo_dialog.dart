import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../services/ultimos_sorteados.dart';

/// Qué se deshace del sorteo de mesas.
enum AlcanceDeshacer {
  /// Solo las familias del último sorteo: vuelven a como estaban antes de él.
  ultimos,

  /// Todas las mesas de la institución.
  todo,
}

/// Pregunta qué se deshace y pide la confirmación. `null` si se cancela.
///
/// Con [ultimos] y alguien que conservaría su mesa, ofrece "Solo los últimos
/// sorteados" (que viene elegido: es lo que menos borra) o "Todo". Si no hay
/// diferencia entre los dos, es el aviso de siempre.
///
/// [adentroEnLaPuerta] es cuántas personas de esta fiesta están marcadas como
/// adentro en Recepción. Al deshacer todo, la lista de la puerta se vacía y
/// esos ingresos se van con ella: el aviso lo dice con el número.
Future<AlcanceDeshacer?> mostrarDeshacerSorteoDialog({
  required BuildContext context,
  required int conMesa,
  UltimosSorteados? ultimos,
  int adentroEnLaPuerta = 0,
}) =>
    showDialog<AlcanceDeshacer>(
      context: context,
      builder: (context) => DeshacerSorteoDialog(
        conMesa: conMesa,
        ultimos: ultimos,
        adentroEnLaPuerta: adentroEnLaPuerta,
      ),
    );

class DeshacerSorteoDialog extends StatefulWidget {
  /// Cuántos alumnos tienen mesa hoy: los que pierde "Todo".
  final int conMesa;
  final UltimosSorteados? ultimos;

  /// Cuántos están marcados como adentro en Recepción (ver
  /// [mostrarDeshacerSorteoDialog]).
  final int adentroEnLaPuerta;

  const DeshacerSorteoDialog({
    super.key,
    required this.conMesa,
    this.ultimos,
    this.adentroEnLaPuerta = 0,
  });

  @override
  State<DeshacerSorteoDialog> createState() => _DeshacerSorteoDialogState();
}

class _DeshacerSorteoDialogState extends State<DeshacerSorteoDialog> {
  static const _copia = 'Antes se guarda una copia: si fue un error, se vuelve '
      'atrás desde SORTEO → "Restaurar sorteo anterior".';

  final _lista = ScrollController();
  late AlcanceDeshacer _alcance;
  var _entendido = false;

  /// Deshacer solo a los últimos deja a alguien con su mesa.
  bool get _sePuedeSolos => widget.ultimos?.deshacerSoloCambiaAlgo ?? false;

  /// Hay un último sorteo aparte del resto, pero todos los suyos cambiaron de
  /// mesa después: la opción se muestra apagada, con el motivo.
  bool get _soloApagado {
    final u = widget.ultimos;
    return u != null &&
        u.aGuardar.isEmpty &&
        u.noSeTocan.isNotEmpty &&
        u.otrosConMesa > 0;
  }

  @override
  void initState() {
    super.initState();
    _alcance = _sePuedeSolos ? AlcanceDeshacer.ultimos : AlcanceDeshacer.todo;
  }

  @override
  void dispose() {
    _lista.dispose();
    super.dispose();
  }

  static String _familias(int n) => n == 1 ? '1 familia' : '$n familias';

  String _deCual(UltimosSorteados u) {
    final r = u.sorteo;
    final cuando = ArTime.formatFechaHora(r.createdAt);
    final que = r.tipo == TipoRegistroSorteo.restaurar
        ? 'restaurado el $cuando'
        : 'sorteo del $cuando';
    final quien = r.hechoPor?.trim().isNotEmpty == true ? ' · ${r.hechoPor}' : '';
    return '$que$quien';
  }

  Widget _renglon(String nombre, String detalle, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(nombre, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Text(
                detalle,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
          ],
        ),
      );

  List<Widget> _detalleUltimos(BuildContext context, UltimosSorteados u) {
    final tema = Theme.of(context);
    final ids = u.aGuardar.keys.toList()
      ..sort((a, b) => (u.nombres[a] ?? '').compareTo(u.nombres[b] ?? ''));
    final renglones = [
      for (final id in ids)
        _renglon(
          u.nombres[id] ?? '',
          '${u.tenian[id]} → ${u.aGuardar[id] ?? 'sin mesa'}',
        ),
      for (final f in u.noSeTocan)
        _renglon(
          f.nombre,
          'No se toca: ${f.motivo}.',
          color: tema.colorScheme.onSurfaceVariant,
        ),
    ];
    return [
      Text('Cómo queda cada uno', style: tema.textTheme.labelLarge),
      const SizedBox(height: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: Scrollbar(
          controller: _lista,
          thumbVisibility: renglones.length > 6,
          child: SingleChildScrollView(
            controller: _lista,
            child: Column(
              key: const Key('deshacer_detalle'),
              children: renglones,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'A nadie más se le toca la mesa.\n\n$_copia',
        style: tema.textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _detalleTodo() => [
        Text(
          'Se van a borrar los números de mesa de ${widget.conMesa} alumno(s) '
          'de esta institución, incluidas las asignaciones a mano y las de '
          'alumnos de baja.\n\n'
          'Recepción y el tótem dejan de mostrar a esta institución: su lista '
          'de la puerta se vacía.\n\n$_copia',
        ),
        if (widget.adentroEnLaPuerta > 0) ...[
          const SizedBox(height: 10),
          Text(
            widget.adentroEnLaPuerta == 1
                ? 'Hay 1 persona marcada como adentro en Recepción: ese '
                    'ingreso se pierde con la lista.'
                : 'Hay ${widget.adentroEnLaPuerta} personas marcadas como '
                    'adentro en Recepción: esos ingresos se pierden con la '
                    'lista.',
            key: const Key('deshacer_adentro'),
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('deshacer_entendido'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Entiendo que se borran los números sorteados'),
          value: _entendido,
          onChanged: (v) => setState(() => _entendido = v == true),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final u = widget.ultimos;
    final parcial = _alcance == AlcanceDeshacer.ultimos;
    final hayOpciones = _sePuedeSolos || _soloApagado;
    return AlertDialog(
      title: const Text('Deshacer sorteo de mesas'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hayOpciones) ...[
                RadioGroup<AlcanceDeshacer>(
                  groupValue: _alcance,
                  onChanged: (v) => setState(() => _alcance = v ?? _alcance),
                  child: Column(
                    children: [
                      RadioListTile<AlcanceDeshacer>(
                        key: const Key('deshacer_ultimos'),
                        value: AlcanceDeshacer.ultimos,
                        enabled: _sePuedeSolos,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Solo los últimos sorteados'),
                        subtitle: Text(
                          _sePuedeSolos
                              ? '${_familias(u!.familias.length)} · '
                                  '${_deCual(u)}'
                              : 'Las ${_familias(u!.familias.length)} de ese '
                                  'sorteo cambiaron de mesa después: no hay '
                                  'nada para deshacer solo de ellas.',
                        ),
                      ),
                      RadioListTile<AlcanceDeshacer>(
                        key: const Key('deshacer_todo'),
                        value: AlcanceDeshacer.todo,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Todo'),
                        subtitle: Text(
                          'Las ${_familias(widget.conMesa)} con mesa, también '
                          'las asignadas a mano y las de baja.',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
              ],
              if (parcial) ..._detalleUltimos(context, u!) else ..._detalleTodo(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          key: const Key('deshacer_confirmar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: parcial || _entendido
              ? () => Navigator.pop(context, _alcance)
              : null,
          child: Text(
            parcial
                ? 'DESHACER A ${_familias(u!.aGuardar.length).toUpperCase()}'
                : 'DESHACER MESAS',
          ),
        ),
      ],
    );
  }
}
