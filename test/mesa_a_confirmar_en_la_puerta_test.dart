// La mesa adicional "a confirmar" en la puerta y en el tótem (6.9.2; pedido
// del jefe, 16-nov-2026).
//
// La noche de la fiesta, la adicional que no está paga entera se ve apagada y
// discreta: "a confirmar", sin palabras de plata, porque la familia puede
// estar mirando la pantalla. La recepcionista no cobra ni anula ("Esta mesa la
// confirma el jefe"), no se le suman sillas, y el tótem enciende solo las
// mesas pagas. Qué mesa es sale de los pagos (`adicional_a_confirmar_test`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/sillas_de_la_puerta.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

import 'helpers/puerta_en_memoria.dart';

/// PÉREZ: una mesa, la 12. ACOSTA: la 14 y una adicional, la 15.
List<ContratoAlumno> _alumnos({List<int> deAcosta = const [14, 15]}) => [
      alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
          mesas: [12], acomp: ['GÓMEZ, ANA']),
      alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
          mesas: deAcosta, extras: 1, acomp: ['ACOSTA, RAÚL'], division: '5° A'),
    ];

Map<String, dynamic> _pago(double monto, {String concepto = 'Mesa extra (1/1)'}) => {
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': 0,
    };

/// ACOSTA pagó su contrato y nada de la adicional.
Map<String, List<Map<String, dynamic>>> _soloLaBase() => {
      'perez': [_pago(300000, concepto: 'Cuota Base')],
      'acosta': [_pago(300000, concepto: 'Cuota Base')],
    };

Map<String, List<Map<String, dynamic>>> _conLaAdicional(double pagado) => {
      'perez': [_pago(300000, concepto: 'Cuota Base')],
      'acosta': [_pago(300000, concepto: 'Cuota Base'), _pago(pagado)],
    };

PuertaDelEvento _puerta({
  Map<String, List<Map<String, dynamic>>>? pagos,
  List<int> deAcosta = const [14, 15],
}) =>
    PuertaDelEvento.masivo(
      alumnos: _alumnos(deAcosta: deAcosta),
      pagos: pagos,
      invitados: const [],
    );

GrupoPuerta _acosta(PuertaDelEvento p) =>
    p.grupos.firstWhere((g) => g.contratoId == 'acosta');

late SupabaseClient _supabase;

Future<PuertaEnMemoria> _abrir(
  WidgetTester tester, {
  Map<String, List<Map<String, dynamic>>>? pagos,
  List<int> deAcosta = const [14, 15],
}) async {
  final mundo = PuertaEnMemoria(
    _supabase,
    alumnos: _alumnos(deAcosta: deAcosta),
    pagos: pagos,
  );
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  await tester.pumpWidget(mundo.panel(eventoMasivo));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  return mundo;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  });

  group('lo que decide la puerta', () {
    test('sin nada pagado de la adicional: esa mesa queda a confirmar, y la '
        'familia se muestra con la que tiene paga', () {
      final g = _acosta(_puerta(pagos: _soloLaBase()));
      expect(g.mesasAConfirmar, {15});
      expect(g.adicionalesSinMesa, 0);
      expect(g.mesaConfirmada, '14');
      final m15 = g.sillasPorMesa.mesa(15)!;
      expect(m15.estado, EstadoMesaPuerta.aConfirmar);
      expect(m15.texto, 'Mesa adicional 15 · a confirmar');
      expect(m15.puedeAgregar, isFalse, reason: 'no se le suman sillas');
      expect(g.sillasPorMesa.mesa(14)!.estado, EstadoMesaPuerta.conLugar);
    });

    test('pagada en parte también queda a confirmar', () {
      final g = _acosta(_puerta(pagos: _conLaAdicional(30000)));
      expect(g.mesasAConfirmar, {15});
      expect(g.mesaConfirmada, '14');
    });

    test('paga entera: es una mesa más', () {
      final g = _acosta(_puerta(pagos: _conLaAdicional(70000)));
      expect(g.mesasAConfirmar, isEmpty);
      expect(g.mesaConfirmada, g.titular.mesa);
      expect(g.sillasPorMesa.mesa(15)!.estado, EstadoMesaPuerta.conLugar);
    });

    test('sin poder leer los pagos no se marca ninguna', () {
      final g = _acosta(_puerta());
      expect(g.mesasAConfirmar, isEmpty);
      expect(g.adicionalesSinMesa, 0);
      expect(g.mesaConfirmada, g.titular.mesa);
    });

    test('la adicional que no salió en el sorteo: a confirmar, sin número', () {
      final g = _acosta(_puerta(pagos: _soloLaBase(), deAcosta: [14]));
      expect(g.mesasAConfirmar, isEmpty);
      expect(g.adicionalesSinMesa, 1);
      expect(g.mesaConfirmada, '14');
    });

    test('la familia de una sola mesa no cambia', () {
      final p = _puerta(pagos: _soloLaBase());
      final perez = p.grupos.firstWhere((g) => g.contratoId == 'perez');
      expect(perez.mesasAConfirmar, isEmpty);
      expect(perez.mesaConfirmada, '12');
    });

    test('una silla pedida para la mesa a confirmar va a la paga, y lo dice', () {
      final p = _puerta(pagos: _soloLaBase());
      final g = _acosta(p);
      DecisionSilla pedir(int? mesa) => decidirSilla(
            pedido: PedidoPuerta(
              id: 'x',
              que: QuePide.sumarSilla,
              personaId: g.titular.id,
              silla: DatosSilla(mesa: mesa, vale: '2 0017'),
            ),
            grupo: g,
            deLaNoche: const [],
          );
      final d = pedir(15);
      expect(d.hace, QueHaceLaCentral.sumarSilla);
      expect(d.mesa, 14);
      expect(d.aviso, 'La mesa 15 la confirma el jefe: la silla va a la mesa 14.');
      expect(pedir(null).mesa, 14);
    });

    test('al celular le llega igual, y sin ningún número de plata', () {
      final p = _puerta(pagos: _conLaAdicional(30000));
      final texto = jsonEncode(p.toJson());
      for (final plata in ['30000', '40000', '70000', 'precio', 'pagado', 'aPagar']) {
        expect(texto, isNot(contains(plata)), reason: plata);
      }
      final llego = PuertaDelEvento.fromJson(
        jsonDecode(texto) as Map<String, dynamic>,
        eventoId: eventoMasivo,
      );
      final g = _acosta(llego);
      expect(g.mesasAConfirmar, {15});
      expect(g.mesaConfirmada, '14');
      expect(g.sillasPorMesa.mesa(15)!.texto, 'Mesa adicional 15 · a confirmar');

      final sinMesa = PuertaDelEvento.fromJson(
        jsonDecode(jsonEncode(
          _puerta(pagos: _soloLaBase(), deAcosta: [14]).toJson(),
        )) as Map<String, dynamic>,
        eventoId: eventoMasivo,
      );
      expect(_acosta(sinMesa).adicionalesSinMesa, 1);
    });
  });

  group('el tótem', () {
    test('enciende solo la mesa paga, también para el acompañante', () {
      final p = _puerta(pagos: _soloLaBase());
      final g = _acosta(p);
      final ficha = FichaTotem.desdePuerta(eventoMasivo, p);
      expect(ficha.de(g.titular.id)!.mesa, '14');
      expect(ficha.de(g.acompanantes.single.id)!.mesa, '14');
      final perez = p.grupos.firstWhere((x) => x.contratoId == 'perez');
      expect(ficha.de(perez.titular.id)!.mesa, '12');
    });

    test('paga entera, o sin los pagos: las dos, como siempre', () {
      for (final pagos in [_conLaAdicional(70000), null]) {
        final p = _puerta(pagos: pagos);
        final g = _acosta(p);
        final ficha = FichaTotem.desdePuerta(eventoMasivo, p);
        expect(ficha.de(g.titular.id)!.mesa, g.titular.mesa);
        expect(g.titular.mesa, contains('15'));
      }
    });
  });

  group('en Recepción', () {
    testWidgets('la adicional sin pagar va en su línea, apagada, y la familia '
        'figura con la mesa paga', (tester) async {
      await _abrir(tester, pagos: _soloLaBase());
      expect(find.text('Mesa 14'), findsOneWidget);
      expect(find.text('Mesa 14-15'), findsNothing);
      expect(find.byKey(const ValueKey('mesa_acosta_15')), findsOneWidget);
      expect(find.text('Mesa adicional 15 · a confirmar'), findsOneWidget);
      // La familia de una sola mesa, igual que siempre.
      expect(find.text('Mesa 12'), findsOneWidget);
    });

    testWidgets('no dice nada de plata: la familia puede estar mirando', (
      tester,
    ) async {
      await _abrir(tester, pagos: _conLaAdicional(30000));
      expect(find.text('Mesa adicional 15 · a confirmar'), findsOneWidget);
      expect(
        find.textContaining(
          RegExp(r'\$|debe|sin pagar|adeuda|a pagar|30\.?000|40\.?000',
              caseSensitive: false),
        ),
        findsNothing,
      );
    });

    testWidgets('al tocarla solo dice que la confirma el jefe: ni cobrar ni '
        'anular', (tester) async {
      await _abrir(tester, pagos: _soloLaBase());
      expect(find.text('Esta mesa la confirma el jefe.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mesa_acosta_15')));
      await tester.pump();
      expect(find.text('Esta mesa la confirma el jefe.'), findsOneWidget);
      expect(find.textContaining(RegExp('COBRAR|ANULAR')), findsNothing);
    });

    testWidgets('SUMAR SILLA no ofrece la mesa a confirmar', (tester) async {
      await _abrir(tester, pagos: _soloLaBase());
      await tester.tap(find.byKey(const ValueKey('sumar_silla_acosta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mesa_14')), findsOneWidget);
      expect(find.byKey(const ValueKey('mesa_15')), findsNothing);
    });

    testWidgets('la que no salió en el sorteo: "Mesa adicional · a confirmar"', (
      tester,
    ) async {
      await _abrir(tester, pagos: _soloLaBase(), deAcosta: [14]);
      expect(find.text('Mesa 14'), findsOneWidget);
      expect(find.byKey(const ValueKey('mesa_acosta_sin_mesa')), findsOneWidget);
      expect(find.text('Mesa adicional · a confirmar'), findsOneWidget);
    });

    testWidgets('paga entera, o sin los pagos: Recepción es la de siempre', (
      tester,
    ) async {
      await _abrir(tester, pagos: _conLaAdicional(70000));
      expect(find.text('Mesa 14-15'), findsOneWidget);
      expect(find.textContaining('a confirmar'), findsNothing);

      await _abrir(tester);
      expect(find.text('Mesa 14-15'), findsOneWidget);
      expect(find.textContaining('a confirmar'), findsNothing);
    });
  });
}
