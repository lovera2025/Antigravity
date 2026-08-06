import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/cierre_caja/services/cobro_agrupado.dart';
import 'package:arguello_events/features/mi_empresa/models/ingreso_detallado.dart';

/// Base fija para que los desfasajes de milisegundos del test sean explícitos.
final _t0 = DateTime.utc(2026, 8, 5, 17, 54, 30);

IngresoDetallado ing({
  required double monto,
  required String concepto,
  String alumno = 'DESCALZO, JONATHAN GABRIEL',
  String? contratoId = 'c-1',
  String medio = 'Efectivo',
  Duration desde = Duration.zero,
  String fuente = 'Masivo',
  String? lineKind,
  String? id,
}) {
  return IngresoDetallado(
    id: id ?? 'p-${concepto.hashCode}-${desde.inMilliseconds}-$medio',
    fuente: fuente,
    fecha: _t0.add(desde),
    monto: monto,
    concepto: concepto,
    alumnoOCliente: alumno,
    nombreEvento: 'Egresados',
    medioPago: medio,
    sesionCajaId: 's-1',
    contratoAlumnoId: contratoId,
    lineKind: lineKind,
  );
}

double _sumaGrupos(List<CobroAgrupado> g) =>
    double.parse(g.fold<double>(0, (s, x) => s + x.monto).toStringAsFixed(2));

double _sumaIngresos(List<IngresoDetallado> i) =>
    double.parse(i.fold<double>(0, (s, x) => s + x.monto).toStringAsFixed(2));

void main() {
  group('agruparIngresosPorCobro', () {
    test('1 · invariante de suma: ningún peso se pierde ni se duplica', () {
      // Mezcla deliberada: mismo alumno junto y separado, otro alumno, mixto,
      // fuentes que no se agrupan, y montos con decimales que redondean.
      final ingresos = [
        ing(monto: 27777.78, concepto: 'Cuota Base (3/9)'),
        ing(
          monto: 27777.78,
          concepto: 'Cuota Base (4/9)',
          desde: const Duration(milliseconds: 40),
        ),
        ing(
          monto: 29722.22,
          concepto: 'Interés mora cuotas 2, 3, 4 (vto May, Jun, Jul)',
          desde: const Duration(milliseconds: 80),
          lineKind: kLineKindInteresMora,
        ),
        ing(
          monto: 30000,
          concepto: 'Cuota Base (5/9)',
          alumno: 'GONZALEZ VALLEJOS, JORGE ANDRES',
          contratoId: 'c-2',
          desde: const Duration(minutes: -92),
        ),
        ing(
          monto: 12500.55,
          concepto: 'Cuota Base (2/9)',
          contratoId: 'c-3',
          alumno: 'ALMIRON, DANA',
          medio: 'Transferencia',
          desde: const Duration(minutes: -5),
        ),
        ing(
          monto: 900.45,
          concepto: 'Costo por transferencia',
          contratoId: 'c-3',
          alumno: 'ALMIRON, DANA',
          medio: 'Transferencia',
          desde: const Duration(minutes: -5, milliseconds: 20),
          lineKind: kLineKindCargoCanal,
        ),
        ing(
          monto: 4000,
          concepto: 'Seña salón',
          fuente: 'Particular',
          contratoId: null,
          alumno: 'FAMILIA PEREZ',
          desde: const Duration(minutes: -30),
        ),
      ];

      final grupos = agruparIngresosPorCobro(ingresos);
      expect(_sumaGrupos(grupos), _sumaIngresos(ingresos));
      // Ninguna línea se cae: la suma de líneas de todos los grupos es el total.
      expect(
        grupos.fold<int>(0, (s, g) => s + g.lineas.length),
        ingresos.length,
      );
    });

    test('2 · plan + mora + recargo del mismo cobro → 1 grupo', () {
      final grupos = agruparIngresosPorCobro([
        ing(monto: 35000, concepto: 'Cuota Base (4/9)'),
        ing(
          monto: 2100,
          concepto:
              'Interés mora cuota 4 (vto Jul 2026) + mora pendiente cuota 3',
          desde: const Duration(milliseconds: 40),
          lineKind: kLineKindInteresMora,
        ),
      ]);

      expect(grupos.length, 1);
      expect(grupos.first.monto, 37100);
      expect(grupos.first.alumno, 'DESCALZO, JONATHAN GABRIEL');
      expect(grupos.first.resumenConceptos, contains('cuota base 4/9'));
      expect(grupos.first.resumenConceptos, contains('int. mora Jul'));
    });

    test('3 · masivo intercalado y un recobro 4 min después → 3 grupos', () {
      final grupos = agruparIngresosPorCobro([
        ing(monto: 100, concepto: 'Cuota Base (1/9)'),
        ing(
          monto: 200,
          concepto: 'Cuota Base (2/9)',
          desde: const Duration(milliseconds: 30),
        ),
        ing(
          monto: 300,
          concepto: 'Cuota Base (1/9)',
          alumno: 'OTRO, ALUMNO',
          contratoId: 'c-9',
          desde: const Duration(milliseconds: 60),
        ),
        ing(
          monto: 400,
          concepto: 'Cuota Base (2/9)',
          alumno: 'OTRO, ALUMNO',
          contratoId: 'c-9',
          desde: const Duration(milliseconds: 90),
        ),
        ing(
          monto: 500,
          concepto: 'Cuota Base (3/9)',
          desde: const Duration(minutes: 4),
        ),
      ]);

      expect(grupos.length, 3);
      // Más reciente primero: el recobro de c-1 a los 4 minutos.
      expect(grupos.first.monto, 500);
      expect(_sumaGrupos(grupos), 1500);
    });

    test('4 · borde de la ventana: 9,9 s junta y 10,1 s separa', () {
      final juntos = agruparIngresosPorCobro([
        ing(monto: 10, concepto: 'Cuota Base (1/9)'),
        ing(
          monto: 20,
          concepto: 'Cuota Base (2/9)',
          desde: const Duration(milliseconds: 9900),
        ),
      ]);
      expect(juntos.length, 1);

      final separados = agruparIngresosPorCobro([
        ing(monto: 10, concepto: 'Cuota Base (1/9)'),
        ing(
          monto: 20,
          concepto: 'Cuota Base (2/9)',
          desde: const Duration(milliseconds: 10100),
        ),
      ]);
      expect(separados.length, 2);
    });

    test('4b · la ventana no encadena cobros separados', () {
      final grupos = agruparIngresosPorCobro([
        ing(monto: 10, concepto: 'Cuota Base (1/9)'),
        ing(
          monto: 20,
          concepto: 'Cuota Base (2/9)',
          desde: const Duration(seconds: 9),
        ),
        ing(
          monto: 30,
          concepto: 'Cuota Base (3/9)',
          desde: const Duration(seconds: 18),
        ),
      ]);

      expect(grupos.length, 2);
      expect(grupos.map((g) => g.monto).toSet(), {10, 50});
      expect(_sumaGrupos(grupos), 60);
    });

    test('5 · homónimos: el id del contrato manda sobre el nombre', () {
      const mismoNombre = 'GONZALEZ, LUCAS';
      final conId = agruparIngresosPorCobro([
        ing(
          monto: 1000,
          concepto: 'Cuota Base (1/9)',
          alumno: mismoNombre,
          contratoId: 'c-A',
        ),
        ing(
          monto: 2000,
          concepto: 'Cuota Base (1/9)',
          alumno: mismoNombre,
          contratoId: 'c-B',
        ),
      ]);
      expect(conId.length, 2, reason: 'dos familias distintas, dos filas');

      // Filas viejas sin la columna: degradan a agrupar por nombre. Se
      // documenta el comportamiento, no se lo celebra.
      final sinId = agruparIngresosPorCobro([
        ing(
          monto: 1000,
          concepto: 'Cuota Base (1/9)',
          alumno: mismoNombre,
          contratoId: null,
          id: 'x1',
        ),
        ing(
          monto: 2000,
          concepto: 'Cuota Base (1/9)',
          alumno: mismoNombre,
          contratoId: null,
          id: 'x2',
        ),
      ]);
      expect(sinId.length, 1);
    });

    test('6 · mixto: un solo grupo, con su desglose', () {
      final ingresos = [
        ing(monto: 20000, concepto: 'Cuota Base (4/9)'),
        ing(
          monto: 17100,
          concepto: 'Cuota Base (5/9)',
          medio: 'Transferencia',
          desde: const Duration(milliseconds: 30),
        ),
        ing(
          monto: 900,
          concepto: 'Costo por transferencia',
          medio: 'Transferencia',
          desde: const Duration(milliseconds: 60),
          lineKind: kLineKindCargoCanal,
        ),
      ];
      final grupos = agruparIngresosPorCobro(ingresos);

      expect(grupos.length, 1);
      final g = grupos.first;
      expect(g.esMixto, isTrue);
      expect(g.medioUnico, isNull);
      expect(g.montoEfectivo, 20000);
      expect(g.montoTransferencia, 18000, reason: 'incluye el cargo por canal');
      expect(g.montoEfectivo + g.montoTransferencia, g.monto);

      final ef = g.parte(transferencia: false);
      final tr = g.parte(transferencia: true);
      expect(ef.monto + tr.monto, g.monto);
      expect(ef.parteDeMixto, isTrue);
      expect(tr.parteDeMixto, isTrue);
      // La hora de la fila proyectada es la misma que la de la lista principal.
      expect(ef.fecha, g.fecha);
      expect(tr.fecha, g.fecha);
    });

    test('6b · las partes por medio suman los brutos de cada bucket', () {
      final ingresos = [
        ing(monto: 20000, concepto: 'Cuota Base (4/9)'),
        ing(
          monto: 18000,
          concepto: 'Cuota Base (5/9)',
          medio: 'Transferencia',
          desde: const Duration(milliseconds: 30),
        ),
        ing(
          monto: 5000,
          concepto: 'Cuota Base (1/9)',
          alumno: 'OTRA, ALUMNA',
          contratoId: 'c-7',
          medio: 'Transferencia',
          desde: const Duration(minutes: -20),
        ),
        ing(
          monto: 7000,
          concepto: 'Cuota Base (2/9)',
          alumno: 'TERCERO, ALUMNO',
          contratoId: 'c-8',
          desde: const Duration(minutes: -40),
        ),
        // Medios que no son 'transferencia' cuentan como efectivo.
        ing(
          monto: 1500,
          concepto: 'Cuota Base (3/9)',
          alumno: 'CUARTO, ALUMNO',
          contratoId: 'c-10',
          medio: 'Mercado Pago',
          desde: const Duration(minutes: -50),
        ),
      ];

      final brutoEfectivo = _sumaIngresos(
        ingresos.where((i) => i.medioPago != 'Transferencia').toList(),
      );
      final brutoTransf = _sumaIngresos(
        ingresos.where((i) => i.medioPago == 'Transferencia').toList(),
      );

      final grupos = agruparIngresosPorCobro(ingresos);
      final sumaEf = grupos
          .map((g) => g.parte(transferencia: false).monto)
          .fold<double>(0, (s, v) => s + v);
      final sumaTr = grupos
          .map((g) => g.parte(transferencia: true).monto)
          .fold<double>(0, (s, v) => s + v);

      expect(sumaEf, brutoEfectivo);
      expect(sumaTr, brutoTransf);
      expect(_sumaGrupos(grupos), brutoEfectivo + brutoTransf);
    });

    test('7 · eventos particulares del mismo segundo no se fusionan', () {
      final grupos = agruparIngresosPorCobro([
        ing(
          monto: 5000,
          concepto: 'Seña',
          fuente: 'Particular',
          contratoId: null,
          alumno: 'FAMILIA PEREZ',
          id: 't1',
        ),
        ing(
          monto: 6000,
          concepto: 'Saldo',
          fuente: 'Particular',
          contratoId: null,
          alumno: 'FAMILIA PEREZ',
          desde: const Duration(milliseconds: 50),
          id: 't2',
        ),
      ]);
      expect(grupos.length, 2);
      expect(_sumaGrupos(grupos), 11000);
    });

    test('8 · compresión del resumen', () {
      final tresCuotas = agruparIngresosPorCobro([
        ing(monto: 100, concepto: 'Cuota Base (2/9)'),
        ing(
          monto: 100,
          concepto: 'Cuota Base (3/9)',
          desde: const Duration(milliseconds: 10),
        ),
        ing(
          monto: 100,
          concepto: 'Cuota Base (4/9)',
          desde: const Duration(milliseconds: 20),
        ),
      ]).first;
      expect(tresCuotas.resumenConceptos, 'cuota base ×3');

      final moraMeses = agruparIngresosPorCobro([
        ing(
          monto: 100,
          concepto: 'Interés mora cuotas 2, 3, 4 (vto May, Jun, Jul)',
          lineKind: kLineKindInteresMora,
        ),
      ]).first;
      expect(moraMeses.resumenConceptos, 'int. mora May–Jul');

      final mesesSalteados = agruparIngresosPorCobro([
        ing(
          monto: 100,
          concepto: 'Interés mora cuotas 2, 4 (vto May, Jul)',
          lineKind: kLineKindInteresMora,
        ),
      ]).first;
      expect(mesesSalteados.resumenConceptos, 'int. mora May, Jul');

      final muchasClases = agruparIngresosPorCobro([
        ing(monto: 100, concepto: 'Cuota Base (2/9)'),
        ing(
          monto: 100,
          concepto: 'Mesa Extra 4 (4/7)',
          desde: const Duration(milliseconds: 10),
        ),
        ing(
          monto: 100,
          concepto: 'Sillas Extras (1/3)',
          desde: const Duration(milliseconds: 20),
        ),
        ing(
          monto: 100,
          concepto: 'Interés mora cuota 2 (vto May 2026)',
          desde: const Duration(milliseconds: 30),
          lineKind: kLineKindInteresMora,
        ),
        ing(
          monto: 100,
          concepto: 'Costo por transferencia',
          desde: const Duration(milliseconds: 40),
          lineKind: kLineKindCargoCanal,
        ),
      ]).first;
      expect(muchasClases.resumenConceptos, endsWith('+2 más'));
      expect(muchasClases.resumenConceptos, startsWith('cuota base 2/9'));
    });

    test('9 · rótulos golden de los generadores reales', () {
      // Copiados de test/concepto_pago_display_test.dart y
      // test/mora_concepto_rotulo_test.dart. Si alguien renombra un generador,
      // este test rompe y se ve, en vez de degradar el resumen en silencio.
      String resumen(String concepto, {String? lineKind}) =>
          agruparIngresosPorCobro([
            ing(monto: 100, concepto: concepto, lineKind: lineKind),
          ]).first.resumenConceptos;

      // Guion largo U+2013, como lo escribe rotularPlanDesdeGross.
      expect(resumen('Cuotas Base (1–2/9)'), 'cuota base ×2');
      expect(resumen('Cuota Base (3/9)'), 'cuota base 3/9');
      expect(resumen('Cuota Base (4/9) — Completada'), 'cuota base 4/9');
      expect(
        resumen('Entrega parcial — Cuota Base (8/9)'),
        'parcial cuota base 8/9',
      );
      expect(
        resumen(
          'Interés mora cuota 3 (vto Jun 2026)',
          lineKind: kLineKindInteresMora,
        ),
        'int. mora Jun',
      );
      expect(
        resumen('Mora pendiente cuota 2', lineKind: kLineKindInteresMora),
        'int. mora',
      );
      expect(resumen('Mesa Extra 4 (4/7)'), 'mesa 4/7');
      // Sin line_kind y sin patrón conocido: nunca vacío.
      expect(resumen('Algo que nadie previó').isNotEmpty, isTrue);
    });

    test('10 · el medio se decide por el monto, no por la primera línea', () {
      final g = agruparIngresosPorCobro([
        // Línea en cero de un medio: no debería definir el medio del cobro.
        ing(monto: 0, concepto: 'Cuota Base (1/9)'),
        ing(
          monto: 9000,
          concepto: 'Cuota Base (2/9)',
          medio: 'Transferencia',
          desde: const Duration(milliseconds: 10),
        ),
      ]).first;
      expect(g.esMixto, isFalse);
      expect(g.medioUnico, 'Transferencia');
    });

    test('11 · entrada vacía no explota', () {
      expect(agruparIngresosPorCobro(const []), isEmpty);
    });
  });
}
