// El tótem de esta PC (`TotemLocal`, paso 3c de la 6.0.0): la escena del salón
// alimentada desde la base de la PC, para la vista de Recepción y la pantalla
// del asesor. Con la puerta en memoria y sin internet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/totem_orientation.dart';
import 'package:arguello_events/features/totem/widgets/totem_local.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

/// Se crea en `setUpAll`: creado adentro de un test deja un reloj suyo andando.
late SupabaseClient _supabase;

const _promocion = TotemConfig(eventoId: eventoMasivo, titulo: 'PROMOCIÓN 2026');

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// Monta el tótem del evento. Con [mostrar] se lo puede sacar de la pantalla.
Future<PuertaEnMemoria> _montar(
  WidgetTester tester, {
  String eventoId = eventoMasivo,
  List<Invitado>? filas,
  Map<String, TotemConfig> config = const {eventoMasivo: _promocion},
  bool encuadrar = false,
  Size tamano = const Size(540, 960),
  ValueNotifier<bool>? mostrar,
}) async {
  final mundo = PuertaEnMemoria(
    _supabase,
    alumnos: alumnosDeLaFicha(),
    filas: [...?filas],
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  final si = mostrar ?? ValueNotifier(true);
  await tester.pumpWidget(
    mundo.recepcion(
      Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<bool>(
          valueListenable: si,
          builder: (_, ver, _) => ver
              ? TotemLocal(
                  key: ValueKey(eventoId),
                  eventoId: eventoId,
                  encuadrar: encuadrar,
                )
              : const SizedBox(),
        ),
      ),
      config: config,
    ),
  );
  await _asentar(tester);
  return mundo;
}

/// Que entre: lo que hace "Ingresar" en Recepción, en la base de esta PC.
Future<void> _ingresar(PuertaEnMemoria mundo, String alumno, [int lugar = 0]) =>
    mundo.invitados.ingresarDesdeLaPuerta(
      eventoId: eventoMasivo,
      id: idDe(alumno, lugar),
      nombre: fichaDePrueba().de(idDe(alumno, lugar))!.nombre,
    );

Future<void> _verLlegada(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(EscenaTotem.entrada);
}

EscenaTotem _escena(WidgetTester tester) =>
    tester.widget<EscenaTotem>(find.byType(EscenaTotem));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    await cargarFuentesTotem();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FondoTotem.precargar();
  });

  tearDown(FondoTotem.olvidar);

  group('un masivo', () {
    testWidgets('los que ya habían entrado al abrir no se saludan',
        (tester) async {
      await _montar(tester, filas: [filaDe('perez'), filaDe('perez', 1)]);
      await _verLlegada(tester);
      expect(_escena(tester).llegada, isNull);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsNothing);
    });

    testWidgets('en Neón, sin QR', (tester) async {
      await _montar(tester);
      expect(_escena(tester).estilo, EstiloTotem.neon);
      expect(find.byType(QrImageView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un alumno sin fila se saluda con la mesa y las sillas',
        (tester) async {
      final mundo = await _montar(tester);
      await _ingresar(mundo, 'perez');
      await _verLlegada(tester);
      // Su fila se creó sin mesa: la mesa sale de los alumnos.
      expect(mundo.invitados.filas.single.numeroMesa, isNull);
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
      expect(_escena(tester).llegada!.mesa, '12');
      expect(find.text('10 sillas (8 + 2 extra)'), findsOneWidget);
      expect(find.text('Tusa · Karol G'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el alumno y sus acompañantes, en una sola tarjeta',
        (tester) async {
      final mundo = await _montar(tester);
      await _ingresar(mundo, 'perez');
      await _verLlegada(tester);
      await _ingresar(mundo, 'perez', 1);
      await tester.pump(const Duration(milliseconds: 400));
      await _ingresar(mundo, 'perez', 2);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
      expect(find.text('con GÓMEZ, ANA y PÉREZ, LUIS'), findsOneWidget);
      expect(_escena(tester).enCamino, 0);
    });

    testWidgets('dos familias seguidas: "1 más en camino" y 3 s',
        (tester) async {
      final mundo = await _montar(tester);
      await _ingresar(mundo, 'perez');
      await _verLlegada(tester);
      await _ingresar(mundo, 'garcia');
      await tester.pump();
      expect(find.text('1 más en camino'), findsOneWidget);
      // Con cola, la tarjeta dura 3 s y no 7: después va la siguiente. De a
      // pasos cortos, como corre la pantalla.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('GARCÍA, BRUNO'), findsOneWidget);
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsNothing);
    });

    testWidgets('la apariencia elegida en Personalizar manda', (tester) async {
      await _montar(
        tester,
        config: {
          eventoMasivo: _promocion.copyWith(estilo: 'gala'),
        },
      );
      expect(_escena(tester).estilo, EstiloTotem.gala);
    });
  });

  group('un particular', () {
    testWidgets('en Cristal, con QR, y saluda con la mesa de su fila',
        (tester) async {
      final mundo = await _montar(
        tester,
        eventoId: eventoParticular,
        config: const {},
        filas: [
          Invitado(
            id: 'i1',
            eventoId: eventoParticular,
            nombreCompleto: 'LÓPEZ, MARTA',
            dni: '30123456',
            numeroMesa: '4',
            estadoIngreso: EstadoIngreso.pendiente,
          ),
        ],
      );
      expect(_escena(tester).estilo, EstiloTotem.cristal);
      expect(find.byType(QrImageView), findsOneWidget);

      await mundo.invitados.marcarIngreso('i1');
      await _verLlegada(tester);
      expect(find.text('LÓPEZ, MARTA'), findsOneWidget);
      expect(_escena(tester).llegada!.mesa, '4');
      expect(tester.takeException(), isNull);
    });
  });

  group('encuadrada', () {
    testWidgets('vertical, si el tótem del evento no se giró', (tester) async {
      await _montar(tester, encuadrar: true, tamano: const Size(900, 700));
      final tam = tester.getSize(find.byType(EscenaTotem));
      expect(tam.height, greaterThan(tam.width));
      expect(tam.width / tam.height, moreOrLessEquals(9 / 16, epsilon: 0.01));
    });

    testWidgets('horizontal, si el tótem del evento quedó así', (tester) async {
      await TotemOrientationStore.save(
        eventoMasivo,
        TotemOrientation.horizontal,
      );
      await _montar(tester, encuadrar: true, tamano: const Size(900, 700));
      final tam = tester.getSize(find.byType(EscenaTotem));
      expect(tam.width / tam.height, moreOrLessEquals(16 / 9, epsilon: 0.01));
    });
  });

  testWidgets('al salir suelta la lista y los temporizadores', (tester) async {
    final mostrar = ValueNotifier(true);
    final mundo = await _montar(tester, mostrar: mostrar);
    final contenedor =
        ProviderScope.containerOf(tester.element(find.byType(TotemLocal)));
    await _ingresar(mundo, 'perez');
    await _verLlegada(tester);
    expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
    expect(contenedor.exists(invitadosStreamProvider(eventoMasivo)), isTrue);

    // Se va con una tarjeta en pantalla: su temporizador no puede quedar
    // andando.
    mostrar.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(TotemLocal), findsNothing);
    expect(contenedor.exists(invitadosStreamProvider(eventoMasivo)), isFalse);
  });
}
