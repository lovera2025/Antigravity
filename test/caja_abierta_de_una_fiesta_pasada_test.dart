// Una caja que no se cerró antes del mediodía siguiente a la fiesta (revisión
// final de la 6.9.0): la fiesta sigue en la lista de quien la abrió, en ese
// equipo, hasta que la cierre. Si no, la caja quedaba abierta para siempre: la
// cajera ya no llegaba a ella y nadie más la podía cerrar (una caja vive en el
// equipo que la abrió). Vale para Entradas y para la barra.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/fiestas_de_la_barra.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/dia_de_la_fiesta.dart';
import 'package:arguello_events/features/entradas/entradas_home_screen.dart';
import 'package:arguello_events/features/entradas/services/fiestas_que_vienen.dart';
import 'package:arguello_events/features/eventos/repositories/eventos_repository.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart' show ConexionApagada, MotorDePrueba;

/// Los eventos de la base, en memoria.
class _Eventos extends EventosRepository {
  _Eventos(EntregaEnMemoria e, this.lista) : super(e.supabase, ConexionApagada(), MotorDePrueba());
  final List<Evento> lista;

  @override
  Future<List<Evento>> getAll({String? modalidad}) async =>
      [for (final e in lista) if (modalidad == null || e.modalidad == modalidad) e];
}

/// Una fiesta de hace un mes y otra que viene, sea cual sea el día de hoy.
final _pasada = fiestaDePrueba(
  'e0000000-0000-4000-8000-0000000000aa',
  'LA DE HACE UN MES',
  DateTime.now().subtract(const Duration(days: 30)),
);
final _queViene = fiestaDePrueba(
  'e0000000-0000-4000-8000-0000000000bb',
  'LA QUE VIENE',
  DateTime.now().add(const Duration(days: 10)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('las listas, sin pantalla', () {
    final anoche = fiestaDePrueba('anoche', 'ANOCHE', DateTime(2026, 12, 4, 21));
    final otra = fiestaDePrueba('otra', 'OTRA', DateTime(2026, 12, 12, 21));
    final alOtroDia = DateTime(2026, 12, 5, 13);

    test('Entradas: pasado el mediodía, la de anoche sigue solo con una caja abierta', () {
      List<String> ids(Set<String> conCaja) => [
            for (final f in fiestasQueVienen([anoche, otra], alOtroDia, conCajaAbierta: conCaja)) f.id,
          ];
      expect(ids(const {}), ['otra']);
      expect(ids({'anoche'}), ['otra', 'anoche'], reason: 'la que ya pasó va al final');
    });

    // Revisión del 15-nov: con fiestas dos noches seguidas, la de anoche con la
    // caja olvidada salía primera, sin marca, y se vendía en la fiesta equivocada.
    test('la segunda noche, la de anoche con la caja olvidada va después de la de hoy', () {
      final viernes = fiestaDePrueba('viernes', 'VIERNES', DateTime(2026, 12, 4, 21));
      final sabado = fiestaDePrueba('sabado', 'SABADO', DateTime(2026, 12, 5, 21));
      final sabadoALaNoche = DateTime(2026, 12, 5, 22);
      expect(
        [for (final f in fiestasQueVienen([viernes, sabado], sabadoALaNoche, conCajaAbierta: {'viernes'})) f.id],
        ['sabado', 'viernes'],
      );
      expect(
        [
          for (final f in fiestasParaLaBarra([viernes, sabado], {'viernes', 'sabado'}, sabadoALaNoche,
              conCajaAbierta: {'viernes'}))
            f.id,
        ],
        ['sabado', 'viernes'],
      );
      expect(laFiestaYaPaso(viernes, sabadoALaNoche), isTrue);
      expect(laFiestaYaPaso(sabado, sabadoALaNoche), isFalse);
      // A la madrugada de la misma fiesta, la de anoche todavía no pasó.
      expect(laFiestaYaPaso(viernes, DateTime(2026, 12, 5, 3)), isFalse);
    });

    test('la barra: lo mismo, siempre que la fiesta tenga precios', () {
      List<String> ids(Set<String> conPrecio, Set<String> conCaja) => [
            for (final f in fiestasParaLaBarra([anoche, otra], conPrecio, alOtroDia, conCajaAbierta: conCaja))
              f.id,
          ];
      expect(ids({'anoche', 'otra'}, const {}), ['otra']);
      expect(ids({'anoche', 'otra'}, {'anoche'}), ['otra', 'anoche'], reason: 'la que ya pasó va al final');
      expect(ids({'otra'}, {'anoche'}), ['otra'], reason: 'sin precios no se elige');
    });
  });

  test('Entradas: la caja abierta de quien entró, en este equipo, le deja la fiesta a mano',
      () async {
    final e = EntregaEnMemoria();
    final entradas = EntradasEnMemoria();
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(),
      ...entradas.reemplazos,
      eventosRepositoryProvider.overrideWithValue(_Eventos(e, [_pasada, _queViene])),
    ]);
    addTearDown(c.dispose);
    final carla = e.operador(vende: true);
    await c.read(appRoleProvider.notifier).entrarComoEntradas(
          carla,
          const PermisosEfectivos(entradas: true, vendeEntradas: true),
        );
    Future<List<String>> ids() async =>
        [for (final f in await c.read(fiestasQueVienenProvider.future)) f.id];

    expect(await ids(), [_queViene.id]);

    // La caja de otro, o la de otro equipo, no cuentan.
    await entradas.abrirCaja(eventoId: _pasada.id, operadorId: 'otro', operadorNombre: 'Otro');
    c.invalidate(fiestasQueVienenProvider);
    expect(await ids(), [_queViene.id]);

    final caja = await entradas.abrirCaja(
      eventoId: _pasada.id,
      operadorId: carla.id,
      operadorNombre: 'Carla',
    );
    c.invalidate(fiestasQueVienenProvider);
    expect(await ids(), [_queViene.id, _pasada.id]);

    await entradas.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Carla');
    c.invalidate(fiestasQueVienenProvider);
    expect(await ids(), [_queViene.id], reason: 'cerrada, la fiesta se va');
  });

  test('la barra: la caja abierta de la cajera, en este equipo, le deja la fiesta a mano',
      () async {
    final prueba = BarraEnPrueba();
    prueba.eventos.addAll([_pasada, _queViene]);
    final b = prueba.barra;
    final p = b.producto('Cerveza', categoria: 'Cervezas', orden: 0);
    b.precio(_pasada.id, p, 3500);
    b.precio(_queViene.id, p, 3500);
    final operadores = OperadoresEnPrueba();
    final marta = operadorDePrueba('a0000000-0000-4000-8000-000000000001', 'Marta', '1111');
    operadores.operadores.lista.add(marta);
    final c = ProviderContainer(overrides: [
      ...operadores.reemplazos,
      ...prueba.reemplazos,
    ]);
    addTearDown(c.dispose);
    await c.read(appRoleProvider.notifier).entrarComoBarra(
          marta,
          const PermisosEfectivos(barra: true),
        );
    Future<List<String>> ids() async =>
        [for (final f in await c.read(fiestasDeLaBarraProvider.future)) f.id];

    expect(await ids(), [_queViene.id]);
    await b.abrirCaja(eventoId: _pasada.id, operadorId: marta.id, operadorNombre: 'Marta', numeroCaja: 1);
    c.invalidate(fiestasDeLaBarraProvider);
    expect(await ids(), [_queViene.id, _pasada.id]);
  });


  // Revisión del 15-nov: cerrada la caja de una fiesta que ya pasó, la lista
  // seguía con "Tu caja sigue abierta" y VENDER ofrecía abrir otra.
  testWidgets('Entradas: al volver de VENDER se relee la lista, y la fiesta ya cerrada se va',
      (tester) async {
    final e = EntregaEnMemoria();
    final entradas = EntradasEnMemoria();
    final c = ProviderContainer(overrides: [
      ...e.reemplazos(),
      ...entradas.reemplazos,
      eventosRepositoryProvider.overrideWithValue(_Eventos(e, [_pasada, _queViene])),
    ]);
    addTearDown(c.dispose);
    final carla = e.operador(vende: true);
    await c.read(appRoleProvider.notifier).entrarComoEntradas(
          carla,
          const PermisosEfectivos(entradas: true, vendeEntradas: true),
        );
    final caja = await entradas.abrirCaja(
      eventoId: _pasada.id,
      operadorId: carla.id,
      operadorNombre: 'Carla',
    );
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: EntradasHomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('caja_abierta_${_pasada.id}')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(Key('fiesta_${_pasada.id}'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(Key('fiesta_${_queViene.id}'))).dy),
      reason: 'la que ya pasó va al final',
    );

    await tester.tap(find.byKey(Key('vender_${_pasada.id}')));
    await tester.pumpAndSettle();
    // La cierra (en la app, con CERRAR CAJA) y vuelve.
    await entradas.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Carla');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(Key('fiesta_${_pasada.id}')), findsNothing, reason: 'cerrada, la fiesta se va');
    expect(find.byKey(Key('fiesta_${_queViene.id}')), findsOneWidget);
  });
}
