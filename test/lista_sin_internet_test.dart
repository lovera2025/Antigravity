// "Lista para trabajar sin internet" (sección 5 de la 6.0.0): qué dice la
// línea de Recepción (`EstadoSinInternet`), cuándo se pone al día el evento
// (`PuestaAlDiaPuerta`) y la línea en el panel de verdad, con los reemplazos en
// memoria de `helpers/puerta_en_memoria.dart`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/recepcion/services/lista_sin_internet.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/puerta_en_memoria.dart';

const _ev = eventoMasivo;
final _ahora = ahoraDePrueba;
final _alDia = DateTime(2026, 12, 12, 21, 32);

EstadoSinInternet _estado(
  DatosSinInternet d, {
  int personas = 1100,
  DateTime? ahora,
}) =>
    EstadoSinInternet.de(d, personas: personas, ahora: ahora ?? _ahora);

String _detalle(EstadoSinInternet e, String clave) =>
    e.detalle.firstWhere((r) => r.$1 == clave).$2;

late SupabaseClient _supabase;

List<ContratoAlumno> _alumnos() => [
      alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN', mesas: [12]),
      alumnoDePrueba('acosta', 'ACOSTA, LUCÍA', mesas: [14]),
    ];

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  });

  group('lo que dice la línea', () {
    test('con internet y todo en la PC: lista', () {
      final e = _estado(DatosSinInternet(
          hayInternet: true, alDia: _alDia, fotoGuardada: true));
      expect(e.tipo, TipoSinInternet.lista);
      expect(e.texto, 'Lista para trabajar sin internet · al día 21:32');
      expect(_detalle(e, 'Personas en esta PC'), '1.100');
      expect(_detalle(e, 'Al día'), 'hoy 21:32');
      expect(_detalle(e, 'Foto del tótem'), 'guardada');
      expect(_detalle(e, 'Ingresos sin subir'), 'ninguno');
    });

    test('un evento sin foto también está listo', () {
      final e = _estado(DatosSinInternet(hayInternet: true, alDia: _alDia));
      expect(e.tipo, TipoSinInternet.lista);
      expect(_detalle(e, 'Foto del tótem'), 'el evento no tiene');
    });

    test('con internet y sin la foto: falta', () {
      final e = _estado(DatosSinInternet(
          hayInternet: true, alDia: _alDia, fotoGuardada: false));
      expect(e.tipo, TipoSinInternet.falta);
      expect(e.texto, contains('falta guardar la foto del tótem'));
      expect(_detalle(e, 'Foto del tótem'), 'no bajó · se reintenta');
    });

    test('la primera vez, mientras baja', () {
      final e = _estado(const DatosSinInternet(hayInternet: true, bajando: true));
      expect(e.tipo, TipoSinInternet.falta);
      expect(e.texto, 'Poniéndose al día para trabajar sin internet…');
      expect(_detalle(e, 'Al día'), 'bajando…');
    });

    test('la primera vez, si no pudo bajar: lo dice', () {
      final e = _estado(const DatosSinInternet(hayInternet: true, fallo: true));
      expect(e.tipo, TipoSinInternet.falta);
      expect(e.texto, contains('no se pudo bajar la lista'));
    });

    test('si hace rato que no puede ponerse al día, lo dice con la hora', () {
      final viejo = _ahora.subtract(const Duration(minutes: 40));
      final e = _estado(
          DatosSinInternet(hayInternet: true, alDia: viejo, fallo: true));
      expect(e.tipo, TipoSinInternet.falta);
      expect(e.texto, startsWith('No se pudo poner al día la lista desde las 21:00'));
    });

    test('un fallo de hace un momento no asusta: sigue lista', () {
      final e = _estado(DatosSinInternet(
          hayInternet: true,
          alDia: _ahora.subtract(const Duration(minutes: 5)),
          fallo: true));
      expect(e.tipo, TipoSinInternet.lista);
    });

    test('sin internet: con lo de la PC, la hora y lo que espera subir', () {
      final e = _estado(DatosSinInternet(
          hayInternet: false, alDia: _alDia, fotoGuardada: true, sinSubir: 12));
      expect(e.tipo, TipoSinInternet.sinInternet);
      expect(
        e.texto,
        'Sin internet · se sigue con lo de esta PC (al día 21:32) · '
        '12 ingresos sin subir: se suben solos al volver',
      );
      expect(_detalle(e, 'Ingresos sin subir'), '12, se suben solos al volver');
    });

    test('sin internet, uno solo sin subir, y bajado ayer', () {
      final e = _estado(DatosSinInternet(
        hayInternet: false,
        alDia: DateTime(2026, 12, 11, 18, 5),
        sinSubir: 1,
      ));
      expect(
        e.texto,
        'Sin internet · se sigue con lo de esta PC (al día ayer 18:05) · '
        '1 ingreso sin subir: se suben solos al volver',
      );
    });

    test('sin internet y sin nada pendiente, no habla de lo que sube', () {
      final e = _estado(DatosSinInternet(hayInternet: false, alDia: _alDia));
      expect(e.texto, 'Sin internet · se sigue con lo de esta PC (al día 21:32)');
    });

    test('sin internet y sin la lista del evento', () {
      final e = _estado(const DatosSinInternet(hayInternet: false), personas: 0);
      expect(e.tipo, TipoSinInternet.sinLista);
      expect(e.texto, contains('esta PC no tiene la lista de este evento'));
      expect(_detalle(e, 'Personas en esta PC'), 'ninguna');
    });
  });

  group('cuándo se pone al día', () {
    late SinInternetEnMemoria mem;
    setUp(() => mem = SinInternetEnMemoria());

    PuestaAlDiaPuerta puesta({bool hay = true, bool masivo = true, String? foto}) {
      final p = PuestaAlDiaPuerta(
        eventoId: _ev,
        accesos: mem.accesos,
        hayInternet: hay,
        cada: const Duration(hours: 1),
        cadaCuenta: const Duration(hours: 1),
      )
        ..masivo = masivo
        ..fotoUrl = foto;
      addTearDown(p.dispose);
      return p;
    }

    test('con internet: baja la lista, los alumnos y la foto, y anota la hora',
        () async {
      final p = puesta(foto: 'https://nube.test/foto.png');
      await p.arrancar();
      expect(mem.listasBajadas, 1);
      expect(mem.alumnosBajados, 1);
      expect(mem.fotosGuardadas, {'https://nube.test/foto.png'});
      expect(p.datos.alDia, _ahora);
      expect(mem.alDia[_ev], _ahora, reason: 'queda guardada para sin internet');
      expect(p.datos.fotoGuardada, isTrue);
      expect(p.datos.fallo, isFalse);
      expect(p.datos.bajando, isFalse);
    });

    test('un particular no baja alumnos', () async {
      await puesta(masivo: false).arrancar();
      expect(mem.alumnosBajados, 0);
      expect(mem.listasBajadas, 1);
    });

    test('si los alumnos no bajan, no se da por al día', () async {
      mem
        ..bajanAlumnos = false
        ..alDia[_ev] = _alDia;
      final p = puesta();
      await p.arrancar();
      expect(p.datos.fallo, isTrue);
      expect(p.datos.alDia, _alDia, reason: 'queda la hora de la última vez');
      expect(mem.alDia[_ev], _alDia);
    });

    test('si la lista no baja, tampoco', () async {
      mem.bajaLista = false;
      final p = puesta();
      await p.arrancar();
      expect(p.datos.fallo, isTrue);
      expect(p.datos.alDia, isNull);
    });

    test('la foto que no baja no frena el "al día": se dice aparte', () async {
      mem.bajaFoto = false;
      final p = puesta(foto: 'https://nube.test/foto.png');
      await p.arrancar();
      expect(p.datos.alDia, _ahora);
      expect(p.datos.fotoGuardada, isFalse);
    });

    test('sin internet: no intenta bajar nada, y dice la hora guardada',
        () async {
      mem
        ..alDia[_ev] = _alDia
        ..fotosGuardadas.add('https://nube.test/foto.png')
        ..sinSubir = 3;
      final p = puesta(hay: false, foto: 'https://nube.test/foto.png');
      await p.arrancar();
      expect(mem.listasBajadas, 0);
      expect(mem.alumnosBajados, 0);
      expect(p.datos.alDia, _alDia);
      expect(p.datos.fotoGuardada, isTrue);
      expect(p.datos.sinSubir, 3);
    });

    test('vuelve internet: se pone al día sola', () async {
      final p = puesta(hay: false);
      await p.arrancar();
      expect(mem.listasBajadas, 0);
      p.conexion(true);
      await p.ponerAlDia();
      expect(mem.listasBajadas, 1);
      expect(p.datos.alDia, _ahora);
    });

    test('dos pedidos a la vez bajan una sola vez', () async {
      final p = puesta();
      await Future.wait([p.arrancar(), p.ponerAlDia(), p.ponerAlDia()]);
      expect(mem.listasBajadas, 1);
    });

    test('si recién se sabe que es masivo, baja también los alumnos', () async {
      final p = puesta(masivo: false);
      await p.arrancar();
      expect(mem.alumnosBajados, 0);
      p.masivo = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mem.alumnosBajados, 1);
    });

    test('si se corta internet mientras baja, lo que seguía no intenta',
        () async {
      final frenar = Completer<void>();
      var listas = 0;
      final p = PuestaAlDiaPuerta(
        eventoId: _ev,
        hayInternet: true,
        cada: const Duration(hours: 1),
        cadaCuenta: const Duration(hours: 1),
        accesos: AccesosPuerta(
          bajarLista: (_) async {
            listas++;
            await frenar.future;
            return true;
          },
          bajarAlumnos: () async => true,
          guardarFoto: (_, _) async => true,
          fotoGuardada: (_, _) async => true,
          contarSinSubir: (_) async => 0,
          leerAlDia: (_) async => null,
          anotarAlDia: (_, _) async {},
          ahora: () => _ahora,
        ),
      );
      addTearDown(p.dispose);
      final arranque = p.arrancar();
      await Future<void>.delayed(Duration.zero);
      // Se sabe que es masivo (queda otra para después) y se corta internet.
      p.masivo = true;
      p.conexion(false);
      frenar.complete();
      await arranque;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(listas, 1);
    });

    test('cuenta lo que espera subir', () async {
      final p = puesta(hay: false);
      await p.arrancar();
      mem.sinSubir = 7;
      await p.recontar();
      expect(p.datos.sinSubir, 7);
    });
  });

  group('la línea en el panel', () {
    Future<PuertaEnMemoria> abrir(
      WidgetTester tester, {
      AppConnectivity conexion = AppConnectivity.online,
      Map<String, TotemConfig> config = const {},
      void Function(PuertaEnMemoria)? antes,
    }) async {
      final mundo = PuertaEnMemoria(_supabase, alumnos: _alumnos());
      mundo.conexion.estado = conexion;
      antes?.call(mundo);
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(mundo.motor.bajo.close);
      await tester.pumpWidget(mundo.panel(_ev, config: config));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      return mundo;
    }

    testWidgets('con internet: lista, y al tocarla el detalle', (tester) async {
      final mundo = await abrir(tester);
      expect(find.text('Lista para trabajar sin internet · al día 21:40'),
          findsOneWidget);
      expect(mundo.sinInternet.listasBajadas, 1);
      expect(mundo.sinInternet.alumnosBajados, 1, reason: 'es masivo');
      expect(find.text('Personas en esta PC'), findsNothing);

      await tester.tap(find.textContaining('Lista para trabajar'));
      await tester.pump();
      expect(find.text('Personas en esta PC'), findsOneWidget);
      expect(find.text('hoy 21:40'), findsOneWidget);
      expect(find.text('el evento no tiene'), findsOneWidget);
    });

    testWidgets('se corta internet: lo dice, con lo que espera subir',
        (tester) async {
      final mundo = await abrir(tester);
      mundo.sinInternet.sinSubir = 4;
      mundo.conexion.poner(AppConnectivity.offline);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(
        find.text('Sin internet · se sigue con lo de esta PC (al día 21:40)'),
        findsOneWidget,
        reason: 'lo que espera subir se cuenta cada 10 s o al entrar alguien',
      );
      // Pasan los 10 s de la cuenta.
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Sin internet · se sigue con lo de esta PC (al día 21:40) · '
            '4 ingresos sin subir: se suben solos al volver'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Sin internet'));
      await tester.pump();
      expect(find.text('4, se suben solos al volver'), findsOneWidget);
    });

    testWidgets('abierto sin internet: con la hora que quedó guardada',
        (tester) async {
      final mundo = await abrir(
        tester,
        conexion: AppConnectivity.offline,
        antes: (m) => m.sinInternet
          ..alDia[_ev] = _alDia
          ..sinSubir = 2,
      );
      expect(mundo.sinInternet.listasBajadas, 0);
      expect(
        find.text('Sin internet · se sigue con lo de esta PC (al día 21:32) · '
            '2 ingresos sin subir: se suben solos al volver'),
        findsOneWidget,
      );
    });

    testWidgets('con foto en el tótem que no baja: falta', (tester) async {
      await abrir(
        tester,
        config: {
          _ev: TotemConfig.defaults(_ev)
              .copyWith(imagenUrl: 'https://nube.test/foto.png'),
        },
        antes: (m) => m.sinInternet.bajaFoto = false,
      );
      expect(find.textContaining('falta guardar la foto del tótem'),
          findsOneWidget);
    });

    testWidgets('vuelve internet: se pone al día de nuevo', (tester) async {
      final mundo = await abrir(tester, conexion: AppConnectivity.offline);
      expect(mundo.sinInternet.listasBajadas, 0);
      mundo.conexion.poner(AppConnectivity.online);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(mundo.sinInternet.listasBajadas, 1);
      expect(find.text('Lista para trabajar sin internet · al día 21:40'),
          findsOneWidget);
    });
  });
}
