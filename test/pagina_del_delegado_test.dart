// La página del link del delegado, entera, con una nube en memoria.
// Lo que se prueba acá es lo que hace la pantalla con lo que contesta la nube;
// las reglas se prueban contra el SQL (`tool/delegado_sandbox/pruebas.mjs`).
//
// Desde la 6.9.2 (decisión del usuario, 17-nov-2026): todos corrigen todo,
// Enviar no cierra, lo único que cierra es la fecha límite, y desde otro
// celular se entra tocando el nombre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/delegado/datos/nube_del_delegado.dart';
import 'package:arguello_events/features/delegado/pagina/pagina_del_delegado.dart';
import 'package:arguello_events/features/delegado/pagina/sesiones_del_delegado.dart';

import 'helpers/delegado_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

DelegadoEnMemoria _nube() => DelegadoEnMemoria(
      eventoId: _fiesta,
      alumnos: [
        AlumnoDeMentira(
          'a1',
          'ACOSTA, LUCÍA',
          '6° A',
          acompanantes: ['ACOSTA, JORGE'],
          musica: 'Vivir mi vida',
        ),
        AlumnoDeMentira('a2', 'ÁLVAREZ, BRUNO', '6° A'),
        AlumnoDeMentira(
          'a3',
          'BENÍTEZ, MATEO',
          '6° A',
          acompanantes: ['BENÍTEZ, CARLA'],
        ),
        AlumnoDeMentira('a4', 'GÓMEZ, SOFÍA', '6° B'),
        AlumnoDeMentira('a5', '[BAJA] SOSA, DYLAN', '6° B', activo: false),
      ],
    );

/// Abre la página en un celular. Con [sesiones] se abre "en el mismo celular".
Future<void> _abrir(
  WidgetTester tester,
  DelegadoEnMemoria nube, {
  SesionesDelDelegado? sesiones,
  String? clave,
}) async {
  tester.view.physicalSize = const Size(390, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PaginaDelDelegado(
        key: UniqueKey(),
        clave: clave ?? nube.clave ?? 'no-existe',
        nube: nube,
        sesiones: sesiones ?? SesionesEnMemoria(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _entrar(WidgetTester tester, String nombre) async {
  await tester.enterText(find.byKey(const Key('delegado_nombre')), nombre);
  await tester.tap(find.byKey(const Key('delegado_entrar')));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String llave) async {
  final f = find.byKey(Key(llave));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Lo que dice el texto con esa llave (o el que lleva adentro, si la llave es
/// de su recuadro).
String _texto(WidgetTester tester, String llave) {
  final f = find.byKey(Key(llave));
  final w = tester.widget(f);
  if (w is Text) return w.data!;
  return tester
      .widget<Text>(find.descendant(of: f, matching: find.byType(Text)).first)
      .data!;
}

String _escrito(WidgetTester tester, String llave) =>
    tester.widget<TextField>(find.byKey(Key(llave))).controller!.text;

Future<void> _guardarDesdeAfuera(
  DelegadoEnMemoria nube,
  String sesion,
  String alumnoId, {
  List<String> acompanantes = const [],
  String musica = '',
}) =>
    nube.guardar(
      clave: nube.clave!,
      sesion: sesion,
      alumnoId: alumnoId,
      acompanantes: acompanantes,
      musica: musica,
    );

void main() {
  group('antes de entrar', () {
    testWidgets('un link que no existe no muestra nada de ninguna fiesta', (
      tester,
    ) async {
      final nube = _nube();
      await nube.conDelegado('Otra Persona');
      await _abrir(tester, nube, clave: 'mal-copiado');
      expect(find.text('Este link no es válido'), findsOneWidget);
      expect(find.textContaining('Escuela Normal'), findsNothing);
      expect(find.textContaining('ÁLVAREZ'), findsNothing);
    });

    testWidgets('dice de qué fiesta es, pregunta si es delegado y pide nombre '
        'y apellido; sin entrar no hay ningún alumno', (tester) async {
      final nube = _nube();
      await nube.crear(
        eventoId: _fiesta,
        fiesta: 'Escuela Normal · Promo 2026',
        venceLocal: '2026-11-19 20:00',
        cupo: 2,
      );
      await _abrir(tester, nube);
      expect(find.text('Escuela Normal · Promo 2026'), findsOneWidget);
      expect(
        find.text('¿Sos delegado de Escuela Normal · Promo 2026?'),
        findsOneWidget,
      );
      expect(
        find.text('Hay tiempo hasta el jueves 19/11 a las 20:00.'),
        findsOneWidget,
      );
      expect(find.textContaining('ÁLVAREZ'), findsNothing);
      // Nadie entró todavía: no hay nombres para tocar.
      expect(find.text('¿Ya entraste? Tocá tu nombre'), findsNothing);

      await _entrar(tester, 'Laura');
      expect(find.text('Escribí tu nombre y tu apellido.'), findsOneWidget);

      await _entrar(tester, 'Laura Gómez');
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect(find.text('ÁLVAREZ, BRUNO'), findsOneWidget);
    });

    testWidgets('con el cupo completo otra persona no entra, pero quien ya '
        'entró toca su nombre desde otro celular y sigue con lo suyo', (
      tester,
    ) async {
      final nube = _nube();
      final primera = await nube.conDelegado('Laura Gómez', cupo: 1);
      await _guardarDesdeAfuera(nube, primera, 'a2', musica: 'Tema de Laura');
      // Otro celular: no tiene ninguna sesión guardada.
      final otroCelular = SesionesEnMemoria();
      await _abrir(tester, nube, sesiones: otroCelular);

      expect(
        find.textContaining('Ya entraron todos los delegados'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_nombre')), findsNothing);
      expect(find.text('¿Ya entraste? Tocá tu nombre'), findsOneWidget);
      expect(find.text('LAURA GÓMEZ'), findsOneWidget);
      expect(find.textContaining('ÁLVAREZ'), findsNothing);

      await _tocar(tester, 'delegado_soy_0');
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect(find.textContaining('Tema de Laura'), findsOneWidget);
      // Lo que cargó en el otro celular es suyo: lo abre sin aviso.
      await _tocar(tester, 'delegado_abrir_a2');
      expect(find.byKey(const Key('delegado_cartel')), findsNothing);
      expect(_escrito(tester, 'delegado_musica'), 'Tema de Laura');

      final sesion = await otroCelular.leer('c1a2b3');
      expect(sesion, isNotNull);
      expect(sesion, isNot(primera), reason: 'cada celular tiene su sesión');
      final e = await nube.estado(_fiesta);
      expect(e.delegados.single.aparatos, 2, reason: 'una persona, dos celulares');
    });

    testWidgets('escribiendo el mismo nombre, sin acentos ni mayúsculas, '
        'también es la misma persona', (tester) async {
      final nube = _nube();
      await nube.conDelegado('Laura Gómez', cupo: 2);
      await _abrir(tester, nube);
      await _entrar(tester, 'laura gomez');
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect((await nube.estado(_fiesta)).delegados, hasLength(1));
    });

    testWidgets('a quien se sacó no lo deja entrar con su nombre, y lo dice', (
      tester,
    ) async {
      final nube = _nube();
      await nube.conDelegado('Laura Gómez', cupo: 2);
      final laura = (await nube.estado(_fiesta)).delegados.single.id;
      await nube.cambiar(_fiesta, 'sacar_dejando', laura);
      await _abrir(tester, nube);
      // Ya no figura entre los nombres para tocar.
      expect(find.text('LAURA GÓMEZ'), findsNothing);
      await _entrar(tester, 'Laura Gómez');
      expect(
        _texto(tester, 'delegado_error_entrada'),
        contains('Con ese nombre ya no se puede entrar'),
      );
      expect(find.textContaining('ÁLVAREZ'), findsNothing);
    });

    testWidgets('apagado o vencido: lo dice y no deja entrar', (tester) async {
      final nube = _nube();
      await nube.crear(
        eventoId: _fiesta,
        fiesta: 'Escuela Normal',
        venceLocal: '2026-11-19 20:00',
        cupo: 2,
      );
      nube.vencido = true;
      await _abrir(tester, nube);
      expect(
        find.text('El plazo para cargar terminó el jueves 19/11 a las 20:00.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_nombre')), findsNothing);

      nube.apagado = true;
      await _abrir(tester, nube);
      expect(find.text('Este link está cerrado'), findsOneWidget);
    });

    testWidgets('sin internet lo dice, y Reintentar abre', (tester) async {
      final nube = _nube();
      await nube.conDelegado('Otra Persona');
      nube.sinRed = true;
      await _abrir(tester, nube);
      expect(find.text('No pudimos conectarnos'), findsOneWidget);
      nube.sinRed = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delegado_nombre')), findsOneWidget);
    });
  });

  group('la lista', () {
    testWidgets('los activos por división, con el avance; el de baja no está',
        (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);

      expect(find.text('6° A'), findsOneWidget);
      expect(find.text('6° B'), findsOneWidget);
      expect(find.textContaining('SOSA'), findsNothing);
      expect(find.text('1 de 4 alumnos cargados'), findsOneWidget);
      expect(
        _texto(tester, 'delegado_plazo'),
        'Tenés hasta el jueves 19/11 a las 20:00 para cargar y corregir.',
      );
    });

    testWidgets('lo ya cargado en el programa se ve, dice "Ya cargado en el '
        'programa" y se puede abrir', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);

      expect(_texto(tester, 'delegado_quien_a1'), 'Ya cargado en el programa');
      expect(find.textContaining('ACOSTA, JORGE'), findsOneWidget);
      expect(find.textContaining('Vivir mi vida'), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a1')), findsOneWidget);
      final nombre = tester.widget<Text>(find.text('ACOSTA, LUCÍA'));
      expect(nombre.style?.decoration, isNull, reason: 'ya no va tachado');
      // Al que le falta algo no le pone el rótulo de cargado.
      expect(find.byKey(const Key('delegado_quien_a3')), findsNothing);
      expect(find.text('Falta'), findsNWidgets(3));
    });

    testWidgets('buscar "gomez" encuentra a GÓMEZ', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await tester.enterText(find.byKey(const Key('delegado_buscar')), 'gomez');
      await tester.pumpAndSettle();
      expect(find.text('GÓMEZ, SOFÍA'), findsOneWidget);
      expect(find.text('ÁLVAREZ, BRUNO'), findsNothing);
    });
  });

  group('un alumno', () {
    testWidgets('dos casilleros de acompañantes, ningún botón para agregar, y '
        'la música con tope de 300', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');

      expect(find.byKey(const Key('delegado_ac1')), findsOneWidget);
      expect(find.byKey(const Key('delegado_ac2')), findsOneWidget);
      expect(find.byKey(const Key('delegado_ac3')), findsNothing);
      expect(find.textContaining('Agregar'), findsNothing);
      final musica =
          tester.widget<TextField>(find.byKey(const Key('delegado_musica')));
      expect(musica.maxLength, kMaxLetrasMusicaDelegado);
      expect(kMaxLetrasMusicaDelegado, 300);
      expect(find.text('0/300'), findsOneWidget);
      final ac =
          tester.widget<TextField>(find.byKey(const Key('delegado_ac1')));
      expect(ac.maxLength, kMaxLetrasAcompananteDelegado);
    });

    testWidgets('el que ya tiene acompañantes en el programa los ve en su '
        'casillero y completa la música', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a3');

      // Le falta la música: no es "corregir lo de otro", abre directo.
      expect(find.byKey(const Key('delegado_cartel')), findsNothing);
      expect(_escrito(tester, 'delegado_ac1'), 'BENÍTEZ, CARLA');
      expect(
        find.textContaining('Un casillero vacío no borra nada'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('delegado_musica')),
        'Tema de Mateo',
      );
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_guardar');
      expect(nube.cargaDe('a3')!.musica, 'Tema de Mateo');
      expect(nube.cargaDe('a3')!.acompanantes, ['BENÍTEZ, CARLA']);
    });

    testWidgets('Guardar guarda ese alumno, dice quién y cuándo, lo marca "Sin '
        'enviar" y no envía', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');
      await tester.enterText(
        find.byKey(const Key('delegado_ac1')),
        'álvarez, eva',
      );
      await tester.enterText(
        find.byKey(const Key('delegado_musica')),
        'Vivir mi vida - Marc Anthony, desde el minuto 0:45',
      );
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_guardar');

      expect(nube.cargaDe('a2')!.acompanantes, ['ÁLVAREZ, EVA']);
      expect(find.text('Sin enviar'), findsOneWidget);
      expect(
        _texto(tester, 'delegado_quien_a2'),
        'Ya cargado · LAURA GÓMEZ · jue 12/11 15:00',
      );
      expect(find.text('2 de 4 alumnos cargados'), findsOneWidget);
      expect(find.byKey(const Key('delegado_gracias')), findsNothing);
      expect(nube.hayAviso, isFalse, reason: 'guardar no le avisa al jefe');
      expect((await nube.estado(_fiesta)).delegados.single.envioTexto, isNull);

      // Cierra la página y vuelve en el mismo celular: sigue adentro.
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect(find.text('Sin enviar'), findsOneWidget);
      expect(find.textContaining('ÁLVAREZ, EVA'), findsOneWidget);
    });

    testWidgets('guardar vacío lo dice y no guarda', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');
      await _tocar(tester, 'delegado_guardar');
      expect(
        find.text('Escribí al menos un acompañante o la música.'),
        findsOneWidget,
      );
      expect(nube.cargaDe('a2'), isNull);
    });

    testWidgets('con cambios sin guardar no deja pasar a otro alumno', (
      tester,
    ) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'Tema');
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_abrir_a4');
      expect(
        find.text('Tenés cambios sin guardar. Tocá Guardar, o Descartar.'),
        findsOneWidget,
      );
      await _tocar(tester, 'delegado_descartar');
      expect(find.byKey(const Key('delegado_guardar')), findsNothing);
      expect(nube.cargaDe('a2'), isNull);
    });

    testWidgets('lo que ya está en el programa: avisa antes de dejar escribir, '
        'y "No, volver" no toca nada', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a1');

      expect(
        find.text('Vas a cambiar lo que ya está cargado en el programa. '
            '¿Seguir?'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_ac1')), findsNothing);
      expect(find.byKey(const Key('delegado_guardar')), findsNothing);
      // Lo que va a cambiar sigue a la vista mientras pregunta.
      expect(find.textContaining('ACOSTA, JORGE'), findsOneWidget);
      expect(find.textContaining('Vivir mi vida'), findsOneWidget);

      await _tocar(tester, 'delegado_no_corregir');
      expect(find.byKey(const Key('delegado_cartel')), findsNothing);
      expect(nube.cargaDe('a1'), isNull);
      // Al abrirlo de nuevo vuelve a avisar.
      await _tocar(tester, 'delegado_abrir_a1');
      expect(find.byKey(const Key('delegado_cartel')), findsOneWidget);
    });

    testWidgets('con "Sí, corregir" se abre con lo que tiene; guardar no cambia '
        'el programa: queda para que el jefe lo acepte', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a1');
      await _tocar(tester, 'delegado_si_corregir');

      expect(_escrito(tester, 'delegado_ac1'), 'ACOSTA, JORGE');
      expect(_escrito(tester, 'delegado_musica'), 'Vivir mi vida');
      await tester.enterText(find.byKey(const Key('delegado_ac2')), 'ríos, marta');
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_guardar');

      expect(nube.cargaDe('a1')!.acompanantes, ['ACOSTA, JORGE', 'RÍOS, MARTA']);
      expect(nube.cargaDe('a1')!.traido, isFalse);
      expect(nube.alumnosDeLaFiesta.first.acompanantes, ['ACOSTA, JORGE'],
          reason: 'el programa no cambió');
      final a1 = (await nube.alumnos(_fiesta)).first;
      expect([a1.estado, a1.otraVez], [EstadoDeLaCarga.sinEnviar, true]);
      expect(
        _texto(tester, 'delegado_quien_a1'),
        'Ya cargado · LAURA GÓMEZ · jue 12/11 15:00',
      );
    });
  });

  group('varios delegados', () {
    testWidgets('lo que cargó otro se ve, con quién lo cargó y cuándo', (
      tester,
    ) async {
      final nube = _nube();
      final laura = await nube.conDelegado('Laura Gómez');
      await _guardarDesdeAfuera(
        nube,
        laura,
        'a2',
        acompanantes: ['ÁLVAREZ, EVA'],
        musica: 'Tema de Laura',
      );
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Pedro Sosa'));
      await _abrir(tester, nube, sesiones: sesiones);

      expect(
        _texto(tester, 'delegado_quien_a2'),
        'Ya cargado · LAURA GÓMEZ · jue 12/11 15:00',
      );
      expect(find.textContaining('Tema de Laura'), findsOneWidget);
      expect(find.textContaining('ÁLVAREZ, EVA'), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a2')), findsOneWidget);
      // Para Pedro no es "sin enviar": eso es de quien lo cargó.
      expect(find.text('Sin enviar'), findsNothing);
    });

    testWidgets('corregir lo de otro: avisa con su nombre y, al guardar, queda '
        'a nombre de quien corrigió, con el historial de los dos', (
      tester,
    ) async {
      final nube = _nube();
      final laura = await nube.conDelegado('Laura Gómez');
      await _guardarDesdeAfuera(nube, laura, 'a2', musica: 'Tema de Laura');
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Pedro Sosa'));
      await _abrir(tester, nube, sesiones: sesiones);

      await _tocar(tester, 'delegado_abrir_a2');
      expect(
        find.text('Vas a cambiar lo que cargó LAURA GÓMEZ. ¿Seguir?'),
        findsOneWidget,
      );
      await _tocar(tester, 'delegado_si_corregir');
      expect(_escrito(tester, 'delegado_musica'), 'Tema de Laura');
      await tester.enterText(
        find.byKey(const Key('delegado_musica')),
        'Tema corregido',
      );
      await tester.pumpAndSettle();
      nube.reloj = 'jue 12/11 16:00';
      await _tocar(tester, 'delegado_guardar');

      expect(nube.cargaDe('a2')!.musica, 'Tema corregido');
      expect((await nube.cargas(_fiesta)).single.cargo, 'PEDRO SOSA');
      expect(
        _texto(tester, 'delegado_quien_a2'),
        'Ya cargado · PEDRO SOSA · jue 12/11 16:00',
      );
      expect(
        [for (final h in await nube.historial(_fiesta)) '${h.quien} ${h.cuandoTexto}'],
        ['LAURA GÓMEZ jue 12/11 15:00', 'PEDRO SOSA jue 12/11 16:00'],
      );
      // Ahora es de Pedro: lo vuelve a abrir sin aviso.
      await _tocar(tester, 'delegado_abrir_a2');
      expect(find.byKey(const Key('delegado_cartel')), findsNothing);
    });

    testWidgets('si otro lo guardó mientras lo tenía abierto, queda lo último '
        'y dice de quién es', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Pedro Sosa'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'De Pedro');
      await tester.pumpAndSettle();
      // Mientras tanto, Laura guarda al mismo alumno.
      final laura = await nube.conDelegado('Laura Gómez');
      await _guardarDesdeAfuera(nube, laura, 'a2', musica: 'De Laura');
      await _tocar(tester, 'delegado_guardar');

      expect(nube.cargaDe('a2')!.musica, 'De Pedro');
      expect(_texto(tester, 'delegado_quien_a2'), startsWith('Ya cargado · PEDRO SOSA'));
      expect(await nube.historial(_fiesta), hasLength(2));
    });
  });

  group('Enviar', () {
    Future<(DelegadoEnMemoria, SesionesEnMemoria)> conUnoGuardado(
      WidgetTester tester,
    ) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      final laura = await nube.conDelegado('Laura Gómez');
      await sesiones.guardar('c1a2b3', laura);
      await _guardarDesdeAfuera(
        nube,
        laura,
        'a2',
        acompanantes: ['ÁLVAREZ, EVA'],
        musica: 'Tema',
      );
      await _abrir(tester, nube, sesiones: sesiones);
      return (nube, sesiones);
    }

    Future<void> enviar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
    }

    testWidgets('Guardar y Enviar no se confunden: uno de contorno en el '
        'alumno, el otro relleno abajo, con su leyenda', (tester) async {
      await conUnoGuardado(tester);
      await _tocar(tester, 'delegado_abrir_a4');
      expect(
        tester.widget(find.byKey(const Key('delegado_guardar'))),
        isA<OutlinedButton>(),
      );
      expect(
        tester.widget(find.byKey(const Key('delegado_enviar'))),
        isA<FilledButton>(),
      );
      expect(
        find.text('Guardar no envía. Cuando termines, tocá Enviar: no cierra '
            'nada, podés seguir corrigiendo.'),
        findsOneWidget,
      );
      final guardar = tester.getCenter(find.byKey(const Key('delegado_guardar')));
      final boton = tester.getCenter(find.byKey(const Key('delegado_enviar')));
      expect(boton.dy, greaterThan(guardar.dy));
    });

    testWidgets('con un alumno abierto y sin guardar, frena y lo dice', (
      tester,
    ) async {
      final (nube, _) = await conUnoGuardado(tester);
      await _tocar(tester, 'delegado_abrir_a4');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'Tema');
      await tester.pumpAndSettle();
      await enviar(tester);
      expect(
        find.text('Tenés cambios sin guardar en GÓMEZ, SOFÍA. Guardalos o '
            'descartalos antes de enviar.'),
        findsOneWidget,
      );
      expect((await nube.estado(_fiesta)).delegados.single.envioTexto, isNull);

      // Al guardar, ese aviso se va: ya no hay nada sin guardar.
      await _tocar(tester, 'delegado_guardar');
      expect(find.textContaining('Tenés cambios sin guardar'), findsNothing);
      expect(nube.cargaDe('a4')!.musica, 'Tema');
    });

    testWidgets('Descartar también saca el aviso de cambios sin guardar', (
      tester,
    ) async {
      await conUnoGuardado(tester);
      await _tocar(tester, 'delegado_abrir_a4');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'Tema');
      await tester.pumpAndSettle();
      await enviar(tester);
      expect(find.textContaining('Tenés cambios sin guardar'), findsOneWidget);
      await _tocar(tester, 'delegado_descartar');
      expect(find.textContaining('Tenés cambios sin guardar'), findsNothing);
    });

    testWidgets('sin haber guardado a nadie no hay nada que enviar', (
      tester,
    ) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await enviar(tester);
      expect(find.text('Todavía no guardaste ningún alumno.'), findsOneWidget);
      expect(nube.hayAviso, isFalse);
    });

    testWidgets('Enviar avisa sin preguntar, agradece con la hora, y todo se '
        'sigue pudiendo abrir y enviar de nuevo', (tester) async {
      final (nube, sesiones) = await conUnoGuardado(tester);
      expect(find.text('Enviar'), findsOneWidget);
      await enviar(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect((await nube.estado(_fiesta)).delegados.single.envioTexto, 'jue 12/11 15:00');
      expect(nube.hayAviso, isTrue, reason: 'enviar sí le avisa al jefe');
      expect(find.byKey(const Key('delegado_gracias')), findsOneWidget);
      expect(
        find.text('¡Gracias! Recibimos tu parte el jue 12/11 15:00.'),
        findsOneWidget,
      );
      expect(
        find.text('Si corregís algo, tocá Enviar otra vez para avisarnos.'),
        findsOneWidget,
      );
      // Nada quedó cerrado.
      expect(find.text('Enviar otra vez'), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a2')), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a4')), findsOneWidget);
      expect(find.text('Sin enviar'), findsNothing);
      expect(
        _texto(tester, 'delegado_plazo'),
        'Tenés hasta el jueves 19/11 a las 20:00 para cargar y corregir.',
      );

      // Vuelve a abrir: sigue diciendo que se recibió, y sigue abierto.
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.byKey(const Key('delegado_gracias')), findsOneWidget);
      expect(find.byKey(const Key('delegado_enviar')), findsOneWidget);
    });

    testWidgets('enviar otra vez sin nada nuevo: lo dice y no avisa de nuevo', (
      tester,
    ) async {
      final (nube, _) = await conUnoGuardado(tester);
      await enviar(tester);
      nube.hayAviso = false; // el jefe ya lo trajo
      await enviar(tester);
      expect(find.text('No tenés nada nuevo para enviar.'), findsOneWidget);
      expect(nube.hayAviso, isFalse);
    });

    testWidgets('corregir después de enviar: dice que quedó sin enviar, y '
        'Enviar otra vez avisa de nuevo', (tester) async {
      final (nube, _) = await conUnoGuardado(tester);
      await enviar(tester);
      nube.hayAviso = false;

      await _tocar(tester, 'delegado_abrir_a2');
      expect(find.byKey(const Key('delegado_cartel')), findsNothing,
          reason: 'es suyo: no avisa');
      await tester.enterText(
        find.byKey(const Key('delegado_musica')),
        'Tema corregido',
      );
      await tester.pumpAndSettle();
      nube.reloj = 'jue 12/11 16:00';
      await _tocar(tester, 'delegado_guardar');

      expect(find.text('Sin enviar'), findsOneWidget);
      expect(
        find.text('Después corregiste 1 alumno: tocá Enviar otra vez para '
            'avisarnos.'),
        findsOneWidget,
      );
      expect(nube.hayAviso, isFalse, reason: 'guardar no avisa');
      expect((await nube.estado(_fiesta)).sinEnviar, 1);

      await enviar(tester);
      expect(nube.hayAviso, isTrue);
      expect((await nube.estado(_fiesta)).sinEnviar, 0);
      expect(
        find.text('¡Gracias! Recibimos tu parte el jue 12/11 16:00.'),
        findsOneWidget,
      );
      expect(find.text('Sin enviar'), findsNothing);
    });

    testWidgets('después de enviar, el agradecimiento queda a la vista aunque '
        'estuviera mirando el final de la lista', (tester) async {
      await conUnoGuardado(tester);
      // Un celular bajito, con la lista corrida hasta abajo.
      tester.view.physicalSize = const Size(390, 520);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Hola, LAURA GÓMEZ.').hitTestable(), findsNothing);
      await enviar(tester);
      expect(find.byKey(const Key('delegado_gracias')).hitTestable(), findsOneWidget);
      // Entero y desde arriba: se ve hasta el saludo.
      expect(find.text('Hola, LAURA GÓMEZ.').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('delegado_gracias'))).dy,
        greaterThan(40),
      );
    });

    testWidgets('si el plazo terminó estando adentro, lo dice y no hay Enviar '
        'ni se abre ningún alumno', (tester) async {
      final (nube, sesiones) = await conUnoGuardado(tester);
      nube.vencido = true;
      await _abrir(tester, nube, sesiones: sesiones);
      expect(
        _texto(tester, 'delegado_plazo'),
        'El plazo terminó el jueves 19/11 a las 20:00. Ya no se puede cargar '
        'ni corregir.',
      );
      expect(find.byKey(const Key('delegado_enviar')), findsNothing);
      expect(find.byKey(const Key('delegado_abrir_a4')), findsNothing);
      // Pero lo cargado se sigue viendo.
      expect(find.textContaining('ÁLVAREZ, EVA'), findsOneWidget);
    });

    testWidgets('el jefe reabre con otra fecha: quien ya había enviado vuelve a '
        'cargar y a enviar', (tester) async {
      final (nube, sesiones) = await conUnoGuardado(tester);
      await enviar(tester);
      nube.vencido = true;
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.byKey(const Key('delegado_enviar')), findsNothing);

      await nube.cambiar(_fiesta, 'vence', '2026-11-25 21:00');
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.byKey(const Key('delegado_enviar')), findsOneWidget);
      await _tocar(tester, 'delegado_abrir_a4');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'Nuevo');
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_guardar');
      expect(nube.cargaDe('a4')!.musica, 'Nuevo');
    });
  });
}
