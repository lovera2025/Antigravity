import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../eventos/services/agregaron_despues.dart';
import 'vender_lista.dart';

/// El aviso de VENDER: las familias que cargaron una mesa adicional o sillas
/// extra **después del sorteo** (pedido del usuario, 27-nov-2026: "que le
/// aparezcan todas las personas que agregaron después del sorteo… y que solo
/// tenga que darle a OK, porque solo avisa").
///
/// **Solo avisa: no guarda, no tilda y no acepta nada.** El programa ya cobra
/// esas entradas al precio del día (`EntradasDeAlumno.cosas`); esto es para que
/// quien vende lo sepa antes de que la familia pregunte por el descuento. Sin
/// plata a la vista: la familia puede estar mirando.
///
/// [faltan]: por alumno, cuántas de esas entradas le falta comprar
/// (`LugaresDeLaFamilia.faltanSinDescuento`). Con 0, ya las compró y su renglón
/// va apagado. Quien no figura en el mapa va normal.
Future<void> avisarQuienesAgregaronDespues(
  BuildContext context, {
  required AgregaronDespues agregaron,
  required String fiesta,
  Map<String, int> faltan = const {},
}) =>
    showDialog<void>(
      context: context,
      // Se cierra con su botón: es lo único que hay que tocar.
      barrierDismissible: false,
      builder: (_) => _AgregaronDespuesDialog(
        agregaron: agregaron,
        fiesta: fiesta,
        faltan: faltan,
      ),
    );

class _AgregaronDespuesDialog extends StatelessWidget {
  const _AgregaronDespuesDialog({
    required this.agregaron,
    required this.fiesta,
    required this.faltan,
  });

  final AgregaronDespues agregaron;
  final String fiesta;
  final Map<String, int> faltan;

  /// Ya compró todo lo que agregó: no hay nada que venderle por eso.
  bool _yaCompro(AgregoDespues f) => f.entradas > 0 && faltan[f.id] == 0;

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).hintColor;
    final sorteo = agregaron.sorteoEl;
    final n = agregaron.familias.length;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agregaron después del sorteo'),
          Text(
            '$fiesta · ${n == 1 ? '1 familia' : '$n familias'}',
            key: const Key('agregaron_cuantas'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: gris),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sorteo == null ? '' : 'El sorteo fue el ${ArTime.formatFechaCorta(sorteo)}. '}'
                'Lo que cargaron después paga la entrada al precio del día, sin '
                'descuento. Lo que ya tenían cargado ese día sigue con descuento.',
                key: const Key('agregaron_intro'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final f in agregaron.familias) ...[
                const Divider(height: 14),
                _Renglon(familia: f, yaCompro: _yaCompro(f)),
              ],
              const Divider(height: 14),
              Text(
                'Es solo un aviso: el programa ya lo cobra así.',
                key: const Key('agregaron_pie'),
                style: TextStyle(fontSize: 12, color: gris),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('agregaron_entendido'),
          onPressed: () => Navigator.pop(context),
          child: const Text('ENTENDIDO'),
        ),
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon({required this.familia, required this.yaCompro});

  final AgregoDespues familia;
  final bool yaCompro;

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).hintColor;
    final a = familia.alumno;
    return Opacity(
      key: Key('agregaron_${familia.id}'),
      opacity: yaCompro ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: a.nombreAlumno.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: '  ·  ${divisionYMesaDe(a)}',
                  style: TextStyle(fontSize: 12.5, color: gris),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${familia.queAgrego} · ${familia.cuantasEntradas}'
            '${yaCompro ? ' · ya las compró' : ''}',
            key: Key('agregaron_que_${familia.id}'),
          ),
        ],
      ),
    );
  }
}

/// El renglón de VENDER que queda arriba mientras haya familias que agregaron
/// después del sorteo: cuántas son, y VER para abrir el aviso de nuevo.
class RenglonAgregaronDespues extends StatelessWidget {
  const RenglonAgregaronDespues({
    super.key,
    required this.familias,
    required this.alVer,
  });

  final int familias;

  /// VER. Null: apagado (VENDER está guardando).
  final VoidCallback? alVer;

  @override
  Widget build(BuildContext context) {
    final color = Colors.blueGrey.shade800;
    return Container(
      key: const Key('vender_agregaron'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Agregaron después del sorteo: '
              '${familias == 1 ? '1 familia' : '$familias familias'} · sin descuento',
              key: const Key('vender_agregaron_texto'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          TextButton(
            key: const Key('vender_agregaron_ver'),
            onPressed: alVer,
            child: const Text('VER'),
          ),
        ],
      ),
    );
  }
}
