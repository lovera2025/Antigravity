import 'package:flutter/material.dart';

import '../modelo/estado_plano.dart' show kLargoDeReservada;
import '../modelo/reserva_de_mesa.dart';
import 'cambio_de_mesa_dialogs.dart' show motivosParaLibre;

/// A quién se le suele reservar una mesa que no es de un alumno.
const paraQuienSeReserva = ['Profes', 'Directivos', 'Invitados de la casa'];

/// Pregunta por qué queda libre una mesa: **porque no se usa** (una columna,
/// el paso de los mozos) o **porque es para alguien** que no es alumno (los
/// profesores), con los nombres de quienes se sientan (6.5.0, pedido del jefe
/// el 10-nov: "una mesa que no es de los alumnos, para los profes").
///
/// Devuelve el motivo como se guarda en la mesa libre (vacío si no se escribió
/// nada; una reserva, como la arma [ReservaDeMesa.motivo]), o null si se
/// cancela. Con [motivoActual] abre con lo que ya tenía, para cambiarlo.
Future<String?> pedirReservaDeMesa({
  required BuildContext context,
  required int mesa,
  String? motivoActual,
  bool yaEstaLibre = false,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservaDeMesaDialog(
        mesa: mesa,
        motivoActual: motivoActual,
        yaEstaLibre: yaEstaLibre,
      ),
    );

class ReservaDeMesaDialog extends StatefulWidget {
  final int mesa;
  final String? motivoActual;

  /// La mesa ya está libre: se le cambia el motivo, no se la deja libre.
  final bool yaEstaLibre;

  const ReservaDeMesaDialog({
    super.key,
    required this.mesa,
    this.motivoActual,
    this.yaEstaLibre = false,
  });

  @override
  State<ReservaDeMesaDialog> createState() => _ReservaDeMesaDialogState();
}

class _ReservaDeMesaDialogState extends State<ReservaDeMesaDialog> {
  late bool _esParaAlguien;
  late final TextEditingController _para;
  late final TextEditingController _quienes;
  late final TextEditingController _motivo;

  @override
  void initState() {
    super.initState();
    final reserva = ReservaDeMesa.deMotivo(widget.motivoActual);
    _esParaAlguien = reserva != null;
    _para = TextEditingController(text: reserva?.para ?? '');
    _quienes = TextEditingController(text: reserva?.quienes.join('\n') ?? '');
    _motivo = TextEditingController(
      text: reserva == null ? (widget.motivoActual ?? '').trim() : '',
    );
  }

  @override
  void dispose() {
    _para.dispose();
    _quienes.dispose();
    _motivo.dispose();
    super.dispose();
  }

  bool get _listo => !_esParaAlguien || _para.text.trim().isNotEmpty;

  String get _resultado => _esParaAlguien
      ? ReservaDeMesa(
          _para.text,
          ReservaDeMesa.nombresDe(_quienes.text),
        ).motivo
      : _motivo.text.trim();

  @override
  Widget build(BuildContext context) {
    final chico = Theme.of(context).textTheme.bodySmall;
    final sugerencias = _esParaAlguien ? paraQuienSeReserva : motivosParaLibre;
    final campo = _esParaAlguien ? _para : _motivo;
    return AlertDialog(
      title: Text(
        widget.yaEstaLibre
            ? 'La mesa ${widget.mesa}, libre'
            : 'Dejar libre la mesa ${widget.mesa}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El sorteo no la va a dar a ninguna familia.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const Key('reserva_tipo'),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.block),
                    label: Text('No se usa'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.event_seat_outlined),
                    label: Text('Es para alguien'),
                  ),
                ],
                selected: {_esParaAlguien},
                onSelectionChanged: (s) =>
                    setState(() => _esParaAlguien = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _esParaAlguien
                    ? 'Para quien no es alumno: los profes, los directivos. '
                        'La mesa lleva ese nombre en el plano, sin contrato '
                        'ni pago.'
                    : 'En el plano sale tachada.',
                style: chico,
              ),
              const SizedBox(height: 12),
              TextField(
                key: Key(_esParaAlguien ? 'reserva_para' : 'motivo'),
                controller: campo,
                autofocus: true,
                maxLength: _esParaAlguien ? kLargoDeReservada : 120,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _esParaAlguien
                      ? '¿Para quién es?'
                      : '¿Por qué? (si querés)',
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in sugerencias)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => campo.text = s),
                    ),
                ],
              ),
              if (_esParaAlguien) ...[
                const SizedBox(height: 14),
                TextField(
                  key: const Key('reserva_quienes'),
                  controller: _quienes,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 600,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Quiénes se sientan (si querés)',
                    hintText: 'Uno por renglón:\nGARCÍA, ANA\nLÓPEZ, LUIS',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se ven al tocar la mesa y al pie del plano impreso.',
                  style: chico,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          // La misma clave que el botón de los demás carteles de cambio de mesa.
          key: const Key('confirmar'),
          onPressed: _listo ? () => Navigator.pop(context, _resultado) : null,
          child: Text(widget.yaEstaLibre ? 'GUARDAR' : 'DEJAR LIBRE'),
        ),
      ],
    );
  }
}
