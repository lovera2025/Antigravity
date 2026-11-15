import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desde cuántas hojas el historial pregunta cómo imprimir (pedido del usuario,
/// 15-nov: "imaginá 1.000 entradas"). Con menos, sale entero como siempre.
const kHojasParaPreguntar = 10;

/// De a cuántas hojas van las tandas.
const kHojasPorTanda = 10;

/// Las hojas elegidas para imprimir, de [desde] a [hasta] (desde 1).
/// [tanda]: se eligió una tanda de las de a [kHojasPorTanda].
typedef HojasElegidas = ({int desde, int hasta, bool tanda});

/// Las tandas de un papel de [hojas] hojas: (1, 10), (11, 20)…
List<({int desde, int hasta})> tandasDeHojas(int hojas, {int deA = kHojasPorTanda}) => [
      for (var d = 1; d <= hojas; d += deA)
        (desde: d, hasta: (d + deA - 1) > hojas ? hojas : d + deA - 1),
    ];

/// El cartel antes de imprimir un historial largo: **Todo junto** (las [hojas]
/// de una vez) o **Por hojas** (de a tandas, o eligiendo "de la hoja X a la Y").
/// [impresas]: las tandas que ya salieron en esta pantalla (por su primera
/// hoja), para marcarlas. Devuelve null si se cerró sin elegir.
Future<HojasElegidas?> elegirHojasParaImprimir(
  BuildContext context, {
  required int hojas,
  required int ventas,
  Set<int> impresas = const {},
}) =>
    showDialog<HojasElegidas>(
      context: context,
      builder: (_) => _ImprimirPorHojas(hojas: hojas, ventas: ventas, impresas: impresas),
    );

class _ImprimirPorHojas extends StatefulWidget {
  final int hojas;
  final int ventas;
  final Set<int> impresas;

  const _ImprimirPorHojas({required this.hojas, required this.ventas, required this.impresas});

  @override
  State<_ImprimirPorHojas> createState() => _ImprimirPorHojasState();
}

class _ImprimirPorHojasState extends State<_ImprimirPorHojas> {
  var _porHojas = true;
  final _desde = TextEditingController(text: '1');
  late final _hasta = TextEditingController(
    text: '${widget.hojas < kHojasPorTanda ? widget.hojas : kHojasPorTanda}',
  );
  String? _error;

  @override
  void dispose() {
    _desde.dispose();
    _hasta.dispose();
    super.dispose();
  }

  void _imprimirElRango() {
    final d = int.tryParse(_desde.text.trim());
    final h = int.tryParse(_hasta.text.trim());
    if (d == null || h == null || d < 1 || h > widget.hojas || d > h) {
      setState(() => _error =
          'Elegí hojas entre 1 y ${widget.hojas}, la primera antes que la última.');
      return;
    }
    Navigator.pop<HojasElegidas>(context, (desde: d, hasta: h, tanda: false));
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final secundario = TextStyle(fontSize: 13, color: Colors.grey.shade700);
    final ventas = widget.ventas == 1 ? '1 venta' : '${widget.ventas} ventas';
    return AlertDialog(
      key: const Key('hojas_cartel'),
      title: const Text('Imprimir el historial'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$ventas · ${widget.hojas} hojas', style: secundario),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const Key('hojas_solapas'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Todo junto', key: Key('hojas_todo'))),
                  ButtonSegment(value: true, label: Text('Por hojas', key: Key('hojas_por_hojas'))),
                ],
                selected: {_porHojas},
                onSelectionChanged: (s) => setState(() {
                  _porHojas = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              if (!_porHojas) ...[
                Text('Las ${widget.hojas} hojas, de una sola vez.'),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('hojas_imprimir_todo'),
                  onPressed: () => Navigator.pop<HojasElegidas>(
                    context,
                    (desde: 1, hasta: widget.hojas, tanda: false),
                  ),
                  child: Text('IMPRIMIR LAS ${widget.hojas} HOJAS'),
                ),
              ] else ...[
                Text(
                  'De a tandas, para no mandar ${widget.hojas} hojas juntas a la impresora:',
                  style: secundario,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tandasDeHojas(widget.hojas))
                      _Tanda(
                        key: Key('hojas_tanda_${t.desde}'),
                        desde: t.desde,
                        hasta: t.hasta,
                        impresa: widget.impresas.contains(t.desde),
                        onTap: () => Navigator.pop<HojasElegidas>(
                          context,
                          (desde: t.desde, hasta: t.hasta, tanda: true),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('O elegí las hojas a mano:', style: secundario),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('De la hoja'),
                    _NumeroDeHoja(clave: 'hojas_desde', controller: _desde, alCambiar: () => setState(() => _error = null)),
                    const Text('a la'),
                    _NumeroDeHoja(clave: 'hojas_hasta', controller: _hasta, alCambiar: () => setState(() => _error = null)),
                    OutlinedButton(
                      key: const Key('hojas_imprimir_rango'),
                      onPressed: _imprimirElRango,
                      child: const Text('IMPRIMIR ESAS'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    key: const Key('hojas_error'),
                    style: TextStyle(fontSize: 13, color: esquema.error),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hojas_volver'),
          onPressed: () => Navigator.pop(context),
          child: const Text('VOLVER'),
        ),
      ],
    );
  }
}

/// Una tanda: "Hojas 1 a 10", y "impresa" si ya salió.
class _Tanda extends StatelessWidget {
  final int desde;
  final int hasta;
  final bool impresa;
  final VoidCallback onTap;

  const _Tanda({
    super.key,
    required this.desde,
    required this.hasta,
    required this.impresa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final verde = Colors.green.shade800;
    return SizedBox(
      width: 130,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          backgroundColor: impresa ? Colors.green.shade50 : null,
          side: impresa ? BorderSide(color: verde) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              desde == hasta ? 'Hoja $desde' : 'Hojas $desde a $hasta',
              style: TextStyle(fontWeight: FontWeight.w700, color: impresa ? verde : null),
            ),
            Text(
              impresa ? 'impresa' : 'imprimir',
              style: TextStyle(fontSize: 12, color: impresa ? verde : Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumeroDeHoja extends StatelessWidget {
  final String clave;
  final TextEditingController controller;
  final VoidCallback alCambiar;

  const _NumeroDeHoja({required this.clave, required this.controller, required this.alCambiar});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        child: TextField(
          key: Key(clave),
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          onChanged: (_) => alCambiar(),
        ),
      );
}
