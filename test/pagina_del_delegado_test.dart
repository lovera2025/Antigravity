// La página del link del delegado (6.8.0), entera, con una nube en memoria.
// Lo que se prueba acá es lo que hace la pantalla con lo que contesta la nube;
// las reglas se prueban contra el SQL (`tool/delegado_sandbox/pruebas.mjs`).
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
  tester.view.physicalSize = const Size(390, 1400);
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

      await _entrar(tester, 'Laura');
      expect(find.text('Escribí tu nombre y tu apellido.'), findsOneWidget);

      await _entrar(tester, 'Laura Gómez');
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect(find.text('ÁLVAREZ, BRUNO'), findsOneWidget);
    });

    testWidgets('con el cupo completo, otro celular no entra', (tester) async {
      final nube = _nube();
      await nube.conDelegado('Laura Gómez', cupo: 1);
      await _abrir(tester, nube);
      expect(
        find.textContaining('Ya entraron todos los delegados'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_nombre')), findsNothing);
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
        find.text('Tenés hasta el jueves 19/11 a las 20:00.'),
        findsOneWidget,
      );
    });

    testWidgets('lo ya cargado en el programa va tachado, dice "Ya cargado" y '
        'no se puede abrir', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);

      expect(find.text('Ya cargado'), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a1')), findsNothing);
      final nombre = tester.widget<Text>(find.text('ACOSTA, LUCÍA'));
      expect(nombre.style?.decoration, TextDecoration.lineThrough);
      // Y no muestra lo que tiene cargado.
      expect(find.textContaining('ACOSTA, JORGE'), findsNothing);
      await tester.tap(find.text('ACOSTA, LUCÍA'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delegado_guardar')), findsNothing);
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

    testWidgets('el que ya tiene acompañantes en el programa solo completa la '
        'música', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Laura Gómez'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a3');

      expect(find.text('Ya están cargados en el programa.'), findsOneWidget);
      expect(find.byKey(const Key('delegado_ac1')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('delegado_musica')),
        'Tema de Mateo',
      );
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_guardar');
      expect(nube.cargaDe('a3')!.musica, 'Tema de Mateo');
      expect(nube.cargaDe('a3')!.acompanantes, isEmpty);
    });

    testWidgets('Guardar guarda ese alumno, lo marca "Guardado" y no envía', (
      tester,
    ) async {
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
      expect(find.text('Guardado'), findsOneWidget);
      expect(find.text('2 de 4 alumnos cargados'), findsOneWidget);
      expect(find.byKey(const Key('delegado_gracias')), findsNothing);
      expect(nube.hayAviso, isFalse, reason: 'guardar no le avisa al jefe');
      expect((await nube.estado(_fiesta)).celulares.single.entregado, isFalse);

      // Cierra la página y vuelve en el mismo celular: sigue adentro.
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.text('Hola, LAURA GÓMEZ.'), findsOneWidget);
      expect(find.text('Guardado'), findsOneWidget);
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
  });

  group('varios delegados', () {
    testWidgets('lo que cargó otro se ve cerrado, con su nombre y sin lo que '
        'escribió', (tester) async {
      final nube = _nube();
      final laura = await nube.conDelegado('Laura Gómez');
      await nube.guardar(
        clave: nube.clave!,
        sesion: laura,
        alumnoId: 'a2',
        acompanantes: ['ÁLVAREZ, EVA'],
        musica: 'Tema secreto',
      );
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Pedro Sosa'));
      await _abrir(tester, nube, sesiones: sesiones);

      expect(find.text('Lo cargó LAURA GÓMEZ'), findsOneWidget);
      expect(find.byKey(const Key('delegado_abrir_a2')), findsNothing);
      expect(find.textContaining('Tema secreto'), findsNothing);
      expect(find.textContaining('ÁLVAREZ, EVA'), findsNothing);
    });

    testWidgets('si otro lo cargó mientras lo tenía abierto, se lo dice y lo '
        'de aquel queda', (tester) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      await sesiones.guardar('c1a2b3', await nube.conDelegado('Pedro Sosa'));
      await _abrir(tester, nube, sesiones: sesiones);
      await _tocar(tester, 'delegado_abrir_a2');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'De Pedro');
      await tester.pumpAndSettle();
      // Mientras tanto, Laura guarda al mismo alumno.
      final laura = await nube.conDelegado('Laura Gómez');
      await nube.guardar(
        clave: nube.clave!,
        sesion: laura,
        alumnoId: 'a2',
        acompanantes: [],
        musica: 'De Laura',
      );
      await _tocar(tester, 'delegado_guardar');
      expect(
        find.text('A ese alumno ya lo cargó LAURA GÓMEZ.'),
        findsOneWidget,
      );
      expect(nube.cargaDe('a2')!.musica, 'De Laura');
      expect(find.text('Lo cargó LAURA GÓMEZ'), findsOneWidget);
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
      await nube.guardar(
        clave: nube.clave!,
        sesion: laura,
        alumnoId: 'a2',
        acompanantes: ['ÁLVAREZ, EVA'],
        musica: 'Tema',
      );
      await _abrir(tester, nube, sesiones: sesiones);
      return (nube, sesiones);
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
        find.text('Guardar no envía. Cuando termines, tocá Enviar.'),
        findsOneWidget,
      );
      final guardar = tester.getCenter(find.byKey(const Key('delegado_guardar')));
      final enviar = tester.getCenter(find.byKey(const Key('delegado_enviar')));
      expect(enviar.dy, greaterThan(guardar.dy));
    });

    testWidgets('con un alumno abierto y sin guardar, frena y lo dice', (
      tester,
    ) async {
      final (nube, _) = await conUnoGuardado(tester);
      await _tocar(tester, 'delegado_abrir_a4');
      await tester.enterText(find.byKey(const Key('delegado_musica')), 'Tema');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
      expect(
        find.text('Tenés cambios sin guardar en GÓMEZ, SOFÍA. Guardalos o '
            'descartalos antes de enviar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_confirmar')), findsNothing);
      expect((await nube.estado(_fiesta)).celulares.single.entregado, isFalse);

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
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
      expect(find.text('Todavía no guardaste ningún alumno.'), findsOneWidget);
      expect(find.byKey(const Key('delegado_confirmar')), findsNothing);
    });

    testWidgets('el aviso dice el número justo de los que faltan; sin tildar '
        'no confirma; "Seguir revisando" no envía', (tester) async {
      final (nube, _) = await conUnoGuardado(tester);
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Antes de enviar, una última revisión'), findsOneWidget);
      expect(
        find.textContaining('El envío se hace una sola vez'),
        findsOneWidget,
      );
      // De 4: uno ya estaba en el programa, uno lo guardó Laura. Faltan 2.
      expect(
        find.text('Todavía hay 2 alumnos de la fiesta sin completar. Si les '
            'tocan a otro delegado, podés enviar igual.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('delegado_confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('Tildá la casilla para confirmar.'), findsOneWidget);
      expect((await nube.estado(_fiesta)).celulares.single.entregado, isFalse);

      await tester.tap(find.byKey(const Key('delegado_seguir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delegado_confirmar')), findsNothing);
      expect((await nube.estado(_fiesta)).celulares.single.entregado, isFalse);
      expect(nube.cargaDe('a2')!.musica, 'Tema');
    });

    testWidgets('con todo completo el aviso no dice que falte nadie', (
      tester,
    ) async {
      final nube = _nube();
      final sesiones = SesionesEnMemoria();
      final laura = await nube.conDelegado('Laura Gómez');
      await sesiones.guardar('c1a2b3', laura);
      for (final id in ['a2', 'a3', 'a4']) {
        await nube.guardar(
          clave: nube.clave!,
          sesion: laura,
          alumnoId: id,
          acompanantes: [],
          musica: 'Tema',
        );
      }
      await _abrir(tester, nube, sesiones: sesiones);
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delegado_faltan')), findsNothing);
    });

    testWidgets('tildar y confirmar envía: agradece, y ya no se puede tocar '
        'nada ni volver a enviar', (tester) async {
      final (nube, sesiones) = await conUnoGuardado(tester);
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delegado_soy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delegado_confirmar')));
      await tester.pumpAndSettle();

      expect((await nube.estado(_fiesta)).celulares.single.entregado, isTrue);
      expect(nube.hayAviso, isTrue, reason: 'enviar sí le avisa al jefe');
      expect(find.text('¡Listo, muchas gracias!'), findsOneWidget);
      expect(
        find.text('Enviaste 1 alumno. Ya no se puede cambiar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_enviar')), findsNothing);
      expect(find.byKey(const Key('delegado_abrir_a2')), findsNothing);
      expect(find.byKey(const Key('delegado_abrir_a4')), findsNothing);

      // Vuelve a abrir: sigue el agradecimiento.
      await _abrir(tester, nube, sesiones: sesiones);
      expect(find.byKey(const Key('delegado_gracias')), findsOneWidget);
      expect(find.byKey(const Key('delegado_enviar')), findsNothing);
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
      await tester.tap(find.byKey(const Key('delegado_enviar')));
      await tester.pumpAndSettle();
      await _tocar(tester, 'delegado_soy');
      await _tocar(tester, 'delegado_confirmar');
      expect(find.text('¡Listo, muchas gracias!').hitTestable(), findsOneWidget);
      // Entero y desde arriba: se ve hasta el saludo.
      expect(find.text('Hola, LAURA GÓMEZ.').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('delegado_gracias'))).dy,
        greaterThan(40),
      );
    });

    testWidgets('si el plazo terminó estando adentro, lo dice y no hay Enviar',
        (tester) async {
      final (nube, sesiones) = await conUnoGuardado(tester);
      nube.vencido = true;
      await _abrir(tester, nube, sesiones: sesiones);
      expect(
        find.text('El plazo terminó el jueves 19/11 a las 20:00. Ya no se '
            'puede cargar ni enviar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_enviar')), findsNothing);
      expect(find.byKey(const Key('delegado_abrir_a4')), findsNothing);
    });
  });
}
