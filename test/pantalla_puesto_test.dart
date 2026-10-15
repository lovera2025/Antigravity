// La pantalla del celular de la puerta (`PantallaPuesto`), entera, con un
// cliente de mentira al que la prueba le pone cada estado: la primera vez, la
// lista, sin conexión, el código cambiado.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_puesto.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';

import 'helpers/puerta_en_memoria.dart';

class _NadaGuardado implements GuardadoDelCelular {
  @override
  Future<String?> leer(String clave) async => null;

  @override
  Future<void> guardar(String clave, String? valor) async {}
}

/// El cliente, con el estado que pone la prueba y lo que se le pidió.
class _ClienteDePrueba extends ClienteCentral {
  _ClienteDePrueba()
      : super(servidor: Uri.parse('http://127.0.0.1:1/'), guardado: _NadaGuardado());

  EstadoDelPuesto e = EstadoDelPuesto.conectado;
  PuertaDelEvento? p;
  String? n = 'Juli';
  String? cod = '4821';
  String? tit = 'ESCUELA DE MUESTRA — Egresados (12/12) · masivo';
  List<PedidoPendiente> pend = [];
  int mandados = 0;
  Map<String, String> marcas = {};

  final ingresados = <String>[];
  final deshechos = <String>[];
  final datos = <(String, String?)>[];
  var reconexiones = 0;
  final avisosDePrueba = StreamController<String>.broadcast();

  void cambio() => notifyListeners();

  @override
  EstadoDelPuesto get estado => e;
  @override
  PuertaDelEvento? get puerta => p;
  @override
  String? get eventoId => p == null ? null : eventoMasivo;
  @override
  String? get nombre => n;
  @override
  String? get codigo => cod;
  @override
  String? get titulo => tit;
  @override
  List<PedidoPendiente> get pendientes => pend;
  @override
  int get seMandaron => mandados;
  @override
  Stream<String> get avisos => avisosDePrueba.stream;
  @override
  String? marca(String personaId) => marcas[personaId];

  @override
  Future<void> ingresar(PersonaPuerta persona) async =>
      ingresados.add(persona.id);
  @override
  Future<void> deshacer(PersonaPuerta persona) async =>
      deshechos.add(persona.id);
  @override
  Future<void> ponerDatos({required String nombre, String? codigo}) async =>
      datos.add((nombre, codigo));
  @override
  void reconectar() => reconexiones++;
}

const _juan = 'c1000000-0000-4000-8000-000000000001';
const _lucia = 'c2000000-0000-4000-8000-000000000002';

/// Una institución sorteada: Juan ya entró; Lucía no. Más una persona cargada
/// a mano en la lista de la puerta.
PuertaDelEvento _lista() => PuertaDelEvento.masivo(
      alumnos: [
        alumnoDePrueba(_juan, 'PÉREZ, JUAN', mesas: [12], acomp: ['GÓMEZ, ANA']),
        alumnoDePrueba(_lucia, 'ACOSTA, LUCÍA', mesas: [14]),
      ],
      invitados: [
        Invitado(
          id: idInvitadoPuerta(_juan, 0),
          eventoId: eventoMasivo,
          nombreCompleto: 'PÉREZ, JUAN',
          dni: '',
          estadoIngreso: EstadoIngreso.ingresado,
          updatedAt: horaDeIngreso,
        ),
        Invitado(
          id: 'a-mano',
          eventoId: eventoMasivo,
          nombreCompleto: 'RUIZ, MARTA',
          dni: '',
          estadoIngreso: EstadoIngreso.pendiente,
        ),
      ],
    );

PedidoPendiente _pendiente(String id) => PedidoPendiente(
      PedidoPuerta(id: 'x$id', que: QuePide.ingresar, personaId: id),
      marcado: horaDeIngreso,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _ClienteDePrueba cliente;

  Future<void> abrir(WidgetTester tester) async {
    // Un celular.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: PantallaPuesto(cliente: cliente),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUp(() => cliente = _ClienteDePrueba());

  group('la primera vez', () {
    testWidgets('con el código del QR, pide solo el nombre', (tester) async {
      cliente
        ..e = EstadoDelPuesto.faltanDatos
        ..n = null;
      await abrir(tester);

      expect(find.text('¿Cómo te llamás?'), findsOneWidget);
      expect(find.text('Código de la PC (4 cifras)'), findsNothing);

      await tester.tap(find.text('EMPEZAR'));
      await tester.pump();
      expect(find.text('Escribí tu nombre.'), findsOneWidget);
      expect(cliente.datos, isEmpty);

      await tester.enterText(find.byType(TextField), 'Juli');
      await tester.tap(find.text('EMPEZAR'));
      await tester.pump();
      expect(cliente.datos, [('Juli', null)]);
    });

    testWidgets('con la dirección sola, pide también el código', (tester) async {
      cliente
        ..e = EstadoDelPuesto.faltanDatos
        ..n = null
        ..cod = null;
      await abrir(tester);

      final campos = find.byType(TextField);
      expect(campos, findsNWidgets(2));
      await tester.enterText(campos.first, 'Juli');
      await tester.enterText(campos.last, '48');
      await tester.tap(find.text('EMPEZAR'));
      await tester.pump();
      expect(find.textContaining('cuatro cifras'), findsOneWidget);
      expect(cliente.datos, isEmpty);

      await tester.enterText(campos.last, '4821');
      await tester.tap(find.text('EMPEZAR'));
      await tester.pump();
      expect(cliente.datos, [('Juli', '4821')]);
    });
  });

  group('con la lista', () {
    setUp(() => cliente.p = _lista());

    testWidgets('la lista de Recepción, con quién es y a qué evento',
        (tester) async {
      await abrir(tester);

      expect(find.text('RECEPCIÓN · JULI'), findsOneWidget);
      expect(find.text('ESCUELA DE MUESTRA — EGRESADOS (12/12) · MASIVO'),
          findsOneWidget);
      expect(find.text('Conectado a la PC'), findsOneWidget);
      expect(find.text('1 de 4 adentro'), findsOneWidget);
      expect(find.text('ACOSTA, LUCÍA'), findsOneWidget);
      expect(find.text('Mesa 14'), findsOneWidget);
      // Lo de la PC no va en el celular.
      expect(find.textContaining('sin internet'), findsNothing);
    });

    testWidgets('INGRESAR se lo pide a la central', (tester) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField), 'lucia');
      await tester.pump();
      await tester.tap(find.text('INGRESAR'));
      await tester.pump();
      expect(cliente.ingresados, [idInvitadoPuerta(_lucia, 0)]);
    });

    testWidgets('lo cargado a mano no se puede eliminar desde el celular',
        (tester) async {
      await abrir(tester);
      await tester.enterText(find.byType(TextField), 'ruiz');
      await tester.pump();
      expect(find.text('RUIZ, MARTA'), findsOneWidget);
      expect(find.byTooltip('Opciones'), findsNothing);
    });

    testWidgets('debajo de ADENTRO, quién lo ingresó', (tester) async {
      cliente.marcas = {idInvitadoPuerta(_juan, 0): 'Pato'};
      await abrir(tester);
      expect(find.textContaining('ADENTRO'), findsOneWidget);
      expect(find.text('Pato'), findsOneWidget);
    });

    testWidgets('lo que contesta la central se dice', (tester) async {
      await abrir(tester);
      cliente.avisosDePrueba.add('ACOSTA, LUCÍA ya ingresó a las 22:41 · Pato.');
      await tester.pump();
      expect(find.text('ACOSTA, LUCÍA ya ingresó a las 22:41 · Pato.'),
          findsOneWidget);
    });

    testWidgets('sin conexión: cuántos faltan mandar, y cuáles', (tester) async {
      cliente
        ..e = EstadoDelPuesto.sinConexion
        ..pend = [_pendiente('x'), _pendiente('y')]
        ..marcas = {idInvitadoPuerta(_juan, 0): kPorMandar};
      await abrir(tester);
      expect(find.text('Sin conexión con la PC · 2 por mandar'), findsOneWidget);
      expect(find.text('POR MANDAR'), findsOneWidget);
      // Se sigue pudiendo marcar.
      await tester.enterText(find.byType(TextField), 'lucia');
      await tester.pump();
      await tester.tap(find.text('INGRESAR'));
      await tester.pump();
      expect(cliente.ingresados, hasLength(1));
    });

    testWidgets('al volver, cuántos se mandaron', (tester) async {
      cliente.mandados = 3;
      await abrir(tester);
      expect(find.text('Conectado · se mandaron 3'), findsOneWidget);
    });

    testWidgets('"Actualizar la lista" vuelve a conectarse', (tester) async {
      await abrir(tester);
      await tester.tap(find.byTooltip('Más'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar la lista'));
      await tester.pumpAndSettle();
      expect(cliente.reconexiones, 1);
    });

    testWidgets('cambia al instante cuando el cliente avisa', (tester) async {
      await abrir(tester);
      expect(find.text('1 de 4 adentro'), findsOneWidget);
      cliente.marcas = {};
      final lucia = idInvitadoPuerta(_lucia, 0);
      cliente.p = PuertaDelEvento.masivo(
        alumnos: [
          alumnoDePrueba(_juan, 'PÉREZ, JUAN', mesas: [12], acomp: ['GÓMEZ, ANA']),
          alumnoDePrueba(_lucia, 'ACOSTA, LUCÍA', mesas: [14]),
        ],
        invitados: [
          Invitado(
            id: lucia,
            eventoId: eventoMasivo,
            nombreCompleto: 'ACOSTA, LUCÍA',
            dni: '',
            estadoIngreso: EstadoIngreso.ingresado,
            updatedAt: horaDeIngreso,
          ),
        ],
      );
      cliente.cambio();
      await tester.pump();
      await tester.pump();
      expect(find.text('1 de 3 adentro'), findsOneWidget);
    });
  });

  group('lo demás', () {
    testWidgets('sin la lista todavía, busca la PC y dice dónde', (tester) async {
      cliente.e = EstadoDelPuesto.conectando;
      await abrir(tester);
      expect(find.text('Buscando la PC central…'), findsOneWidget);
      expect(find.textContaining('wifi del router'), findsOneWidget);
    });

    testWidgets('código cambiado: pide el nuevo', (tester) async {
      cliente.e = EstadoDelPuesto.codigoMal;
      await abrir(tester);
      expect(find.text('El código no es el de la PC.'), findsOneWidget);
      final campos = find.byType(TextField);
      expect(campos, findsNWidgets(2));
      await tester.enterText(campos.last, '5555');
      await tester.tap(find.text('EMPEZAR'));
      await tester.pump();
      expect(cliente.datos, [('Juli', '5555')]);
    });

    testWidgets('otra pestaña: puede volver a usar esta', (tester) async {
      cliente.e = EstadoDelPuesto.otraPestana;
      await abrir(tester);
      expect(find.text('Este celular se abrió en otra pestaña.'), findsOneWidget);
      await tester.tap(find.text('USAR ESTA'));
      expect(cliente.reconexiones, 1);
    });

    testWidgets('frenado por errores: espera', (tester) async {
      cliente.e = EstadoDelPuesto.frenado;
      await abrir(tester);
      expect(find.text('Demasiados códigos equivocados.'), findsOneWidget);
    });
  });
}
