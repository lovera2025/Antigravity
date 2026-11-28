// "CELULARES" en la barra de Recepción de la PC y la ventana "Sumar un
// celular", con Recepción en memoria y una central de mentira a la que la
// prueba le pone cada estado. La central de verdad se prueba en
// `central_puerta_test.dart` y `central_provider_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';

import 'helpers/puerta_en_memoria.dart';

class _CentralDePrueba extends CentralDeLaPuerta {
  _CentralDePrueba(this.alPrender, {this.alAbrir = const EstadoCentral()});

  /// Cómo queda al prenderla.
  EstadoCentral alPrender;

  /// Cómo está al abrir Recepción: apagada, o ya prendida (para otra fiesta).
  final EstadoCentral alAbrir;
  final prendidas = <String>[];
  final reanudadas = <String>[];
  var cambios = 0;

  @override
  EstadoCentral build() => alAbrir;

  @override
  Future<void> prender(String eventoId, {bool comoTele = false}) async {
    prendidas.add(eventoId);
    state = alPrender;
  }

  @override
  Future<void> reanudar(String eventoId) async => reanudadas.add(eventoId);

  @override
  Future<void> cambiarCodigo() async {
    cambios++;
    state = EstadoCentral(
      eventoId: state.eventoId,
      codigo: '5555',
      puerto: state.puerto,
      direcciones: state.direcciones,
    );
  }
}

EstadoCentral _prendida({
  List<String> direcciones = const ['192.168.0.10'],
  List<PuestoConectado> puestos = const [],
  String evento = eventoMasivo,
  int locutores = 0,
}) =>
    EstadoCentral(
      eventoId: evento,
      codigo: '4821',
      codigoLocutor: '7391',
      locutores: locutores,
      puerto: 8787,
      direcciones: direcciones,
      puestos: puestos,
    );

/// Detrás está la vista del tótem, que se anima siempre: `pumpAndSettle` no
/// termina nunca.
Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late SupabaseClient supabase;
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  });

  late _CentralDePrueba central;

  Future<void> abrir(
    WidgetTester tester,
    EstadoCentral alPrender, {
    EstadoCentral alAbrir = const EstadoCentral(),
    String elegido = eventoMasivo,
  }) async {
    central = _CentralDePrueba(alPrender, alAbrir: alAbrir);
    final mundo = PuertaEnMemoria(supabase, alumnos: [
      alumnoDePrueba('c1', 'PÉREZ, JUAN', mesas: [12]),
    ]);
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(mundo.motor.bajo.close);
    await tester.pumpWidget(mundo.recepcion(
      const RecepcionUnifiedScreen(),
      elegido: elegido,
      extra: [centralDeLaPuertaProvider.overrideWith(() => central)],
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> abrirVentana(WidgetTester tester) async {
    await tester.tap(find.text('CELULARES'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('al abrir Recepción con un evento, se fija si la central se usó '
      'esta noche', (tester) async {
    await abrir(tester, _prendida());
    expect(central.reanudadas, [eventoMasivo]);
    expect(central.prendidas, isEmpty);
  });

  testWidgets('CELULARES abre la ventana con el QR, la dirección y el código',
      (tester) async {
    await abrir(tester, _prendida());
    await abrirVentana(tester);

    expect(central.prendidas, [eventoMasivo]);
    expect(find.text('SUMAR UN CELULAR'), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr, isNotNull);
    expect(find.text('192.168.0.10:8787'), findsOneWidget);
    expect(find.textContaining('4821', findRichText: true), findsOneWidget);
    expect(find.textContaining('wifi del router', findRichText: true),
        findsOneWidget);
    expect(find.text('Todavía no hay celulares conectados.'), findsOneWidget);

    await tester.tap(find.text('CERRAR'));
    await asentar(tester);
    expect(find.text('SUMAR UN CELULAR'), findsNothing);
  });

  testWidgets('SUMAR AL LOCUTOR, en un masivo: su QR (otro que el de los celulares), que solo mira, y si se '
      'conectó', (tester) async {
    await abrir(tester, _prendida(locutores: 1));
    await abrirVentana(tester);
    expect(find.byKey(const Key('locutor_qr')), findsNothing, reason: 'cerrado hasta tocarlo');
    await tester.tap(find.byKey(const Key('sumar_al_locutor')));
    await tester.pump();
    final qrs = tester.widgetList<QrImageView>(find.byType(QrImageView)).toList();
    expect(qrs, hasLength(2));
    expect(find.byKey(const Key('locutor_solo_mira')), findsOneWidget);
    expect(find.textContaining('No puede ingresar a nadie ni cambiar nada'), findsOneWidget);
    expect(find.textContaining('7391', findRichText: true), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('locutor_conectado'))).data, 'El locutor está conectado.');
  });

  testWidgets('en una fiesta particular no hay locutor', (tester) async {
    await abrir(tester, _prendida(evento: eventoParticular), elegido: eventoParticular);
    await abrirVentana(tester);
    expect(find.text('SUMAR UN CELULAR'), findsOneWidget);
    expect(find.byKey(const Key('sumar_al_locutor')), findsNothing);
  });

  testWidgets('con celulares: el botón dice cuántos y la ventana quiénes',
      (tester) async {
    final ahora = DateTime.now();
    await abrir(
      tester,
      _prendida(puestos: [
        PuestoConectado(
          celular: 'a',
          nombre: 'Juli',
          conectado: true,
          ultimaVez: ahora,
          marcados: 41,
        ),
        PuestoConectado(
          celular: 'b',
          nombre: 'Mati',
          conectado: false,
          ultimaVez: ahora.subtract(const Duration(minutes: 3)),
          marcados: 2,
        ),
      ]),
    );
    await abrirVentana(tester);
    expect(find.text('Juli · 41 marcados'), findsOneWidget);
    expect(find.text('Mati · sin señal hace 3 min'), findsOneWidget);

    await tester.tap(find.text('CERRAR'));
    await asentar(tester);
    expect(find.text('CELULARES · 1'), findsOneWidget);
  });

  testWidgets('con otra dirección, la ofrece por si la primera no conecta',
      (tester) async {
    await abrir(tester, _prendida(direcciones: ['192.168.0.10', '10.0.0.5']));
    await abrirVentana(tester);
    expect(find.text('Si no conecta, probá con 10.0.0.5:8787'), findsOneWidget);
  });

  testWidgets('sin router lo dice, y deja probar de nuevo', (tester) async {
    await abrir(tester, _prendida(direcciones: const []));
    await abrirVentana(tester);
    expect(find.textContaining('no está conectada a ningún router'),
        findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('Cambiar el código'), findsNothing);

    await tester.tap(find.text('PROBAR DE NUEVO'));
    await tester.pump();
    expect(central.prendidas, hasLength(2));
  });

  testWidgets('si no se pudo abrir, lo dice en palabras', (tester) async {
    await abrir(
      tester,
      const EstadoCentral(
        eventoId: eventoMasivo,
        error: 'No se pudo abrir la central en esta PC.',
      ),
    );
    await abrirVentana(tester);
    expect(find.text('No se pudo abrir la central en esta PC.'), findsOneWidget);
    expect(find.text('PROBAR DE NUEVO'), findsOneWidget);
  });

  // La central es una sola. Hasta la 6.8.0, abrir CELULARES con otro evento
  // elegido apagaba la de la fiesta y dejaba a sus celulares afuera, sin lista
  // y sin poder marcar (revisión del 13-nov).
  group('con la central prendida para otra fiesta', () {
    final ahora = DateTime.now();
    final deLaOtra = EstadoCentral(
      eventoId: eventoParticular,
      codigo: '7310',
      puerto: 8787,
      direcciones: const ['192.168.0.10'],
      puestos: [
        for (final n in ['Juli', 'Mati'])
          PuestoConectado(
            celular: n,
            nombre: n,
            conectado: true,
            ultimaVez: ahora,
            marcados: 10,
          ),
      ],
    );
    final cartel = find.byKey(const Key('celulares_de_otra_fiesta'));

    testWidgets('CELULARES pregunta antes de pasarla, y dice cuántos se cortan',
        (tester) async {
      await abrir(tester, _prendida(), alAbrir: deLaOtra);
      await abrirVentana(tester);

      expect(cartel, findsOneWidget);
      expect(find.textContaining('Tiene 2 celulares conectados.'), findsOneWidget);
      expect(central.prendidas, isEmpty, reason: 'todavía no tocó la central');
    });

    testWidgets('DEJARLA COMO ESTÁ: no la toca y cierra la ventana',
        (tester) async {
      await abrir(tester, _prendida(), alAbrir: deLaOtra);
      await abrirVentana(tester);
      await tester.tap(find.byKey(const Key('celulares_dejarla')));
      await asentar(tester);

      expect(central.prendidas, isEmpty);
      expect(cartel, findsNothing);
      expect(find.text('SUMAR UN CELULAR'), findsNothing);
    });

    testWidgets('PASARLA A ESTA: recién ahí la prende para esta fiesta',
        (tester) async {
      await abrir(tester, _prendida(), alAbrir: deLaOtra);
      await abrirVentana(tester);
      await tester.tap(find.byKey(const Key('celulares_pasarla')));
      await asentar(tester);

      expect(central.prendidas, [eventoMasivo]);
      expect(find.text('SUMAR UN CELULAR'), findsOneWidget);
      expect(find.textContaining('4821', findRichText: true), findsOneWidget);
    });
  });

  testWidgets('cambiar el código pregunta antes, y muestra el nuevo',
      (tester) async {
    await abrir(tester, _prendida());
    await abrirVentana(tester);
    await tester.tap(find.text('Cambiar el código (desconecta a todos)'));
    await asentar(tester);
    expect(find.textContaining('volver a escanear'), findsOneWidget);

    await tester.tap(find.text('CANCELAR'));
    await asentar(tester);
    expect(central.cambios, 0);

    await tester.tap(find.text('Cambiar el código (desconecta a todos)'));
    await asentar(tester);
    await tester.tap(find.text('CAMBIAR'));
    await asentar(tester);
    expect(central.cambios, 1);
    expect(find.textContaining('5555', findRichText: true), findsOneWidget);
  });
}
