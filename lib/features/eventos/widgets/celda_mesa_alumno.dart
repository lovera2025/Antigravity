import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../common/utils/currency_extensions.dart';
import '../services/pago_para_sorteo.dart';
import '../services/reparto_de_sillas.dart';
import '../services/salon_mesas.dart';

/// Celda MESA de la grilla del evento masivo.
///
/// **Con sus mesas ya sorteadas:** los números (juntos o separados), un aviso
/// si no coinciden con la cuenta y sus sillas extra con su reparto
/// ("2P · 1A"). Dice lo mismo que la Planilla, porque sale de [SalonMesas] y de
/// [RepartoDeSillas]. Cuando hay más de una forma de repartir las sillas, el
/// renglón de las sillas se toca y abre el selector ([onElegirSillas]).
///
/// **Antes del sorteo:** cuántas mesas y sillas le corresponden. Todos tienen
/// una mesa por contrato, así que lo que resalta es la agregada ("1 mesa
/// **+1 extra**"). Las sillas dicen solo cuántas son: el reparto se elige
/// recién con las mesas sorteadas.
///
/// Con [marcarPago] dice además cómo está pagado cada extra, y el tooltip trae
/// el detalle: lo cargado, lo pagado y cuántas mesas le da hoy el sorteo.
class CeldaMesaAlumno extends StatelessWidget {
  final ContratoAlumno alumno;
  final bool compacto;
  final SillasReparto? reparto;
  final VoidCallback? onElegirSillas;

  /// Lo cargado y lo pagado, según sus pagos. Null mientras no se leyeron.
  final ExtrasSegunPago? extras;

  /// Mostrar en la celda cómo está pagado cada extra (con el filtro de mesas
  /// y sillas puesto).
  final bool marcarPago;

  /// La grilla está con los montos ocultos: el tooltip dice el estado, sin
  /// plata.
  final bool ocultarMontos;

  /// Lo que `SalonMesas.avisos` marcó de este alumno.
  final List<String> avisos;

  const CeldaMesaAlumno({
    super.key,
    required this.alumno,
    this.compacto = false,
    this.reparto,
    this.onElegirSillas,
    this.extras,
    this.marcarPago = false,
    this.ocultarMontos = false,
    this.avisos = const [],
  });

  static String _plural(int n, String uno, String varios) =>
      n == 1 ? uno : varios;

  static String _estadoEnPalabras(ExtraPagado e) => switch (e.estado) {
        EstadoPagoExtra.sinCargar => '',
        EstadoPagoExtra.sinPagar => 'sin pagar',
        EstadoPagoExtra.enCuotas => 'en cuotas',
        EstadoPagoExtra.pagado => _plural(e.cantidad, 'pagada', 'pagadas'),
      };

  static Color _colorDePago(EstadoPagoExtra e) => switch (e) {
        EstadoPagoExtra.sinPagar => Colors.orange.shade800,
        EstadoPagoExtra.enCuotas => Colors.blue.shade700,
        EstadoPagoExtra.pagado => Colors.green.shade700,
        EstadoPagoExtra.sinCargar => Colors.grey.shade600,
      };

  /// "($70.000, pagado $19.530)", o "(en cuotas)" con los montos ocultos.
  String _detallePago(ExtraPagado e) => ocultarMontos
      ? '(${_estadoEnPalabras(e)})'
      : '(${e.precio.toCurrency()}, pagado ${e.pagado.toCurrency()})';

  /// El detalle fehaciente: qué tiene cargado, cuánto pagó de cada cosa y qué
  /// le da hoy el sorteo.
  List<String> _detalleExtras(ExtrasSegunPago e) {
    final m = e.mesas;
    final s = e.sillas;
    return [
      if (m.cantidad > 0)
        'Mesas: 1 del contrato + ${m.cantidad} '
            '${_plural(m.cantidad, 'agregada', 'agregadas')} ${_detallePago(m)}'
      else
        'Mesas: 1, la de su contrato',
      if (s.cantidad > 0)
        'Sillas: ${s.cantidad} extra ${_detallePago(s)}',
      if (!e.pagoBase) 'No pagó nada de la cuota base.',
      if (e.asignadas < e.mesasCargadas)
        switch (e.mesasConElSorteoDeHoy) {
          0 => 'Con lo pagado hoy, el sorteo no le da mesa.',
          final n => 'Con lo pagado hoy, el sorteo le da $n '
              '${_plural(n, 'mesa', 'mesas')}'
              '${e.recibeMenos ? ': solo la de su contrato' : ''}.',
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Con algo escrito en su mesa (aunque no se entienda), ya no es "antes
    // del sorteo". Para las sillas cuentan los números de verdad.
    final tieneMesa = alumno.numeroMesa?.trim().isNotEmpty ?? false;
    final conNumeros = SalonMesas.tieneNumeros(alumno);
    final texto = SalonMesas.textoMesas(alumno);
    final falta = SalonMesas.avisoMesas(alumno);
    final aviso = falta == null ? null : '⚠ $falta';
    final sillas = SalonMesas.sillasExtra(alumno);
    final chico = compacto ? 10.0 : 11.0;
    final baja = alumno.esBajaTemporal;
    // Antes del sorteo, la celda dice lo que le corresponde. A los de baja no
    // se les reserva nada: quedan con el guion de siempre.
    final antesDelSorteo = !tieneMesa && !baja;

    final estado = RepartoDeSillas.estado(alumno, reparto);
    final vigente = RepartoDeSillas.vigente(alumno, reparto);
    // El reparto se elige con las mesas ya sorteadas.
    final hayQueElegir =
        conNumeros && RepartoDeSillas.opcionesDe(alumno).length > 1;
    final e = extras;

    final detalle = [
      if (tieneMesa) 'Mesa: $texto' else 'Sin mesa asignada todavía.',
      ?aviso,
      if (e != null && !baja) ..._detalleExtras(e),
      if (sillas > 0 && conNumeros)
        'Sillas extra: ${SalonMesas.textoRepartoSillas(alumno, sillasPrincipal: vigente?.principal)}',
      if (sillas > 0 && !conNumeros && estado != EstadoRepartoSillas.revisar)
        'Dónde va cada silla se elige con las mesas ya sorteadas.',
      if (conNumeros && estado == EstadoRepartoSillas.aConfirmar)
        'Falta que la familia elija dónde van las sillas: tocá para elegir.',
      if (estado == EstadoRepartoSillas.revisar)
        'Tiene más sillas de las que entran (2 por mesa): revisá la cuenta.',
      for (final a in avisos) '⚠ $a',
    ].join('\n');

    final cuantas = '+$sillas ${_plural(sillas, 'silla', 'sillas')}';
    final String? textoSillas;
    Color colorSillas = Colors.teal.shade600;
    if (estado == EstadoRepartoSillas.noAplica) {
      textoSillas = null;
    } else if (estado == EstadoRepartoSillas.revisar) {
      textoSillas = '+$sillas sillas: revisar';
      colorSillas = Colors.orange.shade800;
    } else if (!conNumeros) {
      // Antes del sorteo: solo cuántas. Con el filtro puesto, cómo están
      // pagadas.
      final pago = e?.sillas;
      if (marcarPago &&
          pago != null &&
          pago.estado != EstadoPagoExtra.sinCargar) {
        textoSillas = '$cuantas · ${_estadoEnPalabras(pago)}';
        colorSillas = _colorDePago(pago.estado);
      } else {
        textoSillas = cuantas;
      }
    } else if (estado == EstadoRepartoSillas.aConfirmar) {
      textoSillas = '$cuantas: a confirmar';
      colorSillas = Colors.orange.shade800;
    } else {
      textoSillas = '$cuantas: ${vigente?.texto ?? ''}';
    }

    Widget? renglonSillas;
    if (textoSillas != null) {
      final seToca = hayQueElegir && onElegirSillas != null;
      final etiqueta = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              textoSillas,
              style: TextStyle(
                fontSize: chico,
                fontWeight: FontWeight.w700,
                color: colorSillas,
                decoration: seToca ? TextDecoration.underline : null,
                decorationColor: colorSillas,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (conNumeros && estado == EstadoRepartoSillas.elegido)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(Icons.check_circle, size: chico + 2, color: colorSillas),
            ),
        ],
      );
      renglonSillas = seToca
          ? InkWell(
              onTap: onElegirSillas,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: etiqueta,
              ),
            )
          : etiqueta;
    }

    return Tooltip(
      message: detalle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (antesDelSorteo)
            ..._renglonesAntesDelSorteo(chico)
          else
            Text(
              texto,
              style: TextStyle(
                fontSize: compacto ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: tieneMesa ? Colors.indigo : Colors.grey.shade500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          if (aviso != null)
            Text(
              aviso,
              style: TextStyle(
                fontSize: chico,
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade800,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ?renglonSillas,
        ],
      ),
    );
  }

  /// "1 mesa" sin destacar y, si tiene, "+1 extra" bien a la vista. Con
  /// [marcarPago], un renglón más con cómo está pagado.
  List<Widget> _renglonesAntesDelSorteo(double chico) {
    final extra = SalonMesas.mesasExtra(alumno);
    final e = extras;
    final String? pago;
    Color colorPago = Colors.grey.shade600;
    var alDia = false;
    if (!marcarPago || e == null) {
      pago = null;
    } else if (e.sinMesaPorBase) {
      pago = 'sin pago: sin mesa';
      colorPago = Colors.orange.shade800;
    } else if (extra > 0) {
      final estado = e.mesas.estado;
      pago = switch (estado) {
        EstadoPagoExtra.pagado => 'extra pagada',
        EstadoPagoExtra.enCuotas => 'extra en cuotas',
        _ => 'extra sin pagar',
      };
      colorPago = _colorDePago(estado);
      alDia = estado == EstadoPagoExtra.pagado;
    } else {
      // Solo la del contrato, y pagó algo de la base: le corresponde.
      pago = null;
      alDia = true;
    }

    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '1 mesa',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (extra > 0)
                    TextSpan(
                      text: ' +$extra extra',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.deepPurple.shade600,
                      ),
                    ),
                ],
              ),
              style: TextStyle(fontSize: compacto ? 11 : 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (alDia && pago == null)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                Icons.check_circle,
                size: chico + 2,
                color: Colors.green.shade700,
              ),
            ),
        ],
      ),
      if (pago != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                pago,
                style: TextStyle(
                  fontSize: chico,
                  fontWeight: FontWeight.w700,
                  color: colorPago,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (alDia)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.check_circle, size: chico + 2, color: colorPago),
              ),
          ],
        ),
    ];
  }
}
