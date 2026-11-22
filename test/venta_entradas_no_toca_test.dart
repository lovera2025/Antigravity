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
    'lib/features/entradas/providers',
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
    // 17-nov-2026: la venta **lee** qué tenía cada familia al sorteo
    // (`fotoDeLosLugaresProvider`), pero no escribe el registro: la lista de
    // una fiesta ya sorteada la acepta el jefe, en su ventana.
    'completarLugares': 'no escribe el registro de sorteos',
    'revisionDeLugaresProvider': 'la lista de los lugares no es de la venta',
    'mostrarRevisionDeLugares': 'la lista de los lugares no es de la venta',
    'SorteosMesasRepository.registrarEn': 'no agrega renglones al registro de sorteos',
    "insert('sorteos_mesas'": 'no escribe el registro de sorteos',
    "update('sorteos_mesas'": 'no escribe el registro de sorteos',
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

  // Regla 61 de `docs/SPEC_entradas_para_rendir_2026-11-20.md` (22-nov-2026):
  // la tabla de las entradas para rendir la escribe solo `EntradasLocal`, y
  // solo por `_guardar` (la fila y su entrada en la cola, juntas). Las
  // pantallas guardan por el repositorio (`darParaRendir`, `rendir`,
  // `noVolvieron`, `anularDeParaRendir`). El motor de sync no cuenta: la baja
  // con `_pullTable(db, 'entradas_para_rendir', …)` y la escribe con el nombre
  // en una variable; la base la crea en la migración.
  test('la tabla de las entradas para rendir la escribe solo EntradasLocal, por _guardar', () {
    const repoRuta = 'lib/features/entradas/datos/entradas_local.dart';
    final escriben = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_escribeParaRendir(codigoDe(f))) {
        escriben.add(f.path.replaceAll('\\', '/'));
      }
    }
    expect(escriben, contains(repoRuta),
        reason: 'la vigilancia no ve al repositorio: cambió cómo escribe');
    expect(escriben.difference({repoRuta}), isEmpty,
        reason: 'escriben entradas_para_rendir por fuera de EntradasLocal');

    // Adentro del repositorio, por `_guardar`: el único `insert` del archivo es
    // el suyo, y ninguna escritura nombra la tabla por otro camino.
    final repo = codigoDe(File(repoRuta));
    final guardar = repo.substring(repo.indexOf('Future<void> _guardar('));
    final cuerpo = guardar.substring(0, guardar.indexOf('\n  }\n'));
    final inserts = RegExp(r'\.(insert|rawInsert|execute)\s*\(');
    expect(inserts.allMatches(repo).length, 1,
        reason: 'una escritura que no pasa por _guardar no entra en la cola');
    expect(inserts.allMatches(cuerpo).length, 1);
    final sinGuardar = RegExp(
      r'\b(insert|rawInsert|update|rawUpdate|delete|rawDelete|upsert)\s*\(\s*(\w+\s*,\s*)?(EntradasLocal\.)?tablaParaRendir\b',
    );
    expect(sinGuardar.hasMatch(repo), isFalse);
  });

  test('la vigilancia de quién escribe entradas_para_rendir ve cada forma', () {
    for (final c in [
      "await db.insert('entradas_para_rendir', fila);",
      "await txn.insert(\n  'entradas_para_rendir',\n  m.toMap(),\n);",
      'await db.insert(EntradasLocal.tablaParaRendir, m.toMap());',
      'await _guardar(txn, tablaParaRendir, m.id, m.toMap());',
      "await txn.rawInsert('INSERT INTO entradas_para_rendir (id) VALUES (?)', [id]);",
      "await db.execute('INSERT OR REPLACE INTO entradas_para_rendir (id) VALUES (?)');",
      "await db.update('entradas_para_rendir', {'cantidad': 0});",
      "await db.rawUpdate('UPDATE entradas_para_rendir SET que = ?', ['x']);",
      "await db.delete('entradas_para_rendir', where: 'id = ?');",
      "await supabase.from('entradas_para_rendir').upsert(fila);",
      "await SyncQueue.enqueue(\n  executor: db,\n  tabla: 'entradas_para_rendir',\n  operacion: SyncOperation.insert,\n  registroId: id,\n  payload: fila,\n);",
      'await SyncQueue.enqueue(tabla: EntradasLocal.tablaParaRendir, registroId: id);',
    ]) {
      expect(_escribeParaRendir(c), isTrue, reason: c);
    }
    // Leer, bajar o nombrarla no es escribir.
    for (final c in [
      "_pullTable(db, 'entradas_para_rendir', 'updated_at'),",
      "final filas = await txn.query(tablaParaRendir, where: 'id = ?');",
      "final filas = await db.query('entradas_para_rendir');",
      "'entradas_para_rendir': 'updated_at',",
      "if (table == 'entradas_para_rendir') return 5;",
      "const tablas = {'entradas_para_rendir', 'entradas_ventas'};",
      'CREATE TABLE IF NOT EXISTS entradas_para_rendir (',
      'CREATE INDEX IF NOT EXISTS idx_x ON entradas_para_rendir(evento_id)',
      'await ref.read(entradasDelJefeProvider).darParaRendir(evento: e);',
      "await SyncQueue.enqueue(tabla: 'entradas_ventas', registroId: id);",
    ]) {
      expect(_escribeParaRendir(c), isFalse, reason: c);
    }
  });
}

/// Si [codigo] escribe `entradas_para_rendir`: un `insert`/`update`/`delete`/
/// `upsert` (o `_guardar`) con su nombre o con la constante del repositorio, un
/// SQL que la escribe, o una entrada en la cola con esa tabla.
bool _escribeParaRendir(String codigo) {
  const nombre = r"""(['"]entradas_para_rendir['"]|(EntradasLocal\.)?tablaParaRendir\b)""";
  if (RegExp(
    r'\b(insert|rawInsert|update|rawUpdate|delete|rawDelete|upsert|_guardar)\s*\(\s*(\w+\s*,\s*)?'
    '$nombre',
  ).hasMatch(codigo)) {
    return true;
  }
  if (RegExp(r'from\s*\(\s*' '$nombre' r'\s*\)\s*\.\s*(insert|upsert|update|delete)\s*\(')
      .hasMatch(codigo)) {
    return true;
  }
  if (RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|REPLACE\s+INTO|UPDATE|DELETE\s+FROM)\s+entradas_para_rendir\b',
    caseSensitive: false,
  ).hasMatch(codigo)) {
    return true;
  }
  return RegExp(r'enqueue\s*\([^;]*?\btabla\s*:\s*' '$nombre').hasMatch(codigo);
}
