// PRECIOS: el jefe pone el precio de la entrada de una fiesta (etapa 3 del spec
// del 13-nov, sección 6; desde la 6.9.3, primero "¿Qué se vende ahora?
// Anticipada · General" y sin nada opcional). El diálogo de verdad, con la
// venta de entradas en memoria, y la cuenta que hay detrás
// (`EleccionDePrecios`), sin pantalla.
//
// **El reloj va fijo** (`hoyEnArgentinaProvider`): si la anticipada rige y qué
// día ya pasó dependen de hoy, y con el día real estas pruebas cambiarían solas
// después del 28-nov-2026.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/eleccion_de_precios.dart';
import 'package:arguello_events/features/entradas/cuentas/precio_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/precios_de_entradas_dialog.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/entradas_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// Hoy, en el reloj de Argentina: el 20-nov-2026 al mediodía.
final _hoy = DateTime.utc(2026, 11, 20, 12);

/// El día de la fiesta: PRECIOS propone que la anticipada valga hasta el 28.
final _diaDeLaFiesta = DateTime(2026, 11, 29);

void main() {
  late EntradasEnMemoria entradas;

  /// Lo que devolvió el diálogo al cerrarse.
  ConfigEntradas? devuelto;
  var cerrado = false;

  setUp(() {
    entradas = EntradasEnMemoria();
    devuelto = null;
    cerrado = false;
  });

  Future<void> abrir(
    WidgetTester tester, {
    bool jefe = true,
    DateTime? hoy,
    DateTime? fechaFiesta,
    bool sinFecha = false,
    FotoDeLosLugares? lugares,
    RevisarLugares? revisarLugares,
  }) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ahora = hoy ?? _hoy;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...entradas.reemplazos,
        esRolJefeProvider.overrideWith((ref) => jefe),
        hoyEnArgentinaProvider.overrideWithValue(() => ahora),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  devuelto = await mostrarPreciosDeEntradas(
                    context,
                    eventoId: _fiesta,
                    fiesta: 'PUERTO VIEJO',
                    quien: 'Jefe',
                    fechaFiesta:
                        sinFecha ? null : (fechaFiesta ?? _diaDeLaFiesta),
                    lugares: lugares,
                    revisarLugares: revisarLugares,
                  );
                  cerrado = true;
                },
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

  String escrito(WidgetTester tester, String clave) =>
      tester.widget<TextField>(find.byKey(Key(clave))).controller!.text;

  Future<void> poner(WidgetTester tester, String clave, String texto) async {
    await tester.enterText(find.byKey(Key(clave)), texto);
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('precios_guardar')));
    await tester.pumpAndSettle();
  }

  /// Toca ANTICIPADA o GENERAL, arriba de todo.
  Future<void> elegir(WidgetTester tester, QueSeVende que) async {
    await tester.tap(find.byKey(Key('precio_se_vende_${que.name}')));
    await tester.pump();
  }

  /// Lo que se ve elegido arriba. Null: nada.
  QueSeVende? elegido(WidgetTester tester) {
    final s = tester
        .widget<SegmentedButton<QueSeVende>>(
          find.byKey(const Key('precio_que_se_vende')),
        )
        .selected;
    return s.isEmpty ? null : s.single;
  }

  String? problema(WidgetTester tester) {
    final f = find.byKey(const Key('precios_problema'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  group('el día de la anticipada', () {
    test('se escribe 28/11/2026 y se guarda 2026-11-28', () {
      expect(PrecioDeEntradas.diaDeTexto('28/11/2026'), '2026-11-28');
      expect(PrecioDeEntradas.diaDeTexto(' 5/1/2027 '), '2027-01-05');
      expect(PrecioDeEntradas.diaDeTexto('28-11-2026'), '2026-11-28');
      expect(PrecioDeEntradas.textoDelDia('2026-11-28'), '28/11/2026');
      expect(PrecioDeEntradas.textoDelDia(null), '');
    });

    test('un día que no existe no se acepta', () {
      expect(PrecioDeEntradas.diaDeTexto('31/02/2026'), isNull);
      expect(PrecioDeEntradas.diaDeTexto('28/11'), isNull);
      expect(PrecioDeEntradas.diaDeTexto('mañana'), isNull);
      expect(PrecioDeEntradas.diaDeTexto(''), isNull);
    });
  });

  // ── La cuenta, sin pantalla ────────────────────────────────────────────────

  group('lo elegido y las columnas (EleccionDePrecios)', () {
    final vacia = ConfigEntradas.vacia(_fiesta, ahora: DateTime.utc(2026, 11, 1));

    ConfigEntradas conPrecios({
      double? valor = 10000,
      double? anticipada,
      String? hasta,
      double lugares = 50,
      double recargo = 0,
    }) =>
        vacia.conPrecios(
          valorEntrada: valor,
          precioAnticipada: anticipada,
          anticipadaHasta: hasta,
          descuentoLugaresPct: lugares,
          recargoPct: recargo,
          descuentoAMano: false,
        );

    group('leer', () {
      test('sin config, o sin precio, no hay nada elegido; los porcentajes '
          'vienen con lo de siempre y el día, con el anterior a la fiesta', () {
        for (final c in [null, conPrecios(valor: null, lugares: 40)]) {
          final l = EleccionDePrecios.leer(c, _hoy, fiesta: _diaDeLaFiesta);
          expect(l.queSeVende, isNull);
          expect(l.general, isNull);
          expect(l.anticipada, isNull);
          expect(l.hasta, '2026-11-28');
          expect(l.descuentoLugaresPct, c == null ? 50 : 40);
          expect(l.recargoPct, 0);
          expect(l.notaDeLaAnticipada, isNull);
        }
      });

      test('un solo precio es GENERAL', () {
        final l = EleccionDePrecios.leer(conPrecios(recargo: 5), _hoy);
        expect(l.queSeVende, QueSeVende.general);
        expect(l.general, 10000);
        expect(l.anticipada, isNull);
        expect(l.recargoPct, 5);
        expect(l.notaDeLaAnticipada, isNull);
      });

      test('mientras rige la anticipada es ANTICIPADA, con sus tres precios; '
          'el último día rige entero', () {
        final c = conPrecios(anticipada: 8000, hasta: '2026-11-28');
        for (final hoy in [_hoy, DateTime.utc(2026, 11, 28, 23, 59)]) {
          final l = EleccionDePrecios.leer(c, hoy, fiesta: _diaDeLaFiesta);
          expect(l.queSeVende, QueSeVende.anticipada, reason: '$hoy');
          expect(l.anticipada, 8000);
          expect(l.hasta, '2026-11-28');
          expect(l.general, 10000);
        }
      });

      test('una anticipada que terminó se ve como GENERAL, con la nota, y no '
          'se vuelve a ofrecer', () {
        final c = conPrecios(anticipada: 8000, hasta: '2026-11-28');
        final l = EleccionDePrecios.leer(
          c,
          DateTime.utc(2026, 11, 29),
          fiesta: DateTime(2026, 12, 5),
        );
        expect(l.queSeVende, QueSeVende.general);
        expect(l.general, 10000);
        expect(l.notaDeLaAnticipada, 'La anticipada terminó el 28/11');
        expect(l.anticipada, isNull, reason: 'una anticipada nueva se escribe');
        expect(l.hasta, '2026-12-04', reason: 'el día propuesto, no el viejo');
      });

      test('el día propuesto: el anterior a la fiesta, nunca uno que ya pasó',
          () {
        expect(EleccionDePrecios.diaPropuesto(_diaDeLaFiesta, _hoy), '2026-11-28');
        expect(
          EleccionDePrecios.diaPropuesto(DateTime(2026, 12, 1), _hoy),
          '2026-11-30',
        );
        expect(
          EleccionDePrecios.diaPropuesto(DateTime(2026, 11, 21), _hoy),
          '2026-11-20',
          reason: 'la fiesta es mañana: la anticipada vale hasta hoy',
        );
        expect(EleccionDePrecios.diaPropuesto(DateTime(2026, 11, 20), _hoy), isNull);
        expect(EleccionDePrecios.diaPropuesto(null, _hoy), isNull);
      });
    });

    group('a las columnas', () {
      test('GENERAL: solo valor_entrada, y la anticipada queda vacía', () {
        final c = const EleccionDePrecios(
          queSeVende: QueSeVende.general,
          general: 12000,
          // Lo escrito antes de pasar a GENERAL no se guarda.
          anticipada: 8000,
          hasta: '2026-11-28',
          descuentoLugaresPct: 40,
          recargoPct: 5,
          descuentoAMano: true,
        ).enColumnas(
          conPrecios(anticipada: 8000, hasta: '2026-11-28'),
          hoyAr: _hoy,
        );
        expect(c.valorEntrada, 12000);
        expect(c.precioAnticipada, isNull);
        expect(c.anticipadaHasta, isNull);
        expect(c.descuentoLugaresPct, 40);
        expect(c.recargoPct, 5);
        expect(c.descuentoAMano, isTrue);
        expect(c.id, vacia.id);
        expect(c.createdAt, vacia.createdAt);
      });

      test('ANTICIPADA: su precio, su día y la General', () {
        final c = const EleccionDePrecios(
          queSeVende: QueSeVende.anticipada,
          general: 10000,
          anticipada: 8000,
          hasta: '2026-11-28',
          descuentoLugaresPct: 50,
          recargoPct: 0,
        ).enColumnas(vacia, hoyAr: _hoy);
        expect(c.valorEntrada, 10000);
        expect(c.precioAnticipada, 8000);
        expect(c.anticipadaHasta, '2026-11-28');
        expect(PrecioDeEntradas.deHoy(c, _hoy), 8000);
        expect(PrecioDeEntradas.deLugar(c), 5000,
            reason: 'la mesa adicional sale de la General');
      });

      test('lo guardado se vuelve a leer igual', () {
        for (final e in const [
          EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            general: 10000,
            anticipada: 8000,
            hasta: '2026-11-28',
            descuentoLugaresPct: 50,
            recargoPct: 3,
            descuentoAMano: true,
          ),
          EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 15000,
            descuentoLugaresPct: 30,
            recargoPct: 0,
          ),
        ]) {
          final l = EleccionDePrecios.leer(e.enColumnas(vacia, hoyAr: _hoy), _hoy);
          expect(l.queSeVende, e.queSeVende);
          expect(l.general, e.general);
          expect(l.anticipada, e.anticipada);
          if (e.queSeVende == QueSeVende.anticipada) expect(l.hasta, e.hasta);
          expect(l.descuentoLugaresPct, e.descuentoLugaresPct);
          expect(l.recargoPct, e.recargoPct);
          expect(l.descuentoAMano, e.descuentoAMano);
        }
      });

      test('lo que falta se dice en palabras, y no se arma nada', () {
        const bien = EleccionDePrecios(
          queSeVende: QueSeVende.anticipada,
          general: 10000,
          anticipada: 8000,
          hasta: '2026-11-28',
          descuentoLugaresPct: 50,
          recargoPct: 0,
        );
        expect(bien.loQueFalta(_hoy), isNull);
        final casos = <String, EleccionDePrecios>{
          'Elegí qué se vende ahora': const EleccionDePrecios(
            general: 10000,
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Poné el precio de la anticipada': const EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            general: 10000,
            hasta: '2026-11-28',
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Poné hasta qué día': const EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            general: 10000,
            anticipada: 8000,
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Ese día no existe': const EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            general: 10000,
            anticipada: 8000,
            hasta: '2026-02-31',
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Ese día ya pasó': const EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            general: 10000,
            anticipada: 8000,
            hasta: '2026-11-19',
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Poné también el precio de la General': const EleccionDePrecios(
            queSeVende: QueSeVende.anticipada,
            anticipada: 8000,
            hasta: '2026-11-28',
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Poné el precio de la General.': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'sin centavos': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 10000.5,
            descuentoLugaresPct: 50,
            recargoPct: 0,
          ),
          'Escribí el descuento de la mesa adicional': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 10000,
            recargoPct: 0,
          ),
          'va de 0 a 100': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 10000,
            descuentoLugaresPct: 120,
            recargoPct: 0,
          ),
          'Escribí el recargo por transferencia': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 10000,
            descuentoLugaresPct: 50,
          ),
          'El recargo va de 0 a 100.': const EleccionDePrecios(
            queSeVende: QueSeVende.general,
            general: 10000,
            descuentoLugaresPct: 50,
            recargoPct: double.nan,
          ),
        };
        for (final caso in casos.entries) {
          expect(caso.value.loQueFalta(_hoy), contains(caso.key), reason: caso.key);
          expect(
            () => caso.value.enColumnas(vacia, hoyAr: _hoy),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'el mismo texto',
              caso.value.loQueFalta(_hoy),
            )),
            reason: caso.key,
          );
        }
      });

      test('hoy no pasó: la anticipada puede valer hasta hoy', () {
        const hastaHoy = EleccionDePrecios(
          queSeVende: QueSeVende.anticipada,
          general: 10000,
          anticipada: 8000,
          hasta: '2026-11-20',
          descuentoLugaresPct: 50,
          recargoPct: 0,
        );
        expect(hastaHoy.loQueFalta(DateTime.utc(2026, 11, 20, 23, 59)), isNull);
        expect(hastaHoy.loQueFalta(DateTime.utc(2026, 11, 21)), contains('ya pasó'));
      });

      test('un 0 escrito vale: sin descuento y sin recargo', () {
        final c = const EleccionDePrecios(
          queSeVende: QueSeVende.general,
          general: 10000,
          descuentoLugaresPct: 0,
          recargoPct: 0,
        ).enColumnas(vacia, hoyAr: _hoy);
        expect(c.descuentoLugaresPct, 0);
        expect(PrecioDeEntradas.deLugar(c), 10000);
      });
    });
  });

  // ── La pantalla ────────────────────────────────────────────────────────────

  testWidgets('una fiesta sin nada: no viene nada elegido, con el 50 % y sin '
      'recargo, y dice que sin precio no se vende', (tester) async {
    await abrir(tester);
    expect(find.text('Precios de las entradas'), findsOneWidget);
    expect(find.text('PUERTO VIEJO'), findsOneWidget);
    expect(find.text('¿Qué se vende ahora?'), findsOneWidget);
    expect(elegido(tester), isNull);
    expect(find.byKey(const Key('precio_elegi')), findsOneWidget);
    // Sin elegir, no hay precios que poner.
    expect(find.byKey(const Key('precio_valor')), findsNothing);
    expect(find.byKey(const Key('precio_anticipada')), findsNothing);
    expect(find.byKey(const Key('precio_hasta')), findsNothing);
    expect(escrito(tester, 'precio_lugares'), '50');
    expect(escrito(tester, 'precio_recargo'), '0');
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('precio_a_mano'))).value,
      isFalse,
      reason: 'quien vende no descuenta hasta que el jefe lo tilde',
    );
    expect(find.text('Quien vende puede poner descuentos'), findsOneWidget);
    expect(find.text('Sin precio, esta fiesta no se puede vender.'), findsOneWidget);
    expect(find.byKey(const Key('precio_cada_una')), findsNothing);
    // Lo que ya no está.
    expect(find.textContaining('opcional'), findsNothing);
    expect(find.textContaining('las dos cosas o ninguna'), findsNothing);
  });

  testWidgets('sin elegir nada no se guarda', (tester) async {
    await abrir(tester);
    await guardar(tester);
    expect(problema(tester), 'Elegí qué se vende ahora: ANTICIPADA o GENERAL.');
    expect(cerrado, isFalse);
    expect(entradas.escrituras, 0);
  });

  testWidgets('con GENERAL, solo su precio; con ANTICIPADA, su precio, hasta qué '
      'día (el anterior a la fiesta) y la General', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.general);
    expect(elegido(tester), QueSeVende.general);
    expect(find.widgetWithText(TextField, 'Precio de la General'), findsOneWidget);
    expect(find.byKey(const Key('precio_anticipada')), findsNothing);
    expect(find.byKey(const Key('precio_hasta')), findsNothing);

    await elegir(tester, QueSeVende.anticipada);
    expect(elegido(tester), QueSeVende.anticipada);
    expect(find.widgetWithText(TextField, 'Precio de la anticipada'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Vale hasta el día (inclusive)'),
      findsOneWidget,
    );
    expect(escrito(tester, 'precio_hasta'), '28/11/2026');
    expect(
      find.widgetWithText(
        TextField,
        'Precio de la General (cuando termina la anticipada)',
      ),
      findsOneWidget,
    );

    // Tocar la elegida no la saca.
    await elegir(tester, QueSeVende.anticipada);
    expect(elegido(tester), QueSeVende.anticipada);
  });

  testWidgets('sin la fecha de la fiesta no se propone ningún día', (tester) async {
    await abrir(tester, sinFecha: true);
    await elegir(tester, QueSeVende.anticipada);
    expect(escrito(tester, 'precio_hasta'), '');
  });

  testWidgets('la cuenta de los lugares adicionales va a la vista, sale de la '
      'General y sigue lo que se escribe', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.general);
    await poner(tester, 'precio_valor', '10000');
    expect(find.text(r'Cada una: $ 5.000'), findsOneWidget);
    expect(find.byKey(const Key('precio_sin_valor')), findsNothing);
    expect(
      find.text('Pagan el precio de la General con este descuento, nunca el de '
          'la anticipada.'),
      findsOneWidget,
    );
    await poner(tester, 'precio_lugares', '40');
    expect(find.text(r'Cada una: $ 6.000'), findsOneWidget);
    // La anticipada no la cambia, y cambiar de opinión no borra la General.
    await elegir(tester, QueSeVende.anticipada);
    expect(escrito(tester, 'precio_valor'), '10000');
    await poner(tester, 'precio_anticipada', '8000');
    expect(find.text(r'Cada una: $ 6.000'), findsOneWidget);
  });

  testWidgets('guardar la anticipada deja las tres columnas con quién lo puso, y '
      'al volver a abrir está todo', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.anticipada);
    await poner(tester, 'precio_anticipada', '8000');
    // El día viene propuesto: 28/11/2026.
    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_recargo', '5');
    await tester.tap(find.byKey(const Key('precio_a_mano')));
    await tester.pump();
    await guardar(tester);

    expect(cerrado, isTrue);
    final c = entradas.configs[_fiesta]!;
    expect(devuelto!.toMap(), c.toMap());
    expect(c.valorEntrada, 10000);
    expect(c.precioAnticipada, 8000);
    expect(c.anticipadaHasta, '2026-11-28');
    expect(c.descuentoLugaresPct, 50);
    expect(c.recargoPct, 5);
    expect(c.descuentoAMano, isTrue);
    expect(c.hechoPor, 'Jefe');
    expect(entradas.escrituras, 1);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(elegido(tester), QueSeVende.anticipada);
    expect(escrito(tester, 'precio_valor'), '10000');
    expect(escrito(tester, 'precio_anticipada'), '8000');
    expect(escrito(tester, 'precio_hasta'), '28/11/2026');
    expect(escrito(tester, 'precio_recargo'), '5');
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('precio_a_mano'))).value,
      isTrue,
    );
  });

  for (final anticipada in [true, false]) {
    testWidgets('guardar sin cambiar nada no escribe '
        '(${anticipada ? 'con la anticipada' : 'con un solo precio'})',
        (tester) async {
      entradas.conPrecio(
        _fiesta,
        anticipada: anticipada ? 8000 : null,
        hasta: anticipada ? '2026-11-28' : null,
      );
      final antes = entradas.configs[_fiesta]!.toMap();
      await abrir(tester);
      expect(
        elegido(tester),
        anticipada ? QueSeVende.anticipada : QueSeVende.general,
      );
      await guardar(tester);
      expect(cerrado, isTrue);
      expect(entradas.escrituras, 0);
      expect(entradas.configs[_fiesta]!.toMap(), antes,
          reason: 'ni quién ni cuándo cambian');
    });
  }

  testWidgets('la anticipada pide su precio, su día y la General', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.anticipada);
    await guardar(tester);
    expect(problema(tester), 'Poné el precio de la anticipada.');
    expect(cerrado, isFalse, reason: 'no se cierra: no se pierde lo escrito');

    await poner(tester, 'precio_anticipada', '8000');
    expect(problema(tester), isNull, reason: 'al corregir, el aviso se va');
    await poner(tester, 'precio_hasta', '');
    await guardar(tester);
    expect(problema(tester), 'Poné hasta qué día vale la anticipada.');

    await poner(tester, 'precio_hasta', '31/02/2026');
    await guardar(tester);
    expect(problema(tester), contains('Ese día no existe'));

    await poner(tester, 'precio_hasta', '28/11/2026');
    await guardar(tester);
    expect(problema(tester), contains('Poné también el precio de la General'));
    expect(entradas.escrituras, 0);
    expect(entradas.configs, isEmpty);

    await poner(tester, 'precio_valor', '10000');
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.precioAnticipada, 8000);
  });

  testWidgets('la anticipada no puede terminar un día que ya pasó; hoy sí',
      (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.anticipada);
    await poner(tester, 'precio_anticipada', '8000');
    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_hasta', '19/11/2026');
    await guardar(tester);
    expect(problema(tester), contains('Ese día ya pasó'));
    expect(entradas.escrituras, 0);

    await poner(tester, 'precio_hasta', '20/11/2026');
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.anticipadaHasta, '2026-11-20');
  });

  testWidgets('elegir GENERAL borra la anticipada', (tester) async {
    entradas.conPrecio(_fiesta, anticipada: 8000, hasta: '2026-11-28');
    await abrir(tester);
    expect(elegido(tester), QueSeVende.anticipada);
    await elegir(tester, QueSeVende.general);
    expect(find.byKey(const Key('precio_anticipada')), findsNothing);
    expect(escrito(tester, 'precio_valor'), '10000');
    await guardar(tester);
    expect(cerrado, isTrue);
    final c = entradas.configs[_fiesta]!;
    expect(c.valorEntrada, 10000);
    expect(c.precioAnticipada, isNull);
    expect(c.anticipadaHasta, isNull);
    expect(PrecioDeEntradas.deHoy(c, _hoy), 10000);
    expect(entradas.escrituras, 1);
  });

  testWidgets('una anticipada que terminó se ve como GENERAL, con la nota',
      (tester) async {
    entradas.conPrecio(_fiesta, anticipada: 8000, hasta: '2026-11-28');
    await abrir(
      tester,
      hoy: DateTime.utc(2026, 11, 29, 9),
      fechaFiesta: DateTime(2026, 12, 5),
    );
    expect(elegido(tester), QueSeVende.general);
    expect(escrito(tester, 'precio_valor'), '10000');
    expect(
      tester.widget<Text>(find.byKey(const Key('precio_anticipada_termino'))).data,
      'La anticipada terminó el 28/11',
    );
    // Una anticipada nueva se escribe de nuevo, con el día propuesto.
    await elegir(tester, QueSeVende.anticipada);
    expect(escrito(tester, 'precio_anticipada'), '');
    expect(escrito(tester, 'precio_hasta'), '04/12/2026');
  });

  testWidgets('un porcentaje vacío no vale 0: no se guarda; uno fuera de 0 a 100 '
      'tampoco', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.general);
    await poner(tester, 'precio_valor', '10000');
    await poner(tester, 'precio_lugares', '');
    expect(find.byKey(const Key('precio_cada_una')), findsNothing);
    await guardar(tester);
    expect(problema(tester), contains('Escribí el descuento de la mesa adicional'));

    await poner(tester, 'precio_lugares', '120');
    await guardar(tester);
    expect(problema(tester), contains('va de 0 a 100'));
    expect(find.byKey(const Key('precio_cada_una')), findsNothing);

    await poner(tester, 'precio_lugares', '50');
    await poner(tester, 'precio_recargo', '');
    await guardar(tester);
    expect(problema(tester), contains('Escribí el recargo por transferencia'));

    await poner(tester, 'precio_recargo', '250');
    await guardar(tester);
    expect(problema(tester), 'El recargo va de 0 a 100.');
    expect(entradas.escrituras, 0);

    await poner(tester, 'precio_recargo', '0');
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.recargoPct, 0);
  });

  testWidgets('desde PRECIOS ya no se deja una fiesta sin precio', (tester) async {
    entradas.conPrecio(_fiesta);
    await abrir(tester);
    expect(elegido(tester), QueSeVende.general);
    await poner(tester, 'precio_valor', '');
    expect(find.text('Sin precio, esta fiesta no se puede vender.'), findsOneWidget);
    await guardar(tester);
    expect(problema(tester), 'Poné el precio de la General.');
    expect(cerrado, isFalse);
    expect(entradas.escrituras, 0);
    expect(entradas.configs[_fiesta]!.valorEntrada, 10000);
  });

  testWidgets('cambiar el precio no toca ninguna venta hecha', (tester) async {
    entradas.conPrecio(_fiesta);
    final caja = await entradas.abrirCaja(eventoId: _fiesta, operadorNombre: 'F1');
    final venta = await entradas.vender(
      caja: caja,
      compradorNombre: 'COMPRADORA, UNA',
      renglones: [
        RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 20000,
      quien: 'F1',
    );
    final antes = venta.toMap();

    await abrir(tester);
    await poner(tester, 'precio_valor', '15000');
    await guardar(tester);
    expect(entradas.configs[_fiesta]!.valorEntrada, 15000);
    expect(entradas.listaVentas.single.toMap(), antes);
    expect(entradas.listaVentas.single.renglones.single.precio, 10000);
  });

  testWidgets('sin modo jefe se ve todo, con GUARDAR apagado y el motivo',
      (tester) async {
    entradas.conPrecio(_fiesta);
    await abrir(tester, jefe: false);
    expect(elegido(tester), QueSeVende.general);
    expect(escrito(tester, 'precio_valor'), '10000');
    final boton =
        tester.widget<FilledButton>(find.byKey(const Key('precios_guardar')));
    expect(boton.onPressed, isNull);
    expect(find.byTooltip(kSoloEnModoJefe), findsOneWidget);
    await poner(tester, 'precio_valor', '1');
    await tester.tap(find.byKey(const Key('precios_guardar')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(entradas.escrituras, 0);
    expect(entradas.configs[_fiesta]!.valorEntrada, 10000);
  });

  testWidgets('si la base no anda, lo dice en palabras y no se cierra', (tester) async {
    await abrir(tester);
    await elegir(tester, QueSeVende.general);
    await poner(tester, 'precio_valor', '10000');
    entradas.falla = true;
    await guardar(tester);
    expect(problema(tester), 'No se pudieron guardar los precios. Probá de nuevo.');
    expect(cerrado, isFalse);
    // Vuelve a andar: se guarda con lo que estaba escrito.
    entradas.falla = false;
    await guardar(tester);
    expect(cerrado, isTrue);
    expect(entradas.configs[_fiesta]!.valorEntrada, 10000);
  });

  // 17-nov-2026: el descuento de los lugares es para lo que la familia tenía
  // cargado al sorteo. PRECIOS dice qué rige en esa fiesta.
  group('a qué le toca el descuento de los lugares', () {
    // 12/11/2026 21:40 en Argentina.
    final sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);
    SorteoMesasRegistro sorteo({Map<String, String>? lugares}) =>
        SorteoMesasRegistro(
          id: 's',
          eventoId: _fiesta,
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {'a': '12'},
          lugares: lugares,
          createdAt: sorteoEl,
        );
    final sinAnotar = LugaresAlSorteo.vigente([sorteo()]);
    final anotados = LugaresAlSorteo.vigente([sorteo(lugares: const {})]);

    testWidgets('sin el dato no dice nada (quien lo abre de otro lado)',
        (tester) async {
      await abrir(tester);
      expect(find.byKey(const Key('precio_lugares_sin_sorteo')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_anotados')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsNothing);
    });

    testWidgets('una fiesta sin sortear: vale para lo cargado el día del sorteo',
        (tester) async {
      await abrir(tester, lugares: FotoDeLosLugares.sinSorteo);
      final texto = tester
          .widget<Text>(find.byKey(const Key('precio_lugares_sin_sorteo')))
          .data!;
      expect(texto, contains('el día del sorteo'));
      expect(texto, contains('paga el precio del día, sin descuento'));
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });

    testWidgets('con los lugares anotados dice de qué sorteo, con día y hora',
        (tester) async {
      await abrir(tester, lugares: anotados);
      final texto = tester
          .widget<Text>(find.byKey(const Key('precio_lugares_anotados')))
          .data!;
      expect(texto, contains('al sorteo del 12/11/2026 21:40 hs'));
      expect(texto, contains('paga el precio del día, sin descuento'));
      expect(texto, isNot(contains('entrada entera')));
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });

    testWidgets('sorteada antes de la regla: avisa que todo va con descuento y '
        'ofrece REVISAR LA LISTA', (tester) async {
      var abiertas = 0;
      await abrir(
        tester,
        lugares: sinAnotar,
        revisarLugares: (_) async {
          abiertas++;
          return null;
        },
      );
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(find.textContaining('todo va con descuento'), findsOneWidget);
      expect(find.textContaining('el precio del día, sin descuento'), findsOneWidget);
      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await tester.pumpAndSettle();
      expect(abiertas, 1);
      // No cambió nada: sigue avisando.
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(cerrado, isFalse);
    });

    testWidgets('aceptada la lista, PRECIOS pasa a decir qué sorteo rige, sin '
        'cerrarse ni perder lo escrito', (tester) async {
      await abrir(
        tester,
        lugares: sinAnotar,
        revisarLugares: (_) async => anotados,
      );
      await elegir(tester, QueSeVende.general);
      await poner(tester, 'precio_valor', '12000');
      await tester.tap(find.byKey(const Key('precio_revisar_lugares')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsNothing);
      expect(find.byKey(const Key('precio_lugares_anotados')), findsOneWidget);
      expect(elegido(tester), QueSeVende.general);
      expect(escrito(tester, 'precio_valor'), '12000');
      expect(cerrado, isFalse);
    });

    testWidgets('sin quien abra la lista, avisa pero no pone el botón',
        (tester) async {
      await abrir(tester, lugares: sinAnotar);
      expect(find.byKey(const Key('precio_lugares_sin_revisar')), findsOneWidget);
      expect(find.byKey(const Key('precio_revisar_lugares')), findsNothing);
    });
  });
}
