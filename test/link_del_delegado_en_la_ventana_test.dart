// El link del delegado en PLANILLAS → "Acompañantes y música" (6.8.0): la
// sección del link, TRAER LO CARGADO y ACEPTAR Y CARGAR. Lo que mandan los
// delegados entra a la grilla solo cuando el jefe acepta, y por el mismo camino
// que el Excel.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/features/eventos/widgets/link_del_delegado_panel.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

import 'helpers/delegado_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
String _id(String principio) => '${principio.padRight(8, '0')}-0000-4000-8000-000000000000';

final _lucia = _id('a1');
final _bruno = _id('a2');
final _mateo = _id('a3');
final _sofia = _id('a4');
final _dylan = _id('a5');

ContratoAlumno _alumno(
  String id,
  String nombre, {
  List<String> acomp = const [],
  String? musica,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _fiesta,
      nombreAlumno: nombre,
      cantidadAcompanantes: acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: '6° A',
      musicaElegida: musica,
    );

/// La grilla de esta PC.
List<ContratoAlumno> _grilla() => [
      _alumno(_lucia, 'ACOSTA, LUCÍA', acomp: ['ACOSTA, JORGE'], musica: 'Vivir mi vida'),
      _alumno(_bruno, 'ÁLVAREZ, BRUNO'),
      _alumno(_mateo, 'BENÍTEZ, MATEO', acomp: ['BENÍTEZ, CARLA']),
      _alumno(_sofia, 'GÓMEZ, SOFÍA'),
      _alumno(_dylan, '[BAJA] SOSA, DYLAN'),
    ];

/// La misma fiesta, del lado de la nube.
DelegadoEnMemoria _nube() => DelegadoEnMemoria(
      eventoId: _fiesta,
      alumnos: [
        AlumnoDeMentira(_lucia, 'ACOSTA, LUCÍA', '6° A', acompanantes: ['ACOSTA, JORGE'], musica: 'Vivir mi vida'),
        AlumnoDeMentira(_bruno, 'ÁLVAREZ, BRUNO', '6° A'),
        AlumnoDeMentira(_mateo, 'BENÍTEZ, MATEO', '6° A', acompanantes: ['BENÍTEZ, CARLA']),
        AlumnoDeMentira(_sofia, 'GÓMEZ, SOFÍA', '6° A'),
        AlumnoDeMentira(_dylan, '[BAJA] SOSA, DYLAN', '6° A', activo: false),
      ],
    );

class _Mundo {
  final importados = <List<CambioDelegado>>[];
  int avisosRefrescados = 0;

  /// Lo que pasa justo después de guardar en la grilla.
  void Function()? alImportar;
}

Future<_Mundo> _abrir(
  WidgetTester tester,
  DelegadoEnMemoria nube, {
  bool traerAlAbrir = false,
  LimiteElegido? limite,
}) async {
  final mundo = _Mundo();
  tester.view.physicalSize = const Size(1366, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AcompanantesMusicaDialog(
          eventoId: _fiesta,
          institucion: 'NORMAL MARIANO ILOZA',
          alumnos: _grilla(),
          onGuardarArchivo: (_, _) async => true,
          onElegirArchivo: () async => null as Uint8List?,
          onImportar: (cambios) async {
            mundo.importados.add(cambios);
            mundo.alImportar?.call();
            return null;
          },
          link: nube,
          urlDelLink: (clave) => 'https://ejemplo/?delegado&clave=$clave',
          traerAlAbrir: traerAlAbrir,
          onTrajo: () => mundo.avisosRefrescados++,
          elegirLimite: (_, _) async =>
              limite ??
              (dia: DateTime(2026, 11, 19), hora: const TimeOfDay(hour: 20, minute: 0)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return mundo;
}

Future<void> _tocar(WidgetTester tester, String llave) async {
  final f = find.byKey(Key(llave));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Laura carga a Bruno y envía; Pedro carga a Sofía y no envía.
Future<void> _cargaron(DelegadoEnMemoria nube) async {
  final laura = await nube.conDelegado('Laura Gómez');
  await nube.guardar(
    clave: nube.clave!,
    sesion: laura,
    alumnoId: _bruno,
    acompanantes: ['ÁLVAREZ, EVA', 'DE LA CRUZ Y SOSA / PAZ, ANA'],
    musica: 'Vivir mi vida - Marc Anthony',
  );
  await nube.entregar(nube.clave!, laura);
  final pedro = await nube.conDelegado('Pedro Sosa');
  await nube.guardar(
    clave: nube.clave!,
    sesion: pedro,
    alumnoId: _sofia,
    acompanantes: [],
    musica: 'Persiana americana',
  );
}

void main() {
  group('la sección del link', () {
    testWidgets('sin link: se elige el límite y cuántos, y CREAR LINK lo crea '
        'con el nombre de la fiesta', (tester) async {
      final nube = _nube();
      await _abrir(tester, nube);
      expect(find.text('LINK PARA LOS DELEGADOS'), findsOneWidget);
      // El Excel sigue ahí.
      expect(find.byKey(const Key('delegado_exportar')), findsOneWidget);
      expect(find.byKey(const Key('delegado_importar')), findsOneWidget);

      await _tocar(tester, 'link_elegir_limite');
      expect(find.text('Hasta el 19/11 a las 20:00'), findsOneWidget);
      await _tocar(tester, 'link_crear');

      expect(nube.pedidos, ['crear|NORMAL MARIANO ILOZA|2026-11-19 20:00|1']);
      expect(
        find.text('https://ejemplo/?delegado&clave=c1a2b3'),
        findsOneWidget,
      );
      expect(find.text('Abierto'), findsOneWidget);
      expect(find.byKey(const Key('link_crear')), findsNothing);
      // Nadie cargó nada: no hay qué traer.
      final traer = tester.widget<ElevatedButton>(find.byKey(const Key('link_traer')));
      expect(traer.onPressed, isNull);
    });

    testWidgets('un límite que ya pasó: lo dice y no crea', (tester) async {
      final nube = _nube();
      await _abrir(
        tester,
        nube,
        limite: (dia: DateTime(2026, 11, 1), hora: const TimeOfDay(hour: 9, minute: 5)),
      );
      await _tocar(tester, 'link_elegir_limite');
      expect(find.text('Hasta el 01/11 a las 09:05'), findsOneWidget);
      await _tocar(tester, 'link_crear');
      expect(
        find.text('El día y la hora límite tienen que ser futuros.'),
        findsOneWidget,
      );
      expect(nube.clave, isNull);
    });

    testWidgets('con link: quién entró, cuánto cargó y si envió; apagar, '
        'reabrirle y sacar', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      await _abrir(tester, nube);

      expect(find.textContaining('LAURA GÓMEZ · entró el'), findsOneWidget);
      expect(find.textContaining('cargó 1 · envió el'), findsOneWidget);
      expect(find.textContaining('PEDRO SOSA · entró el'), findsOneWidget);
      expect(find.textContaining('todavía no envió'), findsOneWidget);
      expect(
        find.text('De 4 alumnos: 1 ya estaban en el programa · 2 cargaron los '
            'delegados · faltan 1'),
        findsOneWidget,
      );

      await _tocar(tester, 'link_apagar');
      expect(find.text('Apagado'), findsOneWidget);
      await _tocar(tester, 'link_apagar');
      expect(find.text('Abierto'), findsOneWidget);

      await _tocar(tester, 'link_reabrir_celular-1');
      await _tocar(tester, 'link_cambiar_limite');
      await _tocar(tester, 'link_sacar_celular-2');
      expect(find.text('Sacar a PEDRO SOSA'), findsOneWidget);
      await tester.tap(find.byKey(const Key('link_sacar_dejando')));
      await tester.pumpAndSettle();

      expect(nube.pedidos, [
        'apagar|',
        'prender|',
        'reabrir|celular-1',
        'vence|2026-11-19 20:00',
        'sacar_dejando|celular-2',
      ]);
      expect(find.textContaining('PEDRO SOSA (sacado)'), findsOneWidget);
    });

    testWidgets('sin internet lo dice, y el Excel sigue andando', (tester) async {
      final nube = _nube()..sinRed = true;
      await _abrir(tester, nube);
      expect(find.byKey(const Key('link_sin_internet')), findsOneWidget);
      final exportar = tester.widget<ElevatedButton>(
        find.byKey(const Key('delegado_exportar')),
      );
      expect(exportar.onPressed, isNotNull);
      nube.sinRed = false;
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('link_crear')), findsOneWidget);
    });
  });

  group('traer y aceptar', () {
    testWidgets('TRAER muestra lo enviado, quién lo cargó, y no guarda nada; '
        'ACEPTAR Y CARGAR guarda eso y le avisa a la nube', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);
      await _tocar(tester, 'link_traer');

      expect(find.text('Antes de guardar'), findsOneWidget);
      expect(mundo.importados, isEmpty);
      expect(nube.pedidos, isEmpty);
      expect(
        find.textContaining('ÁLVAREZ, BRUNO · ÁLVAREZ, EVA'),
        findsOneWidget,
      );
      expect(find.textContaining('lo cargó LAURA GÓMEZ'), findsOneWidget);
      // Lo de Pedro, que no envió, no está en la lista: va aparte.
      expect(find.textContaining('GÓMEZ, SOFÍA ·'), findsNothing);
      expect(
        find.text('Incluir también lo que todavía no enviaron (1 alumno(s))'),
        findsOneWidget,
      );
      // En el link la coma es parte del nombre: no hay aviso.
      expect(find.textContaining('con coma'), findsNothing);
      expect(find.textContaining('traen una coma'), findsNothing);
      expect(find.text('ACEPTAR Y CARGAR 1 ALUMNO(S)'), findsOneWidget);

      await _tocar(tester, 'delegado_confirmar');

      expect(mundo.importados, hasLength(1));
      final cambio = mundo.importados.single.single;
      expect(cambio.alumno.id, _bruno);
      // Un apellido con " y " o con una barra no se parte.
      expect(cambio.acompanantes, ['ÁLVAREZ, EVA', 'DE LA CRUZ Y SOSA / PAZ, ANA']);
      expect(cambio.musica, 'Vivir mi vida - Marc Anthony');
      expect(cambio.datos.keys.toSet(), {
        'nombres_acompanantes',
        'cantidad_acompanantes',
        'musica_elegida',
      });
      expect(nube.pedidos, ['traido|["$_bruno"]']);
      expect(nube.cargaDe(_bruno)!.traido, isTrue);
      expect(nube.cargaDe(_sofia)!.traido, isFalse);
      expect(nube.hayAviso, isFalse);
      expect(mundo.avisosRefrescados, 1);
      expect(find.textContaining('Se cargaron 1 alumno(s)'), findsOneWidget);
    });

    testWidgets('VOLVER sin aceptar no cambia nada', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);
      await _tocar(tester, 'link_traer');
      await _tocar(tester, 'delegado_volver');
      expect(mundo.importados, isEmpty);
      expect(nube.pedidos, isEmpty);
      expect(nube.hayAviso, isTrue);
      expect(find.text('LINK PARA LOS DELEGADOS'), findsOneWidget);
    });

    testWidgets('lo que no enviaron entra solo si se tilda', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);
      await _tocar(tester, 'link_traer');
      await _tocar(tester, 'delegado_incluir_sin_enviar');
      expect(find.text('ACEPTAR Y CARGAR 2 ALUMNO(S)'), findsOneWidget);
      expect(find.textContaining('lo cargó PEDRO SOSA'), findsOneWidget);
      await _tocar(tester, 'delegado_confirmar');
      expect(
        [for (final c in mundo.importados.single) c.alumno.id]..sort(),
        [_bruno, _sofia]..sort(),
      );
      expect(nube.pedidos, ['traido|["$_bruno","$_sofia"]']);
    });

    testWidgets('llegando desde la alerta abre directo en la revisión', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube, traerAlAbrir: true);
      expect(find.text('Antes de guardar'), findsOneWidget);
      expect(find.text('ACEPTAR Y CARGAR 1 ALUMNO(S)'), findsOneWidget);
    });

    testWidgets('si no se le puede avisar a la nube que se trajo, lo cargado '
        'queda cargado y se dice', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      final mundo = await _abrir(tester, nube);
      mundo.alImportar = () => nube.sinRed = true;
      await _tocar(tester, 'link_traer');
      await _tocar(tester, 'delegado_confirmar');
      expect(mundo.importados, hasLength(1));
      expect(
        find.textContaining('No se le pudo avisar a la nube que ya se trajo'),
        findsOneWidget,
      );
    });
  });

  group('la revisión de lo del link', () {
    ResultadoPlanilla revisar(List<CargaDelDelegado> cargas) =>
        PlanillaDelegado.comparar(
          lectura: lecturaDeLasCargas(
            eventoId: _fiesta,
            fiesta: 'NORMAL',
            cargas: cargas,
          ),
          alumnos: _grilla(),
          eventoId: _fiesta,
          institucion: 'NORMAL',
        );
    CargaDelDelegado carga(
      String id, {
      List<String> acomp = const [],
      String musica = '',
      String alumno = 'CUALQUIERA',
    }) =>
        CargaDelDelegado(
          alumnoId: id,
          alumno: alumno,
          division: '6° A',
          activo: true,
          acompanantes: acomp,
          musica: musica,
          cargo: 'LAURA GÓMEZ',
          entregado: true,
        );

    test('el alumno se toma por su id, no por el nombre que viene de la nube', () {
      final r = revisar([carga(_bruno, musica: 'Tema', alumno: 'OTRO NOMBRE')]);
      expect(r.cambios.single.alumno.id, _bruno);
      expect(r.revisar, isEmpty);
    });

    test('un casillero vacío no borra: del que ya tiene acompañantes entra '
        'solo la música', () {
      final r = revisar([carga(_mateo, musica: 'Tema de Mateo')]);
      final c = r.cambios.single;
      expect(c.acompanantes, isNull);
      expect(c.musica, 'Tema de Mateo');
      expect(c.datos, {'musica_elegida': 'Tema de Mateo'});
      expect(c.pisaAlgo, isFalse);
    });

    test('si mientras tanto en el programa le cargaron otra cosa, se marca '
        'que se reemplaza', () {
      final r = revisar([carga(_lucia, musica: 'Otra música')]);
      expect(r.cambios.single.pisaAlgo, isTrue);
      expect(r.cambios.single.tenia, 'Música: Vivir mi vida');
    });

    test('lo que ya está igual no se vuelve a cargar', () {
      final r = revisar([
        carga(_lucia, acomp: ['ACOSTA, JORGE'], musica: 'Vivir mi vida'),
      ]);
      expect(r.cambios, isEmpty);
      expect(r.iguales, 1);
    });

    test('un alumno dado de baja, o que ya no está en la fiesta, no se carga', () {
      final r = revisar([
        carga(_dylan, musica: 'Tema'),
        carga(_id('ff'), musica: 'Tema', alumno: 'FANTASMA, ANA'),
      ]);
      expect(r.cambios, isEmpty);
      expect(r.rechazo, isNull);
      expect(
        [for (final x in r.revisar) '$x'],
        [
          'SOSA, DYLAN: está dado de baja. No se carga.',
          'FANTASMA, ANA: ya no está en esta fiesta. No se carga.',
        ],
      );
    });

    test('la música entra en un solo renglón, como la del Excel', () {
      final r = revisar([carga(_bruno, musica: 'Tema  uno\n  desde 0:45 ')]);
      expect(r.cambios.single.musica, 'Tema uno desde 0:45');
    });

    test('el Excel sigue avisando la coma; el link, no', () {
      final delLink = revisar([carga(_bruno, acomp: ['ÁLVAREZ, EVA'])]);
      expect(delLink.cambios.single.conComa, isFalse);
      final delExcel = CambioDelegado(
        alumno: _grilla()[1],
        acompanantes: const ['ÁLVAREZ, EVA'],
        musica: null,
      );
      expect(delExcel.conComa, isTrue);
    });
  });
}
