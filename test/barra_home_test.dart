import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/services/fiestas_de_la_barra.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La pantalla de quien entra a la Barra: las fiestas con precios, la línea sin
/// internet y abrir (o retomar) su caja, sin cambio ni turno.
const _marta = 'a0000000-0000-4000-8000-000000000001';

void main() {
  final hoy = DateTime.now();
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba barra;
  late Evento puertoViejo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    operadores.operadores.lista.add(operadorDePrueba(_marta, 'Marta', '5555'));
    barra = BarraEnPrueba();
    puertoViejo = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', hoy.add(const Duration(days: 10)));
    barra.eventos.addAll([
      puertoViejo,
      fiestaDePrueba(BarraEnPrueba.id(2), 'SIN PRECIOS', hoy.add(const Duration(days: 3))),
      fiestaDePrueba(BarraEnPrueba.id(3), 'PASADA', hoy.subtract(const Duration(days: 3))),
    ]);
    final cerveza = barra.barra.producto('Cerveza lata');
    barra.barra.precio(puertoViejo.id, cerveza, 3500);
    barra.barra.precio(BarraEnPrueba.id(3), cerveza, 3500);
  });

  group('las fiestas que se eligen', () {
    test('con precios, por hacer y por fecha; masivas o particulares', () {
      final e = [
        fiestaDePrueba('c', 'C', DateTime(2026, 12, 12), modalidad: 'particular'),
        fiestaDePrueba('a', 'A', DateTime(2026, 11, 3, 9)),
        fiestaDePrueba('b', 'B', DateTime(2026, 12, 1)),
        fiestaDePrueba('sin', 'SIN', DateTime(2026, 12, 2)),
        fiestaDePrueba('vieja', 'VIEJA', DateTime(2026, 11, 2)),
      ];
      final lista = fiestasParaLaBarra(e, {'a', 'b', 'c', 'vieja'}, DateTime(2026, 11, 3, 22));
      expect([for (final f in lista) f.id], ['a', 'b', 'c']);
    });
  });

  Future<ProviderContainer> abrir(
    WidgetTester tester, {
    Size tamano = const Size(1024, 800),
    void Function(BuildContext, Evento, CajaBarra)? alAbrir,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [...operadores.reemplazos, ...barra.reemplazos],
      child: MaterialApp(home: BarraHomeScreen(onCajaLista: alAbrir ?? (_, _, _) {})),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(BarraHomeScreen)));
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          operadores.operadores.lista.single,
          const PermisosEfectivos(barra: true),
        );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('dice quién es y lista solo las fiestas con precios que vienen', (tester) async {
    await abrir(tester);
    expect(find.text('BARRA · MARTA'), findsOneWidget);
    expect(find.text('PUERTO VIEJO'), findsOneWidget);
    expect(find.text('SIN PRECIOS'), findsNothing);
    expect(find.text('PASADA'), findsNothing);
  });

  testWidgets('sin fiestas con precios, lo dice', (tester) async {
    barra.barra.preciosGuardados.clear();
    await abrir(tester);
    expect(find.byKey(const Key('barra_sin_fiestas')), findsOneWidget);
  });

  testWidgets('abrir la caja pide solo el número y la sede, sin cambio ni turno', (tester) async {
    CajaBarra? lista;
    await abrir(tester, alAbrir: (_, _, caja) => lista = caja);
    await tester.tap(find.byKey(Key('barra_fiesta_${puertoViejo.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Abrir tu caja'), findsOneWidget);
    expect(find.textContaining('ambio'), findsNothing, reason: 'nada de cambio');
    expect(find.textContaining('urno'), findsNothing, reason: 'nada de turno');
    expect(find.textContaining('Mañana'), findsNothing);
    expect(
      tester.widget<ButtonStyleButton>(find.byKey(const Key('caja_abrir'))).onPressed,
      isNull,
      reason: 'sin número no abre',
    );
    await tester.tap(find.byKey(const Key('caja_numero_2')));
    await tester.enterText(find.byKey(const Key('caja_sede')), 'Barra del fondo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('caja_abrir')));
    await tester.pumpAndSettle();
    expect(lista, isNotNull);
    expect(lista!.numeroCaja, 2);
    expect(lista!.sede, 'Barra del fondo');
    expect(lista!.cambioInicial, 0);
    expect(lista!.operadorNombre, 'Marta');
    expect(barra.barra.cajasGuardadas, hasLength(1));
  });

  testWidgets('con la caja ya abierta en este equipo, entra derecho', (tester) async {
    await barra.barra.abrirCaja(
      eventoId: puertoViejo.id,
      operadorId: _marta,
      operadorNombre: 'Marta',
      numeroCaja: 3,
    );
    CajaBarra? lista;
    await abrir(tester, alAbrir: (_, _, caja) => lista = caja);
    await tester.tap(find.byKey(Key('barra_fiesta_${puertoViejo.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Abrir tu caja'), findsNothing);
    expect(lista!.numeroCaja, 3);
    expect(barra.barra.cajasGuardadas, hasLength(1));
  });

  testWidgets('si otra caja abierta tiene ese número, lo avisa y deja seguir', (tester) async {
    await barra.barra.abrirCaja(
      eventoId: puertoViejo.id,
      operadorId: 'a0000000-0000-4000-8000-000000000009',
      operadorNombre: 'Juan',
      numeroCaja: 2,
    );
    CajaBarra? lista;
    await abrir(tester, alAbrir: (_, _, caja) => lista = caja);
    await tester.tap(find.byKey(Key('barra_fiesta_${puertoViejo.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('caja_numero_2')));
    await tester.pump();
    expect(find.byKey(const Key('caja_numero_ocupada')), findsOneWidget);
    expect(find.textContaining('Juan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('caja_abrir')));
    await tester.pumpAndSettle();
    expect(lista!.numeroCaja, 2);
  });

  testWidgets('SALIR vuelve a la entrada', (tester) async {
    final c = await abrir(tester);
    await tester.tap(find.byKey(const Key('barra_salir')));
    await tester.pumpAndSettle();
    expect(c.read(appRoleProvider).kind, AppRoleKind.none);
  });

  testWidgets('la línea sin internet se pone al día al abrir', (tester) async {
    await abrir(tester);
    expect(barra.bajadas, 1);
    expect(find.textContaining('Lista para trabajar sin internet'), findsOneWidget);
  });

  testWidgets('en un celular, con un nombre largo, no se desborda', (tester) async {
    operadores.operadores.lista
      ..clear()
      ..add(operadorDePrueba(_marta, 'MARIA DE LOS ANGELES FERNANDEZ DE LA TORRE', '5555'));
    await abrir(tester, tamano: const Size(360, 700));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('barra_salir')), findsOneWidget);
  });

  group('lo que dice la línea sin internet', () {
    final ahora = DateTime(2026, 12, 4, 23, 50);
    String texto(DatosSinInternetBarra d) => EstadoSinInternetBarra.de(d, ahora: ahora).texto;

    test('con internet y al día', () {
      expect(
        texto(DatosSinInternetBarra(hayInternet: true, alDia: DateTime(2026, 12, 4, 21, 40), fiestas: 2)),
        'Lista para trabajar sin internet · al día hoy 21:40',
      );
    });

    test('con internet y ventas subiendo', () {
      expect(
        texto(DatosSinInternetBarra(hayInternet: true, alDia: DateTime(2026, 12, 4, 21, 40), fiestas: 2, sinSubir: 3)),
        'Lista para trabajar sin internet · al día hoy 21:40 · 3 ventas subiendo',
      );
    });

    test('nunca bajó: se está poniendo al día, o no pudo', () {
      expect(texto(const DatosSinInternetBarra(hayInternet: true, bajando: true)),
          'Poniéndose al día para trabajar sin internet…');
      expect(texto(const DatosSinInternetBarra(hayInternet: true, fallo: true)),
          'Todavía no está lista para trabajar sin internet: no se pudo bajar. Se vuelve a intentar sola.');
    });

    test('sin internet, sigue con lo de este equipo y cuenta lo que espera subir', () {
      final e = EstadoSinInternetBarra.de(
        DatosSinInternetBarra(hayInternet: false, alDia: DateTime(2026, 12, 4, 21, 40), fiestas: 1, sinSubir: 1),
        ahora: ahora,
      );
      expect(e.tipo, TipoSinInternet.sinInternet);
      expect(e.texto,
          'Sin internet · se sigue con lo de este equipo (al día 21:40) · 1 venta sin subir: se suben solas al volver');
    });

    test('sin internet y sin precios, pide conectarlo', () {
      final e = EstadoSinInternetBarra.de(const DatosSinInternetBarra(hayInternet: false), ahora: ahora);
      expect(e.tipo, TipoSinInternet.sinLista);
      expect(e.texto, contains('conectalo un momento a internet'));
    });
  });

  group('la puesta al día', () {
    test('con internet baja, anota la hora y cuenta; sin internet no intenta', () async {
      final b = BarraEnPrueba();
      final p = b.barra.producto('Agua');
      b.barra.precio(BarraEnPrueba.id(1), p, 1000);
      DateTime? anotada;
      final puesta = PuestaAlDiaBarra(
        accesos: AccesosBarra(
          bajar: () async {
            b.bajadas++;
            return true;
          },
          contarFiestas: () async => (await b.barra.fiestasConPrecio()).length,
          contarSinSubir: b.barra.ventasSinSubir,
          leerAlDia: () async => null,
          anotarAlDia: (c) async => anotada = c,
          ahora: () => DateTime.utc(2026, 12, 5),
        ),
        hayInternet: true,
      );
      addTearDown(puesta.dispose);
      await puesta.arrancar();
      expect(b.bajadas, 1);
      expect(anotada, DateTime.utc(2026, 12, 5));
      expect(puesta.datos.fiestas, 1);

      puesta.conexion(false);
      await puesta.ponerAlDia();
      expect(b.bajadas, 1, reason: 'sin internet no baja');
      puesta.conexion(true);
      await Future<void>.delayed(Duration.zero);
      expect(b.bajadas, 2, reason: 'al volver internet, baja');
    });

    test('si no bajó, lo dice y no anota la hora', () async {
      var anoto = false;
      final puesta = PuestaAlDiaBarra(
        accesos: AccesosBarra(
          bajar: () async => false,
          contarFiestas: () async => 0,
          contarSinSubir: () async => 0,
          leerAlDia: () async => null,
          anotarAlDia: (_) async => anoto = true,
        ),
        hayInternet: true,
      );
      addTearDown(puesta.dispose);
      await puesta.arrancar();
      expect(puesta.datos.fallo, isTrue);
      expect(puesta.datos.alDia, isNull);
      expect(anoto, isFalse);
    });
  });
}
