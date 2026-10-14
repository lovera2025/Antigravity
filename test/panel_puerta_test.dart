// El panel de Recepción entero, con sus providers, sin base ni red.
//
// Se monta `PanelPuerta` de verdad. En lugar de la base lleva reemplazos en
// memoria (`helpers/puerta_en_memoria.dart`), puestos por los mismos providers
// que usa la app: los alumnos de la institución, la lista de la puerta y quién
// entró. Así un test puede decir "este evento es masivo y no se sorteó" y
// mirar qué se ve y qué se marcó.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';

import 'helpers/puerta_en_memoria.dart';

const _masivo = eventoMasivo;
const _particular = eventoParticular;

/// Una institución chica; [sorteada] dice si ya tiene las mesas.
List<ContratoAlumno> _institucion({bool sorteada = true}) {
  List<int> m(List<int> mesas) => sorteada ? mesas : const [];
  return [
    alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
        mesas: m([12]), sillas: 2, acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS'],
        musica: 'Tusa · Karol G'),
    alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
        mesas: m([14, 15]), extras: 1, sillas: 3, division: '5° A'),
    alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS',
        mesas: m([13]), acomp: ['BENÍTEZ, SOL']),
    alumnoDePrueba('baja', '[BAJA] RÍOS, MARTA', mesas: m([16])),
  ];
}

List<ContratoAlumno> _sorteada() => _institucion();
List<ContratoAlumno> _sinSortear() => _institucion(sorteada: false);

/// Se crea en `setUpAll`, fuera de los tests: creado adentro del primero, deja
/// un reloj suyo andando y el test falla por eso.
late SupabaseClient _supabase;

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<PuertaEnMemoria> _abrir(
  WidgetTester tester, {
  String eventoId = _masivo,
  List<ContratoAlumno>? alumnos,
  List<Invitado>? filas,
  Size tamano = const Size(1366, 900),
}) async {
  final mundo = PuertaEnMemoria(
    _supabase,
    alumnos: alumnos ?? _sorteada(),
    filas: filas,
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  await tester.pumpWidget(mundo.panel(eventoId));
  await _asentar(tester);
  return mundo;
}

Future<void> _buscar(WidgetTester tester, String texto, {bool enter = false}) async {
  await tester.enterText(find.byType(TextField), texto);
  await tester.pump();
  if (enter) {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _asentar(tester);
  }
}

void main() {
  setUpAll(() {
    // La letra del panel es Outfit, que viene con la app: no hace falta bajarla.
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  });

  group('masivo sin sortear', () {
    testWidgets('los alumnos sin las bajas, con el aviso y sin mesa',
        (tester) async {
      await _abrir(tester, alumnos: _sinSortear());

      expect(find.textContaining('Todavía no se sorteó'), findsOneWidget);
      expect(find.text('PÉREZ, JUAN MARTÍN'), findsOneWidget);
      expect(find.text('GÓMEZ, ANA'), findsOneWidget);
      expect(find.text('Tusa · Karol G'), findsOneWidget);
      expect(find.textContaining('RÍOS, MARTA'), findsNothing);
      expect(find.text('1 dado de baja: no aparece.'), findsOneWidget);
      expect(find.textContaining('Mesa'), findsNothing);
      // El aviso nombra "las sillas"; lo que no tiene que haber es una cuenta.
      expect(find.textContaining(RegExp(r'\d+ sillas')), findsNothing);
      expect(find.text('0 de 6 adentro'), findsOneWidget);
    });

    testWidgets('Enter ingresa al único que coincide, creando su fila',
        (tester) async {
      final mundo = await _abrir(tester, alumnos: _sinSortear());

      await _buscar(tester, 'lucia', enter: true);

      expect(mundo.invitados.creados, [idInvitadoPuerta('acosta', 0)]);
      expect(find.text('ACOSTA, LUCÍA ingresó.'), findsOneWidget);
      expect(find.text('1 de 6 adentro'), findsOneWidget);
      // La búsqueda queda lista para el siguiente.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });

  group('masivo sorteado', () {
    testWidgets('la mesa, las sillas debajo y la música', (tester) async {
      await _abrir(tester);

      expect(find.textContaining('Todavía no se sorteó'), findsNothing);
      expect(find.text('Mesa 12'), findsOneWidget);
      expect(find.text('10 sillas (8 + 2 extra)'), findsOneWidget);
      expect(find.text('Mesa 14-15'), findsOneWidget);
      expect(find.text('14: 10 sillas · 15: 9 sillas · reparto a confirmar'),
          findsOneWidget);
      expect(find.text('acompañante'), findsNWidgets(3));
      // En un masivo la lista sale de los alumnos: no se agrega a mano.
      expect(find.text('AGREGAR'), findsNothing);
    });

    testWidgets('Enter con varios no ingresa a nadie y dice cuántos',
        (tester) async {
      final mundo = await _abrir(tester);

      await _buscar(tester, '12', enter: true);

      expect(mundo.invitados.creados, isEmpty);
      expect(mundo.invitados.marcados, isEmpty);
      expect(find.textContaining('Hay 3 sin ingresar'), findsOneWidget);
    });

    testWidgets('se ingresa a un acompañante con su botón', (tester) async {
      final mundo = await _abrir(tester, filas: [
        Invitado(
          id: idInvitadoPuerta('perez', 1),
          eventoId: _masivo,
          nombreCompleto: 'GÓMEZ, ANA',
          dni: '',
          numeroMesa: '12',
          estadoIngreso: EstadoIngreso.pendiente,
        ),
      ]);

      await _buscar(tester, 'ana gomez');
      // La familia entera: Juan, Ana y Luis, cada uno con su botón.
      expect(find.text('INGRESAR'), findsNWidgets(3));
      await tester.tap(find.text('INGRESAR').at(1));
      await _asentar(tester);

      // Ana ya tenía fila: se marca como siempre.
      expect(mundo.invitados.marcados, [idInvitadoPuerta('perez', 1)]);
      expect(find.textContaining('ADENTRO'), findsOneWidget);
    });

    testWidgets('los filtros y deshacer un ingreso', (tester) async {
      final mundo = await _abrir(tester, filas: [
        Invitado(
          id: idInvitadoPuerta('benitez', 0),
          eventoId: _masivo,
          nombreCompleto: 'BENÍTEZ, TOMÁS',
          dni: '',
          numeroMesa: '13',
          estadoIngreso: EstadoIngreso.ingresado,
          updatedAt: DateTime.utc(2026, 12, 13, 1, 41),
        ),
      ]);

      expect(find.text('Adentro 1'), findsOneWidget);
      await tester.tap(find.text('Adentro 1'));
      await _asentar(tester);
      expect(find.text('BENÍTEZ, TOMÁS'), findsOneWidget);
      expect(find.text('ACOSTA, LUCÍA'), findsNothing);

      await tester.tap(find.byTooltip('Deshacer el ingreso'));
      await _asentar(tester);
      await tester.tap(find.text('DESHACER'));
      await _asentar(tester);

      expect(mundo.invitados.desmarcados, [idInvitadoPuerta('benitez', 0)]);
      expect(find.text('Todavía no entró nadie.'), findsOneWidget);

      await tester.tap(find.text('Faltan 6'));
      await _asentar(tester);
      expect(find.text('ACOSTA, LUCÍA'), findsOneWidget);
    });

    testWidgets('el menú Más solo actualiza', (tester) async {
      final mundo = await _abrir(tester);
      await tester.tap(find.byTooltip('Más'));
      await _asentar(tester);
      expect(find.text('Vaciar lista…'), findsNothing);
      expect(find.text('Importar lista'), findsNothing);
      await tester.tap(find.text('Actualizar la lista'));
      await _asentar(tester);
      expect(mundo.actualizado, 1);
    });
  });

  group('particular', () {
    List<Invitado> lista() => [
          Invitado(
            id: 'i0000000-0000-4000-8000-000000000001',
            eventoId: _particular,
            nombreCompleto: 'LÓPEZ, MARTA',
            dni: '30123456',
            numeroMesa: '4',
            estadoIngreso: EstadoIngreso.pendiente,
          ),
          Invitado(
            id: 'i0000000-0000-4000-8000-000000000002',
            eventoId: _particular,
            nombreCompleto: 'RÍOS, PABLO',
            dni: '28555111',
            numeroMesa: '7',
            estadoIngreso: EstadoIngreso.pendiente,
          ),
        ];

    testWidgets('nombre, DNI y mesa; Agregar y el menú completo',
        (tester) async {
      final mundo = await _abrir(tester, eventoId: _particular, filas: lista());

      expect(find.text('DNI 30.123.456 · Mesa 4'), findsOneWidget);
      expect(find.textContaining('Todavía no se sorteó'), findsNothing);
      await tester.tap(find.text('AGREGAR'));
      expect(mundo.agregar, 1);

      await tester.tap(find.byTooltip('Más'));
      await _asentar(tester);
      expect(find.text('Importar lista'), findsOneWidget);
      await tester.tap(find.text('Vaciar lista…'));
      await _asentar(tester);
      expect(mundo.vaciar, 1);
    });

    testWidgets('Enter por DNI ingresa; eliminar pide confirmación desde el '
        'menú de la fila', (tester) async {
      final mundo = await _abrir(tester, eventoId: _particular, filas: lista());

      await _buscar(tester, '2855', enter: true);
      expect(mundo.invitados.marcados, ['i0000000-0000-4000-8000-000000000002']);

      // El tacho ya no está a la vista: se llega por ⋮.
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      await tester.tap(find.byTooltip('Opciones').first);
      await _asentar(tester);
      await tester.tap(find.text('Eliminar de la lista'));
      await _asentar(tester);
      expect(mundo.invitados.eliminados, isEmpty, reason: 'falta confirmar');
      await tester.tap(find.text('ELIMINAR'));
      await _asentar(tester);
      expect(mundo.invitados.eliminados, ['i0000000-0000-4000-8000-000000000001']);
    });
  });

  group('sin desbordes', () {
    for (final tamano in const [Size(360, 640), Size(800, 900), Size(1366, 900)]) {
      testWidgets('masivo a ${tamano.width.toInt()} px', (tester) async {
        await _abrir(tester, tamano: tamano);
        expect(tester.takeException(), isNull);
        await _buscar(tester, 'perez');
        expect(tester.takeException(), isNull);
      });

      testWidgets('masivo sin sortear a ${tamano.width.toInt()} px',
          (tester) async {
        await _abrir(tester, tamano: tamano, alumnos: _sinSortear());
        expect(tester.takeException(), isNull);
      });

      testWidgets('particular a ${tamano.width.toInt()} px', (tester) async {
        await _abrir(
          tester,
          tamano: tamano,
          eventoId: _particular,
          filas: [
            Invitado(
              id: 'i0000000-0000-4000-8000-000000000003',
              eventoId: _particular,
              nombreCompleto: 'DE LA FUENTE SAN MARTÍN, MARÍA DE LOS ÁNGELES',
              dni: '30123456',
              numeroMesa: '4',
              estadoIngreso: EstadoIngreso.ingresado,
              updatedAt: DateTime.utc(2026, 12, 13, 1, 41),
            ),
          ],
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
