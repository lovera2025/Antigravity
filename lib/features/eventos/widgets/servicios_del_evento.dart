import 'package:flutter/material.dart';

import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';

/// Un renglón suelto o un combo de la lista de servicios del evento.
class BloqueServicios {
  /// Nombre del combo; null para un renglón suelto.
  final String? combo;
  final List<EventosServicios> lineas;

  const BloqueServicios({this.combo, required this.lineas});

  /// Lo que suma el bloque al total: los extras no suman.
  double get total => lineas
      .where((l) => !l.esExtra)
      .fold<double>(0, (s, l) => s + l.precioFinalAcordado * l.cantidad);
}

/// Arma los bloques en el orden en que vienen: cada combo (mismo `grupo`) va
/// junto, donde aparece su primer renglón, y adentro por `combo_orden`.
List<BloqueServicios> bloquesDeServicios(List<EventosServicios> servicios) {
  final bloques = <BloqueServicios>[];
  final porCombo = <String, List<EventosServicios>>{};
  for (final s in servicios) {
    final g = s.grupo?.trim() ?? '';
    if (g.isEmpty) {
      bloques.add(BloqueServicios(lineas: [s]));
      continue;
    }
    final lista = porCombo[g];
    if (lista != null) {
      lista.add(s);
    } else {
      final nueva = [s];
      porCombo[g] = nueva;
      bloques.add(BloqueServicios(combo: g, lineas: nueva));
    }
  }
  for (final l in porCombo.values) {
    l.sort((a, b) => a.comboOrden.compareTo(b.comboOrden));
  }
  return bloques;
}

/// La cantidad tal cual se cargó: 2 → "2", 1,5 → "1,5". Antes se redondeaba a
/// entero y 1,5 se veía "2".
String cantidadParaMostrar(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  var t = q.toStringAsFixed(2);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  return t.replaceAll('.', ',');
}

/// El nombre del servicio; si no está en el catálogo de esta PC, su detalle.
String nombreDelServicio(EventosServicios s) {
  final n = s.servicio?.nombre.trim() ?? '';
  if (n.isNotEmpty) return n;
  final d = s.detalleServicio?.trim() ?? '';
  return d.isNotEmpty ? d : 'Servicio';
}

/// El detalle que se escribió en el presupuesto, si dice algo más que el
/// nombre. Es lo que el cliente buscaba en el evento (23-oct-2026).
String? detalleDelServicio(EventosServicios s) {
  final d = s.detalleServicio?.trim() ?? '';
  if (d.isEmpty || d == nombreDelServicio(s)) return null;
  return d;
}

/// La lista de servicios de un evento particular: el detalle de cada uno, los
/// combos juntos, los extras marcados y la cantidad tal cual (6.2.1).
class ServiciosDelEvento extends StatelessWidget {
  final List<EventosServicios> servicios;
  final VoidCallback onEditar;

  const ServiciosDelEvento({
    super.key,
    required this.servicios,
    required this.onEditar,
  });

  static const _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bloques = bloquesDeServicios(servicios);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SERVICIOS',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: Colors.grey),
            ),
            TextButton.icon(
              onPressed: onEditar,
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('EDITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: _gold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final b in bloques)
          b.combo == null
              ? Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: _Renglon(linea: b.lineas.single, isDark: isDark),
                )
              : Card(
                  key: Key('combo_${b.combo}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: _gold.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 16, color: _gold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b.combo!,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                                ),
                              ),
                              Text(
                                b.total.toCurrency(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: _gold),
                              ),
                            ],
                          ),
                        ),
                        // Si un solo renglón lleva el precio (lo de siempre: el
                        // primero lleva el del bloque), ya está arriba.
                        for (final l in b.lineas)
                          _Renglon(
                            linea: l,
                            isDark: isDark,
                            enCombo: true,
                            mostrarPrecio: b.lineas.where((x) => x.precioFinalAcordado.abs() >= 0.01).length > 1,
                          ),
                      ],
                    ),
                  ),
                ),
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  final EventosServicios linea;
  final bool isDark;
  final bool enCombo;
  final bool mostrarPrecio;

  const _Renglon({
    required this.linea,
    required this.isDark,
    this.enCombo = false,
    this.mostrarPrecio = true,
  });

  @override
  Widget build(BuildContext context) {
    final detalle = detalleDelServicio(linea);
    final q = linea.cantidad;
    final precio = linea.precioFinalAcordado;
    final secundario = isDark ? Colors.white60 : Colors.black54;

    return ListTile(
      key: Key('servicio_${linea.id}'),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: enCombo ? 0 : 4),
      dense: enCombo,
      leading: enCombo
          ? null
          : const CircleAvatar(
              backgroundColor: Colors.transparent,
              child: Icon(Icons.storefront_rounded, color: ServiciosDelEvento._gold),
            ),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(nombreDelServicio(linea), style: const TextStyle(fontWeight: FontWeight.bold)),
          if (linea.esExtra)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'EXTRA · no suma al total',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.orange),
              ),
            ),
        ],
      ),
      subtitle: (detalle == null && q == 1)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detalle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detalle, style: TextStyle(fontSize: 12, height: 1.35, color: secundario)),
                  ),
                if (q != 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'CANTIDAD: ${cantidadParaMostrar(q)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
      // En un combo, el precio del bloque va arriba: los renglones en $0 no
      // muestran precio, ni el único que lo lleva.
      trailing: (!mostrarPrecio || (enCombo && precio.abs() < 0.01))
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  precio.toCurrency(),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: linea.esExtra ? Colors.orange : ServiciosDelEvento._gold,
                  ),
                ),
                if (q != 1)
                  Text(
                    'TOTAL: ${(q * precio).toCurrency()}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
    );
  }
}
