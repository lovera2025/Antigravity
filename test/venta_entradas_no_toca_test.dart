import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Una venta de entradas no es un pago de cuota.** No toca
/// `pagos_contrato_alumno`, ni `sesiones_caja`, ni el saldo o la mora de un
/// alumno, ni cobra por el camino de los cobros
/// (`docs/SPEC_venta_de_entradas_2026-11-13.md`, sección 2).
///
/// Lee todo el código de la venta de entradas y falla si aparece algo de eso:
/// así una pantalla nueva no puede terminar escribiendo donde no debe sin que
/// alguien lo vea.
void main() {
  /// Las carpetas donde vive la venta de entradas. `lib/features/entradas/`
  /// tiene además lo que ya había (el inicio de quien entrega y "En caja"),
  /// que tampoco cobra.
  const carpetas = [
    'lib/features/entradas/datos',
    'lib/features/entradas/cuentas',
    'lib/features/entradas/widgets',
    'lib/features/entradas/pdf',
  ];

  /// Lo que no puede aparecer, y por qué.
  const prohibido = {
    'pagos_contrato_alumno': 'una venta de entradas no es un pago de cuota',
    'sesiones_caja': 'su caja no es la de cuotas',
    'sesionCajaIdParaCobro': 'no cobra por el camino de los cobros',
    'registrarPago': 'no registra pagos de un contrato',
    // La columna, no el dato: VENDER puede **mostrar** lo que debe la familia
    // ("se salda en caja"), pero no leer ni escribir la columna.
    'saldo_deudor': 'no toca el saldo',
    'mora_tracked': 'no toca la mora',
    'mora_cobrada': 'no toca la mora',
    "update('contratos_alumnos'": 'no escribe el contrato',
    "insert('contratos_alumnos'": 'no escribe el contrato',
    "delete('contratos_alumnos'": 'no escribe el contrato',
    "from('contratos_alumnos')": 'no va a la tabla de contratos por la nube',
    'RepartoDeSillas': 'no vende sillas ni lugares: no toca el reparto',
    'asignarNumerosMesa': 'no toca las mesas',
    'sillas_puerta': 'la silla de la noche se paga en la barra',
    'planos_evento': 'no toca el plano',
  };

  List<File> archivos() => [
        for (final c in carpetas)
          if (Directory(c).existsSync())
            for (final f in Directory(c).listSync(recursive: true))
              if (f is File && f.path.endsWith('.dart')) f,
      ];

  /// El código sin los comentarios: ahí se explica justamente qué no se toca.
  String codigoDe(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('hay código que revisar', () {
    expect(archivos(), isNotEmpty);
    expect(
      archivos().any((f) => f.path.replaceAll('\\', '/').endsWith('datos/entradas_local.dart')),
      isTrue,
    );
  });

  test('nada de la venta de entradas toca cuotas, saldo, mora, mesas ni sillas', () {
    for (final f in archivos()) {
      final codigo = codigoDe(f);
      for (final e in prohibido.entries) {
        expect(codigo, isNot(contains(e.key)),
            reason: '${f.path}: ${e.value} (apareció "${e.key}")');
      }
    }
  });

  test('el repositorio escribe solo en sus cinco tablas, y nunca borra', () {
    final repo = codigoDe(File('lib/features/entradas/datos/entradas_local.dart'));
    // Toda escritura pasa por `_guardar`, con una de las cinco tablas.
    final escrituras = RegExp(r'_guardar\(\s*txn,\s*(\w+)').allMatches(repo);
    expect(escrituras, isNotEmpty);
    for (final m in escrituras) {
      expect(m.group(1), startsWith('tabla'), reason: 'escribe en ${m.group(1)}');
    }
    expect(RegExp(r'\.(delete|rawDelete|update|rawUpdate)\(').hasMatch(repo), isFalse,
        reason: 'nada se borra ni se edita a mano: una caja se cierra y una venta '
            'se anula con otra fila');
    // Y cada escritura va con su entrada en la cola, en la misma transacción.
    final guardar = repo.substring(repo.indexOf('Future<void> _guardar('));
    final cuerpo = guardar.substring(0, guardar.indexOf('\n  }\n'));
    expect(cuerpo, contains('SyncQueue.enqueue('));
    expect(cuerpo, contains('executor: db'));
  });
}
