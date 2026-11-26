import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../barra/cuentas/cierre_de_barra.dart';
import '../../barra/cuentas/dia_de_operacion.dart';
import '../../barra/cuentas/pesos.dart';
import '../../barra/jefe/barra_jefe_providers.dart';
import 'estilo_del_sector.dart';

const _gold = oroDelSector;
const _efectivo = efectivoDelSector;
const _transferencia = transferenciaDelSector;
const _colorDiferencia = colorDeLaDiferencia;
const _diferencia = diferenciaCorta;

/// BARRA en el cierre de caja (6.4.0): la fiesta (la de esta noche, o la de anoche hasta el
/// día siguiente; CAMBIAR DE FIESTA para otra) y **una línea por caja** con el cambio, el
/// efectivo, la transferencia, los mixtos, las anuladas, lo contado y la diferencia; los
/// totales y las sillas extra vendidas. **Solo para mirar:** anular y reimprimir siguen en
/// BARRA → CAJAS. Lee lo mismo que CAJAS del jefe (`cajasDelJefeProvider`), así que en la
/// web lee la nube.
///
/// **Las cajas de una noche** (25-nov-2026, `cuentas/dia_de_operacion.dart`): la del día
/// del cierre ([diaDelCierre]) si hubo cajas; si no, la de esta noche o la última con
/// cajas. Las otras noches de la fiesta van arriba para tocar: una caja de prueba de otro
/// día no se suma.
class SectorBarraDelCierre extends ConsumerStatefulWidget {
  final bool isDark;

  /// El día que muestra el cierre de caja. Null: el de hoy.
  final DateTime? diaDelCierre;

  const SectorBarraDelCierre({super.key, required this.isDark, this.diaDelCierre});

  @override
  ConsumerState<SectorBarraDelCierre> createState() => _SectorBarraDelCierreState();
}

class _SectorBarraDelCierreState extends ConsumerState<SectorBarraDelCierre> {
  /// La noche que se eligió tocando arriba; null: la del cierre.
  DiaDeOperacion? _noche;

  /// La fiesta de la noche elegida: si cambia la fiesta, se vuelve a la del cierre.
  String? _deLaFiesta;

  @override
  void didUpdateWidget(SectorBarraDelCierre anterior) {
    super.didUpdateWidget(anterior);
    // Otro día en el cierre: manda ese.
    if (anterior.diaDelCierre != widget.diaDelCierre) _noche = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final fiestas = ref.watch(fiestasDelJefeProvider);
    final ahora = ref.watch(relojDelJefeProvider)();
    final diaDelCierre = widget.diaDelCierre;
    // El día del cierre ya es una fecha de Argentina sin la hora: va tal cual. Pasarlo de
    // nuevo por la hora de Argentina lo corría un día en una PC con otra zona (26-nov-2026).
    final delCierre = diaDelCierre == null ? null : DiaDeOperacion.delCalendario(diaDelCierre);
    // El cierre de hoy mira la noche en curso (a la mañana, la de anoche); el de otro día,
    // la noche de ese día. Esa noche elige la fiesta y sus cajas.
    final hoyCalendario = DiaDeOperacion.delCalendario(ArTime.toAr(ahora));
    final preferido =
        delCierre == null || delCierre == hoyCalendario ? DiaDeOperacion.de(ahora) : delCierre;
    return fiestas.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: _gold)),
      ),
      error: (_, _) => const Text('No se pudieron leer las fiestas.'),
      data: (datos) {
        // La elegida con CAMBIAR DE FIESTA; si no, la fiesta de la noche del cierre; si
        // no hay, la de esta noche o la próxima (26-nov-2026: antes la decidía la hora, y
        // el cierre de otro día mostraba la fiesta de hoy).
        final id = ref.watch(fiestaElegidaDelJefeProvider);
        final fiesta = id != null
            ? datos.elegida(id, enLaBarra: true)
            : (datos.deLaNoche(preferido) ?? datos.laQueAbreEnLaBarra);
        if (fiesta == null) {
          return Text(
            'Todavía no hay fiestas cargadas.',
            key: const Key('cierre_barra_sin_fiestas'),
            style: TextStyle(color: muted),
          );
        }
        final cajas = ref.watch(cajasDelJefeProvider(fiesta.id));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FiestaDelCierre(
              fiestas: datos,
              fiesta: fiesta,
              isDark: isDark,
              clave: 'cierre_barra',
            ),
            const SizedBox(height: 8),
            Text(
              'La barra va por fiesta y por noche: la de anoche sigue acá hasta el mediodía, y '
              'las cajas de otros días van aparte. Solo para mirar: anular y reimprimir siguen en '
              'BARRA, en la pestaña CAJAS.',
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
              data: (d) {
                if (d.sinCajas) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Todavía no se abrió ninguna caja en esta fiesta.',
                      key: const Key('cierre_barra_sin_cajas'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  );
                }
                final elegida = _deLaFiesta == fiesta.id ? _noche : null;
                final dia = elegida != null && d.porDia.tiene(elegida)
                    ? elegida
                    : d.porDia.inicial(ahora: ahora, fechaDeLaFiesta: fiesta.fechaEvento, preferido: preferido);
                final noche = d.delDia(dia);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NochesDelCierre(
                      dias: d.porDia.dias,
                      cuantas: (x) => d.porDia.delDia(x).length,
                      elegida: dia,
                      isDark: isDark,
                      onElegir: (x) => setState(() {
                        _noche = x;
                        _deLaFiesta = fiesta.id;
                      }),
                    ),
                    if (noche.sinCajas)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          dia == DiaDeOperacion.de(ahora)
                              ? 'Todavía no se abrió ninguna caja esta noche.'
                              : 'Esa noche no se abrió ninguna caja de esta fiesta.',
                          key: const Key('cierre_barra_sin_cajas_esa_noche'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted),
                        ),
                      )
                    else
                      _Resumen(resumen: noche.resumen, isDark: isDark),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Las noches de la fiesta con cajas, para tocar: la que se mira marcada. Con una sola, la
/// dice sin botones ("Las cajas del viernes 4 de diciembre").
class _NochesDelCierre extends StatelessWidget {
  final List<DiaDeOperacion> dias;
  final int Function(DiaDeOperacion) cuantas;
  final DiaDeOperacion elegida;
  final bool isDark;
  final ValueChanged<DiaDeOperacion> onElegir;

  const _NochesDelCierre({
    required this.dias,
    required this.cuantas,
    required this.elegida,
    required this.isDark,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white60 : Colors.black54;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Las cajas del ${elegida.largo}',
            key: const Key('cierre_barra_noche'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          if (dias.length > 1 || !dias.contains(elegida)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final x in dias.reversed)
                  ChoiceChip(
                    key: Key('cierre_barra_noche_${x.anio}-${x.mes}-${x.dia}'),
                    label: Text('${x.corto} · ${cuantas(x) == 1 ? '1 caja' : '${cuantas(x)} cajas'}'),
                    selected: x == elegida,
                    selectedColor: _gold.withValues(alpha: 0.25),
                    labelStyle: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    onSelected: (_) => onElegir(x),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cada noche aparte, como un cierre de caja en su fecha.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
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
