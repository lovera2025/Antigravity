import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../barra/cuentas/pesos.dart';
import 'cobro_abono_acumulado.dart';
import 'mesas_extra_utils.dart';
import 'salon_mesas.dart';

/// Una mesa adicional que todavía no está paga entera: **"a confirmar"**
/// (pedido del jefe, 16-nov-2026).
///
/// La noche de la fiesta la recepcionista la ve apagada, sin palabras de plata
/// ni botones ("Esta mesa la confirma el jefe"); el tótem no la enciende; y en
/// el PLANO, solo en modo jefe, se la cobra o se la anula.
class AdicionalAConfirmar {
  /// La adicional de la familia (1 es la primera adicional, después de la
  /// principal).
  final int n;

  /// Su mesa en el salón, o null si no salió en el sorteo (se sorteó solo la
  /// base porque no estaba paga).
  final int? mesa;

  final double precio;

  /// Lo pagado de esta adicional, de los pagos: lo de las mesas se reparte de
  /// la primera adicional a la última.
  final double pagado;

  const AdicionalAConfirmar({
    required this.n,
    required this.mesa,
    required this.precio,
    required this.pagado,
  });

  double get aPagar => max(0, precio - pagado);

  /// Esa noche se anula solo si no tiene nada pagado (decisión del usuario,
  /// 16-nov-2026): con algo pagado queda "a confirmar" y el jefe decide
  /// después, en la oficina, si devuelve o deja a cuenta.
  bool get sePuedeAnular => pagado <= 0.01;
}

/// Por qué una adicional con algo pagado no se anula esa noche. Lo dicen la
/// tarjeta del PLANO, debajo de ANULAR apagado, y el aviso si se llega igual.
/// Lleva plata: es solo para el jefe.
String textoNoSeAnula(AdicionalAConfirmar x) =>
    'Tiene ${pesos(x.pagado)} pagado: esta noche no se anula. Decidilo en la '
    'oficina.';

/// Las mesas adicionales "a confirmar" de una familia. Sin pantalla ni base.
///
/// **Sale de los pagos, nunca de los campos del contrato** (`mesa_extra_pagado`
/// y compañía pueden no coincidir con los pagos): lo de las mesas
/// ([grossHistoricoClaseCobro], que ya saca lo anulado, la mora y el costo por
/// transferencia, y cuenta lo perdonado) se reparte de la primera adicional a
/// la última, como en la cuenta del alumno
/// ([MesasExtraUtils.repartirPagadoFifo]). La que no queda cubierta entera
/// está "a confirmar".
///
/// **Sin los pagos (null) no hay nada a confirmar**: una pantalla que todavía
/// no los leyó no puede marcar una mesa.
class AdicionalesDeLaFamilia {
  AdicionalesDeLaFamilia._();

  static List<AdicionalAConfirmar> aConfirmar(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>>? pagos,
  ) {
    if (pagos == null) return const [];
    final extra = SalonMesas.mesasExtra(a);
    final unit = SalonMesas.precioUnitarioMesa(a);
    if (extra < 1 || unit == null) return const [];
    // Sin mesa todavía (antes del sorteo, o sin nada pagado de la base): no
    // hay nada que confirmar en la puerta.
    final numeros = [for (final t in SalonMesas.tramos(a)) ...t];
    if (numeros.isEmpty) return const [];
    final items = MesasExtraUtils.repartirPagadoFifo(
      cantidad: extra,
      precioUnitario: unit,
      cuotasPlan: max(1, a.mesaExtraCuotas),
      pagadoTotal: grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
    );
    return [
      for (var k = 1; k <= extra && k <= items.length; k++)
        if (!items[k - 1].liquidada)
          AdicionalAConfirmar(
            n: k,
            mesa: k < numeros.length ? numeros[k] : null,
            precio: items[k - 1].precio,
            pagado: items[k - 1].pagado,
          ),
    ];
  }

  /// Los números de mesa "a confirmar" de la familia.
  static Set<int> mesas(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>>? pagos,
  ) =>
      {
        for (final x in aConfirmar(a, pagos))
          if (x.mesa != null) x.mesa!,
      };

  /// Cuántas adicionales "a confirmar" no tienen mesa (no salieron en el
  /// sorteo).
  static int sinMesa(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>>? pagos,
  ) =>
      aConfirmar(a, pagos).where((x) => x.mesa == null).length;
}
