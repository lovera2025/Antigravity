// La ventana "Link para los delegados" (6.9.2), entera, con una nube en
// memoria: el estado en grande, reabrir con otra fecha, los delegados por
// persona, los alumnos con quién los cargó y cuándo, el historial, y TRAER LO
// CARGADO → ACEPTAR Y CARGAR. Lo que mandan los delegados entra a la grilla
// solo cuando el jefe acepta, y por el mismo camino que el Excel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/features/eventos/widgets/link_del_delegado_ventana.dart';
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

  /// El límite que "elige" el jefe en los selectores.
  LimiteElegido limite =
      (dia: DateTime(2026, 11, 19), hora: const TimeOfDay(hour: 20, minute: 0));
}

/// Abre la ventana del link como la abre la fiesta: TRAER LO CARGADO abre el
/// "Antes de guardar" de siempre, encima.
Future<_Mundo> _abrir(WidgetTester tester, DelegadoEnMemoria nube) async {
  final mundo = _Mundo();
  tester.view.physicalSize = const Size(1366, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LinkDelDelegadoVentana(
                  link: nube,
                  eventoId: _fiesta,
                  fiesta: 'NORMAL MARIANO ILOZA',
                  urlDelLink: (clave) => 'https://ejemplo/?delegado&clave=$clave',
                  elegirLimite: (_, _) async => mundo.limite,
                  onTraer: () => showDialog<bool>(
                    context: context,
                    builder: (_) => AcompanantesMusicaDialog(
                      eventoId: _fiesta,
                      institucion: 'NORMAL MARIANO ILOZA',
                      alumnos: _grilla(),
                      onGuardarArchivo: (_, _) async => true,
                      onElegirArchivo: () async => null as Uint8List?,
                      onImportar: (cambios) async {
                        mundo.importados.add(cambios);
                        // Lo aceptado queda en el programa, como en la app.
                        for (final c in cambios) {
                          final a = nube.alumnosDeLaFiesta
                              .firstWhere((x) => x.id == c.alumno.id);
                          if (c.acompanantes != null) a.acompanantes = c.acompanantes!;
                          if (c.musica != null) a.musica = c.musica!;
                        }
                        mundo.alImportar?.call();
                        return null;
                      },
                      link: nube,
                      traerAlAbrir: true,
                      onTrajo: () => mundo.avisosRefrescados++,
                    ),
                  ),
                ),
              ),
              child: const Text('abrir la ventana'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir la ventana'));
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

String _texto(WidgetTester tester, String llave) =>
    tester.widget<Text>(find.byKey(Key(llave))).data!;

/// El texto del recuadro con esa llave (el chip de estado de un alumno).
String _chip(WidgetTester tester, String llave) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(llave)), matching: find.byType(Text)),
    )
    .data!;

/// Laura carga a Bruno y envía; una hora después Pedro carga a Sofía y no
/// envía.
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
  nube.reloj = 'jue 12/11 16:00';
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
  group('sin link', () {
    testWidgets('se elige el límite y cuántos, y CREAR LINK lo crea con el '
        'nombre de la fiesta', (tester) async {
      final nube = _nube();
      await _abrir(tester, nube);
      expect(find.text('Link para los delegados'), findsOneWidget);
      expect(find.text('NORMAL MARIANO ILOZA'), findsOneWidget);
      expect(find.textContaining('todavía no tiene link'), findsOneWidget);

      await _tocar(tester, 'link_elegir_limite');
      expect(find.text('Hasta el 19/11 a las 20:00'), findsOneWidget);
      await _tocar(tester, 'link_crear');

      expect(nube.pedidos, ['crear|NORMAL MARIANO ILOZA|2026-11-19 20:00|1']);
      expect(_texto(tester, 'link_estado'), 'ABIERTO hasta el jueves 19/11 a las 20:00');
      expect(find.text('https://ejemplo/?delegado&clave=c1a2b3'), findsOneWidget);
      expect(find.byKey(const Key('link_crear')), findsNothing);
      expect(find.byKey(const Key('link_sin_delegados')), findsOneWidget);
      // Nadie cargó nada: no hay qué traer.
      final traer = tester.widget<ElevatedButton>(find.byKey(const Key('link_traer')));
      expect(traer.onPressed, isNull);
    });

    testWidgets('un límite que ya pasó: lo dice y no crea', (tester) async {
      final nube = _nube();
      final mundo = await _abrir(tester, nube);
      mundo.limite =
          (dia: DateTime(2026, 11, 1), hora: const TimeOfDay(hour: 9, minute: 5));
      await _tocar(tester, 'link_elegir_limite');
      expect(find.text('Hasta el 01/11 a las 09:05'), findsOneWidget);
      await _tocar(tester, 'link_crear');
      expect(
        _texto(tester, 'link_dicho'),
        'El día y la hora límite tienen que ser futuros.',
      );
      expect(nube.clave, isNull);
    });

    testWidgets('sin internet lo dice, y REINTENTAR abre', (tester) async {
      final nube = _nube()..sinRed = true;
      await _abrir(tester, nube);
      expect(find.byKey(const Key('link_sin_red')), findsOneWidget);
      nube.sinRed = false;
      await _tocar(tester, 'link_reintentar');
      expect(find.byKey(const Key('link_crear')), findsOneWidget);
    });
  });

  group('arriba: el estado', () {
    testWidgets('abierto: lo dice en grande, con la cuenta de cada estado', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube);
      expect(_texto(tester, 'link_estado'), 'ABIERTO hasta el jueves 19/11 a las 20:00');
      expect(
        _texto(tester, 'link_cuenta'),
        // Con uno solo va en singular: no dice "1 enviados".
        'De 4 alumnos: 1 falta · 1 sin enviar · 1 enviado · 0 aceptados · '
        '1 ya estaba en el programa.',
      );
      expect(find.text('TRAER LO CARGADO (1)'), findsOneWidget);
      expect(find.text('CAMBIAR LA FECHA…'), findsOneWidget);
      expect(find.text('CERRAR AHORA'), findsOneWidget);
    });

    testWidgets('CERRAR AHORA lo cierra; REABRIR HASTA… con otra fecha lo abre '
        'para todos, las veces que haga falta', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);

      await _tocar(tester, 'link_apagar');
      expect(_texto(tester, 'link_estado'), 'CERRADO');
      expect(_texto(tester, 'link_estado_detalle'), contains('Lo cerraste vos'));
      expect(find.text('CERRAR AHORA'), findsNothing);
      expect(find.text('REABRIR HASTA…'), findsOneWidget);

      mundo.limite =
          (dia: DateTime(2026, 11, 25), hora: const TimeOfDay(hour: 21, minute: 0));
      await _tocar(tester, 'link_cambiar_limite');
      expect(_texto(tester, 'link_estado'), startsWith('ABIERTO hasta el'));
      expect(
        _texto(tester, 'link_dicho'),
        'Abierto hasta el 25/11 a las 21:00. Todos pueden volver a cargar y '
        'corregir.',
      );

      mundo.limite =
          (dia: DateTime(2026, 11, 30), hora: const TimeOfDay(hour: 10, minute: 30));
      await _tocar(tester, 'link_cambiar_limite');
      expect(_texto(tester, 'link_dicho'), 'El límite quedó para el 30/11 a las 10:30.');
      expect(nube.pedidos, [
        'apagar|',
        'vence|2026-11-25 21:00',
        'vence|2026-11-30 10:30',
      ]);
    });

    testWidgets('vencido: dice que el plazo terminó y ofrece reabrir', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.vencido = true;
      await _abrir(tester, nube);
      expect(_texto(tester, 'link_estado'), 'CERRADO');
      expect(
        _texto(tester, 'link_estado_detalle'),
        contains('El plazo terminó el jueves 19/11 a las 20:00'),
      );
      await _tocar(tester, 'link_cambiar_limite');
      expect(_texto(tester, 'link_estado'), startsWith('ABIERTO hasta el'));
      expect(nube.vencido, isFalse);
    });

    testWidgets('COPIAR LINK lo dice, y el cupo se cambia y es de personas', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      // El portapapeles de la prueba: anota lo que se copió.
      final copiado = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (llamada) async {
          if (llamada.method == 'Clipboard.setData') {
            copiado.add('${(llamada.arguments as Map)['text']}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _abrir(tester, nube);
      await _tocar(tester, 'link_copiar');
      expect(copiado, ['https://ejemplo/?delegado&clave=c1a2b3']);
      expect(_texto(tester, 'link_dicho'), 'Link copiado. Pegalo en WhatsApp.');
      expect(find.text('3 personas'), findsOneWidget);
      await _tocar(tester, 'link_cupo');
      await tester.tap(find.text('5 personas').last);
      await tester.pumpAndSettle();
      expect(nube.pedidos, ['cupo|5']);
      expect(nube.cupo, 5);
    });

    testWidgets('si el equipo no deja copiar, lo dice y el link queda escrito '
        'para seleccionarlo', (tester) async {
      // Pasó en el navegador de la prueba (18-nov): el botón no hacía nada.
      final nube = _nube();
      await _cargaron(nube);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (llamada) async {
          if (llamada.method == 'Clipboard.setData') {
            throw PlatformException(code: 'copy_fail');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _abrir(tester, nube);
      await _tocar(tester, 'link_copiar');
      expect(tester.takeException(), isNull);
      expect(
        _texto(tester, 'link_dicho'),
        'No se pudo copiar solo. El link está escrito arriba: seleccionalo y '
        'copialo.',
      );
      expect(
        tester.widget<SelectableText>(find.byKey(const Key('link_url'))).data,
        'https://ejemplo/?delegado&clave=c1a2b3',
      );
    });
  });

  group('los delegados', () {
    testWidgets('por persona: cuándo entró, cuánto cargó y cuándo envió', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      // Laura entra además desde otro celular.
      await nube.entrar(nube.clave!, 'laura gomez');
      await _abrir(tester, nube);

      expect(find.text('LAURA GÓMEZ'), findsOneWidget, reason: 'una sola vez');
      expect(
        find.text('Entró jue 12/11 15:00 · desde 2 celulares'),
        findsOneWidget,
      );
      expect(find.text('Cargó 1 · envió jue 12/11 15:00'), findsOneWidget);
      expect(find.text('PEDRO SOSA'), findsOneWidget);
      expect(find.text('Entró jue 12/11 16:00'), findsOneWidget);
      expect(find.text('Cargó 1 · todavía no envió'), findsOneWidget);
    });

    testWidgets('tocar un delegado deja ver solo sus alumnos; "Todos" vuelve', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube);
      expect(find.byKey(Key('link_alumno_$_bruno')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_sofia')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_lucia')), findsOneWidget);

      await _tocar(tester, 'link_delegado_celular-2'); // Pedro
      expect(find.byKey(Key('link_alumno_$_sofia')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_bruno')), findsNothing);
      expect(find.byKey(Key('link_alumno_$_lucia')), findsNothing);

      await _tocar(tester, 'link_delegado_todos');
      expect(find.byKey(Key('link_alumno_$_bruno')), findsOneWidget);
    });

    testWidgets('SACAR dejando lo que cargó: no entra más y lo suyo sigue '
        'diciendo que lo cargó; DEJAR ENTRAR lo vuelve a dejar', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      await _abrir(tester, nube);

      await _tocar(tester, 'link_sacar_celular-2');
      expect(find.text('Sacar a PEDRO SOSA'), findsOneWidget);
      expect(
        find.textContaining('sigue diciendo que lo cargó PEDRO SOSA'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('link_sacar_dejando')));
      await tester.pumpAndSettle();

      expect(_texto(tester, 'link_dicho'), 'PEDRO SOSA ya no puede entrar.');
      expect(find.text('Sacado · entró jue 12/11 16:00'), findsOneWidget);
      expect(_texto(tester, 'link_quien_$_sofia'), 'Lo cargó PEDRO SOSA · jue 12/11 16:00');
      expect((await nube.entrar(nube.clave!, 'Pedro Sosa')).motivo, 'sacado');

      await _tocar(tester, 'link_readmitir_celular-2');
      expect(_texto(tester, 'link_dicho'), 'PEDRO SOSA puede entrar de nuevo.');
      expect((await nube.entrar(nube.clave!, 'Pedro Sosa')).ok, isTrue);
      expect(nube.pedidos, ['sacar_dejando|celular-2', 'readmitir|celular-2']);
    });

    testWidgets('SACAR borrando: lo que cargó vuelve a faltar, y queda en el '
        'historial', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube);
      await _tocar(tester, 'link_sacar_celular-2');
      await tester.tap(find.byKey(const Key('link_sacar_borrando')));
      await tester.pumpAndSettle();

      expect(nube.cargaDe(_sofia), isNull);
      expect(_chip(tester, 'link_estado_$_sofia'), 'Falta');
      await _tocar(tester, 'link_historial_$_sofia');
      expect(
        find.text('jue 12/11 16:00 · Junior Eventos · Se borró al sacar al delegado'),
        findsOneWidget,
      );
    });
  });

  group('los alumnos', () {
    testWidgets('cada uno con su estado, lo vigente, quién lo cargó y cuándo', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube);

      expect(_chip(tester, 'link_estado_$_lucia'), 'Ya estaba en el programa');
      expect(_chip(tester, 'link_estado_$_bruno'), 'Enviado · falta traerlo');
      expect(_chip(tester, 'link_estado_$_mateo'), 'Falta');
      expect(_chip(tester, 'link_estado_$_sofia'), 'Sin enviar');
      expect(find.textContaining('SOSA, DYLAN'), findsNothing);

      expect(_texto(tester, 'link_quien_$_bruno'), 'Lo cargó LAURA GÓMEZ · jue 12/11 15:00');
      expect(_texto(tester, 'link_quien_$_sofia'), 'Lo cargó PEDRO SOSA · jue 12/11 16:00');
      expect(find.byKey(Key('link_quien_$_lucia')), findsNothing);
      expect(
        find.text('Acompañantes: ÁLVAREZ, EVA · DE LA CRUZ Y SOSA / PAZ, ANA — '
            'Música: Vivir mi vida - Marc Anthony'),
        findsOneWidget,
      );
      // Al que le falta la música se le ven los acompañantes del programa.
      expect(find.text('Acompañantes: BENÍTEZ, CARLA'), findsOneWidget);
    });

    testWidgets('los filtros: faltan, sin enviar y para traer', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      await _abrir(tester, nube);

      await _tocar(tester, 'link_filtro_faltan');
      expect(find.byKey(Key('link_alumno_$_mateo')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_bruno')), findsNothing);

      await _tocar(tester, 'link_filtro_sinEnviar');
      expect(find.byKey(Key('link_alumno_$_sofia')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_mateo')), findsNothing);

      await _tocar(tester, 'link_filtro_paraTraer');
      expect(find.byKey(Key('link_alumno_$_bruno')), findsOneWidget);
      expect(find.byKey(Key('link_alumno_$_sofia')), findsNothing);

      // Con un delegado elegido y un filtro que no le toca: lo dice.
      await _tocar(tester, 'link_delegado_celular-2');
      await _tocar(tester, 'link_filtro_paraTraer');
      expect(find.byKey(const Key('link_sin_alumnos')), findsOneWidget);
    });

    testWidgets('HISTORIAL: cada vez que alguien guardó, con quién y cuándo', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      // Pedro corrige lo que había cargado Laura.
      nube.reloj = 'jue 12/11 17:30';
      final pedro = (await nube.entrar(nube.clave!, 'Pedro Sosa')).sesion!;
      await nube.guardar(
        clave: nube.clave!,
        sesion: pedro,
        alumnoId: _bruno,
        acompanantes: ['ÁLVAREZ, EVA'],
        musica: 'Otro tema',
      );
      await _abrir(tester, nube);

      expect(_texto(tester, 'link_quien_$_bruno'), 'Lo cargó PEDRO SOSA · jue 12/11 17:30');
      expect(_chip(tester, 'link_estado_$_bruno'), 'Sin enviar',
          reason: 'lo corregido después de enviar vuelve a quedar sin enviar');
      expect(find.byKey(Key('link_cambios_$_bruno')), findsNothing);

      await _tocar(tester, 'link_historial_$_bruno');
      expect(
        find.text('jue 12/11 15:00 · LAURA GÓMEZ · Guardó: ÁLVAREZ, EVA · DE LA '
            'CRUZ Y SOSA / PAZ, ANA — Música: Vivir mi vida - Marc Anthony'),
        findsOneWidget,
      );
      expect(
        find.text('jue 12/11 17:30 · PEDRO SOSA · Guardó: ÁLVAREZ, EVA — '
            'Música: Otro tema'),
        findsOneWidget,
      );
      // El que ya estaba en el programa lo dice.
      await _tocar(tester, 'link_historial_$_lucia');
      expect(
        find.textContaining('Se cargó en el programa (por Excel o a mano)'),
        findsOneWidget,
      );
      await _tocar(tester, 'link_historial_$_bruno');
      expect(find.byKey(Key('link_cambios_$_bruno')), findsNothing);
    });
  });

  group('traer y aceptar', () {
    testWidgets('TRAER muestra lo enviado, quién lo cargó y cuándo, y no guarda '
        'nada; ACEPTAR Y CARGAR guarda eso, le avisa a la nube, y la ventana lo '
        'muestra aceptado', (tester) async {
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
      expect(
        find.textContaining('lo cargó LAURA GÓMEZ · jue 12/11 15:00'),
        findsOneWidget,
      );
      // Lo de Pedro, que no envió, no está en la lista: va aparte.
      expect(find.textContaining('lo cargó PEDRO SOSA'), findsNothing);
      expect(
        find.text('Incluir también lo que todavía no enviaron (1 alumno(s))'),
        findsOneWidget,
      );
      // En el link la coma es parte del nombre: no hay aviso.
      expect(find.textContaining('con coma'), findsNothing);
      expect(find.text('ACEPTAR Y CARGAR 1 ALUMNO(S)'), findsOneWidget);
      // Llegando desde el link, lo del Excel no va.
      expect(find.byKey(const Key('delegado_exportar')), findsNothing);

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
      expect(find.byKey(const Key('delegado_exportar')), findsNothing);

      // Cierra la revisión: la ventana del link se releyó.
      await _tocar(tester, 'delegado_cerrar');
      expect(find.text('Antes de guardar'), findsNothing);
      expect(_chip(tester, 'link_estado_$_bruno'), 'Aceptado');
      expect(
        _texto(tester, 'link_cuenta'),
        contains('0 enviados · 1 aceptado ·'),
      );
      await _tocar(tester, 'link_historial_$_bruno');
      expect(
        find.text('jue 12/11 16:00 · Junior Eventos · Aceptado y cargado en el '
            'programa'),
        findsOneWidget,
      );
    });

    testWidgets('VOLVER sin aceptar no cambia nada y vuelve a la ventana', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);
      await _tocar(tester, 'link_traer');
      await _tocar(tester, 'delegado_volver');
      expect(mundo.importados, isEmpty);
      expect(nube.pedidos, isEmpty);
      expect(nube.hayAviso, isTrue);
      expect(find.text('Antes de guardar'), findsNothing);
      expect(find.text('Link para los delegados'), findsOneWidget);
      expect(find.text('TRAER LO CARGADO (1)'), findsOneWidget);
    });

    testWidgets('lo que no enviaron entra solo si se tilda', (tester) async {
      final nube = _nube();
      await _cargaron(nube);
      nube.pedidos.clear();
      final mundo = await _abrir(tester, nube);
      await _tocar(tester, 'link_traer');
      await _tocar(tester, 'delegado_incluir_sin_enviar');
      expect(find.text('ACEPTAR Y CARGAR 2 ALUMNO(S)'), findsOneWidget);
      expect(
        find.textContaining('lo cargó PEDRO SOSA · jue 12/11 16:00'),
        findsOneWidget,
      );
      await _tocar(tester, 'delegado_confirmar');
      expect(
        [for (final c in mundo.importados.single) c.alumno.id]..sort(),
        [_bruno, _sofia]..sort(),
      );
      expect(nube.pedidos, ['traido|["$_bruno","$_sofia"]']);
    });

    testWidgets('lo aceptado se corrige y vuelve para aceptar: la ventana lo '
        'marca, y la revisión dice qué reemplaza y quién lo cambió', (
      tester,
    ) async {
      final nube = _nube();
      await _cargaron(nube);
      await nube.aceptar([_bruno]);
      // Al otro día, Pedro corrige la música de Bruno y envía.
      nube.reloj = 'vie 13/11 09:10';
      final pedro = (await nube.entrar(nube.clave!, 'Pedro Sosa')).sesion!;
      await nube.guardar(
        clave: nube.clave!,
        sesion: pedro,
        alumnoId: _bruno,
        acompanantes: ['ÁLVAREZ, EVA', 'DE LA CRUZ Y SOSA / PAZ, ANA'],
        musica: 'Tema corregido',
      );
      await nube.entregar(nube.clave!, pedro);
      final mundo = await _abrir(tester, nube);

      expect(_chip(tester, 'link_estado_$_bruno'), 'Enviado · falta traerlo');
      expect(
        _chip(tester, 'link_otra_vez_$_bruno'),
        'Corrige lo que ya está en el programa',
      );
      expect(nube.hayAviso, isTrue, reason: 'le llega para aceptar de nuevo');

      await _tocar(tester, 'link_traer');
      // En la revisión se ve con lo que quedó en la grilla de esta PC (que en
      // la prueba no cambió): lo que importa es quién y qué.
      expect(
        find.textContaining('lo cargó PEDRO SOSA · vie 13/11 09:10'),
        findsWidgets,
      );
      await _tocar(tester, 'delegado_confirmar');
      expect(
        mundo.importados.single.map((c) => c.musica).toSet(),
        containsAll(['Tema corregido', 'Persiana americana']),
      );
      await _tocar(tester, 'delegado_cerrar');
      expect(_chip(tester, 'link_estado_$_bruno'), 'Aceptado');
      expect(find.byKey(Key('link_otra_vez_$_bruno')), findsNothing);
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

    test('corregir lo que ya está en el programa se marca: se reemplaza', () {
      final r = revisar([carga(_lucia, musica: 'Otra música')]);
      expect(r.cambios.single.pisaAlgo, isTrue);
      expect(r.cambios.single.tenia, 'Música: Vivir mi vida');
    });

    test('lo que ya está igual no se vuelve a cargar: el delegado que abre uno '
        'del programa y guarda sin cambiar nada no genera nada', () {
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
