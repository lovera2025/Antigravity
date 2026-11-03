import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/utils/cortes_pantalla.dart';
import '../cuentas/cobro_barra.dart';
import '../cuentas/pesos.dart';
import '../datos/venta_barra.dart';
import 'pesos_enteros_formatter.dart';

/// El cobro que abre EFECTIVO, TRANSFERENCIA o MIXTO: en el celular, una hoja desde
/// abajo; en la tablet y la PC, un diálogo al centro. Devuelve el cobro confirmado, o
/// null si volvió a la cuenta. Las cuentas las hace [CobroBarra].
Future<CobroBarra?> pedirCobro(
  BuildContext context, {
  required double total,
  required MedioBarra medio,
  required bool recargoPrendido,
  required double recargoPct,
}) {
  final hoja = CobrarHoja(
    total: total,
    medio: medio,
    recargoPrendido: recargoPrendido,
    recargoPct: recargoPct,
  );
  if (CortesPantalla.esCelular(MediaQuery.sizeOf(context).width)) {
    return showModalBottomSheet<CobroBarra>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => hoja,
    );
  }
  return showDialog<CobroBarra>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: hoja),
    ),
  );
}

class CobrarHoja extends StatefulWidget {
  final double total;
  final MedioBarra medio;
  final bool recargoPrendido;
  final double recargoPct;

  const CobrarHoja({
    super.key,
    required this.total,
    required this.medio,
    required this.recargoPrendido,
    required this.recargoPct,
  });

  @override
  State<CobrarHoja> createState() => _CobrarHojaState();
}

class _CobrarHojaState extends State<CobrarHoja> {
  late CobroBarra _cobro = CobroBarra.de(
    widget.total,
    medio: widget.medio,
    recargo: widget.recargoPrendido,
    recargoPct: widget.recargoPct,
  );
  final _recibe = TextEditingController();
  final _efectivo = TextEditingController();
  final _transfiere = TextEditingController();
  late final _pct = TextEditingController(text: _numero(widget.recargoPct));
  final _recargoPesos = TextEditingController();

  /// En el mixto, si ya se escribió alguna de las dos partes.
  bool _mixtoEscrito = false;

  @override
  void dispose() {
    for (final c in [_recibe, _efectivo, _transfiere, _pct, _recargoPesos]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _numero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

  void _poner(TextEditingController c, String texto) =>
      c.value = TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));

  /// Después de cambiar el recargo, en el mixto la transferencia se vuelve a mostrar con
  /// el recargo nuevo; lo que se pagó en efectivo no se toca.
  void _rehacerMixto() {
    if (_cobro.medio == MedioBarra.mixto && _mixtoEscrito) {
      _poner(_transfiere, PesosEnterosFormatter.escribir(_cobro.transfiere));
    }
  }

  void _cambiarRecargo(CobroBarra nuevo) => setState(() {
        _cobro = nuevo;
        _rehacerMixto();
      });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = _cobro;
    final titulo = switch (c.medio) {
      MedioBarra.efectivo => 'Pagar en efectivo',
      MedioBarra.transferencia => 'Pagar por transferencia',
      _ => 'Pagar mixto',
    };
    final hayTransferencia = c.medio != MedioBarra.efectivo;
    final hayEfectivo = c.medio != MedioBarra.transferencia;
    final grande = tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: tema.textTheme.titleLarge)),
              Text('Total ${pesos(c.total)}', key: const Key('cobro_total')),
            ],
          ),
          const SizedBox(height: 12),
          if (c.medio == MedioBarra.mixto) ...[
            _Plata(
              key: const Key('cobro_mixto_efectivo'),
              etiqueta: 'En efectivo',
              controller: _efectivo,
              onChanged: (v) => setState(() {
                _mixtoEscrito = true;
                _cobro = c.conEfectivoDelMixto((v ?? 0).toDouble());
                _poner(_transfiere, v == null ? '' : PesosEnterosFormatter.escribir(_cobro.transfiere));
              }),
            ),
            const SizedBox(height: 10),
            _Plata(
              key: const Key('cobro_mixto_transferencia'),
              etiqueta: 'Por transferencia',
              ayuda: c.recargo > 0 ? '${pesos(c.transferencia)} + recargo ${pesos(c.recargo)}' : null,
              controller: _transfiere,
              onChanged: (v) => setState(() {
                _mixtoEscrito = true;
                _cobro = c.conTransfiereDelMixto((v ?? 0).toDouble());
                _poner(_efectivo, v == null ? '' : PesosEnterosFormatter.escribir(_cobro.efectivo));
              }),
            ),
            const SizedBox(height: 10),
          ],
          if (hayTransferencia) ...[
            _Recargo(
              cobro: c,
              pct: _pct,
              pesosCtrl: _recargoPesos,
              alCambiar: _cambiarRecargo,
            ),
            const SizedBox(height: 10),
          ],
          if (c.medio == MedioBarra.transferencia)
            Row(
              children: [
                const Expanded(child: Text('Transfiere')),
                Text(pesos(c.transfiere), key: const Key('cobro_transfiere'), style: grande),
              ],
            ),
          if (hayEfectivo) ...[
            _Plata(
              key: const Key('cobro_recibe'),
              etiqueta: 'Recibe',
              ayuda: 'Vacío: paga justo',
              controller: _recibe,
              onChanged: (v) => setState(() => _cobro = c.conRecibe(v?.toDouble())),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Vuelto')),
                Text(
                  c.vuelto == null ? '—' : pesos(c.vuelto!),
                  key: const Key('cobro_vuelto'),
                  style: grande,
                ),
              ],
            ),
          ],
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(child: Text('A cobrar', style: TextStyle(fontWeight: FontWeight.bold))),
              Text(pesos(c.aCobrar), key: const Key('cobro_a_cobrar'), style: grande),
            ],
          ),
          if (c.falta != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.falta!,
                key: const Key('cobro_falta'),
                style: TextStyle(color: tema.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                key: const Key('cobro_volver'),
                onPressed: () => Navigator.pop(context),
                child: const Text('VOLVER'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('cobro_confirmar'),
                onPressed: c.puedeConfirmar ? () => Navigator.pop(context, c) : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una casilla de plata: el "$" puesto y los puntos al escribir, en pesos enteros.
class _Plata extends StatelessWidget {
  final String etiqueta;
  final String? ayuda;
  final TextEditingController controller;
  final ValueChanged<int?> onChanged;

  const _Plata({
    super.key,
    required this.etiqueta,
    this.ayuda,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: const [PesosEnterosFormatter()],
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          prefixText: r'$ ',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (t) => onChanged(PesosEnterosFormatter.leer(t)),
      );
}

/// El check del recargo por transferencia, por % o en $.
class _Recargo extends StatelessWidget {
  final CobroBarra cobro;
  final TextEditingController pct;
  final TextEditingController pesosCtrl;
  final ValueChanged<CobroBarra> alCambiar;

  const _Recargo({
    required this.cobro,
    required this.pct,
    required this.pesosCtrl,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final c = cobro;
    final porPct = c.modoRecargo == ModoRecargo.porcentaje;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: const Key('cobro_recargo'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: c.recargoPrendido,
            title: const Text('Recargo por transferencia'),
            onChanged: (v) => alCambiar(c.conRecargo(v ?? false)),
          ),
          if (c.recargoPrendido)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<ModoRecargo>(
                    key: const Key('cobro_recargo_modo'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ModoRecargo.porcentaje, label: Text('%')),
                      ButtonSegment(value: ModoRecargo.pesos, label: Text(r'$')),
                    ],
                    selected: {c.modoRecargo},
                    onSelectionChanged: (s) => alCambiar(c.conModoRecargo(s.first)),
                  ),
                  SizedBox(
                    width: porPct ? 90 : 140,
                    child: porPct
                        ? TextField(
                            key: const Key('cobro_recargo_pct'),
                            controller: pct,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(suffixText: '%', isDense: true),
                            onChanged: (t) => alCambiar(
                              c.conRecargoPct(double.tryParse(t.replaceAll(',', '.')) ?? 0),
                            ),
                          )
                        : TextField(
                            key: const Key('cobro_recargo_pesos'),
                            controller: pesosCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [PesosEnterosFormatter()],
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(prefixText: r'$ ', isDense: true),
                            onChanged: (t) => alCambiar(
                              c.conRecargoPesos((PesosEnterosFormatter.leer(t) ?? 0).toDouble()),
                            ),
                          ),
                  ),
                  if (c.transferencia > 0)
                    Text(
                      porPct
                          ? '${pesos(c.transferencia)} + ${_numero(c.recargoPct)} % = ${pesos(c.transfiere)}'
                          : '${pesos(c.transferencia)} + ${pesos(c.recargo)} = ${pesos(c.transfiere)}',
                      key: const Key('cobro_recargo_cuenta'),
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _numero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');
}
