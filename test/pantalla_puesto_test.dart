// La pantalla del celular de la puerta (`PantallaPuesto`), entera, con un
// cliente de mentira al que la prueba le pone cada estado: la primera vez, la
// lista, sin conexión, el código cambiado.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_puesto.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/invitado.dart';

import 'helpers/cliente_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

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

  late ClienteDePrueba cliente;

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

  setUp(() => cliente = ClienteDePrueba());

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
  group('las sillas y los segundos desde el celular', () {
    testWidgets('SUMAR SILLA se lo pide a la central, con el vale y la mesa',
        (tester) async {
      cliente.p = _lista();
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('sumar_silla_$_lucia')));
      await tester.pumpAndSettle();
      expect(find.text('Queda anotada a nombre de Juli.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vale')), '2 0017');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_silla')));
      await tester.pumpAndSettle();

      final (que, persona, datos) = cliente.sillasPedidas.single;
      expect(que, QuePide.sumarSilla);
      expect(persona, idInvitadoPuerta(_lucia, 0));
      expect(datos.mesa, 14);
      expect(datos.vale, '2 0017');
      expect(
        find.text('Se mandó a la central: aparece en la lista en un momento.'),
        findsOneWidget,
      );
    });

    testWidgets('sin conexión, la silla queda para mandar y lo dice',
        (tester) async {
      cliente
        ..p = _lista()
        ..e = EstadoDelPuesto.sinConexion;
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('sumar_silla_$_lucia')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('vale')), '2 0017');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar_silla')));
      await tester.pumpAndSettle();
      expect(cliente.sillasPedidas, hasLength(1));
      final porMandar = tester.widget<Text>(
          find.text('Sin conexión con la central: se manda sola al volver.'));
      expect(porMandar.style!.color, const Color(0xFFFBBF24),
          reason: 'es un aviso, no algo hecho: en ámbar, no en verde');

      // Al volver la conexión, la central la confirma y eso es lo que queda.
      cliente.hechosDePrueba
          .add('Silla sumada a la mesa 14 de ACOSTA, LUCÍA.');
      // El aviso llega por un stream: se dibuja en el cuadro siguiente.
      await tester.pump();
      await tester.pump();
      final hecho =
          tester.widget<Text>(find.text('Silla sumada a la mesa 14 de ACOSTA, LUCÍA.'));
      expect(hecho.style!.color, const Color(0xFF4ADE80));
      expect(
        find.text('Sin conexión con la central: se manda sola al volver.'),
        findsNothing,
      );
    });

    testWidgets('el reloj cambia los segundos de la tele por la central',
        (tester) async {
      cliente
        ..p = _lista()
        ..tie = TiemposAMano(nombre: 4, camino: 8);
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('reloj_del_celular')));
      await tester.pumpAndSettle();
      expect(find.text('LA LLEGADA · ESTA NOCHE'), findsOneWidget);
      expect(find.text('4 s'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mas_nombre')));
      await tester.pump();
      expect(cliente.tiemposPedidos, [TiemposAMano(nombre: 5, camino: 8)]);
      expect(find.text('5 s'), findsOneWidget);
    });

    testWidgets('sin conexión, el reloj no deja cambiar y dice por qué',
        (tester) async {
      cliente
        ..p = _lista()
        ..tie = TiemposAMano(nombre: 4, camino: 8)
        ..e = EstadoDelPuesto.sinConexion;
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('reloj_del_celular')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin conexión con la PC: los segundos'),
          findsOneWidget);
      final mas = tester.widget<IconButton>(find.byKey(const ValueKey('mas_nombre')));
      expect(mas.onPressed, isNull);
    });

    testWidgets('sin los segundos de la PC (una PC de antes), no hay reloj',
        (tester) async {
      cliente.p = _lista();
      await abrir(tester);
      expect(find.byKey(const ValueKey('reloj_del_celular')), findsNothing);
    });
  });
}
