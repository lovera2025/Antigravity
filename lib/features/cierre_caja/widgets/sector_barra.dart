import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../barra/cuentas/cierre_de_barra.dart';
import '../../barra/cuentas/pesos.dart';
import '../../barra/jefe/barra_jefe_providers.dart';
import '../../barra/jefe/elegir_fiesta.dart';
import '../../barra/services/fiestas_del_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';

const _gold = Color(0xFFD4AF37);
const _efectivo = Color(0xFF00B894);
const _transferencia = Color(0xFF6C63FF);

Color _colorDiferencia(double d) {
  final c = centavos(d);
  if (c == 0) return const Color(0xFF2E9E5B);
  return c < 0 ? const Color(0xFFE74C3C) : const Color(0xFFD68A00);
}

/// "Justo", "Sobran $ 500", "Faltan $ 1.500".
String _diferencia(double d) =>
    diferenciaEnPalabras(d).replaceFirst('Justo, sin diferencia', 'Justo');

/// BARRA en el cierre de caja (6.4.0): la fiesta (la próxima, o la de anoche hasta el día
/// siguiente; CAMBIAR DE FIESTA para otra) y **una línea por caja** con el cambio, el
/// efectivo, la transferencia, los mixtos, las anuladas, lo contado y la diferencia; los
/// totales y las sillas extra vendidas. **Solo para mirar:** anular y reimprimir siguen en
/// BARRA → CAJAS. Lee lo mismo que CAJAS del jefe (`cajasDelJefeProvider`), así que en la
/// web lee la nube.
class SectorBarraDelCierre extends ConsumerWidget {
  final bool isDark;

  const SectorBarraDelCierre({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = isDark ? Colors.white60 : Colors.black54;
    final fiestas = ref.watch(fiestasDelJefeProvider);
    return fiestas.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      ),
      error: (_, _) => const Text('No se pudieron leer las fiestas.'),
      data: (datos) {
        final fiesta = datos.elegida(ref.watch(fiestaElegidaDelJefeProvider));
        if (fiesta == null) {
          return Text(
            'Todavía no hay fiestas cargadas.',
            key: const Key('cierre_barra_sin_fiestas'),
            style: TextStyle(color: muted),
          );
        }
        final hoy = ref.read(relojDelJefeProvider)();
        final cajas = ref.watch(cajasDelJefeProvider(fiesta.id));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Fiesta(
              titulo: EventoPresentacion.tituloPrincipal(fiesta),
              fecha: fechaConCuando(fiesta.fechaEvento, hoy, esLaQueAbre: fiesta.id == datos.laQueAbre?.id),
              isDark: isDark,
              onCambiar: datos.todas.length > 1
                  ? () async {
                      final id = await showDialog<String>(
                        context: context,
                        builder: (_) => ElegirFiestaDelJefe(fiestas: datos, actual: fiesta.id, hoy: hoy),
                      );
                      if (id != null) ref.read(fiestaElegidaDelJefeProvider.notifier).elegir(id);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              'La barra va por fiesta, no por día: la de anoche sigue acá hasta mañana. Solo para '
              'mirar: anular y reimprimir siguen en BARRA, en la pestaña CAJAS.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            cajas.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: _gold)),
              ),
              error: (_, _) => const Text('No se pudieron leer las cajas.'),
              data: (d) => d.sinCajas
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Todavía no se abrió ninguna caja en esta fiesta.',
                        key: const Key('cierre_barra_sin_cajas'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    )
                  : _Resumen(resumen: d.resumen, isDark: isDark),
            ),
          ],
        );
      },
    );
  }
}

class _Fiesta extends StatelessWidget {
  final String titulo;
  final String fecha;
  final bool isDark;
  final VoidCallback? onCambiar;

  const _Fiesta({required this.titulo, required this.fecha, required this.isDark, this.onCambiar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LA FIESTA',
                style: TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: _gold),
              ),
              Text(
                titulo,
                key: const Key('cierre_barra_fiesta'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                fecha,
                style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.black54),
              ),
            ],
          ),
          OutlinedButton(
            key: const Key('cierre_barra_cambiar_fiesta'),
            onPressed: onCambiar,
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: const BorderSide(color: _gold),
            ),
            child: const Text('CAMBIAR DE FIESTA', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// La tabla de cajas, con su línea de totales, y debajo lo vendido y las sillas.
class _Resumen extends StatelessWidget {
  final ResumenDeCajas resumen;
  final bool isDark;

  const _Resumen({required this.resumen, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final linea = isDark ? Colors.white12 : Colors.black12;
    final cerradas = r.cajas.length - r.abiertas;

    Widget celda(String t, {Color? color, bool fuerte = false, bool izquierda = false, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(
            t,
            key: key,
            textAlign: izquierda ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        );
    Widget titulo(String t, {bool izquierda = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            t,
            textAlign: izquierda ? TextAlign.left : TextAlign.right,
            style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: muted),
          ),
        );

    /// [repartir]: lo que mide cada columna y lo que sobra se reparte (con ancho fijo, en
    /// la PC). Sin eso, cada columna lo suyo (en el celular, que se desliza de costado).
    Table tabla({required bool repartir}) => Table(
      defaultColumnWidth: IntrinsicColumnWidth(flex: repartir ? 1 : null),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: linea)),
      children: [
        TableRow(children: [
          titulo('CAJA', izquierda: true),
          titulo('CAMBIO'),
          titulo('EFECTIVO'),
          titulo('TRANSF.'),
          titulo('MIXTOS'),
          titulo('ANUL.'),
          titulo('CONTÓ'),
          titulo('DIFERENCIA'),
        ]),
        for (final c in r.cajas)
          TableRow(
            children: [
              celda(
                'Caja ${c.caja.numeroCaja}'
                '${c.caja.operadorNombre == null ? '' : ' · ${c.caja.operadorNombre}'}'
                '${c.caja.abierta ? ' · abierta' : ''}',
                izquierda: true,
                fuerte: true,
                key: Key('cierre_barra_caja_${c.caja.id}'),
              ),
              celda(pesos(c.caja.cambioInicial)),
              celda(pesos(c.cuentas.efectivo), color: _efectivo),
              celda(pesos(c.cuentas.transferencia), color: _transferencia),
              celda('${c.cuentas.mixtos}'),
              celda('${c.cuentas.anuladas}'),
              celda(c.contado == null ? '—' : pesos(c.contado!)),
              c.caja.abierta || c.diferencia == null
                  ? celda('abierta', color: muted)
                  : celda(_diferencia(c.diferencia!), color: _colorDiferencia(c.diferencia!), fuerte: true),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.5), width: 2))),
          children: [
            celda('TOTAL', izquierda: true, fuerte: true, key: const Key('cierre_barra_total')),
            celda(pesos(r.cambio), fuerte: true),
            celda(pesos(r.efectivo), color: _efectivo, fuerte: true),
            celda(pesos(r.transferencia), color: _transferencia, fuerte: true),
            celda('${r.mixtos}', fuerte: true),
            celda('${r.anuladas}', fuerte: true),
            celda(cerradas == 0 ? '—' : pesos(r.contado), fuerte: true),
            cerradas == 0
                ? celda('—', color: muted)
                : celda(_diferencia(r.diferencia), color: _colorDiferencia(r.diferencia), fuerte: true),
          ],
        ),
      ],
    );

    Widget dato(String clave, String titulo, String valor, String sub, {Color? color}) => Container(
          key: Key('cierre_barra_$clave'),
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: linea),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: muted)),
              Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(sub, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: linea),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          // En la PC, a todo el ancho; en el celular se desliza de costado.
          child: LayoutBuilder(
            builder: (context, caja) => caja.maxWidth >= 720
                ? SizedBox(width: caja.maxWidth, child: tabla(repartir: true))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: tabla(repartir: false),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            dato(
              'vendido',
              'TOTAL VENDIDO',
              pesos(r.total),
              r.anuladas == 1 ? 'sin la anulada' : 'sin las ${r.anuladas} anuladas',
              color: _gold,
            ),
            dato(
              'sillas',
              'SILLA EXTRA',
              r.sillas == 1 ? '1 vendida' : '${r.sillas} vendidas',
              'para comparar con las que sumó la puerta',
            ),
            // Las sueltas (6.5.0) no van a una mesa: van aparte, y solo si hubo.
            if (r.sillasSueltas > 0)
              dato(
                'sueltas',
                'SILLA SUELTA',
                r.sillasSueltas == 1
                    ? '1 vendida'
                    : '${r.sillasSueltas} vendidas',
                'no van a la mesa',
              ),
            dato(
              'cajas',
              'CAJAS',
              r.abiertas == 1 ? '1 abierta' : '${r.abiertas} abiertas',
              cerradas == 1 ? '1 cerrada' : '$cerradas cerradas',
            ),
          ],
        ),
      ],
    );
  }
}

/// ENTRADAS en el cierre de caja: todavía no hay venta de entradas en la app (las del
/// 50 % se venden a mano). El lugar queda listo.
class SectorEntradasDelCierre extends StatelessWidget {
  final bool isDark;

  const SectorEntradasDelCierre({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white60 : Colors.black54;
    return Container(
      key: const Key('cierre_entradas_vacio'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        children: [
          const Icon(Icons.confirmation_number_outlined, size: 36, color: _gold),
          const SizedBox(height: 10),
          const Text(
            'Todavía no hay ventas de entradas',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Hasta que esté la venta de entradas, las del 50 % se venden a mano, fuera de la '
            'app. El lugar queda listo para cuando esté.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}
