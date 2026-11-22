import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../barra/cuentas/pesos.dart';
import '../../barra/jefe/barra_jefe_providers.dart';
import '../../barra/providers/barra_providers.dart' show eventosDeLaBarraProvider;
import '../../barra/services/fiestas_del_jefe.dart';
import '../../../models/evento.dart';
import '../../entradas/cuentas/cierre_de_entradas.dart';
import '../../entradas/pdf/cierre_caja_entradas_pdf.dart';
import '../../entradas/pdf/papeles_de_entradas.dart';
import '../../entradas/providers/entradas_providers.dart';
import '../../entradas/services/nombre_de_la_fiesta.dart';
import 'entregas_del_cierre.dart';
import 'estilo_del_sector.dart';

/// Las fiestas de ENTRADAS en el cierre de caja: **solo los eventos masivos**,
/// que son los que venden entradas (revisión del 15-nov: con la lista de BARRA,
/// que trae también los particulares, podía abrir en un casamiento y mandar a un
/// PRECIOS que ahí no existe). La elección sigue siendo la misma que la de BARRA:
/// si allá se eligió un particular, acá abre en el próximo masivo.
final fiestasDeEntradasDelCierreProvider = FutureProvider<FiestasDelJefe>((ref) async {
  final eventos = await ref.watch(eventosDeLaBarraProvider.future);
  return FiestasDelJefe.de(
    eventos.where((e) => e.modalidad == 'masivo'),
    ref.read(relojDelJefeProvider)(),
  );
});

/// ENTRADAS en el cierre de caja (6.9.0, sección 9.2 del spec del 13-nov): la
/// fiesta (la misma elección que BARRA: la próxima, la de anoche hasta el día
/// siguiente, CAMBIAR DE FIESTA) y **una línea por caja de entradas** con el
/// cambio, el efectivo, la transferencia, los mixtos, las vendidas, los
/// descuentos a mano, las anuladas, lo contado y la diferencia; los totales de
/// la fiesta y lo anulado después de cerrar.
///
/// Anular, verificar y reimprimir una venta están en VENTAS. Lo único que se
/// hace acá es **sacar el papel del cierre de una caja cerrada** (22-nov-2026:
/// ningún papel sale solo, y al cerrar se puede salir sin sacarlo). La web no
/// tiene la base del equipo: ahí lo dice ([kEntradasDesdeLaPc]).
class SectorEntradasDelCierre extends ConsumerWidget {
  final bool isDark;

  const SectorEntradasDelCierre({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = isDark ? Colors.white60 : Colors.black54;
    Widget aviso(String clave, String texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            texto,
            key: Key(clave),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        );
    if (!ref.watch(entradasEnEsteEquipoProvider)) {
      return aviso('cierre_entradas_web', kEntradasDesdeLaPc);
    }
    final fiestas = ref.watch(fiestasDeEntradasDelCierreProvider);
    return fiestas.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: oroDelSector)),
      ),
      error: (_, _) => const Text('No se pudieron leer las fiestas.'),
      data: (datos) {
        final fiesta = datos.elegida(ref.watch(fiestaElegidaDelJefeProvider));
        if (fiesta == null) {
          return aviso('cierre_entradas_sin_fiestas', 'Todavía no hay fiestas cargadas.');
        }
        final cajas = ref.watch(cajasDeEntradasDeLaFiestaProvider(fiesta.id));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FiestaDelCierre(
              fiestas: datos,
              fiesta: fiesta,
              isDark: isDark,
              clave: 'cierre_entradas',
            ),
            const SizedBox(height: 8),
            Text(
              'Las entradas van por fiesta, no por día: la de anoche sigue acá hasta '
              'mañana. El papel del cierre de cada caja cerrada sale con la '
              'impresora de su renglón; anular, verificar y reimprimir una venta '
              'están en VENTAS.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            cajas.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: oroDelSector)),
              ),
              error: (_, _) => const Text('No se pudieron leer las cajas de entradas.'),
              data: (d) => d.sinCajas
                  ? (d.tienePrecio
                      ? aviso(
                          'cierre_entradas_sin_cajas',
                          'Todavía no se abrió ninguna caja de entradas en esta fiesta.',
                        )
                      : aviso(
                          'cierre_entradas_sin_precio',
                          'Esta fiesta todavía no tiene precio de entrada: se pone en '
                              'ENTRADAS → PRECIOS.',
                        ))
                  : _Resumen(
                      datos: d,
                      isDark: isDark,
                      alSacarElPapel: (c) => _papelDelCierre(context, ref, fiesta, c),
                    ),
            ),
            // La caja de entregas (20-nov-2026): lo sin cargo no necesita caja
            // ni precio, así que va siempre, aunque no haya cajas de venta.
            const SizedBox(height: 22),
            EntregasDelCierre(fiesta: fiesta, isDark: isDark),
          ],
        );
      },
    );
  }

  /// PAPEL DEL CIERRE de la caja cerrada [c]: el mismo de IMPRIMIR EL CIERRE,
  /// con las cuentas de su renglón (lo contado y la diferencia, de lo anotado
  /// al cerrar). No escribe nada.
  Future<void> _papelDelCierre(
    BuildContext context,
    WidgetRef ref,
    Evento fiesta,
    ResumenDeCajaEntradas c,
  ) async {
    try {
      await ref.read(abrirCierreDeEntradasProvider)(
        DatosDelCierreDeEntradas(
          caja: c.caja,
          cuentas: c.cuentas,
          fiesta: nombreDeLaFiesta(fiesta),
          fechaFiesta: fiesta.fechaEvento,
        ),
        context: context,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el papel del cierre. Probá de nuevo.'),
        ),
      );
    }
  }
}

/// La tabla de cajas, con su línea de totales, y debajo lo vendido, lo anulado
/// después del cierre y cuántas cajas.
class _Resumen extends StatelessWidget {
  final CajasDeEntradasDeLaFiesta datos;
  final bool isDark;

  /// PAPEL DEL CIERRE de una caja cerrada.
  final void Function(ResumenDeCajaEntradas caja) alSacarElPapel;

  const _Resumen({
    required this.datos,
    required this.isDark,
    required this.alSacarElPapel,
  });

  @override
  Widget build(BuildContext context) {
    final d = datos;
    final t = d.total;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final linea = isDark ? Colors.white12 : Colors.black12;

    Widget celda(String texto,
            {Color? color, bool fuerte = false, bool izquierda = false, Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(
            texto,
            key: key,
            textAlign: izquierda ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        );
    Widget titulo(String texto, {bool izquierda = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            texto,
            textAlign: izquierda ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        );

    /// [repartir]: lo que sobra se reparte entre las columnas (en la PC). Sin
    /// eso, cada columna lo suyo (en el celular, que se desliza de costado).
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
              titulo('VENDIDAS'),
              titulo('DESC.'),
              titulo('ANUL.'),
              titulo('CONTÓ'),
              titulo('DIFERENCIA'),
              titulo('PAPEL'),
            ]),
            for (final c in d.cajas)
              TableRow(
                children: [
                  celda(
                    '${(c.caja.operadorNombre ?? '').isEmpty ? 'Jefe' : c.caja.operadorNombre}'
                    '${c.caja.abierta ? ' · abierta' : ''}',
                    izquierda: true,
                    fuerte: true,
                    key: Key('cierre_entradas_caja_${c.caja.id}'),
                  ),
                  celda(pesos(c.caja.cambioInicial)),
                  celda(pesos(c.cuentas.efectivo), color: efectivoDelSector),
                  celda(pesos(c.cuentas.transferencia), color: transferenciaDelSector),
                  celda('${c.cuentas.mixtos}'),
                  celda('${c.cuentas.entradas}'),
                  celda(pesos(c.cuentas.descuentos)),
                  celda('${c.cuentas.anuladas}'),
                  celda(c.caja.abierta || c.contado == null ? '—' : pesos(c.contado!)),
                  c.caja.abierta || c.diferencia == null
                      ? celda('abierta', color: muted)
                      : celda(
                          diferenciaCorta(c.diferencia!),
                          color: colorDeLaDiferencia(c.diferencia!),
                          fuerte: true,
                          key: Key('cierre_entradas_diferencia_${c.caja.id}'),
                        ),
                  // El papel del cierre, solo de una caja cerrada: el de una
                  // abierta todavía no existe.
                  c.caja.abierta
                      ? celda('—', color: muted)
                      : Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            key: Key('cierre_entradas_papel_${c.caja.id}'),
                            tooltip: 'PAPEL DEL CIERRE',
                            icon: const Icon(Icons.print_outlined, size: 20),
                            onPressed: () => alSacarElPapel(c),
                          ),
                        ),
                ],
              ),
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: oroDelSector.withValues(alpha: 0.5), width: 2),
                ),
              ),
              children: [
                celda('TOTAL', izquierda: true, fuerte: true, key: const Key('cierre_entradas_total')),
                celda(pesos(t.cambioInicial), fuerte: true),
                celda(pesos(t.efectivo), color: efectivoDelSector, fuerte: true),
                celda(pesos(t.transferencia), color: transferenciaDelSector, fuerte: true),
                celda('${t.mixtos}', fuerte: true),
                celda('${t.entradas}', fuerte: true),
                celda(pesos(t.descuentos), fuerte: true),
                celda('${t.anuladas}', fuerte: true),
                celda(d.cerradas == 0 ? '—' : pesos(d.contado), fuerte: true),
                d.cerradas == 0
                    ? celda('—', color: muted)
                    : celda(
                        diferenciaCorta(d.diferencia),
                        color: colorDeLaDiferencia(d.diferencia),
                        fuerte: true,
                      ),
                const SizedBox.shrink(),
              ],
            ),
          ],
        );

    Widget dato(String clave, String titulo, String valor, String sub, {Color? color}) =>
        Container(
          key: Key('cierre_entradas_$clave'),
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
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: muted,
                ),
              ),
              Text(
                valor,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              ),
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
            builder: (context, caja) => caja.maxWidth >= 860
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
              pesos(t.total),
              '${t.entradas == 1 ? '1 entrada' : '${t.entradas} entradas'} · '
                  '${t.sueltas} sueltas y ${t.deLugar} de lugares'
                  '${t.otras > 0 ? ' y ${t.otras} otras' : ''}',
              color: oroDelSector,
            ),
            if (t.hayAnuladoDespues)
              dato(
                'anulado_despues',
                'ANULADO DESPUÉS DEL CIERRE',
                pesos(t.anuladoDespues),
                'el cierre de esa caja no se corrige',
              ),
            dato(
              'cajas',
              'CAJAS',
              d.abiertas == 1 ? '1 abierta' : '${d.abiertas} abiertas',
              d.cerradas == 1 ? '1 cerrada' : '${d.cerradas} cerradas',
            ),
          ],
        ),
      ],
    );
  }
}
