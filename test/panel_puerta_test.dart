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

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/silla_puerta.dart';

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
  List<SillaPuerta> sillasDeLaNoche = const [],
  Size tamano = const Size(1366, 900),
  void Function(PuertaEnMemoria mundo)? preparar,
}) async {
  final mundo = PuertaEnMemoria(
    _supabase,
    alumnos: alumnos ?? _sorteada(),
    filas: filas,
    sillasDeLaNoche: sillasDeLaNoche,
  );
  preparar?.call(mundo);
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
      // Debajo, una línea por mesa: cuántas sillas tiene y si puede agregar.
      expect(find.text('Mesa 12: 8 sillas + 2 extra · ya no puede agregar'),
          findsOneWidget);
      expect(find.text('Mesa 14-15'), findsOneWidget);
      expect(find.text('Mesa 14: 8 sillas + 2 extra · ya no puede agregar'),
          findsOneWidget);
      expect(
        find.text('Mesa adicional 15: 8 sillas + 1 extra · puede agregar 1 más '
            '· se cobran en la barra'),
        findsOneWidget,
      );
      expect(
        find.text('El reparto de las sillas del contrato está a confirmar.'),
        findsOneWidget,
      );
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
  group('las sillas de la noche', () {
    SillaPuerta sumada(String contrato, int mesa, String vale, {int min = 0}) =>
        SillaPuerta(
          id: 'previa-$vale',
          eventoId: _masivo,
          contratoAlumnoId: contrato,
          mesa: mesa,
          vale: vale,
          anotadoPor: 'Pato',
          createdAt: horaDeIngreso.add(Duration(minutes: min)),
          updatedAt: horaDeIngreso.add(Duration(minutes: min)),
        );

    testWidgets('SUMAR SILLA anota con el vale y quién, y la lista lo dice',
        (tester) async {
      final mundo = await _abrir(tester);
      expect(
        find.text('Mesa 13: 8 sillas · puede agregar hasta 2 · se cobran en la '
            'barra'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('conteo_de_la_noche')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sumar_silla_benitez')));
      await _asentar(tester);
      expect(find.text('Sumar una silla a BENÍTEZ, TOMÁS'), findsOneWidget);
      expect(find.text('Le quedan 2 en esa mesa.'), findsOneWidget);
      expect(find.text('Queda anotada a nombre de PC.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vale')), '2 0017');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_silla')));
      await _asentar(tester);

      final s = mundo.sillasPuerta.filas.single;
      expect(s.mesa, 13);
      expect(s.vale, '2-17');
      expect(s.anotadoPor, 'PC');
      expect(find.text('Silla sumada a la mesa 13 de BENÍTEZ, TOMÁS.'),
          findsOneWidget);
      expect(find.textContaining('+1 silla · mesa 13 · vale 2-17 · PC'),
          findsOneWidget);
      expect(
        find.text('Mesa 13: 8 sillas + 1 extra (1 esta noche) · puede agregar 1 '
            'más · se cobran en la barra'),
        findsOneWidget,
      );
      expect(find.text('Esta noche: 1 silla sumada · vale 2-17'), findsOneWidget);
    });

    testWidgets('sin el número del vale no se puede confirmar', (tester) async {
      final mundo = await _abrir(tester);
      await tester.tap(find.byKey(const ValueKey('sumar_silla_benitez')));
      await _asentar(tester);
      FilledButton confirmar() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirmar_silla')));
      expect(confirmar().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('vale')), 'sin número');
      await tester.pump();
      expect(confirmar().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('vale')), '17');
      await tester.pump();
      expect(confirmar().onPressed, isNotNull);
      await tester.tap(find.text('CANCELAR'));
      await _asentar(tester);
      expect(mundo.sillasPuerta.filas, isEmpty);
    });

    testWidgets('en el tope, SUMAR SILLA está apagado y dice por qué',
        (tester) async {
      await _abrir(tester);
      final boton = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('sumar_silla_perez')));
      expect(boton.onPressed, isNull);
      expect(
        find.byTooltip('Ya no puede agregar a la mesa: 2 extra por mesa. Una silla suelta, con el botón de al lado'),
        findsOneWidget,
      );
    });

    testWidgets('en el tope, SILLA SUELTA sí: sin mesa, con el vale',
        (tester) async {
      final mundo = await _abrir(tester);
      await tester.tap(find.byKey(const ValueKey('silla_suelta_perez')));
      await _asentar(tester);
      expect(find.text('Sumar una silla suelta a PÉREZ, JUAN MARTÍN'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sin_mesa')), findsOneWidget);
      expect(find.text('¿A qué mesa?'), findsNothing);
      FilledButton confirmar() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirmar_silla')));
      expect(confirmar().onPressed, isNull, reason: 'sin vale no se suma');
      await tester.enterText(find.byKey(const ValueKey('vale')), '2 0051');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_silla')));
      await _asentar(tester);

      final s = mundo.sillasPuerta.filas.single;
      expect(s.esSuelta, isTrue);
      expect(s.vale, '2-51');
      expect(find.text('Silla suelta anotada para PÉREZ, JUAN MARTÍN.'),
          findsOneWidget);
      expect(find.textContaining('+1 silla suelta · vale 2-51 · PC'),
          findsOneWidget);
      // SUMAR SILLA sigue apagado: la suelta no ocupa lugar en la mesa.
      final sumar = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('sumar_silla_perez')));
      expect(sumar.onPressed, isNull);
    });

    testWidgets('sin sortear, no hay SILLA SUELTA', (tester) async {
      await _abrir(tester, alumnos: _sinSortear());
      expect(find.text('SILLA SUELTA'), findsNothing);
    });

    testWidgets('a una mesa adicional con lugar, aunque la principal esté llena',
        (tester) async {
      final mundo = await _abrir(tester);
      await tester.tap(find.byKey(const ValueKey('sumar_silla_acosta')));
      await _asentar(tester);
      // Solo se ofrece la que tiene lugar.
      expect(find.byKey(const ValueKey('mesa_14')), findsNothing);
      expect(find.byKey(const ValueKey('mesa_15')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vale')), '1 0040');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_silla')));
      await _asentar(tester);
      expect(mundo.sillasPuerta.filas.single.mesa, 15);
    });

    testWidgets('QUITAR pide el motivo y la línea queda tachada, con quién',
        (tester) async {
      final mundo = await _abrir(
        tester,
        sillasDeLaNoche: [sumada('benitez', 13, '1-12')],
      );
      expect(find.textContaining('+1 silla · mesa 13 · vale 1-12 · Pato'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quitar_previa-1-12')));
      await _asentar(tester);
      FilledButton quitar() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirmar_quitar')));
      expect(quitar().onPressed, isNull, reason: 'sin motivo no se quita');
      await tester.enterText(
          find.byKey(const ValueKey('motivo')), 'devolvieron el vale');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_quitar')));
      await _asentar(tester);

      final s = mundo.sillasPuerta.filas.single;
      expect(s.vigente, isFalse);
      expect(s.quitadaPor, 'PC');
      expect(find.text('Silla quitada de la mesa 13 de BENÍTEZ, TOMÁS.'),
          findsOneWidget);
      // La línea sigue, tachada, y abajo quién y por qué.
      final linea = tester.widget<Text>(find.byKey(const ValueKey('silla_previa-1-12')));
      expect(linea.style!.decoration, TextDecoration.lineThrough);
      expect(find.textContaining('quitada por PC'), findsOneWidget);
      expect(find.textContaining(': devolvieron el vale'), findsOneWidget);
      expect(find.byKey(const ValueKey('quitar_previa-1-12')), findsNothing);
      expect(find.text('Esta noche: ninguna silla sumada · 1 quitada'),
          findsOneWidget);
    });

    testWidgets('sin desbordes en un celular, con dos sumadas y una quitada',
        (tester) async {
      await _abrir(
        tester,
        tamano: const Size(360, 780),
        sillasDeLaNoche: [
          sumada('acosta', 15, '1-12', min: 1),
          sumada('benitez', 13, '2-30', min: 2),
          sumada('benitez', 13, '2-31', min: 3).quitada(
            por: 'Juli',
            motivo: 'la familia se arrepintió y devolvieron el vale en la barra',
            ahora: horaDeIngreso.add(const Duration(minutes: 9)),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Esta noche: 2 sillas sumadas · vales 1-12, 2-30 · 1 quitada'),
          findsOneWidget);
    });
  });
  group('el vale anulado en la barra', () {
    SillaPuerta sumada(String vale) => SillaPuerta(
          id: 'previa-$vale',
          eventoId: _masivo,
          contratoAlumnoId: 'benitez',
          mesa: 13,
          vale: vale,
          anotadoPor: 'Pato',
          createdAt: horaDeIngreso,
          updatedAt: horaDeIngreso,
        );

    /// La caja 2 de la barra vendió dos sillas (ventas 17 y 18).
    Future<List<VentaBarra>> venderSillas(PuertaEnMemoria mundo) async {
      final caja = await mundo.barra.abrirCaja(
        eventoId: _masivo,
        operadorId: 'o1',
        operadorNombre: 'Marta',
        numeroCaja: 2,
      );
      final ventas = <VentaBarra>[];
      for (var i = 0; i < 18; i++) {
        ventas.add(await mundo.barra.vender(
          caja: caja,
          renglones: const [
            RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 1),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 8000,
          quien: 'Marta',
        ));
      }
      return ventas;
    }

    testWidgets('la silla con la venta anulada va en rojo, para revisar', (tester) async {
      late List<VentaBarra> ventas;
      final mundo = await _abrir(
        tester,
        sillasDeLaNoche: [sumada('2-17'), sumada('2-18')],
        preparar: (m) {
          // Se arma antes de dibujar, en memoria.
          final caja = CajaBarra.abrir(
            eventoId: _masivo,
            operadorNombre: 'Marta',
            numeroCaja: 2,
            ahora: horaDeIngreso,
          );
          m.barra.cajasGuardadas.add(caja);
          ventas = [
            for (final n in [17, 18])
              VentaBarra.nueva(
                cajaBarraId: caja.id,
                eventoId: _masivo,
                numero: n,
                renglones: const [
                  RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 1),
                ],
                medio: MedioBarra.efectivo,
                efectivo: 8000,
                ahora: horaDeIngreso,
              ),
          ];
          m.barra.ventasGuardadas.addAll(ventas);
          m.barra.anulacionesGuardadas
              .add(AnulacionBarra.de(ventas.first, motivo: 'se arrepintió', ahora: horaDeIngreso));
        },
      );
      expect(mundo.barra.ventasGuardadas, hasLength(2));
      final rojo = tester.widget<Text>(find.byKey(const ValueKey('vale_anulado_previa-2-17')));
      expect(rojo.data, 'vale anulado en la barra: revisar');
      expect(rojo.style!.color, Colors.redAccent);
      expect(find.byKey(const ValueKey('vale_anulado_previa-2-18')), findsNothing);
      expect(
        find.text('Esta noche: 2 sillas sumadas · vales 2-17, 2-18 · 1 con el vale anulado'),
        findsOneWidget,
      );
      // No se saca sola: QUITAR sigue ahí.
      expect(find.byKey(const ValueKey('quitar_previa-2-17')), findsOneWidget);
    });

    testWidgets('si la barra la anula con el panel abierto, se pone en rojo al bajar',
        (tester) async {
      final mundo = await _abrir(tester, sillasDeLaNoche: [sumada('2-17')]);
      late List<VentaBarra> ventas;
      await tester.runAsync(() async => ventas = await venderSillas(mundo));
      mundo.motor.bajo.add({'barra_ventas'});
      await _asentar(tester);
      expect(find.byKey(const ValueKey('vale_anulado_previa-2-17')), findsNothing);

      await tester.runAsync(() => mundo.barra.anular(ventas[16], motivo: 'se arrepintió', quien: 'Jefe'));
      mundo.motor.bajo.add({'barra_anulaciones'});
      await _asentar(tester);
      expect(find.byKey(const ValueKey('vale_anulado_previa-2-17')), findsOneWidget);
    });

    testWidgets('al quitarla con motivo, deja de estar en rojo', (tester) async {
      final mundo = await _abrir(
        tester,
        sillasDeLaNoche: [sumada('2-17')],
        preparar: (m) {
          final caja = CajaBarra.abrir(
            eventoId: _masivo,
            operadorNombre: 'Marta',
            numeroCaja: 2,
            ahora: horaDeIngreso,
          );
          m.barra.cajasGuardadas.add(caja);
          final v = VentaBarra.nueva(
            cajaBarraId: caja.id,
            eventoId: _masivo,
            numero: 17,
            renglones: const [
              RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 1),
            ],
            medio: MedioBarra.efectivo,
            efectivo: 8000,
            ahora: horaDeIngreso,
          );
          m.barra.ventasGuardadas.add(v);
          m.barra.anulacionesGuardadas
              .add(AnulacionBarra.de(v, motivo: 'se arrepintió', ahora: horaDeIngreso));
        },
      );
      expect(find.byKey(const ValueKey('vale_anulado_previa-2-17')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quitar_previa-2-17')));
      await _asentar(tester);
      await tester.enterText(find.byKey(const ValueKey('motivo')), 'vale anulado en la barra');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_quitar')));
      await _asentar(tester);
      expect(mundo.sillasPuerta.filas.single.vigente, isFalse);
      expect(find.byKey(const ValueKey('vale_anulado_previa-2-17')), findsNothing);
      expect(find.textContaining(': vale anulado en la barra'), findsOneWidget);
    });
  });
}
