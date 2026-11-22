// PRECIOS → "¿Poner estos precios también en otras fiestas?" (pedido del
// usuario, 22-nov-2026: "sabés lo que es ir poniendo el precio fiesta por
// fiesta"). La cuenta (`PreciosEnOtrasFiestas`), sin pantalla, y el cartel de
// verdad, abierto desde PRECIOS con la venta de entradas en memoria.
//
// **El reloj va fijo** (`hoyEnArgentinaProvider`), como en
// `precios_de_entradas_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/entradas/cuentas/eleccion_de_precios.dart';
import 'package:arguello_events/features/entradas/cuentas/precios_en_otras_fiestas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/precios_de_entradas_dialog.dart';
import 'package:arguello_events/features/entradas/widgets/precios_en_otras_fiestas_dialog.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart' show fiestaDePrueba;
import 'helpers/entradas_en_memoria.dart';

const _estaId = 'e0000000-0000-4000-8000-000000000001';
const _otraId = 'e0000000-0000-4000-8000-000000000002';
const _terceraId = 'e0000000-0000-4000-8000-000000000003';
const _hoyId = 'e0000000-0000-4000-8000-000000000004';

/// Hoy, en el reloj de Argentina: el 20-nov-2026 al mediodía.
final _hoy = DateTime.utc(2026, 11, 20, 12);

/// Esta fiesta es el 29-nov: PRECIOS propone la anticipada hasta el 28.
final _diaDeEsta = DateTime(2026, 11, 29);

final _otra = fiestaDePrueba(_otraId, 'LA OTRA', DateTime(2026, 12, 6));
final _tercera = fiestaDePrueba(_terceraId, 'LA TERCERA', DateTime(2026, 12, 13));

/// Lo que se eligió en PRECIOS: la anticipada a $ 8.000 hasta [hasta] y la
/// General a $ 10.000, con el 50 % y el 5 % de recargo.
EleccionDePrecios _anticipada({String hasta = '2026-11-28'}) => EleccionDePrecios(
      queSeVende: QueSeVende.anticipada,
      anticipada: 8000,
      general: 10000,
      hasta: hasta,
      descuentoLugaresPct: 50,
      recargoPct: 5,
      descuentoAMano: true,
    );

const _general = EleccionDePrecios(
  queSeVende: QueSeVende.general,
  general: 12000,
  descuentoLugaresPct: 40,
  recargoPct: 0,
);

void main() {
  group('la cuenta (PreciosEnOtrasFiestas)', () {
    test('con "el día anterior a cada fiesta", cada una termina la víspera de la suya',
        () {
      final e = PreciosEnOtrasFiestas.paraLaFiesta(
        _anticipada(),
        fechaFiesta: DateTime(2026, 12, 6),
        dia: DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
        hoyAr: _hoy,
      );
      expect(e.hasta, '2026-12-05');
      // Todo lo demás, igual.
      expect(e.queSeVende, QueSeVende.anticipada);
      expect(e.anticipada, 8000);
      expect(e.general, 10000);
      expect(e.descuentoLugaresPct, 50);
      expect(e.recargoPct, 5);
      expect(e.descuentoAMano, isTrue);
      expect(e.loQueFalta(_hoy), isNull);
    });

    test('con "el mismo día", todas terminan el que se escribió', () {
      final e = PreciosEnOtrasFiestas.paraLaFiesta(
        _anticipada(hasta: '2026-11-25'),
        fechaFiesta: DateTime(2026, 12, 6),
        dia: DiaDeLaAnticipada.elMismo,
        hoyAr: _hoy,
      );
      expect(e.hasta, '2026-11-25');
    });

    test('con la General no hay día: se copia igual', () {
      final e = PreciosEnOtrasFiestas.paraLaFiesta(
        _general,
        fechaFiesta: DateTime(2026, 12, 6),
        dia: DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
        hoyAr: _hoy,
      );
      expect(e.queSeVende, QueSeVende.general);
      expect(e.general, 12000);
      expect(e.hasta, isNull);
      expect(e.descuentoLugaresPct, 40);
    });

    test('una fiesta sin fecha, o cuya víspera ya pasó, no puede tener "el día anterior"',
        () {
      expect(
        PreciosEnOtrasFiestas.problema(
          _anticipada(),
          fechaFiesta: null,
          dia: DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
          hoyAr: _hoy,
        ),
        'No tiene fecha: no se sabe su día anterior.',
      );
      expect(
        PreciosEnOtrasFiestas.problema(
          _anticipada(),
          fechaFiesta: DateTime(2026, 11, 20),
          dia: DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
          hoyAr: _hoy,
        ),
        'Su día anterior ya pasó: la anticipada no tendría días.',
      );
      // Con "el mismo día" sí se puede.
      expect(
        PreciosEnOtrasFiestas.problema(
          _anticipada(),
          fechaFiesta: null,
          dia: DiaDeLaAnticipada.elMismo,
          hoyAr: _hoy,
        ),
        isNull,
      );
    });

    test('viene elegido "el día anterior" si en PRECIOS quedó el propuesto; si no, "el '
        'mismo día"', () {
      expect(
        PreciosEnOtrasFiestas.diaQueViene(_anticipada(),
            fechaDeEstaFiesta: _diaDeEsta, hoyAr: _hoy),
        DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
      );
      expect(
        PreciosEnOtrasFiestas.diaQueViene(_anticipada(hasta: '2026-11-25'),
            fechaDeEstaFiesta: _diaDeEsta, hoyAr: _hoy),
        DiaDeLaAnticipada.elMismo,
      );
    });

    test('lo que tiene hoy cada fiesta, en un renglón', () {
      final vacia = ConfigEntradas.vacia(_otraId, ahora: _hoy);
      expect(PreciosEnOtrasFiestas.loQueTieneHoy(null, _hoy), 'Sin precio');
      expect(PreciosEnOtrasFiestas.loQueTieneHoy(vacia, _hoy), 'Sin precio');
      final general = vacia.conPrecios(
        valorEntrada: 10000,
        precioAnticipada: null,
        anticipadaHasta: null,
        descuentoLugaresPct: 50,
        recargoPct: 0,
        descuentoAMano: false,
      );
      expect(PreciosEnOtrasFiestas.loQueTieneHoy(general, _hoy), r'General $ 10.000');
      final conAnticipada = vacia.conPrecios(
        valorEntrada: 10000,
        precioAnticipada: 8000,
        anticipadaHasta: '2026-11-28',
        descuentoLugaresPct: 50,
        recargoPct: 0,
        descuentoAMano: false,
      );
      expect(PreciosEnOtrasFiestas.loQueTieneHoy(conAnticipada, _hoy),
          r'Anticipada $ 8.000 hasta el 28/11 · General $ 10.000');
    });
  });

  group('el cartel, desde PRECIOS', () {
    late EntradasEnMemoria entradas;
    late List<Evento> otras;

    setUp(() {
      entradas = EntradasEnMemoria();
      otras = [_otra, _tercera];
    });

    Future<void> abrir(WidgetTester tester, {bool jefe = true}) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...entradas.reemplazos,
          esRolJefeProvider.overrideWith((ref) => jefe),
          hoyEnArgentinaProvider.overrideWithValue(() => _hoy),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => mostrarPreciosDeEntradas(
                    context,
                    eventoId: _estaId,
                    fiesta: 'PUERTO VIEJO',
                    quien: 'Jefe',
                    fechaFiesta: _diaDeEsta,
                    // La de acá viene en la lista: PRECIOS la saca sola.
                    otrasFiestas: () async => [
                      fiestaDePrueba(_estaId, 'PUERTO VIEJO', _diaDeEsta),
                      ...otras,
                    ],
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> tocar(WidgetTester tester, String clave) async {
      await tester.ensureVisible(find.byKey(Key(clave)));
      await tester.tap(find.byKey(Key(clave)));
      await tester.pumpAndSettle();
    }

    /// PRECIOS con la anticipada a $ 8.000 (hasta el 28, el propuesto) y la
    /// General a $ 10.000, y GUARDAR.
    Future<void> guardarAnticipada(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('precio_se_vende_anticipada')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('precio_anticipada')), '8000');
      await tester.enterText(find.byKey(const Key('precio_valor')), '10000');
      await tester.enterText(find.byKey(const Key('precio_recargo')), '5');
      await tester.pump();
      await tocar(tester, 'precios_guardar');
    }

    String texto(WidgetTester tester, String clave) =>
        tester.widget<Text>(find.byKey(Key(clave))).data!;

    testWidgets('guardado, pregunta por las otras fiestas sin ninguna tildada; NO, '
        'SOLO ESTA deja las otras como estaban', (tester) async {
      entradas.conPrecio(_otraId, valor: 9000);
      await abrir(tester);
      await guardarAnticipada(tester);
      expect(entradas.configs[_estaId]!.precioAnticipada, 8000, reason: 'esta ya quedó');
      expect(find.text('¿Poner estos precios también en otras fiestas?'), findsOneWidget);
      expect(find.byKey(const Key('precios_otras_$_estaId')), findsNothing,
          reason: 'la de acá no se ofrece');
      expect(texto(tester, 'precios_otras_${_otraId}_hoy'), r'Hoy: General $ 9.000');
      expect(texto(tester, 'precios_otras_${_terceraId}_hoy'), 'Hoy: Sin precio');
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('precios_otras_poner'))).onPressed,
        isNull,
        reason: 'ninguna viene tildada',
      );
      final escriturasAntes = entradas.escrituras;
      await tocar(tester, 'precios_otras_no');
      expect(find.text('Precios de las entradas'), findsNothing, reason: 'PRECIOS se cierra');
      expect(entradas.escrituras, escriturasAntes);
      expect(entradas.configs[_otraId]!.valorEntrada, 9000);
      expect(entradas.configs[_terceraId], isNull);
    });

    testWidgets('tildadas dos, cada una queda con los mismos precios y su anticipada '
        'hasta la víspera de la suya', (tester) async {
      await abrir(tester);
      await guardarAnticipada(tester);
      expect(texto(tester, 'precios_otras_que'),
          r'Anticipada $ 8.000 hasta el día anterior a cada fiesta · General $ 10.000');
      await tocar(tester, 'precios_otras_$_otraId');
      await tocar(tester, 'precios_otras_$_terceraId');
      expect(find.text('PONER EN 2 FIESTAS'), findsOneWidget);
      await tocar(tester, 'precios_otras_poner');

      for (final (id, hasta) in [(_otraId, '2026-12-05'), (_terceraId, '2026-12-12')]) {
        final c = entradas.configs[id]!;
        expect(c.eventoId, id);
        expect(c.valorEntrada, 10000);
        expect(c.precioAnticipada, 8000);
        expect(c.anticipadaHasta, hasta);
        expect(c.descuentoLugaresPct, 50);
        expect(c.recargoPct, 5);
        expect(c.hechoPor, 'Jefe');
      }
      expect(entradas.configs[_estaId]!.anticipadaHasta, '2026-11-28');
      expect(texto(tester, 'precios_otras_quedaron'),
          'Listo: los precios quedaron en 2 fiestas: LA OTRA, LA TERCERA.');
      await tocar(tester, 'precios_otras_listo_cerrar');
      expect(find.text('Precios de las entradas'), findsNothing);
    });

    testWidgets('con "el 28/11", todas terminan ese día; TODAS tilda las que se pueden',
        (tester) async {
      otras = [_otra, _tercera, fiestaDePrueba(_hoyId, 'ES HOY', DateTime(2026, 11, 20))];
      await abrir(tester);
      await guardarAnticipada(tester);
      // La del 20-nov: su víspera ya pasó, no se puede con "el día anterior".
      expect(texto(tester, 'precios_otras_${_hoyId}_hoy'),
          'Su día anterior ya pasó: la anticipada no tendría días.');
      await tocar(tester, 'precios_otras_todas');
      expect(find.text('PONER EN 2 FIESTAS'), findsOneWidget);
      await tester.tap(find.byKey(const Key('precios_otras_dia_mismo')));
      await tester.pumpAndSettle();
      await tocar(tester, 'precios_otras_todas');
      expect(find.text('PONER EN 3 FIESTAS'), findsOneWidget);
      await tocar(tester, 'precios_otras_poner');
      for (final id in [_otraId, _terceraId, _hoyId]) {
        expect(entradas.configs[id]!.anticipadaHasta, '2026-11-28');
      }
    });

    testWidgets('con la General, sin la pregunta del día', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const Key('precio_se_vende_general')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('precio_valor')), '12000');
      await tester.enterText(find.byKey(const Key('precio_recargo')), '0');
      await tester.pump();
      await tocar(tester, 'precios_guardar');
      expect(find.byKey(const Key('precios_otras_dia')), findsNothing);
      await tocar(tester, 'precios_otras_$_otraId');
      await tocar(tester, 'precios_otras_poner');
      final c = entradas.configs[_otraId]!;
      expect(c.valorEntrada, 12000);
      expect(c.precioAnticipada, isNull);
      expect(c.anticipadaHasta, isNull);
    });

    testWidgets('sin otras fiestas no pregunta nada', (tester) async {
      otras = [];
      await abrir(tester);
      await guardarAnticipada(tester);
      expect(find.text('¿Poner estos precios también en otras fiestas?'), findsNothing);
      expect(find.text('Precios de las entradas'), findsNothing);
    });

    testWidgets('si una no se puede guardar, las demás quedan y lo dice', (tester) async {
      await abrir(tester);
      await guardarAnticipada(tester);
      await tocar(tester, 'precios_otras_$_otraId');
      await tocar(tester, 'precios_otras_$_terceraId');
      entradas.falla = true;
      await tocar(tester, 'precios_otras_poner');
      expect(find.byKey(const Key('precios_otras_quedaron')), findsNothing);
      expect(find.text('· LA OTRA: no se pudo guardar.'), findsOneWidget);
      expect(find.text('· LA TERCERA: no se pudo guardar.'), findsOneWidget);
    });

    // La segunda llave: el modo jefe pudo cerrarse con el cartel abierto.
    testWidgets('sin modo jefe, PONER está apagado', (tester) async {
      final c = ProviderContainer(overrides: [
        ...entradas.reemplazos,
        esRolJefeProvider.overrideWith((ref) => false),
        hoyEnArgentinaProvider.overrideWithValue(() => _hoy),
      ]);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarPreciosEnOtrasFiestas(
                  context,
                  elegido: _anticipada(),
                  fechaDeEstaFiesta: _diaDeEsta,
                  fiestas: otras,
                  quien: 'Jefe',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tocar(tester, 'precios_otras_$_otraId');
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('precios_otras_poner'))).onPressed,
        isNull,
      );
      expect(entradas.configs[_otraId], isNull);
    });
  });
}
