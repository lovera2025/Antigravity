import 'dart:io';

import 'package:arguello_events/features/eventos/services/despues_de_guardar_cobro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **El modal del cobro se cierra apenas el cobro queda guardado** (6.5.0).
///
/// El 9-nov el usuario contó que a veces, al CONFIRMAR PAGO, el modal quedaba
/// abierto con el pago ya hecho. Esperaba la subida a la nube antes de cerrarse,
/// y si algo de lo de después fallaba decía "No se pudo guardar el cobro.
/// Reintentá": reintentar cobraba dos veces.
void main() {
  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantalla = 'lib/features/eventos/detalle_evento_masivo_screen.dart';

  group('el modal del cobro, leído del texto', () {
    // La pantalla son casi 10.000 líneas y no se monta en un test (ver
    // CLAUDE.md): se lee, como `solo_modo_jefe_test.dart`.
    final fuente = leer(pantalla);
    const guardado = 'await repo.registrarPagosLote(';
    const cierre = 'cerrarRuta(rutaDelCobro, resultado: true);';

    test('guarda una sola vez', () {
      expect(guardado.allMatches(fuente).length, 1);
    });

    test('entre el guardado y el cierre no se espera nada', () {
      final i = fuente.indexOf(guardado);
      final finDelGuardado = fuente.indexOf(');', i) + 2;
      final j = fuente.indexOf(cierre, finDelGuardado);
      expect(j, greaterThan(finDelGuardado), reason: 'falta cerrar el modal');
      final entreMedio = fuente.substring(finDelGuardado, j);
      expect(
        RegExp(r'\bawait\b').hasMatch(entreMedio),
        isFalse,
        reason: 'el modal tiene que cerrarse sin esperar nada: con internet '
            'lento quedaba en GUARDANDO con el pago hecho',
      );
    });

    test('la subida no se espera y lo de después va por su lado', () {
      final i = fuente.indexOf(guardado);
      final fin = fuente.indexOf("'Error al registrar cobro masivo", i);
      final despues = fuente.substring(i, fin);
      expect(
        despues,
        isNot(contains('await ref\n')),
        reason: 'la subida va sin esperarla, dentro de DespuesDeGuardarCobro',
      );
      expect(despues, isNot(contains('Navigator.pop(context, true)')));
      expect(despues, contains('DespuesDeGuardarCobro.correr('));
      expect(despues, contains("'la subida a la nube'"));
    });

    test('con el cobro guardado, el error nunca dice "Reintentá"', () {
      final i = fuente.indexOf('} catch (e) {\n', fuente.indexOf(guardado));
      final catchDelCobro = fuente.substring(i, i + 2000);
      final reintenta =
          catchDelCobro.indexOf("'No se pudo guardar el cobro. Reintentá.");
      expect(reintenta, greaterThanOrEqualTo(0));
      final guardadoYa = catchDelCobro.indexOf('if (cobroGuardado)');
      expect(guardadoYa, greaterThanOrEqualTo(0));
      expect(guardadoYa, lessThan(reintenta));
      final rama = catchDelCobro.substring(guardadoYa, reintenta);
      expect(rama, contains('return;'));
    });
  });

  group('DespuesDeGuardarCobro.correr', () {
    test('cada paso corre aunque el anterior falle, y lo que falla se anota',
        () async {
      final hechos = <String>[];
      final anotado = <String, List<String>>{};
      final fallas = await DespuesDeGuardarCobro.correr(
        alumno: 'GÓMEZ, ANA',
        anotar: (alumno, f) async =>
            anotado[alumno] = [for (final x in f) x.paso],
        pasos: [
          PasoDespuesDeGuardar('la subida a la nube', () => throw 'sin red'),
          PasoDespuesDeGuardar('releer la ficha', () => hechos.add('ficha')),
          PasoDespuesDeGuardar('el recibo', () async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('sin impresora');
          }),
          PasoDespuesDeGuardar('refrescar', () async => hechos.add('lista')),
        ],
      );
      expect(hechos, ['ficha', 'lista']);
      expect([for (final f in fallas) f.paso], ['la subida a la nube', 'el recibo']);
      expect(anotado, {
        'GÓMEZ, ANA': ['la subida a la nube', 'el recibo'],
      });
    });

    test('sin fallas no anota nada', () async {
      var anoto = false;
      final fallas = await DespuesDeGuardarCobro.correr(
        alumno: 'X',
        anotar: (_, _) async => anoto = true,
        pasos: [PasoDespuesDeGuardar('nada', () {})],
      );
      expect(fallas, isEmpty);
      expect(anoto, isFalse);
    });

    test('si no puede anotar, igual no lanza', () async {
      final fallas = await DespuesDeGuardarCobro.correr(
        alumno: 'X',
        anotar: (_, _) async => throw const FileSystemException('ocupado'),
        pasos: [PasoDespuesDeGuardar('el recibo', () => throw 'roto')],
      );
      expect(fallas, hasLength(1));
    });

    test('el renglón del archivo dice cuándo, de quién y qué falló', () {
      final texto = DespuesDeGuardarCobro.textoDe(
        'GÓMEZ, ANA',
        const [FallaDespuesDeGuardar('la subida a la nube', 'sin red')],
        DateTime(2026, 11, 9, 23, 5, 7),
      );
      expect(
        texto,
        '09/11/2026 23:05:07 · cobro de GÓMEZ, ANA, ya guardado en esta PC. '
        'Después falló:\n'
        '  la subida a la nube: sin red\n'
        '\n',
      );
    });
  });

  group('cerrarRuta', () {
    Future<(Route<dynamic>, Future<Object?>)> abrir(
      WidgetTester tester,
      BuildContext context,
      String texto,
    ) async {
      late Route<dynamic> ruta;
      final resultado = showDialog<Object?>(
        context: context,
        builder: (c) {
          ruta = ModalRoute.of(c)!;
          return AlertDialog(content: Text(texto));
        },
      );
      await tester.pumpAndSettle();
      return (ruta, resultado);
    }

    testWidgets('cierra el cobro aunque haya otra ventana encima, sin tocarla',
        (tester) async {
      late BuildContext contexto;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          contexto = c;
          return const SizedBox();
        }),
      ));
      final (cobro, resultadoCobro) = await abrir(tester, contexto, 'COBRO');
      await abrir(tester, contexto, 'OTRA');
      expect(find.text('COBRO'), findsOneWidget);
      expect(find.text('OTRA'), findsOneWidget);

      cerrarRuta(cobro, resultado: true);
      await tester.pumpAndSettle();
      expect(find.text('COBRO'), findsNothing);
      expect(find.text('OTRA'), findsOneWidget);
      await resultadoCobro;

      // Ya cerrado, no hace nada (ni cierra la otra).
      cerrarRuta(cobro, resultado: true);
      await tester.pumpAndSettle();
      expect(find.text('OTRA'), findsOneWidget);
    });

    testWidgets('arriba de todo, se cierra con el resultado', (tester) async {
      late BuildContext contexto;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          contexto = c;
          return const SizedBox();
        }),
      ));
      final (cobro, resultado) = await abrir(tester, contexto, 'COBRO');
      cerrarRuta(cobro, resultado: true);
      await tester.pumpAndSettle();
      expect(find.text('COBRO'), findsNothing);
      expect(await resultado, true);
    });
  });
}
