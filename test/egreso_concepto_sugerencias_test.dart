import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/egresos/services/egreso_concepto_sugerencias.dart';
import 'package:arguello_events/models/egreso.dart';

void main() {
  EgresoConceptoFila fila({
    required String proveedor,
    required String categoria,
    double monto = 100,
    DateTime? fecha,
    String? eventoTipo,
  }) {
    return EgresoConceptoFila(
      proveedor: proveedor,
      categoria: categoria,
      monto: monto,
      fecha: fecha,
      eventoTipo: eventoTipo,
    );
  }

  group('alias Operadores / Personal', () {
    test('el combo Operadores se guarda como Personal', () {
      expect(categoriaEgresoParaGuardar('Operadores'), kCategoriaPersonal);
      expect(categoriaEgresoParaGuardar('Proveedores'), 'Proveedores');
    });

    test('Personal se muestra como Operadores en el combo', () {
      expect(categoriaEgresoParaCombo('Personal'), kCategoriaOperadores);
      expect(categoriaEgresoParaCombo('Proveedores'), 'Proveedores');
    });

    test('el desglose junta Personal y Operadores en un solo rubro', () {
      expect(rubroDesgloseEgreso('Personal'), kCategoriaOperadores);
      expect(rubroDesgloseEgreso('Operadores'), kCategoriaOperadores);
      expect(rubroDesgloseEgreso('Proveedores'), 'Proveedores');
      expect(rubroDesgloseEgreso(''), 'Sin categoría');
    });

    test('esCategoriaOperador acepta las dos grafías', () {
      expect(esCategoriaOperador('Personal'), isTrue);
      expect(esCategoriaOperador('Operadores'), isTrue);
      expect(esCategoriaOperador('Proveedores'), isFalse);
    });
  });

  group('buscador de nombres', () {
    test('excluye bolsillo (categoría y prefijos) de las sugerencias', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(proveedor: 'JUAN', categoria: 'Personal'),
        fila(proveedor: 'PAGO GALPON', categoria: 'Proveedores'),
        fila(proveedor: 'Supermercado', categoria: kCategoriaGastoPersonal),
        fila(proveedor: 'Aparté', categoria: kCategoriaRetiroDueno),
        fila(
          proveedor: '$kPrefijoGastoPersonalEmpresa Nafta',
          categoria: 'Proveedores',
        ),
        fila(
          proveedor: '$kPrefijoGastoPersonalPendiente Feria',
          categoria: 'Otro',
        ),
      ]);
      expect(s.nombresUnicos, ['JUAN', 'PAGO GALPON']);
    });

    test('filtra contains case-insensitive y no fusiona variantes', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(proveedor: 'PAGO GALPON', categoria: 'Proveedores'),
        fila(proveedor: 'GALPON', categoria: 'Proveedores'),
        fila(proveedor: 'JUAN', categoria: 'Personal'),
      ]);
      expect(s.filtrarNombres('gal').toList(), ['PAGO GALPON', 'GALPON']);
      expect(s.filtrarNombres('').toList(), isEmpty);
    });

    test('nombre conocido copia la última categoría; el nuevo no inventa', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(
          proveedor: 'PAGO GALPON',
          categoria: 'Logística',
          fecha: DateTime.utc(2026, 8, 1),
        ),
        fila(
          proveedor: 'PAGO GALPON',
          categoria: 'Proveedores',
          fecha: DateTime.utc(2026, 8, 10),
        ),
        fila(
          proveedor: 'JUAN',
          categoria: 'Personal',
          fecha: DateTime.utc(2026, 8, 5),
        ),
      ]);
      expect(s.categoriaComboAlElegir('PAGO GALPON'), 'Proveedores');
      expect(s.categoriaComboAlElegir('pago galpon'), 'Proveedores');
      expect(s.categoriaComboAlElegir('JUAN'), kCategoriaOperadores);
      expect(s.categoriaComboAlElegir('CHISPAS'), isNull);
    });

    test('al elegir se usa el string canónico del historial', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(proveedor: 'PAGO GALPON', categoria: 'Proveedores'),
      ]);
      expect(s.nombreCanonico('pago galpon'), 'PAGO GALPON');
      expect(s.nombreCanonico('CHISPAS'), 'CHISPAS');
    });

    test('si hay dos grafías del mismo lower-case, gana la más reciente', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(
          proveedor: 'Juan',
          categoria: 'Operadores',
          fecha: DateTime.utc(2026, 1, 1),
        ),
        fila(
          proveedor: 'JUAN',
          categoria: 'Personal',
          fecha: DateTime.utc(2026, 8, 1),
        ),
      ]);
      expect(s.nombreCanonico('juan'), 'JUAN');
    });
  });

  group('monto y chips de operador', () {
    test('no sugiere monto si el nombre no es operador', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(proveedor: 'PAGO GALPON', categoria: 'Proveedores', monto: 500),
      ]);
      expect(s.montoSugeridoOperador('PAGO GALPON'), isNull);
    });

    test('moda del operador; empate usa el más reciente', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(
          proveedor: 'JUAN',
          categoria: 'Personal',
          monto: 80000,
          fecha: DateTime.utc(2026, 8, 10),
          eventoTipo: '15_años',
        ),
        fila(
          proveedor: 'JUAN',
          categoria: 'Operadores',
          monto: 70000,
          fecha: DateTime.utc(2026, 7, 1),
          eventoTipo: '15_años',
        ),
        fila(
          proveedor: 'JUAN',
          categoria: 'Personal',
          monto: 70000,
          fecha: DateTime.utc(2026, 6, 1),
          eventoTipo: '15_años',
        ),
      ]);
      expect(s.montoSugeridoOperador('JUAN', tipoEvento: '15 años'), 70000);
    });

    test('chips por tipo agrupan Personal y Operadores', () {
      final s = EgresoConceptoSugerencias.fromFilas([
        fila(
          proveedor: 'JUAN',
          categoria: 'Personal',
          monto: 50000,
          eventoTipo: 'boda',
        ),
        fila(
          proveedor: 'PEDRO',
          categoria: 'Operadores',
          monto: 40000,
          eventoTipo: 'boda',
        ),
        fila(
          proveedor: 'ANA',
          categoria: 'Personal',
          monto: 30000,
          eventoTipo: 'bautismo',
        ),
      ]);
      final chips = s.operadoresParaTipo('Boda');
      expect(chips.map((e) => e.key).toList(), ['JUAN', 'PEDRO']);
      expect(s.operadoresParaTipo('bautismo').single.key, 'ANA');
    });
  });

  group('fromEgresos', () {
    test('arma el índice desde el modelo', () {
      final s = EgresoConceptoSugerencias.fromEgresos([
        Egreso(
          id: '1',
          eventoId: 'ev',
          monto: 10,
          proveedor: 'JUAN',
          categoria: 'Personal',
        ),
        Egreso(
          id: '2',
          eventoId: '',
          monto: 20,
          proveedor: '[pendiente] Súper',
          categoria: kCategoriaGastoPersonal,
        ),
      ], tipoPorEventoId: const {'ev': 'boda'});
      expect(s.nombresUnicos, ['JUAN']);
      expect(s.operadoresParaTipo('boda').single.value, 10);
    });
  });
}
