import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/ganancia_del_jefe.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';

/// **Leer** el precio de lista también es solo del jefe (27-nov-2026, pedido del usuario:
/// "fijate que solo el jefe pueda ver ganancia"). Hasta acá lo cuidaba la pantalla (no lo
/// mostraba) y el guardado (no lo dejaba escribir); la lectura no tenía llave, así que una
/// pantalla nueva que se equivocara podía mostrarlo. Ninguna de estas llaves pregunta
/// nada: miran quién entró en el aparato.
const _losQueNo = <RolEnLaBarra?>[
  RolEnLaBarra.cajera,
  RolEnLaBarra.encargada,
  RolEnLaBarra.repositor,
  RolEnLaBarra.central,
  null,
];

String _nombre(RolEnLaBarra? rol) => rol?.name ?? 'nadie de la barra';

void main() {
  late BarraEnPrueba prueba;
  late Evento viernes;
  late ProductoBarra lata;

  setUp(() async {
    prueba = BarraEnPrueba();
    viernes = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA', DateTime(2026, 12, 4, 22));
    prueba.eventos.add(viernes);
    final b = prueba.barra;
    lata = b.producto('Cerveza lata', categoria: 'Cervezas');
    final fernetConCoca = b.producto('Fernet con coca', categoria: 'Tragos');
    b.precio(viernes.id, lata, 5000);
    final antes = DateTime(2026, 11, 20);
    await b.guardarCosto(
      CostoBarra.para(eventoId: viernes.id, productoId: lata.id, precioLista: 1500, ahora: antes),
      quien: 'Jefe',
    );
    await b.guardarReceta(
      RecetaBarra.para(
        eventoId: viernes.id,
        productoId: fernetConCoca.id,
        ingredienteId: lata.id,
        cantidad: 1,
        unidad: UnidadDeReceta.cc,
        ahora: antes,
      ),
      quien: 'Jefe',
    );
    // Dos latas vendidas: al jefe la cuenta le da algo; a los demás, nada.
    b.reloj = () => DateTime.utc(2026, 12, 5, 2);
    final caja = await b.abrirCaja(eventoId: viernes.id, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
    await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: lata.id, nombre: lata.nombre, precio: 5000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 10000,
      quien: 'Marta',
    );
  });

  group('la segunda llave (BarraConLaRed.costos)', () {
    BarraConLaRed con(RolEnLaBarra? rol) {
      final b = prueba.barra;
      return BarraConLaRed(caja: b, jefe: b, red: b, aviso: AvisoALaRed(), rolDeQuienUsa: () => rol);
    }

    for (final rol in _losQueNo) {
      test('${_nombre(rol)} lee el precio de lista vacío, aunque esté en la base del equipo', () async {
        expect(await con(rol).costos(viernes.id), isEmpty);
      });
    }

    test('el jefe lo lee', () async {
      expect((await con(RolEnLaBarra.jefe).costos(viernes.id)).single.precioLista, 1500);
    });

    test('las recetas (sin plata) las lee cualquiera: hacen falta para el stock', () async {
      expect(await con(RolEnLaBarra.cajera).recetas(viernes.id), hasLength(1));
    });
  });

  group('lo que leen PRECIOS y GANANCIA (también en la web, donde la barra es la nube)', () {
    ProviderContainer conRol(RolEnLaBarra? rol) {
      final c = ProviderContainer(overrides: [
        // Sin la segunda llave, como `BarraNube` en la web: la que frena es la del provider.
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        eventosDeLaBarraProvider.overrideWith((ref) async => prueba.eventos),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 11, 20, 15)),
        rolEnLaBarraProvider.overrideWithValue(rol),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    for (final rol in _losQueNo) {
      test('${_nombre(rol)}: la lista del proveedor llega vacía', () async {
        final lista = await conRol(rol).read(listaDelProveedorProvider(viernes.id).future);
        expect(lista.costos, isEmpty);
        expect(lista.recetas, isEmpty);
      });

      test('${_nombre(rol)}: la ganancia llega sin ninguna fiesta, y sin quedar cargando', () async {
        final cuenta = await conRol(rol).read(gananciaDelJefeProvider(viernes.id).future);
        expect(cuenta.fiestas, isEmpty);
        expect(cuenta.productos, isEmpty);
        expect(cuenta.leDebo, 0);
        expect(cuenta.seVendio, 0);
      });
    }

    test('el jefe: la lista del proveedor y la ganancia llegan enteras', () async {
      final c = conRol(RolEnLaBarra.jefe);
      final lista = await c.read(listaDelProveedorProvider(viernes.id).future);
      expect(lista.costoDe(lata.id)?.precioLista, 1500);
      expect(lista.recetas, hasLength(1));
      final cuenta = await c.read(gananciaDelJefeProvider(viernes.id).future);
      expect(cuenta.fiestas, hasLength(1));
      expect(cuenta.seVendio, greaterThan(0));
      expect(cuenta.leDebo, greaterThan(0));
    });
  });

  test('en la app, el precio de lista se lee solo desde PRECIOS y GANANCIA del jefe', () {
    const permitidos = {
      'lib/features/barra/central/barra_con_la_red.dart', // la segunda llave
      'lib/features/barra/jefe/barra_jefe_providers.dart', // listaDelProveedorProvider
      'lib/features/barra/jefe/ganancia_del_jefe.dart', // gananciaDelJefeProvider
      'lib/features/barra/jefe/precios_de_la_fiesta.dart', // copiar de otra fiesta (jefe)
    };
    final lectura = RegExp(r'\.costos\(');
    final fuera = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final ruta = f.path.replaceAll('\\', '/');
      if (!ruta.endsWith('.dart') || permitidos.contains(ruta)) continue;
      if (lectura.hasMatch(f.readAsStringSync())) fuera.add(ruta);
    }
    expect(fuera, isEmpty, reason: 'una pantalla nueva que lea el precio de lista tiene que ser del jefe');

    // Y los dos providers que lo leen preguntan por el rol antes.
    for (final ruta in [
      'lib/features/barra/jefe/barra_jefe_providers.dart',
      'lib/features/barra/jefe/ganancia_del_jefe.dart',
    ]) {
      final texto = File(ruta).readAsStringSync();
      final llave = texto.indexOf('veElCostoYLaGanancia(ref.watch(rolEnLaBarraProvider))');
      final lee = texto.indexOf('.costos(');
      expect(llave, greaterThan(-1), reason: '$ruta perdió la llave del rol');
      expect(llave, lessThan(lee), reason: '$ruta lee el precio de lista antes de mirar el rol');
    }
  });
}
