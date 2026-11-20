import 'package:flutter/material.dart';

import '../../barra/cuentas/pesos.dart';
import '../../eventos/services/lugares_pagos.dart';

/// Por debajo de este ancho, VENDER se acomoda como en un celular: todo uno
/// debajo del otro.
const kVenderAngosto = 560.0;

/// "50" o "37,5": un porcentaje como se lee.
String porcentajeLegible(double pct) => pct == pct.roundToDouble()
    ? pct.round().toString()
    : pct.toStringAsFixed(1).replaceAll('.', ',');

/// La clave de una línea de A PAGAR: la mesa adicional por su número (una mesa
/// es de antes o de después del sorteo, nunca las dos), y las sillas por de
/// cuándo son. Con esto VENDER recuerda cuántas lleva de cada línea.
String claveDeLinea(LineaAPagar l) => l.cosa == CosaAPagar.mesa
    ? 'mesa_${l.mesa}'
    : (l.conDescuento ? 'sillas' : 'sillas_despues');

/// − cantidad + y el subtotal, contra el borde derecho. [tope]: no deja pasar
/// de ahí (null: sin tope).
class ControlDeCantidad extends StatelessWidget {
  const ControlDeCantidad({
    super.key,
    required this.clave,
    required this.cantidad,
    required this.subtotal,
    required this.alCambiar,
    this.tope,
    this.antes,
  });

  final String clave;
  final int cantidad;
  final double subtotal;
  final ValueChanged<int> alCambiar;
  final int? tope;
  final Widget? antes;

  @override
  Widget build(BuildContext context) {
    final tope = this.tope;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (antes != null) ...[antes!, const SizedBox(width: 12)],
        IconButton(
          key: Key('${clave}_menos'),
          tooltip: 'Una menos',
          onPressed: cantidad <= 0 ? null : () => alCambiar(cantidad - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$cantidad',
            key: Key('${clave}_cantidad'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          key: Key('${clave}_mas'),
          tooltip: 'Una más',
          onPressed:
              tope != null && cantidad >= tope ? null : () => alCambiar(cantidad + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
        SizedBox(
          width: 96,
          child: Text(
            pesos(subtotal),
            key: Key('${clave}_subtotal'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Un chip chico de color: "Con descuento 50 %", "Pagó todo", "Debe $ 70.000".
class ChipDeVender extends StatelessWidget {
  const ChipDeVender(this.texto, {super.key, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Las líneas de A PAGAR de una familia en VENDER (20-nov-2026): **un renglón
/// por mesa adicional y por las sillas extra**, con su precio, cuántas lleva y
/// el subtotal. Lo que no está pago entero se ve apagado, "a confirmar", sin
/// botones.
///
/// **No hace ninguna cuenta**: las líneas y qué está pago salen de
/// [APagarDeLaFamilia]; cuántas le quedan de cada una y cuántas siguen "a
/// confirmar", de `LugaresDeLaFamilia.porLinea` ([quedan], [aConfirmar]); y lo
/// que se vende lo arma `PedidoDeEntradas`, que pone los topes. Acá solo se
/// muestra y se cuenta con los botones.
class LineasAPagar extends StatelessWidget {
  const LineasAPagar({
    super.key,
    required this.aPagar,
    required this.quedan,
    required this.aConfirmar,
    required this.cantidades,
    required this.alCambiar,
    required this.precioConDescuento,
    required this.precioEntero,
    required this.precioDelDia,
    required this.rigeLaAnticipada,
    required this.descuentoPct,
    this.frenadas = false,
  });

  final APagarDeLaFamilia aPagar;

  /// Cuántas le quedan de cada línea, en el orden de `aPagar.lineas`.
  final List<int> quedan;

  /// Cuántas de cada línea siguen "a confirmar" (esperan el pago y no las
  /// compró antes), en el mismo orden.
  final List<int> aConfirmar;

  /// No se le vende nada hasta que el jefe revise su cuenta: todas las líneas
  /// apagadas y sin botones (el porqué lo dice VENDER debajo).
  final bool frenadas;

  /// Cuántas lleva de cada línea, en el mismo orden.
  final List<int> cantidades;

  /// La línea [i] pasa a llevar [n].
  final void Function(int i, int n) alCambiar;

  /// Lo que vale cada entrada con el descuento de PRECIOS, y sin él (el precio
  /// de la General, que se ve tachado).
  final double precioConDescuento;
  final double precioEntero;

  /// Lo que vale hoy cada entrada sin descuento (la anticipada mientras rige).
  final double precioDelDia;
  final bool rigeLaAnticipada;

  /// El descuento de PRECIOS para los lugares que tenía al sorteo.
  final double descuentoPct;

  static String _entradas(int n) => n == 1 ? '1 entrada' : '$n entradas';

  String _titulo(LineaAPagar l) {
    if (l.cosa == CosaAPagar.mesa) {
      final numero = l.numeroEnElSalon;
      final cual = numero != null
          ? ' $numero'
          : (aPagar.mesasAdicionales > 1 ? ' ${l.mesa}' : '');
      final despues = l.conDescuento ? '' : ', agregada después del sorteo';
      return 'Mesa adicional$cual$despues · ${_entradas(l.entradas)}';
    }
    final una = l.cantidad == 1;
    final quien = una ? 'Silla extra' : 'Sillas extra';
    final despues = l.conDescuento
        ? ''
        : (una ? ', agregada después del sorteo' : ', agregadas después del sorteo');
    return '$quien$despues · ${_entradas(l.entradas)}';
  }

  /// Los lugares de la línea que ocupan sus VIP con cena (no se pagan).
  static int _deVip(LineaAPagar l) =>
      (l.cosa == CosaAPagar.mesa ? 8 : l.cantidad) - l.entradas;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < aPagar.lineas.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _linea(context, i),
          ],
        ],
      );

  /// Lo que dice una línea que ocupan sus VIP (revisión del 20-nov-2026: decía
  /// "2 lugares los ocupan un VIP").
  static String _notaDeVip(int vip) => vip == 1
      ? '1 lugar es de un VIP con cena: esa entrada no se paga.'
      : '$vip lugares son de VIP con cena: esas entradas no se pagan.';

  Widget _linea(BuildContext context, int i) {
    final l = aPagar.lineas[i];
    final clave = 'vender_linea_${claveDeLinea(l)}';
    final gris = Colors.grey.shade700;
    final naranja = Colors.orange.shade800;
    final precio = l.conDescuento ? precioConDescuento : precioDelDia;
    final vip = _deVip(l);
    final sinEntradas = l.entradas <= 0;
    final esperaElPago = !sinEntradas && l.habilitadas <= 0;
    final apagada = frenadas || sinEntradas || esperaElPago;
    // Lo que sigue "a confirmar" de esta línea: lo que espera el pago, menos lo
    // que ya compró antes de pagarlo (la 6.9.0 lo vendía igual).
    final porConfirmar = aConfirmar[i];
    final yaComproTodo = !sinEntradas && quedan[i] <= 0 && porConfirmar <= 0;

    final chip = ChipDeVender(
      l.conDescuento
          ? 'Con descuento ${porcentajeLegible(descuentoPct)} %'
          : 'Sin descuento',
      key: Key('${clave}_chip'),
      color: l.conDescuento ? Colors.teal.shade700 : Colors.blueGrey.shade700,
    );
    final elPrecio = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${pesos(precio)} c/u',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (l.conDescuento && precioEntero > precio) ...[
            const TextSpan(text: '  '),
            TextSpan(
              text: pesos(precioEntero),
              style: TextStyle(
                color: gris,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
          if (!l.conDescuento)
            TextSpan(
              text: rigeLaAnticipada ? ' · precio del día (anticipada)' : ' · precio del día',
              style: TextStyle(color: gris),
            ),
        ],
      ),
      key: Key('${clave}_precio'),
    );

    final notas = <Widget>[
      if (vip > 0 && !sinEntradas)
        Text(_notaDeVip(vip), style: TextStyle(fontSize: 12.5, color: gris)),
      // Lo que no se compra, dicho sin que parezca que el lugar no se paga: si
      // la familia lo debe, el lugar se paga en caja con el contrato (revisión
      // del 20-nov-2026).
      if (sinEntradas)
        Text(
          'La ocupan sus VIP con cena: no hay entradas para comprar.'
          '${l.pagaEntera ? '' : ' (el lugar se paga en caja con el contrato)'}',
          key: Key('${clave}_sin_entradas'),
          style: TextStyle(fontSize: 12.5, color: gris),
        ),
      if (porConfirmar > 0)
        Text(
          esperaElPago && porConfirmar >= l.entradas
              ? 'A confirmar: falta ${l.cantidad == 1 ? 'pagarla' : 'pagarlas'} en caja.'
              : '$porConfirmar a confirmar: falta pagarlas en caja.',
          key: Key('${clave}_a_confirmar'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: naranja,
          ),
        ),
      if (!frenadas && yaComproTodo)
        Text(
          'Ya compró las de esta línea.',
          key: Key('${clave}_ya_compro'),
          style: TextStyle(fontSize: 12.5, color: gris),
        )
      else if (!frenadas && !sinEntradas && l.habilitadas > 0 && quedan[i] <= 0)
        Text(
          'Ya compró las que están pagas.',
          key: Key('${clave}_ya_compro'),
          style: TextStyle(fontSize: 12.5, color: gris),
        ),
    ];

    // Apagado va solo lo que no se compra (el título, el chip y el precio): las
    // notas, con su color entero, que el "A confirmar" en naranja al 60 % casi
    // no se leía (revisión del 20-nov-2026).
    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: apagada ? 0.6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titulo(l),
                key: Key('${clave}_titulo'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [chip, if (!sinEntradas) elPrecio],
              ),
            ],
          ),
        ),
        ...notas,
      ],
    );

    final controles = apagada || quedan[i] <= 0
        ? null
        : ControlDeCantidad(
            clave: clave,
            cantidad: cantidades[i],
            tope: quedan[i],
            subtotal: deCentavos(centavos(precio) * cantidades[i]),
            alCambiar: (n) => alCambiar(i, n.clamp(0, quedan[i])),
          );

    return KeyedSubtree(
      key: Key(clave),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, caja) {
            if (controles == null) return nombre;
            if (caja.maxWidth < kVenderAngosto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nombre,
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: controles),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: nombre),
                const SizedBox(width: 12),
                controles,
              ],
            );
          },
        ),
      ),
    );
  }
}
