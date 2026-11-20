import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/evento.dart';
import '../../eventos/services/caja_de_entregas.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../providers/caja_de_entregas_provider.dart';
import 'estilo_del_sector.dart';

/// "20/11 10:02": el día y la hora de Argentina, sin el año.
String horaCortaDeLaEntrega(DateTime d) {
  final ar = ArTime.toAr(d);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(ar.day)}/${dos(ar.month)} ${dos(ar.hour)}:${dos(ar.minute)}';
}

/// ENTREGAS SIN CARGO en Cierre de caja → ENTRADAS (pedido del usuario,
/// 20-nov-2026): la caja de entregas, como el cierre. Arriba, cuántas pulseras
/// y generales se dieron de las que tienen que llegar, las familias con todo y
/// las anuladas; después **una tabla por quién entregó** (con muchos entregando
/// a la vez se ve quién dio qué) y, al tocar a cada uno, cada entrega con hora,
/// familia, qué parte, cuántas, quién retiró, los números y las anuladas con su
/// motivo. IMPRIMIR saca todo, o lo de la persona elegida.
///
/// **Solo para mirar e imprimir**: anular sigue siendo del jefe, en ENTRADAS de
/// la fiesta. La cuenta es [CajaDeEntregas] (pura, con tests).
class EntregasDelCierre extends ConsumerStatefulWidget {
  final Evento fiesta;
  final bool isDark;

  const EntregasDelCierre({super.key, required this.fiesta, required this.isDark});

  @override
  ConsumerState<EntregasDelCierre> createState() => _EntregasDelCierreState();
}

class _EntregasDelCierreState extends ConsumerState<EntregasDelCierre> {
  /// La persona elegida en la tabla; null: la primera.
  String? _elegido;
  bool _imprimiendo = false;

  Color get _muted => widget.isDark ? Colors.white60 : Colors.black54;
  Color get _linea => widget.isDark ? Colors.white12 : Colors.black12;

  Future<void> _imprimir(CajaDeEntregas caja, {String? soloDe}) async {
    if (_imprimiendo) return;
    setState(() => _imprimiendo = true);
    try {
      await ref.read(imprimirEntregasSinCargoProvider)(
        caja,
        fiesta: EventoPresentacion.tituloPrincipal(widget.fiesta),
        fechaFiesta: widget.fiesta.fechaEvento,
        soloDe: soloDe,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo armar el papel. Probá de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caja = ref.watch(cajaDeEntregasDeLaFiestaProvider(widget.fiesta.id));
    return Column(
      key: const Key('cierre_entregas'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        caja.when(
          skipLoadingOnRefresh: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: oroDelSector)),
          ),
          error: (_, _) => Text(
            'No se pudieron leer las entregas.',
            key: const Key('cierre_entregas_error'),
            style: TextStyle(color: _muted),
          ),
          data: _contenido,
        ),
      ],
    );
  }

  Widget _contenido(CajaDeEntregas caja) {
    final r = caja.resumen;
    final elegida = caja.personas.isEmpty
        ? null
        : caja.personas.firstWhere(
            (p) => p.quien == _elegido,
            orElse: () => caja.personas.first,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'ENTREGAS SIN CARGO',
                style: TextStyle(
                  fontSize: 13.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton(
              key: const Key('cierre_entregas_imprimir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: oroDelSector,
                side: const BorderSide(color: oroDelSector),
              ),
              onPressed: _imprimiendo ? null : () => _imprimir(caja),
              child: const Text('IMPRIMIR'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Las pulseras VIP con cena y las generales que completan la mesa del '
          'contrato. No pasan por ninguna caja de plata: acá se ve quién las dio. '
          'Solo para mirar: anular está en ENTRADAS de la fiesta.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _dato(
              'pulseras',
              'PULSERAS VIP',
              '${r.pulserasEntregadas} de ${r.pulserasTotales}',
              _falta(r.pulserasTotales - r.pulserasEntregadas),
            ),
            _dato(
              'generales',
              'GENERALES',
              '${r.generalesEntregadas} de ${r.generalesTotales}',
              _falta(r.generalesTotales - r.generalesEntregadas),
            ),
            _dato(
              'familias',
              'FAMILIAS CON TODO',
              '${r.familiasConTodo} de ${r.familias}',
              caja.conUnaSolaParte == 1
                  ? '1 con una sola parte'
                  : '${caja.conUnaSolaParte} con una sola parte',
            ),
            _dato(
              'anuladas',
              'ANULADAS',
              '${caja.anuladas}',
              'las anula el jefe, con motivo',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (caja.sinEntregas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Todavía no se entregó nada sin cargo en esta fiesta.',
              key: const Key('cierre_entregas_vacio'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          )
        else ...[
          _tabla(caja, elegida!),
          ..._debajoDelTotal(caja),
          const SizedBox(height: 12),
          _detalle(caja, elegida),
        ],
        if (caja.anulacionesAnteriores.isNotEmpty) ...[
          const SizedBox(height: 12),
          _anulacionesAnteriores(caja),
        ],
      ],
    );
  }

  /// Lo que explica el TOTAL: lo de las familias hoy de baja (va en el total y
  /// arriba no cuenta) y la familia que está en dos filas.
  List<Widget> _debajoDelTotal(CajaDeEntregas caja) {
    final bajas = caja.textoDeLasBajas;
    return [
      if (bajas != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text(
            bajas,
            key: const Key('cierre_entregas_bajas'),
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      if (caja.familiasEnDosFilas)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text(
            CajaDeEntregas.notaDeLasFamilias,
            key: const Key('cierre_entregas_nota_familias'),
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
    ];
  }

  /// Las anulaciones que no van al lado de ninguna entrega de la lista.
  Widget _anulacionesAnteriores(CajaDeEntregas caja) => Container(
        key: const Key('cierre_entregas_anulaciones_anteriores'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _linea),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ANULACIONES DE UNA ENTREGA ANTERIOR',
              style: TextStyle(fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Cada una anuló una entrega que ya no está en la lista: quedó '
              'reescrita al volver a entregar, o ya estaba anulada.',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 6),
            for (final (i, x) in caja.anulacionesAnteriores.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${horaCortaDeLaEntrega(x.cuando)} · ${x.familia}'
                  '${x.deBaja ? ' (hoy de baja)' : ''} · ${x.texto}',
                  key: Key('cierre_entregas_anulacion_anterior_$i'),
                  style: TextStyle(fontSize: 13, color: Colors.red.shade400),
                ),
              ),
          ],
        ),
      );

  String _falta(int n) => n <= 0 ? 'no falta ninguna' : 'faltan $n';

  Widget _dato(String clave, String titulo, String valor, String sub) => Container(
        key: Key('cierre_entregas_$clave'),
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _linea),
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
                color: _muted,
              ),
            ),
            Text(
              valor,
              key: Key('cierre_entregas_${clave}_valor'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(sub, style: TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      );

  /// Una fila por quién entregó; tocarla muestra lo suyo abajo.
  Widget _tabla(CajaDeEntregas caja, PersonaDeLaCaja elegida) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 600;
      Widget num(String t, {bool fuerte = false, Key? key}) => SizedBox(
            width: ancho ? 96 : 64,
            child: Text(
              t,
              key: key,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          );
      // En un celular la columna es angosta: el título se achica en vez de
      // partirse en dos renglones ("GENERALE / S").
      Widget titulo(String t, {bool izquierda = false}) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: izquierda ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              t,
              maxLines: 1,
              textAlign: izquierda ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
          );
      Widget fila(List<Widget> hijos) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: hijos),
          );
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _linea),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            fila([
              Expanded(child: titulo('QUIÉN ENTREGÓ', izquierda: true)),
              SizedBox(width: ancho ? 96 : 64, child: titulo('PULSERAS')),
              SizedBox(width: ancho ? 96 : 64, child: titulo('GENERALES')),
              SizedBox(width: ancho ? 96 : 64, child: titulo('FAMILIAS')),
              if (ancho) SizedBox(width: 120, child: titulo('LA ÚLTIMA')),
            ]),
            for (final p in caja.personas)
              Material(
                color: p.quien == elegida.quien
                    ? oroDelSector.withValues(alpha: widget.isDark ? 0.18 : 0.22)
                    : Colors.transparent,
                child: InkWell(
                  key: Key('cierre_entregas_persona_${p.quien}'),
                  onTap: () => setState(() => _elegido = p.quien),
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: _linea))),
                    child: fila([
                      Expanded(
                        child: Text(
                          p.quien,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      num('${p.pulseras}'),
                      num('${p.generales}'),
                      num('${p.familias}'),
                      if (ancho)
                        SizedBox(
                          width: 120,
                          child: Text(
                            p.ultima == null ? '—' : horaCortaDeLaEntrega(p.ultima!),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 12.5, color: _muted),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: oroDelSector.withValues(alpha: 0.5), width: 2),
                ),
              ),
              child: fila([
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                num('${caja.pulserasDeLasFilas}', fuerte: true, key: const Key('cierre_entregas_total_pulseras')),
                num('${caja.generalesDeLasFilas}', fuerte: true, key: const Key('cierre_entregas_total_generales')),
                num('${caja.familiasConAlgo}', fuerte: true, key: const Key('cierre_entregas_total_familias')),
                if (ancho) const SizedBox(width: 120),
              ]),
            ),
          ],
        ),
      );
    });
  }

  /// Cada entrega de [p], de la más vieja a la más nueva, con las anuladas.
  Widget _detalle(CajaDeEntregas caja, PersonaDeLaCaja p) {
    final resumen = '${p.pulseras == 1 ? '1 pulsera' : '${p.pulseras} pulseras'} · '
        '${p.generales == 1 ? '1 general' : '${p.generales} generales'}';
    return Container(
      key: const Key('cierre_entregas_detalle'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _linea),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Text(
                  '${p.quien} · lo que entregó',
                  key: const Key('cierre_entregas_detalle_titulo'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    resumen,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('cierre_entregas_imprimir_persona'),
                  style: TextButton.styleFrom(foregroundColor: oroDelSector),
                  onPressed: _imprimiendo ? null : () => _imprimir(caja, soloDe: p.quien),
                  child: Text('IMPRIMIR LO DE ${p.quien.toUpperCase()}'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final (i, e) in p.entregas.indexed)
              DecoratedBox(
                key: Key('cierre_entregas_renglon_$i'),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: _linea))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  child: ancho ? _renglonAncho(e) : _renglonAngosto(e),
                ),
              ),
          ],
        );
      }),
    );
  }

  TextStyle get _normal => const TextStyle(fontSize: 13);

  TextStyle get _tachado => TextStyle(
        fontSize: 13,
        color: _muted,
        decoration: TextDecoration.lineThrough,
      );

  /// "Pulseras VIP", o en las 8 juntas "Pulseras y generales (las 8 juntas)",
  /// tachando **solo la parte que ya no cuenta**.
  InlineSpan _que(EntregaDeLaCaja e) {
    if (!e.partida) {
      final texto = e.deLasOchoJuntas
          ? (e.parte == null ? 'Pulseras y generales (las 8 juntas)' : '${e.que} (las 8 juntas)')
          : e.que;
      return TextSpan(text: texto, style: e.vigente ? _normal : _tachado);
    }
    return TextSpan(children: [
      TextSpan(text: 'Pulseras', style: e.pulserasVigentes ? _normal : _tachado),
      TextSpan(text: ' y ', style: _normal),
      TextSpan(text: 'generales', style: e.generalesVigentes ? _normal : _tachado),
      TextSpan(text: ' (las 8 juntas)', style: _normal),
    ]);
  }

  /// "3", "3 + 5", con la parte que no cuenta tachada.
  InlineSpan _cantidad(EntregaDeLaCaja e) {
    if (!e.partida) return TextSpan(text: e.cantidad, style: e.vigente ? _normal : _tachado);
    return TextSpan(children: [
      TextSpan(text: '${e.pulseras}', style: e.pulserasVigentes ? _normal : _tachado),
      TextSpan(text: ' + ', style: _normal),
      TextSpan(text: '${e.generales}', style: e.generalesVigentes ? _normal : _tachado),
    ]);
  }

  Color? _color(TonoDeLaLinea t) => switch (t) {
        TonoDeLaLinea.normal => null,
        TonoDeLaLinea.apagado => _muted,
        TonoDeLaLinea.anulada => Colors.red.shade400,
        TonoDeLaLinea.noCuenta =>
          widget.isDark ? Colors.orange.shade300 : Colors.orange.shade800,
      };

  /// Quién retiró, y por qué no cuenta lo que no cuenta (`EntregaDeLaCaja.estado`).
  Widget _retiro(EntregaDeLaCaja e) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in e.estado(horaCortaDeLaEntrega))
            Text(
              l.texto,
              style: TextStyle(
                fontSize: 13,
                color: _color(l.tono),
                fontWeight: l.tono == TonoDeLaLinea.anulada || l.tono == TonoDeLaLinea.noCuenta
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
        ],
      );

  List<InlineSpan> _familia(EntregaDeLaCaja e) => [
        TextSpan(
          text: e.familia,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        if (e.deBaja)
          TextSpan(text: ' · hoy de baja', style: TextStyle(fontSize: 12, color: _muted)),
      ];

  Widget _renglonAncho(EntregaDeLaCaja e) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(horaCortaDeLaEntrega(e.cuando), style: TextStyle(fontSize: 13, color: _muted)),
        ),
        Expanded(flex: 3, child: Text.rich(TextSpan(children: _familia(e)))),
        Expanded(flex: 3, child: Text.rich(_que(e))),
        SizedBox(width: 52, child: Text.rich(_cantidad(e))),
        Expanded(flex: 5, child: _retiro(e)),
        Expanded(
          flex: 3,
          child: Text(
            e.numeros.isEmpty ? '—' : e.numeros,
            style: TextStyle(fontSize: 13, color: e.numerosApagados ? _muted : null),
          ),
        ),
      ],
    );
  }

  Widget _renglonAngosto(EntregaDeLaCaja e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
            text: '${horaCortaDeLaEntrega(e.cuando)} · ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          ..._familia(e),
        ])),
        Text.rich(TextSpan(children: [
          _que(e),
          TextSpan(text: ' · ', style: _normal),
          _cantidad(e),
          if (e.numeros.isNotEmpty)
            TextSpan(
              text: ' · ${e.numeros}',
              style: TextStyle(fontSize: 13, color: e.numerosApagados ? _muted : null),
            ),
        ])),
        _retiro(e),
      ],
    );
  }
}
