import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/models/egreso.dart';
import 'package:arguello_events/features/mi_empresa/bolsa_personal_helpers.dart';

/// El prefijo de bolsa (`[pendiente]` / `[empresa]`) no se muestra nunca.
///
/// Es una marca interna que dice de qué bolsa salió la plata, y se estaba
/// filtrando a 12 pantallas y a 4 celdas del cierre de caja impreso. Ahí
/// `[pendiente] Supermercado` se lee como "falta pagarlo" cuando significa lo
/// contrario: ya se pagó, del bolsillo del dueño.
void main() {
  Egreso eg(String? proveedor, {String? categoria}) => Egreso(
        id: 'x',
        eventoId: '',
        monto: 100,
        proveedor: proveedor,
        categoria: categoria,
      );

  group('Egreso.proveedorVisible', () {
    test('saca el prefijo [pendiente]', () {
      expect(eg('[pendiente] Supermercado').proveedorVisible, 'Supermercado');
    });

    test('saca el prefijo [empresa]', () {
      expect(eg('[empresa] Nafta').proveedorVisible, 'Nafta');
    });

    test('un concepto sin prefijo queda intacto', () {
      expect(eg('Maderas del Litoral').proveedorVisible, 'Maderas del Litoral');
    });

    test('no confunde un concepto que arranca con corchete', () {
      expect(eg('[urgente] Flete').proveedorVisible, '[urgente] Flete');
    });

    test('null cuando no queda nada, para que cada pantalla ponga su respaldo',
        () {
      // El cierre de caja pone "Egreso"; el bolsillo, "Gasto personal".
      expect(eg(null).proveedorVisible, isNull);
      expect(eg('   ').proveedorVisible, isNull);
      expect(eg('[pendiente]').proveedorVisible, isNull);
    });

    test('el helper de string suelto sigue dando el respaldo del bolsillo', () {
      expect(proveedorGastoPersonalVisible('[pendiente] Feria'), 'Feria');
      expect(proveedorGastoPersonalVisible(null), 'Gasto personal');
    });
  });

  group('la clasificación de bolsa sigue leyendo el campo crudo', () {
    test('el prefijo se conserva en proveedor aunque no se muestre', () {
      final e = eg('[empresa] Nafta');
      expect(e.proveedor, '[empresa] Nafta');
      expect(gastoPersonalEsDesdeEmpresa(e), isTrue);
    });

    test('un gasto [pendiente] no resta del saldo de empresa', () {
      final e = eg('[pendiente] Feria', categoria: 'Gasto personal');
      expect(finanzasEgresoAfectaCajaEmpresa(e), isFalse);
    });

    test('un gasto [empresa] sí resta del saldo de empresa', () {
      final e = eg('[empresa] Nafta', categoria: 'Gasto personal');
      expect(finanzasEgresoAfectaCajaEmpresa(e), isTrue);
    });
  });
}
