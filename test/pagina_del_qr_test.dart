// La página del QR del tótem (`/lista` y `?buscar`, sección 8 de la 6.0.0),
// montada entera con una nube de mentira que hace lo mismo que las funciones
// `puerta_buscar` y `puerta_checkin` del SQL. El celular busca desde 3 letras,
// nunca recibe un DNI, y el DNI lo compara la nube.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/lista_invitados_screen.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/supabase_invitados_repository.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';

/// Una persona en la lista de la puerta de la nube.
class _Fila {
  final String id;
  final String nombre;
  final String? mesa;
  final String dni;
  bool ingresado;
  int intentos = 0;

  _Fila(this.id, this.nombre, {this.mesa, this.dni = '', this.ingresado = false});
}

/// Hace lo que hacen `puerta_buscar` y `puerta_checkin` en la nube.
class _Nube {
  final filas = <_Fila>[
    _Fila('i1', 'GÓMEZ, LAURA', mesa: '12', dni: '30.111.222'),
    _Fila('i2', 'GÓMEZ, PEDRO', mesa: '12'),
    _Fila('i3', 'GOMEZA, RUTH', dni: '28999000'),
    _Fila('i4', 'PÉREZ, JUAN', mesa: '5', dni: '27444555', ingresado: true),
  ];
  bool masivo = false;
  bool caida = false;
  final buscados = <String>[];
  final pedidos = <Map<String, dynamic>>[];
  final avisados = <Invitado>[];

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll(',', ' ');

  Future<dynamic> llamar(String funcion, Map<String, dynamic> p) async {
    if (caida) throw Exception('SocketException: Failed host lookup');
    pedidos.add({'funcion': funcion, ...p});
    if (funcion == 'puerta_buscar') {
      buscados.add(p['p_texto'] as String);
      if (masivo) return <dynamic>[];
      final palabras = _norm(p['p_texto'] as String)
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty);
      return [
        for (final f in filas)
          if (palabras.every((w) => _norm(f.nombre).contains(w)))
            {
              'id': f.id,
              'nombre_completo': f.nombre,
              'numero_mesa': f.mesa,
              'ingresado': f.ingresado,
              'tiene_dni': f.dni.isNotEmpty,
            },
      ];
    }
    if (funcion == 'puerta_checkin') {
      final f = filas.firstWhere((f) => f.id == p['p_invitado']);
      Map<String, dynamic> inv() => {
            'id': f.id,
            'evento_id': _ev,
            'nombre_completo': f.nombre,
            'numero_mesa': f.mesa,
            'estado_ingreso': f.ingresado ? 'ingresado' : 'pendiente',
          };
      if (masivo) return {'resultado': 'masivo'};
      if (f.ingresado) return {'resultado': 'ya_ingresado', 'invitado': inv()};
      if (f.intentos >= 3) return {'resultado': 'bloqueado'};
      final cargado = f.dni.replaceAll(RegExp(r'\D'), '');
      if (cargado.isEmpty) return {'resultado': 'no_dni'};
      final dado = (p['p_dni'] as String).replaceAll(RegExp(r'\D'), '');
      if (dado == cargado) {
        f.ingresado = true;
        f.intentos = 0;
        return {'resultado': 'ok', 'invitado': inv()};
      }
      f.intentos++;
      if (f.intentos >= 3) return {'resultado': 'bloqueado'};
      return {'resultado': 'dni_incorrecto', 'quedan': 3 - f.intentos};
    }
    throw StateError('función desconocida: $funcion');
  }
}

void main() {
  late _Nube nube;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => nube = _Nube());

  Future<void> abrir(WidgetTester tester, {String eventoId = _ev}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseInvitadosRepositoryProvider.overrideWithValue(
            SupabaseInvitadosRepository.con(
              llamar: nube.llamar,
              avisar: (i) async => nube.avisados.add(i),
            ),
          ),
          totemConfigProvider(eventoId).overrideWith(
            (ref) => Stream.value(
              TotemConfig.defaults(eventoId).copyWith(titulo: 'CASAMIENTO GÓMEZ'),
            ),
          ),
        ],
        child: MaterialApp(home: ListaInvitadosScreen(eventoId: eventoId)),
      ),
    );
    await tester.pump();
  }

  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(const ValueKey('buscador')), texto);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  Future<void> ponerDni(WidgetTester tester, String dni) async {
    await tester.enterText(find.byKey(const ValueKey('dni')), dni);
    await tester.tap(find.byKey(const ValueKey('ingresar')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('arranca sin nadie: hay que escribir al menos 3 letras',
      (tester) async {
    await abrir(tester);
    expect(find.text('CASAMIENTO GÓMEZ'), findsOneWidget);
    expect(find.text(ListaInvitadosScreen.faltanLetras), findsOneWidget);
    await escribir(tester, 'go');
    expect(find.text(ListaInvitadosScreen.faltanLetras), findsOneWidget);
    expect(nube.buscados, isEmpty, reason: 'con 2 letras no le pregunta a la nube');
    expect(find.text('GÓMEZ, LAURA'), findsNothing);
  });

  testWidgets('desde 3 letras busca, y muestra nombre y mesa', (tester) async {
    await abrir(tester);
    await escribir(tester, 'gom');
    expect(nube.buscados, ['gom']);
    expect(find.text('GÓMEZ, LAURA'), findsOneWidget);
    expect(find.text('GÓMEZ, PEDRO'), findsOneWidget);
    expect(find.text('GOMEZA, RUTH'), findsOneWidget);
    expect(find.text('Mesa 12'), findsNWidgets(2));
    expect(find.text('Mesa por asignar'), findsOneWidget);
    expect(find.text('PÉREZ, JUAN'), findsNothing);
  });

  testWidgets('escribiendo rápido pregunta una sola vez, con lo último',
      (tester) async {
    await abrir(tester);
    await tester.enterText(find.byKey(const ValueKey('buscador')), 'gom');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const ValueKey('buscador')), 'gomez la');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(nube.buscados, ['gomez la']);
    expect(find.text('GÓMEZ, LAURA'), findsOneWidget);
    expect(find.text('GÓMEZ, PEDRO'), findsNothing);
  });

  testWidgets('sin encontrar a nadie lo dice', (tester) async {
    await abrir(tester);
    await escribir(tester, 'zzz');
    expect(find.text(ListaInvitadosScreen.noEncontrado('zzz')), findsOneWidget);
  });

  testWidgets('con DNI: lo pide, la nube lo compara, entra y ve su mesa',
      (tester) async {
    await abrir(tester);
    await escribir(tester, 'laura');
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('¿Sos vos?'), findsOneWidget);

    await ponerDni(tester, '30111222');
    expect(find.text('TU MESA ES LA'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(nube.filas.first.ingresado, isTrue);

    // Al tótem le avisa sin el DNI.
    expect(nube.avisados, hasLength(1));
    expect(nube.avisados.single.id, 'i1');
    expect(nube.avisados.single.dni, '');
    expect(nube.avisados.single.paraAviso().containsKey('dni'), isFalse);
  });

  testWidgets('un DNI que no coincide: cuántos intentos quedan, y al tercero a '
      'la recepción', (tester) async {
    await abrir(tester);
    await escribir(tester, 'laura');
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await tester.pump(const Duration(milliseconds: 250));

    await ponerDni(tester, '1');
    expect(find.text(ListaInvitadosScreen.dniNoCoincide(2)), findsOneWidget);
    await ponerDni(tester, '2');
    expect(find.text(ListaInvitadosScreen.dniNoCoincide(1)), findsOneWidget);
    expect(find.text('Ese DNI no coincide. Te queda 1 intento.'), findsOneWidget);
    await ponerDni(tester, '3');
    expect(find.text(ListaInvitadosScreen.bloqueado), findsOneWidget);
    expect(nube.filas.first.ingresado, isFalse);
    expect(nube.avisados, isEmpty);
  });

  testWidgets('sin escribir el DNI no le pregunta a la nube', (tester) async {
    await abrir(tester);
    await escribir(tester, 'laura');
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await tester.pump(const Duration(milliseconds: 250));
    await ponerDni(tester, '');
    expect(find.text(ListaInvitadosScreen.escribiTuDni), findsOneWidget);
    expect(nube.pedidos.where((p) => p['funcion'] == 'puerta_checkin'), isEmpty);
  });

  testWidgets('sin DNI cargado no entra: a la recepción', (tester) async {
    await abrir(tester);
    await escribir(tester, 'pedro');
    await tester.tap(find.text('GÓMEZ, PEDRO'));
    await tester.pump();
    expect(find.text(ListaInvitadosScreen.aLaRecepcion), findsOneWidget);
    expect(find.text('¿Sos vos?'), findsNothing);
    expect(nube.pedidos.where((p) => p['funcion'] == 'puerta_checkin'), isEmpty);
    expect(nube.filas[1].ingresado, isFalse);
  });

  testWidgets('el que ya entró ve su mesa sin que le pidan nada',
      (tester) async {
    await abrir(tester);
    await escribir(tester, 'perez');
    expect(find.text('Ya ingresó'), findsOneWidget);
    await tester.tap(find.text('PÉREZ, JUAN'));
    await tester.pump();
    expect(find.text('TU MESA ES LA'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(nube.pedidos.where((p) => p['funcion'] == 'puerta_checkin'), isEmpty);
  });

  testWidgets('sin mesa no dice "sin mesa"', (tester) async {
    await abrir(tester);
    await escribir(tester, 'ruth');
    await tester.tap(find.text('GOMEZA, RUTH'));
    await tester.pump(const Duration(milliseconds: 250));
    await ponerDni(tester, '28999000');
    expect(find.text(ListaInvitadosScreen.mesaPorAsignar), findsOneWidget);
  });

  testWidgets('en un masivo no aparece nadie', (tester) async {
    nube.masivo = true;
    await abrir(tester);
    await escribir(tester, 'gomez');
    expect(find.text('GÓMEZ, LAURA'), findsNothing);
    expect(find.text(ListaInvitadosScreen.noEncontrado('gomez')), findsOneWidget);
  });

  testWidgets('sin internet lo dice en palabras y deja reintentar',
      (tester) async {
    nube.caida = true;
    await abrir(tester);
    await escribir(tester, 'laura');
    expect(find.text(ListaInvitadosScreen.noSePudoBuscar), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);

    nube.caida = false;
    await tester.tap(find.text('REINTENTAR'));
    await tester.pump();
    await tester.pump();
    expect(find.text('GÓMEZ, LAURA'), findsOneWidget);
  });

  testWidgets('si se corta al verificar, no entra y se puede volver a probar',
      (tester) async {
    await abrir(tester);
    await escribir(tester, 'laura');
    await tester.tap(find.text('GÓMEZ, LAURA'));
    await tester.pump(const Duration(milliseconds: 250));
    nube.caida = true;
    await ponerDni(tester, '30111222');
    expect(find.text(ListaInvitadosScreen.noSePudoVerificar), findsOneWidget);
    expect(nube.filas.first.ingresado, isFalse);

    nube.caida = false;
    await ponerDni(tester, '30111222');
    expect(find.text('TU MESA ES LA'), findsOneWidget);
  });

  testWidgets('un QR con un evento que no sirve lo dice', (tester) async {
    await abrir(tester, eventoId: 'corto');
    expect(find.textContaining('No se especificó un evento válido'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('buscador')), findsNothing);
  });
}
