// La lista de la puerta cerrada a los anónimos (sección 8 de la 6.0.0).
//
// Con los permisos cerrados, quien no tiene usuario (la ventana del tótem, el
// tótem por el navegador, la página del QR y `?buscar`) no puede leer ni cambiar
// `invitados` ni anotar en `accesos`: va por las funciones de
// `supabase/migrations/20261016120000_puerta_funciones.sql`. Un anónimo que lee
// la tabla con los permisos cerrados recibe **una lista vacía, sin error**: si
// algo de eso volviera a leerla, el tótem sacaría a todos de la pantalla. Este
// test lee los archivos y falla si pasa.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/op_ya_no_se_usa.dart';
import 'package:arguello_events/features/totem/services/lista_del_totem.dart';
import 'package:arguello_events/models/invitado.dart';

String _leer(String ruta) =>
    File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

/// El cuerpo de una función del SQL, de su `create or replace` al `$$;`.
String _funcion(String sql, String nombre) {
  final i = sql.indexOf('create or replace function public.$nombre(');
  expect(i, isNot(-1), reason: 'falta la función $nombre');
  return sql.substring(i, sql.indexOf(r'$$;', i));
}

void main() {
  final funciones =
      _leer('supabase/migrations/20261016120000_puerta_funciones.sql');
  final cerrar =
      _leer('supabase/migrations/20261016130000_puerta_cerrar_permisos.sql');

  group('el SQL y lo que llama la app', () {
    test('cada función con los parámetros que manda la app', () {
      final llamadas = {
        'totem_clave': ['p_evento'],
        'totem_lista': ['p_evento', 'p_clave'],
        'puerta_buscar': ['p_evento', 'p_texto'],
        'puerta_checkin': ['p_invitado', 'p_dni'],
      };
      final app = [
        _leer('lib/features/totem/providers/clave_totem_provider.dart'),
        _leer('lib/features/totem/services/lista_del_totem.dart'),
        _leer('lib/features/recepcion/repositories/supabase_invitados_repository.dart'),
      ].join('\n');
      llamadas.forEach((funcion, params) {
        final cuerpo = _funcion(funciones, funcion);
        expect(app, contains("'$funcion'"), reason: 'la app llama a $funcion');
        for (final p in params) {
          expect(cuerpo, contains(p), reason: '$funcion($p) en el SQL');
          expect(app, contains("'$p'"), reason: '$funcion($p) en la app');
        }
      });
    });

    test('lo que contesta puerta_checkin es lo que entiende la app', () {
      final cuerpo = _funcion(funciones, 'puerta_checkin');
      final repo = _leer(
          'lib/features/recepcion/repositories/supabase_invitados_repository.dart');
      for (final r in [
        'ok',
        'ya_ingresado',
        'dni_incorrecto',
        'bloqueado',
        'no_dni',
        'masivo',
        'no_encontrado',
      ]) {
        expect(cuerpo, contains("'$r'"), reason: 'el SQL contesta $r');
        expect(repo, contains("'$r'"), reason: 'la app entiende $r');
      }
      expect(cuerpo, contains("'quedan'"));
    });

    test('puerta_buscar da lo que muestra la página', () {
      final cuerpo = _funcion(funciones, 'puerta_buscar');
      for (final c in [
        'id',
        'nombre_completo',
        'numero_mesa',
        'ingresado',
        'tiene_dni',
      ]) {
        expect(cuerpo, contains("'$c'"), reason: c);
      }
      expect(cuerpo, contains("'masivo'"), reason: 'en un masivo, nadie');
      expect(cuerpo, contains('< 3'), reason: 'desde 3 letras');
      expect(cuerpo, contains('limit 10'));
    });

    test('ninguna función le da a un anónimo el DNI ni los intentos', () {
      for (final f in ['totem_lista', 'puerta_buscar', 'puerta_checkin']) {
        final salida = _funcion(funciones, f)
            .split('\n')
            .where((l) => l.contains('jsonb_build_object') || l.contains("', "))
            .join('\n');
        expect(salida, isNot(contains("'dni'")), reason: f);
        expect(salida, isNot(contains("'intentos_fallidos'")), reason: f);
      }
    });

    test('una clave mala da error, nunca una lista vacía, con el código que '
        'mira la app', () {
      final cuerpo = _funcion(funciones, 'totem_lista');
      expect(cuerpo, contains('raise exception'));
      expect(cuerpo, contains("errcode = '${ListaDelTotem.codigoClaveMala}'"));
    });

    test('la clave la pide solo quien tiene usuario', () {
      expect(funciones,
          contains('revoke all on function public.totem_clave(uuid) from public, anon;'));
      expect(funciones,
          contains('grant execute on function public.totem_clave(uuid) to authenticated;'));
      expect(_funcion(funciones, 'totem_clave'),
          contains("auth.role() is distinct from 'authenticated'"));
      expect(funciones,
          contains('revoke all on table public.claves_totem from anon, authenticated;'));
      for (final f in [
        'totem_lista(uuid, text)',
        'puerta_buscar(uuid, text)',
        'puerta_checkin(uuid, text)',
      ]) {
        expect(funciones,
            contains('grant execute on function public.$f to anon, authenticated;'));
      }
    });

    test('las funciones van como security definer y con search_path', () {
      for (final f in ['totem_clave', 'totem_lista', 'puerta_buscar', 'puerta_checkin']) {
        final cuerpo = _funcion(funciones, f);
        expect(cuerpo, contains('security definer'), reason: f);
        expect(cuerpo, contains('set search_path = public'), reason: f);
      }
    });

    test('el primer SQL solo agrega: no saca permisos ni toca filas', () {
      final sinComentarios = funciones
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n')
          .toLowerCase();
      expect(sinComentarios, isNot(contains('drop policy')));
      expect(sinComentarios, isNot(contains('alter table public.invitados')));
      expect(sinComentarios, isNot(contains('add constraint')));
      expect(sinComentarios, isNot(contains('supabase_realtime')));
    });

    test('cerrar saca los tres permisos, cada uno con su ROLLBACK arriba', () {
      for (final (politica, tabla) in [
        ('lectura_publica_invitados', 'invitados'),
        ('actualizacion_publica_invitados', 'invitados'),
        ('"Permitir inserción de accesos"', 'accesos'),
      ]) {
        final drop = 'drop policy if exists $politica on public.$tabla;';
        final i = cerrar.indexOf(drop);
        expect(i, isNot(-1), reason: drop);
        final antes = cerrar.substring(0, i).trimRight().split('\n').last;
        expect(antes, startsWith('-- ROLLBACK: create policy $politica on public.$tabla'),
            reason: 'el ROLLBACK de $politica va justo arriba');
      }
      expect(cerrar, contains('VA ÚLTIMO AL PUBLICAR'));
    });
  });

  group('nada sin usuario lee la tabla', () {
    for (final ruta in [
      'lib/features/totem/totem_display.dart',
      'lib/features/totem/services/lista_del_totem.dart',
      'lib/features/recepcion/lista_invitados_screen.dart',
      'lib/features/recepcion/repositories/supabase_invitados_repository.dart',
      'lib/services/supabase_service.dart',
    ]) {
      test(ruta, () {
        final fuente = _leer(ruta);
        expect(fuente, isNot(contains("from('invitados')")));
        expect(fuente, isNot(contains("from('accesos')")));
        expect(fuente, isNot(contains('.stream(')),
            reason: 'Realtime de la tabla no le manda nada a un anónimo');
      });
    }

    test('el tótem lee la lista por ListaDelTotem, cada 20 s, y lo corta al '
        'pausarse', () {
      final fuente = _leer('lib/features/totem/totem_display.dart');
      final i = fuente.indexOf('Future<void> _reconciliar() async {');
      final reconciliar = fuente.substring(i, fuente.indexOf('\n  }\n', i));
      expect(reconciliar, contains('await _lista.leer(evento)'));
      // La clave: en la ventana, por el puente; en la web, del link.
      final c = fuente.indexOf('Future<String?> _claveDelEvento(String eventoId) {');
      final clave = fuente.substring(c, fuente.indexOf('\n  }\n', c));
      expect(clave,
          contains('if (widget.windowId != null) return PuenteFichaTotem.pedirClave(eventoId);'));
      expect(clave,
          contains("if (kIsWeb) return Future.value(Uri.base.queryParameters['clave']);"));
      expect(fuente,
          contains('static const _cadaCuanto = Duration(seconds: 20);'));
      final p = fuente.indexOf('Future<void> _pausar() async {');
      expect(fuente.substring(p, fuente.indexOf('\n  }\n', p)),
          contains('_reconciliarTimer?.cancel();'));
    });

    test('la ventana principal le da la clave al tótem por el puente', () {
      final main = _leer('lib/main.dart');
      final i = main.indexOf('PuenteFichaTotem.atenderEnLaVentanaPrincipal(');
      final atender = main.substring(i, main.indexOf('\n      );\n', i));
      expect(atender,
          contains('clave: (eventoId) => ref.read(claveTotemProvider).de(eventoId)'));
      expect(atender,
          contains('claveMala: (eventoId) => ref.read(claveTotemProvider).olvidar(eventoId)'));
    });

    test('?buscar es la página del QR, y /op ya no marca a nadie', () {
      final main = _leer('lib/main.dart');
      expect(main, isNot(contains('OpCheckinScreen')));
      expect(main, isNot(contains('TotemCheckinScreen')));
      final buscar = main.substring(main.indexOf('class BuscarApp'));
      expect(buscar.substring(0, buscar.indexOf('\n}\n')),
          contains('ListaInvitadosScreen(eventoId: eventoId)'));
      final op = main.substring(main.indexOf('class OpApp'));
      expect(op.substring(0, op.indexOf('\n}\n')), contains('OpYaNoSeUsa()'));
    });
  });

  group('el aviso al tótem va sin DNI', () {
    final invitado = Invitado(
      id: 'i1',
      eventoId: 'e1',
      nombreCompleto: 'GÓMEZ, LAURA',
      dni: '30111222',
      numeroMesa: '12',
      estadoIngreso: EstadoIngreso.ingresado,
      intentosFallidos: 2,
    );

    test('paraAviso saca el DNI y los intentos, y deja lo que usa el tótem', () {
      final aviso = invitado.paraAviso();
      expect(aviso.containsKey('dni'), isFalse);
      expect(aviso.containsKey('intentos_fallidos'), isFalse);
      final leido = Invitado.fromJson(aviso);
      expect(leido.id, 'i1');
      expect(leido.nombreCompleto, 'GÓMEZ, LAURA');
      expect(leido.numeroMesa, '12');
      expect(leido.estadoIngreso, EstadoIngreso.ingresado);
      expect(leido.dni, '');
    });

    test('sinDatosPrivados no toca lo que recibe', () {
      final json = invitado.toJson();
      Invitado.sinDatosPrivados(json);
      expect(json['dni'], '30111222');
    });

    test('la página del QR avisa con paraAviso', () {
      final repo = _leer(
          'lib/features/recepcion/repositories/supabase_invitados_repository.dart');
      expect(repo, contains("sendBroadcastMessage(event: 'checkin', payload: inv.paraAviso())"));
    });

    test('Recepción los saca en el único lugar por donde salen los avisos', () {
      final repo = _leer(
          'lib/features/recepcion/repositories/invitados_repository.dart');
      final i = repo.indexOf('Future<void> _emitir(');
      final emitir = repo.substring(i, repo.indexOf('\n  }\n', i));
      expect(emitir, contains('payload: Invitado.sinDatosPrivados(payload)'));
      expect(
        RegExp(r'sendBroadcastMessage\(').allMatches(repo).length,
        1,
        reason: 'todo aviso de Recepción pasa por _emitir',
      );
    });
  });

  testWidgets('/op dice dónde se suman ahora los celulares', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(const MaterialApp(home: OpYaNoSeUsa()));
    expect(find.text(OpYaNoSeUsa.titulo), findsOneWidget);
    expect(find.text(OpYaNoSeUsa.explicacion), findsOneWidget);
    expect(kCelularesDesdeRecepcion, contains('CELULARES'));
  });
}
