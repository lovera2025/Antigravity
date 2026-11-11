import '../datos/barra_repositorio.dart';
import 'pesos.dart';
import 'silla_de_la_puerta.dart';

/// Los ids de las ventas anuladas: una venta anulada no cuenta.
Set<String> ventasAnuladas(Iterable<AnulacionBarra> anulaciones) =>
    {for (final a in anulaciones) a.ventaId};

/// Lo vendido de un producto en una caja: cuántas unidades y cuánta plata, con el nombre
/// de la última venta (si el jefe le cambió el nombre en el medio, sale el último).
class VendidoDeProducto {
  final String productoId;
  final String nombre;
  final int unidades;
  final double plata;

  /// La categoría del catálogo ("Tragos"). Vacía si no tiene o si el producto ya no
  /// está en el catálogo de este equipo.
  final String categoria;

  const VendidoDeProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.plata,
    this.categoria = '',
  });
}

/// Lo vendido de una categoría del catálogo: el renglón del **cierre corto** (11-nov-2026),
/// que no crece con las ventas. Lleva adentro sus productos, para el detalle en la app.
class VendidoDeCategoria {
  /// "Tragos"; [sinCategoria] para lo que no tiene.
  final String nombre;
  final int unidades;
  final double plata;
  final List<VendidoDeProducto> productos;

  const VendidoDeCategoria({
    required this.nombre,
    required this.unidades,
    required this.plata,
    this.productos = const [],
  });

  /// Cómo se llama el grupo de lo que no tiene categoría.
  static const sinCategoria = 'Otros';
}

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

  /// Lo vendido que cuenta, por producto: el que más salió primero.
  final List<VendidoDeProducto> porProducto;

  /// Lo mismo, junto por categoría del catálogo: la que más salió primero, y "Otros"
  /// al final. Es lo que va al papel corto.
  final List<VendidoDeCategoria> porCategoria;

  /// Cuántas ventas que cuentan tuvieron algo por transferencia (las mixtas también):
  /// las que hay que mirar en Mercado Pago.
  final int conTransferencia;

  /// Cuántas unidades salieron, y de ellas cuántas sillas de la noche
  /// ([esSillaDeLaPuerta]): la puerta tiene que haber anotado esas mismas.
  /// [sillas] son las que van a una mesa; [sillasSueltas] ([esSillaSuelta],
  /// 6.5.0), las que no.
  final int unidades;
  final int sillas;
  final int sillasSueltas;

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
    this.porProducto = const [],
    this.porCategoria = const [],
    this.conTransferencia = 0,
    this.unidades = 0,
    this.sillas = 0,
    this.sillasSueltas = 0,
  });

  /// Las de [caja] entre [ventas]; las de otra caja no se cuentan. [categorias] es la
  /// categoría de cada producto del catálogo (id → "Tragos"): sin ella todo va a "Otros".
  factory CierreDeBarra.de(
    CajaBarra caja,
    Iterable<VentaBarra> ventas,
    Iterable<AnulacionBarra> anulaciones, {
    Map<String, String> categorias = const {},
  }) =>
      CierreDeBarra._contar(
        cajaId: caja.id,
        cambioInicial: caja.cambioInicial,
        ventas: ventas,
        anulaciones: anulaciones,
        categorias: categorias,
      );

  /// **Todas las cajas de la fiesta juntas** (LO VENDIDO DE LA FIESTA): las mismas
  /// cuentas, sin mirar de qué caja es cada venta. [cambioInicial] es la suma del cambio
  /// con que abrieron.
  factory CierreDeBarra.deLaFiesta(
    Iterable<VentaBarra> ventas,
    Iterable<AnulacionBarra> anulaciones, {
    double cambioInicial = 0,
    Map<String, String> categorias = const {},
  }) =>
      CierreDeBarra._contar(
        cajaId: null,
        cambioInicial: cambioInicial,
        ventas: ventas,
        anulaciones: anulaciones,
        categorias: categorias,
      );

  /// [cajaId] null: las de todas las cajas.
  factory CierreDeBarra._contar({
    required String? cajaId,
    required double cambioInicial,
    required Iterable<VentaBarra> ventas,
    required Iterable<AnulacionBarra> anulaciones,
    required Map<String, String> categorias,
  }) {
    final anuladasIds = ventasAnuladas(anulaciones);
    var cuentan = 0, anuladas = 0, mixtos = 0, conTransferencia = 0;
    var efectivo = 0, transferencia = 0, efectivoAnulado = 0, transferenciaAnulada = 0;
    var recargos = 0;
    var unidades = 0, sillas = 0, sueltas = 0;
    // Por producto, en el orden de las ventas: así el nombre que queda es el último.
    final nombres = <String, String>{};
    final cantidades = <String, int>{};
    final plata = <String, int>{};
    // Con todas las cajas juntas el número de ticket se repite: ahí manda la hora.
    final orden = [...ventas]..sort((a, b) {
        if (cajaId == null) {
          final n = a.createdAt.compareTo(b.createdAt);
          if (n != 0) return n;
        }
        return a.numero.compareTo(b.numero);
      });
    for (final v in orden) {
      if (cajaId != null && v.cajaBarraId != cajaId) continue;
      if (anuladasIds.contains(v.id)) {
        anuladas++;
        efectivoAnulado += centavos(v.efectivo);
        transferenciaAnulada += centavos(v.transferencia);
        continue;
      }
      cuentan++;
      if (v.medio == MedioBarra.mixto) mixtos++;
      if (centavos(v.transferencia) > 0) conTransferencia++;
      efectivo += centavos(v.efectivo);
      transferencia += centavos(v.transferencia);
      recargos += centavos(v.recargo);
      for (final r in v.renglones) {
        nombres[r.productoId] = r.nombre;
        cantidades[r.productoId] = (cantidades[r.productoId] ?? 0) + r.cantidad;
        plata[r.productoId] = (plata[r.productoId] ?? 0) + centavos(r.subtotal);
        unidades += r.cantidad;
        if (esSillaSuelta(r.nombre)) {
          sueltas += r.cantidad;
        } else if (esSillaDeLaPuerta(r.nombre)) {
          sillas += r.cantidad;
        }
      }
    }
    final porProducto = [
      for (final id in cantidades.keys)
        VendidoDeProducto(
          productoId: id,
          nombre: nombres[id]!,
          unidades: cantidades[id]!,
          plata: deCentavos(plata[id]!),
          categoria: (categorias[id] ?? '').trim(),
        ),
    ]..sort((a, b) {
        final n = b.unidades.compareTo(a.unidades);
        return n != 0 ? n : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    // Por categoría: "Tragos" y "tragos" son la misma, con el nombre de la primera.
    final grupos = <String, List<VendidoDeProducto>>{};
    final rotulos = <String, String>{};
    for (final p in porProducto) {
      final clave = p.categoria.toLowerCase();
      grupos.putIfAbsent(clave, () => []).add(p);
      rotulos.putIfAbsent(
        clave,
        () => p.categoria.isEmpty ? VendidoDeCategoria.sinCategoria : p.categoria,
      );
    }
    final porCategoria = [
      for (final e in grupos.entries)
        VendidoDeCategoria(
          nombre: rotulos[e.key]!,
          unidades: e.value.fold(0, (s, p) => s + p.unidades),
          plata: deCentavos(e.value.fold(0, (s, p) => s + centavos(p.plata))),
          productos: List.unmodifiable(e.value),
        ),
    ]..sort((a, b) {
        // Lo que no tiene categoría, al final.
        final sinA = a.nombre == VendidoDeCategoria.sinCategoria ? 1 : 0;
        final sinB = b.nombre == VendidoDeCategoria.sinCategoria ? 1 : 0;
        if (sinA != sinB) return sinA - sinB;
        final n = b.unidades.compareTo(a.unidades);
        return n != 0 ? n : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return CierreDeBarra(
      cambioInicial: cambioInicial,
      ventas: cuentan,
      anuladas: anuladas,
      mixtos: mixtos,
      efectivo: deCentavos(efectivo),
      transferencia: deCentavos(transferencia),
      efectivoAnulado: deCentavos(efectivoAnulado),
      transferenciaAnulada: deCentavos(transferenciaAnulada),
      recargos: deCentavos(recargos),
      porProducto: List.unmodifiable(porProducto),
      porCategoria: List.unmodifiable(porCategoria),
      conTransferencia: conTransferencia,
      unidades: unidades,
      sillas: sillas,
      sillasSueltas: sueltas,
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

  /// Las sillas de la noche vendidas en todas las cajas (sin las anuladas): las que la
  /// puerta tendría que haber anotado. Las de mesa y, aparte, las sueltas (6.5.0).
  final int sillas;
  final int sillasSueltas;

  /// El cambio con que abrieron todas las cajas.
  final double cambio;

  /// Las cuentas de **toda la fiesta**, con las cajas juntas: lo vendido por producto y
  /// por categoría (LO VENDIDO DE LA FIESTA, 11-nov-2026).
  final CierreDeBarra? deLaFiesta;

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
    this.sillas = 0,
    this.sillasSueltas = 0,
    this.cambio = 0,
    this.deLaFiesta,
  });

  factory ResumenDeCajas.de({
    required Iterable<CajaBarra> cajas,
    required Iterable<VentaBarra> ventas,
    required Iterable<AnulacionBarra> anulaciones,
    Map<String, String> categorias = const {},
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
        ResumenDeCaja(
          c,
          CierreDeBarra.de(c, listaVentas, listaAnulaciones, categorias: categorias),
        ),
    ];
    // Solo lo de las cajas de esta lista: una venta de otra fiesta no entra.
    final idsDeCajas = {for (final c in ordenadas) c.id};
    var v = 0, an = 0, mx = 0, si = 0, su = 0;
    var ef = 0, tr = 0, rec = 0, cont = 0, dif = 0, cam = 0;
    for (final r in resumenes) {
      v += r.cuentas.ventas;
      an += r.cuentas.anuladas;
      mx += r.cuentas.mixtos;
      si += r.cuentas.sillas;
      su += r.cuentas.sillasSueltas;
      cam += centavos(r.caja.cambioInicial);
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
      sillas: si,
      sillasSueltas: su,
      cambio: deCentavos(cam),
      deLaFiesta: CierreDeBarra.deLaFiesta(
        [for (final x in listaVentas) if (idsDeCajas.contains(x.cajaBarraId)) x],
        listaAnulaciones,
        cambioInicial: deCentavos(cam),
        categorias: categorias,
      ),
    );
  }

  double get total => deCentavos(centavos(efectivo) + centavos(transferencia));

  int get abiertas => cajas.where((c) => c.caja.abierta).length;
}
