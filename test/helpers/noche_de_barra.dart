// Una noche inventada de la barra, en memoria: TÉCNICA PINAROLI (el 4 de diciembre) con
// su catálogo, sus precios, tres cajas (dos abiertas y una cerrada con $ 500 de menos),
// 60 ventas y una anulada. La usan las muestras de BARRA del jefe
// (`tool/barra_jefe_muestra_test.dart`), el arnés de la web (`tool/barra_web_prueba.dart`)
// y sus tests. Nada toca la base ni la nube.
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/services/imagen_de_producto.dart';

import 'barra_en_memoria.dart';
import 'operadores_en_memoria.dart';

/// Lo que deja armado [nocheDeBarra].
class NocheDeBarra {
  final BarraEnPrueba prueba;
  final OperadoresEnPrueba operadores;

  /// La Caja 1, de Marta: abierta, con ventas.
  final CajaBarra marta;

  /// La fiesta de la noche.
  final String pinaroliId;

  const NocheDeBarra({
    required this.prueba,
    required this.operadores,
    required this.marta,
    required this.pinaroliId,
  });
}

/// Arma la noche. Con [fotos], cada producto trae su foto de la biblioteca (para
/// mirarla); sin eso, la inicial (los tests no leen archivos).
Future<NocheDeBarra> nocheDeBarra({bool fotos = true}) async {
  final operadores = OperadoresEnPrueba();
  final prueba = BarraEnPrueba();
  if (fotos) prueba.imagen = imagenDelProducto;
  final pinaroli = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
  prueba.eventos.addAll([
    pinaroli,
    fiestaDePrueba(BarraEnPrueba.id(2), 'ROTONDA', DateTime(2026, 12, 12, 22)),
    fiestaDePrueba(BarraEnPrueba.id(3), 'GUEMEZ DE TEJADA', DateTime(2026, 12, 18, 22)),
    fiestaDePrueba(BarraEnPrueba.id(4), 'LA DE OCTUBRE', DateTime(2026, 10, 30, 22)),
  ]);
  final b = prueba.barra;
  final productos = <(ProductoBarra, double, int?, int?)>[];
  var orden = 0;
  for (final (nombre, categoria, precio, stock, aviso) in [
    ('Fernet con coca', 'Tragos', 6000.0, 120, 20),
    ('Gin tonic', 'Tragos', 6500.0, 80, 15),
    ('Mojito', 'Tragos', 6500.0, 60, 10),
    ('Campari con naranja', 'Tragos', 6000.0, 40, 8),
    ('Speed con vodka', 'Tragos', 6500.0, 30, 5),
    ('Cerveza tirada', 'Cervezas', 4000.0, 200, 30),
    ('Quilmes lata', 'Cervezas', 3500.0, 96, 12),
    ('Coca-Cola', 'Sin alcohol', 2500.0, 72, 12),
    ('Agua sin gas', 'Sin alcohol', 2000.0, null, null),
    ('Champán', 'Botellas', 35000.0, 12, 2),
    ('Silla extra', 'Otros', 8000.0, null, null),
  ]) {
    final p = b.producto(nombre, categoria: categoria, orden: orden++);
    b.precio(pinaroli.id, p, precio, orden: orden, stock: stock, aviso: aviso);
    productos.add((p, precio, stock, aviso));
  }
  final redBull = b.producto('Red Bull', categoria: 'Sin alcohol', orden: orden);
  await b.guardarProducto(redBull.conCambios(activo: false), quien: 'Jefe');
  await b.guardarRecargo(
    RecargoBarra.para(eventoId: pinaroli.id, pct: 5, ahora: DateTime(2026, 11, 1)),
    quien: 'Jefe',
  );

  var hora = DateTime.utc(2026, 12, 5, 1, 5); // 22:05 en Argentina
  b.reloj = () => hora;
  final cajas = <CajaBarra>[];
  for (final (numero, nombre) in [(1, 'Marta'), (2, 'Sofía'), (3, 'Lucas')]) {
    cajas.add(await b.abrirCaja(eventoId: pinaroli.id, operadorId: 'op$numero', operadorNombre: nombre, numeroCaja: numero));
    hora = hora.add(const Duration(minutes: 5));
  }
  VentaBarra? anular;
  for (var i = 0; i < 60; i++) {
    hora = hora.add(Duration(minutes: 2 + i % 3));
    final caja = cajas[i % 3];
    final (p, precio, _, _) = productos[(i * 7) % productos.length];
    final n = 1 + i % 3;
    final total = precio * n;
    final transferencia = i % 4 == 1;
    final recargo = transferencia ? (total * 0.05).roundToDouble() : 0.0;
    final v = await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: n)],
      medio: transferencia ? MedioBarra.transferencia : MedioBarra.efectivo,
      efectivo: transferencia ? 0 : total,
      transferencia: transferencia ? total + recargo : 0,
      recargo: recargo,
      recargoPct: transferencia ? 5 : null,
      quien: caja.operadorNombre!,
    );
    await b.anotarVale(ValeBarra.salio(
      venta: v,
      bebidas: [BebidaDelVale(n, p.nombre)],
      porSeparado: false,
      hechoPor: caja.operadorNombre,
      ahora: hora,
    ));
    if (i == 9) anular = v;
  }
  await b.anular(anular!, motivo: 'se cobró dos veces', quien: 'Marta');
  hora = hora.add(const Duration(minutes: 30));
  final lucas = cajas[2];
  final ventasLucas = await b.ventasDeLaCaja(lucas.id);
  final efectivo = ventasLucas.fold<double>(0, (s, v) => s + v.efectivo);
  await b.cerrarCaja(lucas, efectivoContado: efectivo - 500, diferencia: -500, quien: 'Lucas');
  // Lo que subió, subió: la web lo ve todo.
  b.sinSubir.clear();
  return NocheDeBarra(prueba: prueba, operadores: operadores, marta: cajas.first, pinaroliId: pinaroli.id);
}
