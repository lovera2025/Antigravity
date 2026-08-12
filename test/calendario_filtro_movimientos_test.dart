import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/mi_empresa/widgets/calendario_filtro_movimientos.dart';

/// El día que muestra la fila y el día por el que filtra el calendario tienen
/// que ser el mismo. Las fechas se guardan en UTC y se leen en hora argentina
/// (UTC−3), así que todo lo cargado después de las 21:00 cae en el día
/// siguiente si se compara mal.
void main() {
  group('claveDiaAr', () {
    test('un gasto de las 22:00 AR pertenece a ESE día, no al siguiente', () {
      // 11/08/2026 22:30 AR == 12/08/2026 01:30 UTC.
      final utc = DateTime.utc(2026, 8, 12, 1, 30);
      expect(RangoFiltroMovimientos.claveDiaAr(utc), '2026-08-11');
    });

    test('las 00:30 AR siguen siendo el día que arranca', () {
      // 12/08/2026 00:30 AR == 12/08/2026 03:30 UTC.
      final utc = DateTime.utc(2026, 8, 12, 3, 30);
      expect(RangoFiltroMovimientos.claveDiaAr(utc), '2026-08-12');
    });

    test('el mes también se corta en hora argentina', () {
      // 31/08/2026 23:00 AR == 01/09/2026 02:00 UTC: es agosto, no septiembre.
      final utc = DateTime.utc(2026, 9, 1, 2);
      expect(RangoFiltroMovimientos.claveMesAr(utc), '2026-08');
    });
  });

  group('contiene', () {
    final tarde = DateTime.utc(2026, 8, 12, 1, 30); // 11/08 22:30 AR

    test('sin filtro entra todo', () {
      const r = RangoFiltroMovimientos.todo();
      expect(r.contiene(tarde), isTrue);
      expect(r.contiene(null), isTrue);
    });

    test('filtro por día toma el movimiento de las 22:00 del mismo día', () {
      final r = RangoFiltroMovimientos(
        mes: DateTime(2026, 8),
        dia: DateTime(2026, 8, 11),
      );
      expect(r.contiene(tarde), isTrue);
    });

    test('filtro por el día siguiente NO lo toma', () {
      final r = RangoFiltroMovimientos(
        mes: DateTime(2026, 8),
        dia: DateTime(2026, 8, 12),
      );
      expect(r.contiene(tarde), isFalse);
    });

    test('filtro por mes toma cualquier día de ese mes', () {
      final r = RangoFiltroMovimientos(mes: DateTime(2026, 8));
      expect(r.contiene(tarde), isTrue);
      expect(r.contiene(DateTime.utc(2026, 8, 3, 15)), isTrue);
      expect(r.contiene(DateTime.utc(2026, 7, 20, 15)), isFalse);
    });

    test('un movimiento sin fecha queda fuera de cualquier recorte', () {
      final r = RangoFiltroMovimientos(mes: DateTime(2026, 8));
      expect(r.contiene(null), isFalse);
    });
  });

  group('etiqueta', () {
    test('describe el recorte en castellano', () {
      expect(const RangoFiltroMovimientos.todo().etiqueta, 'Todo el historial');
      expect(
        RangoFiltroMovimientos(mes: DateTime(2026, 8)).etiqueta,
        'Agosto 2026',
      );
      expect(
        RangoFiltroMovimientos(
          mes: DateTime(2026, 8),
          dia: DateTime(2026, 8, 11),
        ).etiqueta,
        '11 de agosto de 2026',
      );
    });
  });
}
