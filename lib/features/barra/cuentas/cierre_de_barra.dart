import '../datos/barra_repositorio.dart';
import 'pesos.dart';

/// Los ids de las ventas anuladas: una venta anulada no cuenta.
Set<String> ventasAnuladas(Iterable<AnulacionBarra> anulaciones) =>
    {for (final a in anulaciones) a.ventaId};

/// Las cuentas de una caja de barra: qué se vendió, cómo se cobró y cuánto efectivo
/// tiene que haber. Es lo que ve la cajera después de contar a ciegas, y lo que ve el
/// jefe por caja.
///
/// **Una venta anulada no cuenta, tampoco en el efectivo esperado:** se supone que esa
/// plata se devolvió (decisión del 3-nov). Lo anulado se muestra aparte.
class CierreDeBarra {
  final double cambioInicial;

  /// Las que cuentan: sin las anuladas.
  final int ventas;
  final int anuladas;
  final int mixtos;
  final double efectivo;
  final double transferencia;
  final double efectivoAnulado;
  final double transferenciaAnulada;

  /// De lo cobrado por transferencia, lo que fue recargo: no es de ninguna bebida.
  final double recargos;

  const CierreDeBarra({
    required this.cambioInicial,
    required this.ventas,
    required this.anuladas,
    required this.mixtos,
    required this.efectivo,
    required this.transferencia,
    required this.efectivoAnulado,
    required this.transferenciaAnulada,
    this.recargos = 0,
  });

  /// Las de [caja] entre [ventas]; las de otra caja no se cuentan.
  factory CierreDeBarra.de(
    CajaBarra caja,
    Iterable<VentaBarra> ventas,
    Iterable<AnulacionBarra> anulaciones,
  ) {
    final anuladasIds = ventasAnuladas(anulaciones);
    var cuentan = 0, anuladas = 0, mixtos = 0;
    var efectivo = 0, transferencia = 0, efectivoAnulado = 0, transferenciaAnulada = 0;
    var recargos = 0;
    for (final v in ventas) {
      if (v.cajaBarraId != caja.id) continue;
      if (anuladasIds.contains(v.id)) {
        anuladas++;
        efectivoAnulado += centavos(v.efectivo);
        transferenciaAnulada += centavos(v.transferencia);
        continue;
      }
      cuentan++;
      if (v.medio == MedioBarra.mixto) mixtos++;
      efectivo += centavos(v.efectivo);
      transferencia += centavos(v.transferencia);
      recargos += centavos(v.recargo);
    }
    return CierreDeBarra(
      cambioInicial: caja.cambioInicial,
      ventas: cuentan,
      anuladas: anuladas,
      mixtos: mixtos,
      efectivo: deCentavos(efectivo),
      transferencia: deCentavos(transferencia),
      efectivoAnulado: deCentavos(efectivoAnulado),
      transferenciaAnulada: deCentavos(transferenciaAnulada),
      recargos: deCentavos(recargos),
    );
  }

  /// Lo cobrado que cuenta, en efectivo y por transferencia (con los recargos).
  double get total => deCentavos(centavos(efectivo) + centavos(transferencia));

  /// El cambio con que abrió más el efectivo de lo vendido.
  double get efectivoEsperado => deCentavos(centavos(cambioInicial) + centavos(efectivo));

  /// Lo contado menos lo esperado: positivo sobra, negativo falta.
  double diferenciaCon(double contado) =>
      deCentavos(centavos(contado) - centavos(efectivoEsperado));
}

/// La diferencia en palabras, para la pantalla y el papel.
String diferenciaEnPalabras(double diferencia) {
  final c = centavos(diferencia);
  if (c == 0) return 'Justo, sin diferencia';
  return c > 0 ? 'Sobran ${pesos(diferencia)}' : 'Faltan ${pesos(-diferencia)}';
}

/// Una caja en el resumen del jefe: la caja como está guardada y sus cuentas.
///
/// **La diferencia es la que se anotó al cerrar**, no una cuenta de ahora: si el jefe
/// anula una venta después del cierre, el cierre no se corrige.
class ResumenDeCaja {
  final CajaBarra caja;
  final CierreDeBarra cuentas;

  const ResumenDeCaja(this.caja, this.cuentas);

  double? get contado => caja.efectivoContado;
  double? get diferencia => caja.diferencia;
}

/// CAJAS del jefe: cada caja de la fiesta y los totales.
class ResumenDeCajas {
  final List<ResumenDeCaja> cajas;
  final int ventas;
  final int anuladas;
  final int mixtos;
  final double efectivo;
  final double transferencia;
  final double recargos;

  /// La suma de lo contado y de las diferencias, **de las cajas ya cerradas**.
  final double contado;
  final double diferencia;

  const ResumenDeCajas({
    required this.cajas,
    required this.ventas,
    required this.anuladas,
    required this.mixtos,
    required this.efectivo,
    required this.transferencia,
    this.recargos = 0,
    required this.contado,
    required this.diferencia,
  });

  factory ResumenDeCajas.de({
    required Iterable<CajaBarra> cajas,
    required Iterable<VentaBarra> ventas,
    required Iterable<AnulacionBarra> anulaciones,
  }) {
    final listaVentas = ventas.toList();
    final listaAnulaciones = anulaciones.toList();
    final ordenadas = cajas.toList()
      ..sort((a, b) {
        final n = a.numeroCaja.compareTo(b.numeroCaja);
        return n != 0 ? n : a.abiertaAt.compareTo(b.abiertaAt);
      });
    final resumenes = [
      for (final c in ordenadas)
        ResumenDeCaja(c, CierreDeBarra.de(c, listaVentas, listaAnulaciones)),
    ];
    var v = 0, an = 0, mx = 0;
    var ef = 0, tr = 0, rec = 0, cont = 0, dif = 0;
    for (final r in resumenes) {
      v += r.cuentas.ventas;
      an += r.cuentas.anuladas;
      mx += r.cuentas.mixtos;
      ef += centavos(r.cuentas.efectivo);
      tr += centavos(r.cuentas.transferencia);
      rec += centavos(r.cuentas.recargos);
      if (!r.caja.abierta) {
        cont += centavos(r.contado ?? 0);
        dif += centavos(r.diferencia ?? 0);
      }
    }
    return ResumenDeCajas(
      cajas: resumenes,
      ventas: v,
      anuladas: an,
      mixtos: mx,
      efectivo: deCentavos(ef),
      transferencia: deCentavos(tr),
      recargos: deCentavos(rec),
      contado: deCentavos(cont),
      diferencia: deCentavos(dif),
    );
  }

  double get total => deCentavos(centavos(efectivo) + centavos(transferencia));

  int get abiertas => cajas.where((c) => c.caja.abierta).length;
}
