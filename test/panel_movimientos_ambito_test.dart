import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/models/egreso.dart';
import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/mi_empresa/widgets/panel_movimientos_sheet.dart';

/// Qué movimiento ve cada panel.
///
/// Apartar plata para el dueño es una transferencia entre dos bolsas: se
/// registra UNA vez y se ve desde los dos lados —salida en el negocio, entrada
/// en el bolsillo—. Si el negocio no la mostrara, faltarían $X en el historial
/// sin ninguna línea que lo explique.
void main() {
  Egreso eg(String categoria, {String? proveedor, double monto = 1000}) => Egreso(
        id: categoria,
        eventoId: '',
        monto: monto,
        proveedor: proveedor ?? categoria,
        categoria: categoria,
        fecha: DateTime.utc(2026, 8, 11, 15),
      );

  final retiroAlBolsillo = eg(kCategoriaRetiroDueno);
  final gastoPropio = eg(kCategoriaGastoPersonal, proveedor: '[pendiente] Feria');
  final gastoPropioDelNegocio =
      eg(kCategoriaGastoPersonal, proveedor: '[empresa] Nafta');
  final gastoEmpresa = eg(kCategoriaGastoEmpresa, proveedor: 'Maderas');
  final retiroDeCaja = eg(kCategoriaRetiroCaja);
  final pagoOperador = eg('Personal', proveedor: 'Operador Juan');
  final proveedores = eg('Proveedores', proveedor: 'Alquiler');

  final todos = [
    retiroAlBolsillo,
    gastoPropio,
    gastoPropioDelNegocio,
    gastoEmpresa,
    retiroDeCaja,
    pagoOperador,
    proveedores,
  ];

  group('panel BOLSILLO', () {
    final vistos = movimientosDelAmbito(todos, AmbitoPanel.bolsillo);

    test('muestra lo que apartaste y lo que gastaste', () {
      expect(vistos, contains(retiroAlBolsillo));
      expect(vistos, contains(gastoPropio));
      expect(vistos, contains(gastoPropioDelNegocio));
    });

    test('no mezcla gastos del negocio', () {
      expect(vistos, isNot(contains(gastoEmpresa)));
      expect(vistos, isNot(contains(retiroDeCaja)));
      expect(vistos, isNot(contains(pagoOperador)));
      expect(vistos, isNot(contains(proveedores)));
    });
  });

  group('panel NEGOCIO', () {
    final vistos = movimientosDelAmbito(todos, AmbitoPanel.negocio);

    test('muestra todo lo que le salió al negocio', () {
      expect(vistos, contains(proveedores));
      expect(vistos, contains(pagoOperador));
      expect(vistos, contains(gastoEmpresa));
      expect(vistos, contains(retiroDeCaja));
    });

    test('incluye lo apartado para el dueño: es plata que salió', () {
      expect(vistos, contains(retiroAlBolsillo));
    });

    test('incluye el gasto personal pagado con plata del negocio', () {
      expect(vistos, contains(gastoPropioDelNegocio));
    });

    test('excluye el gasto pagado desde el bolsillo: ya había salido', () {
      // Contarlo otra vez restaría dos veces la misma plata.
      expect(vistos, isNot(contains(gastoPropio)));
    });
  });

  test('el retiro al bolsillo aparece en los dos paneles, una vez en cada uno',
      () {
    final enNegocio = movimientosDelAmbito(todos, AmbitoPanel.negocio)
        .where((e) => e.id == kCategoriaRetiroDueno);
    final enBolsillo = movimientosDelAmbito(todos, AmbitoPanel.bolsillo)
        .where((e) => e.id == kCategoriaRetiroDueno);
    expect(enNegocio.length, 1);
    expect(enBolsillo.length, 1);
  });
}
