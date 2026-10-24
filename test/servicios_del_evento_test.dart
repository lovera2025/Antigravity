// La lista de servicios del evento particular (6.2.1): el detalle de cada uno
// (lo que el cliente buscaba), los combos juntos, los extras marcados y la
// cantidad tal cual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/widgets/servicios_del_evento.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/servicio.dart';

EventosServicios _linea(
  String id,
  String nombre, {
  double precio = 100000,
  double cantidad = 1,
  String? grupo,
  int orden = 0,
  bool extra = false,
  String? detalle,
}) =>
    EventosServicios(
      id: id,
      eventoId: 'e',
      servicioId: 's$id',
      precioFinalAcordado: precio,
      cantidad: cantidad,
      grupo: grupo,
      comboOrden: orden,
      esExtra: extra,
      detalleServicio: detalle,
      servicio: Servicio.fromJson({'id': 's$id', 'nombre': nombre}),
    );

final _ejemplo = [
  _linea('1', 'Barra libre', precio: 300000, cantidad: 1.5, detalle: 'Fernet, cerveza y gaseosas'),
  _linea('3', 'Iluminación', precio: 0, grupo: 'Combo Fiesta', orden: 1, detalle: 'Robóticas'),
  _linea('2', 'DJ', precio: 500000, grupo: 'Combo Fiesta', orden: 0, detalle: '5 hs con pantalla LED'),
  _linea('4', 'Mesa dulce', precio: 150000, extra: true, detalle: 'Para 120 personas'),
];

void main() {
  test('los combos van juntos, en su orden, donde aparece el primero', () {
    final b = bloquesDeServicios(_ejemplo);
    expect(b.map((x) => x.combo), [null, 'Combo Fiesta', null]);
    expect(b[1].lineas.map((l) => l.id), ['2', '3']);
    expect(b[1].total, 500000);
  });

  test('un extra no suma al bloque', () {
    final b = bloquesDeServicios(_ejemplo);
    expect(b.last.total, 0);
    expect(b.first.total, 450000);
  });

  test('la cantidad tal cual', () {
    expect(cantidadParaMostrar(1.5), '1,5');
    expect(cantidadParaMostrar(2), '2');
    expect(cantidadParaMostrar(2.25), '2,25');
  });

  test('el detalle solo si dice algo más que el nombre', () {
    expect(detalleDelServicio(_ejemplo.first), 'Fernet, cerveza y gaseosas');
    expect(detalleDelServicio(_linea('9', 'DJ', detalle: 'DJ')), isNull);
    expect(detalleDelServicio(_linea('9', 'DJ')), isNull);
  });

  test('sin el servicio en el catálogo, el nombre sale del detalle', () {
    final suelto = EventosServicios(
      id: '9',
      eventoId: 'e',
      servicioId: 'x',
      precioFinalAcordado: 1,
      detalleServicio: 'Show de magia',
    );
    expect(nombreDelServicio(suelto), 'Show de magia');
  });

  testWidgets('se ve el detalle, el combo, la marca de extra y 1,5', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServiciosDelEvento(servicios: _ejemplo, onEditar: () {}),
          ),
        ),
      ),
    );
    expect(find.text('SERVICIOS'), findsOneWidget);
    expect(find.text('PROVEEDORES ASIGNADOS'), findsNothing);
    expect(find.text('Fernet, cerveza y gaseosas'), findsOneWidget);
    expect(find.text('5 hs con pantalla LED'), findsOneWidget);
    expect(find.text('Para 120 personas'), findsOneWidget);
    expect(find.text('CANTIDAD: 1,5'), findsOneWidget);
    expect(find.text('EXTRA · no suma al total'), findsOneWidget);
    expect(find.byKey(const Key('combo_Combo Fiesta')), findsOneWidget);
    expect(find.text('Combo Fiesta'), findsOneWidget);
  });
}
