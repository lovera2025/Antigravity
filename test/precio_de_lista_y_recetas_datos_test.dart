import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_local.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

import 'helpers/barra_en_memoria.dart';

/// El precio de lista y las recetas de los tragos se guardan (v84, maqueta aprobada el
/// 27-nov-2026): **solo el jefe**, con la cola de subida, sin salir a la red del salón, y
/// nada se borra (sacar un ingrediente es guardarlo apagado).
const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _fernetConCoca = 'b0000000-0000-4000-8000-000000000001';
const _fernet = 'b0000000-0000-4000-8000-000000000002';
const _coca = 'b0000000-0000-4000-8000-000000000003';

void main() {
  final antes = DateTime.utc(2026, 12, 1, 12);
  final despues = DateTime.utc(2026, 12, 2, 12);

  group('en la base del equipo (BarraLocal, SQLite de verdad)', () {
    sqfliteFfiInit();
    late Database db;
    late DateTime reloj;
    late BarraLocal barra;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE _sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tabla TEXT NOT NULL,
          operacion TEXT NOT NULL,
          registro_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          intentos INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
      await LocalDatabase.crearTablasV77(db);
      await LocalDatabase.crearTablasV84(db);
      reloj = antes;
      barra = BarraLocal(abrir: () async => db, equipo: () async => 'pc-del-jefe', reloj: () => reloj);
    });

    tearDown(() => db.close());

    Future<List<String>> encolado(String tabla) async => [
          for (final f in await db.query('_sync_queue', where: 'tabla = ?', whereArgs: [tabla]))
            f['registro_id'] as String,
        ];

    test('el precio de lista: sellado, encolado, y guardarlo de nuevo pisa la misma fila sin cambiar cuándo nació',
        () async {
      final primero = await barra.guardarCosto(
        CostoBarra.para(eventoId: _fiesta, productoId: _fernet, precioLista: 11740, contenidoCc: 750, ahora: antes),
        quien: 'Jefe',
      );
      expect(primero.hechoPor, 'Jefe');
      expect(primero.deviceId, 'pc-del-jefe');
      expect(await encolado('barra_costos'), [primero.id]);

      reloj = despues;
      await barra.guardarCosto(
        CostoBarra.para(eventoId: _fiesta, productoId: _fernet, precioLista: 12000, contenidoCc: 750, ahora: despues),
        quien: 'Jefe',
      );
      final costos = await barra.costos(_fiesta);
      expect(costos, hasLength(1));
      expect(costos.single.precioLista, 12000);
      expect(costos.single.createdAt, primero.createdAt, reason: 'guardar de nuevo no le cambia cuándo nació');
      expect(await barra.costos('e0000000-0000-4000-8000-000000000009'), isEmpty, reason: 'cada fiesta, el suyo');
    });

    test('la receta: guardar un ingrediente, y sacarlo lo deja apagado sin borrarlo', () async {
      final fernet = RecetaBarra.para(
        eventoId: _fiesta,
        productoId: _fernetConCoca,
        ingredienteId: _fernet,
        cantidad: 200,
        unidad: UnidadDeReceta.cc,
        ahora: antes,
      );
      final coca = RecetaBarra.para(
        eventoId: _fiesta,
        productoId: _fernetConCoca,
        ingredienteId: _coca,
        cantidad: 500,
        unidad: UnidadDeReceta.cc,
        ahora: antes,
      );
      await barra.guardarReceta(fernet, quien: 'Jefe');
      await barra.guardarReceta(coca, quien: 'Jefe');
      expect((await barra.recetas(_fiesta)).map((r) => r.cantidad), unorderedEquals([200, 500]));
      expect(await encolado('barra_recetas'), unorderedEquals([fernet.id, coca.id]));

      await barra.guardarReceta(
        RecetaBarra.para(
          eventoId: _fiesta,
          productoId: _fernetConCoca,
          ingredienteId: _coca,
          cantidad: 500,
          unidad: UnidadDeReceta.cc,
          activo: false,
          ahora: despues,
        ),
        quien: 'Jefe',
      );
      expect((await barra.recetas(_fiesta)).single.ingredienteId, _fernet, reason: 'la coca ya no va');
      expect(await db.query('barra_recetas'), hasLength(2), reason: 'nada se borra');
    });
  });

  group('la segunda llave (BarraConLaRed): solo el jefe, y no sale a la red del salón', () {
    late BarraEnMemoria b;
    final salieron = <String>[];

    setUp(() {
      b = BarraEnMemoria();
      salieron.clear();
    });

    BarraConLaRed con(RolEnLaBarra? rol) {
      final aviso = AvisoALaRed()..salida = (tabla, id) async => salieron.add('$tabla $id');
      return BarraConLaRed(caja: b, jefe: b, red: b, aviso: aviso, rolDeQuienUsa: () => rol);
    }

    CostoBarra costo() => CostoBarra.para(eventoId: _fiesta, productoId: _fernet, precioLista: 11740, ahora: antes);
    RecetaBarra receta() => RecetaBarra.para(
          eventoId: _fiesta,
          productoId: _fernetConCoca,
          ingredienteId: _fernet,
          cantidad: 200,
          unidad: UnidadDeReceta.cc,
          ahora: antes,
        );

    for (final rol in [RolEnLaBarra.encargada, RolEnLaBarra.cajera, RolEnLaBarra.repositor, null]) {
      test('${rol?.name ?? 'nadie de la barra'} no guarda el precio de lista ni una receta', () async {
        await expectLater(con(rol).guardarCosto(costo(), quien: 'X'), throwsA(isA<NoLeTocaEnLaBarra>()));
        await expectLater(con(rol).guardarReceta(receta(), quien: 'X'), throwsA(isA<NoLeTocaEnLaBarra>()));
        expect(b.costosGuardados, isEmpty);
        expect(b.recetasGuardadas, isEmpty);
      });
    }

    test('el jefe sí, y nada sale por el wifi del salón', () async {
      final red = con(RolEnLaBarra.jefe);
      await red.guardarCosto(costo(), quien: 'Jefe');
      await red.guardarReceta(receta(), quien: 'Jefe');
      expect((await red.costos(_fiesta)).single.precioLista, 11740);
      expect((await red.recetas(_fiesta)).single.cantidad, 200);
      expect(salieron, isEmpty);
      expect(red.aviso.escrituras.value, 2, reason: 'cuenta como algo que escribió este equipo');
    });
  });

  test('lo que dice PRECIOS de un trago es lo mismo que cuenta GANANCIA (una sola cuenta)', () {
    final noche = DateTime.utc(2026, 12, 5, 2);
    final caja = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 1, ahora: noche);
    RecetaBarra lleva(String id, int cc) => RecetaBarra.para(
          eventoId: _fiesta,
          productoId: _fernetConCoca,
          ingredienteId: id,
          cantidad: cc,
          unidad: UnidadDeReceta.cc,
          ahora: noche,
        );
    final recetas = [lleva(_fernet, 200), lleva(_coca, 500)];
    final listas = <String, double?>{_fernet: 11740, _coca: 3000};
    final contenidos = <String, int?>{_fernet: 750, _coca: 2250};
    final venta = VentaBarra.nueva(
      cajaBarraId: caja.id,
      eventoId: _fiesta,
      numero: 1,
      renglones: const [RenglonVenta(productoId: _fernetConCoca, nombre: 'Fernet con coca', precio: 10000, cantidad: 1)],
      medio: MedioBarra.efectivo,
      efectivo: 10000,
      ahora: noche,
    );
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _fiesta,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [caja],
        ventas: [venta],
        precios: [PrecioBarra.para(eventoId: _fiesta, productoId: _fernetConCoca, precio: 10000, ahora: noche)],
        listas: listas,
        recetas: recetas,
        contenidos: contenidos,
      ),
    ]);
    final trago = cuenta.productos.firstWhere((p) => p.productoId == _fernetConCoca);
    final dePrecios = costoDeUnTrago(recetas, lista: (id) => listas[id], contenidoCc: (id) => contenidos[id]);
    expect(dePrecios.centavos, 379733);
    expect(dePrecios.centavos, trago.lista, reason: 'PRECIOS y GANANCIA dicen lo mismo');
    final sinCoca = costoDeUnTrago(
      recetas,
      lista: (id) => id == _coca ? null : listas[id],
      contenidoCc: (id) => contenidos[id],
    );
    expect(sinCoca.centavos, isNull, reason: 'sin la lista de algo que lleva, no se sabe');
    expect(sinCoca.faltan, [_coca]);
  });
}
