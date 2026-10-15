// Arnés manual: la ventana "Sumar un celular" de la PC y la pantalla del
// celular de la puerta, con datos inventados, en PNG para mirarlas sin
// levantar la app (sección 7 de la 6.0.0).
//
//   flutter test tool/celulares_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - Celulares_1_PC_ventana.png: el QR, la dirección y el código, con dos
//   celulares (uno sin señal).
// - Celulares_2_PC_sin_router.png: la PC sin conexión a ningún router.
// - Celulares_3_celular_primera_vez.png: pide el nombre.
// - Celulares_4_celular_lista.png: la lista, con quién ingresó a cada uno.
// - Celulares_5_celular_sin_conexion.png: sin la PC, "2 por mandar".
// - Celulares_6_celular_ya_ingreso.png: lo que dice la central cuando otro
//   celular ya lo había ingresado.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_puesto.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/widgets/sumar_celular.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/invitado.dart';

import '../test/helpers/cliente_de_prueba.dart';
import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

class _CentralFija extends CentralDeLaPuerta {
  _CentralFija(this.fijo);
  final EstadoCentral fijo;

  @override
  EstadoCentral build() => fijo;

  @override
  Future<void> prender(String eventoId) async {}
}

final _familias = [
  ('PÉREZ, JUAN MARTÍN', ['GÓMEZ, ANA', 'PÉREZ, LUIS'], 'Tusa · Karol G'),
  ('ACOSTA, LUCÍA', <String>[], 'Despechá · Rosalía'),
  ('BENÍTEZ, TOMÁS', ['BENÍTEZ, SOL'], null),
  ('FERNÁNDEZ, MÍA', ['FERNÁNDEZ, JUAN'], 'Ella · Callejero Fino'),
  ('GARCÍA, BRUNO', <String>[], null),
];

String _id(int i) => 'c${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000';

/// Una institución sorteada; [adentro] son los índices que ya entraron.
PuertaDelEvento _lista({Set<int> adentro = const {}}) {
  final alumnos = [
    for (var i = 0; i < _familias.length; i++)
      alumnoDePrueba(
        _id(i),
        _familias[i].$1,
        mesas: [10 + i],
        sillas: i.isEven ? 2 : 0,
        acomp: _familias[i].$2,
        musica: _familias[i].$3,
        division: '5° A',
      ),
  ];
  return PuertaDelEvento.masivo(
    alumnos: alumnos,
    invitados: [
      for (final i in adentro)
        Invitado(
          id: idInvitadoPuerta(_id(i), 0),
          eventoId: eventoMasivo,
          nombreCompleto: _familias[i].$1,
          dni: '',
          estadoIngreso: EstadoIngreso.ingresado,
          updatedAt: horaDeIngreso,
        ),
    ],
  );
}

Future<void> _guardar(
  WidgetTester tester,
  GlobalKey clave,
  String nombre,
  String carpeta,
) async {
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$carpeta${Platform.pathSeparator}$nombre')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('celulares_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  setUpAll(() async {
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    final regular = FontLoader('Outfit_regular')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'));
    await regular.load();
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();
    await cargarFuentesTotem();
  });

  Future<GlobalKey> pc(WidgetTester tester, EstadoCentral estado) async {
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(720, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          centralDeLaPuertaProvider.overrideWith(() => _CentralFija(estado)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: RepaintBoundary(
            key: clave,
            child: const ColoredBox(
              color: Color(0xFF0E0E11),
              child: Center(child: VentanaSumarCelular(eventoId: eventoMasivo)),
            ),
          ),
        ),
      ),
    );
    await _asentar(tester);
    expect(tester.takeException(), isNull);
    return clave;
  }

  Future<GlobalKey> celular(WidgetTester tester, ClienteDePrueba c) async {
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: RepaintBoundary(key: clave, child: PantallaPuesto(cliente: c)),
      ),
    );
    await _asentar(tester);
    expect(tester.takeException(), isNull);
    return clave;
  }

  testWidgets('la ventana de la PC', (tester) async {
    final ahora = DateTime.now();
    final clave = await pc(
      tester,
      EstadoCentral(
        eventoId: eventoMasivo,
        codigo: '4821',
        puerto: kPuertoCentral,
        direcciones: const ['192.168.0.10'],
        puestos: [
          PuestoConectado(
            celular: 'a',
            nombre: 'Juli',
            conectado: true,
            ultimaVez: ahora,
            marcados: 41,
          ),
          PuestoConectado(
            celular: 'b',
            nombre: 'Pato',
            conectado: true,
            ultimaVez: ahora,
            marcados: 18,
          ),
          PuestoConectado(
            celular: 'c',
            nombre: 'Mati',
            conectado: false,
            ultimaVez: ahora.subtract(const Duration(minutes: 3)),
            marcados: 2,
          ),
        ],
      ),
    );
    await _guardar(tester, clave, 'Celulares_1_PC_ventana.png', carpeta);
  });

  testWidgets('la PC sin router', (tester) async {
    final clave = await pc(
      tester,
      const EstadoCentral(
        eventoId: eventoMasivo,
        codigo: '4821',
        puerto: kPuertoCentral,
      ),
    );
    await _guardar(tester, clave, 'Celulares_2_PC_sin_router.png', carpeta);
  });

  testWidgets('el celular, la primera vez', (tester) async {
    final c = ClienteDePrueba()
      ..e = EstadoDelPuesto.faltanDatos
      ..n = null;
    final clave = await celular(tester, c);
    await _guardar(tester, clave, 'Celulares_3_celular_primera_vez.png', carpeta);
  });

  testWidgets('el celular, con la lista', (tester) async {
    final c = ClienteDePrueba()
      ..p = _lista(adentro: {1, 2})
      ..marcas = {
        idInvitadoPuerta(_id(1), 0): 'Juli',
        idInvitadoPuerta(_id(2), 0): 'Pato',
      };
    final clave = await celular(tester, c);
    await _guardar(tester, clave, 'Celulares_4_celular_lista.png', carpeta);
  });

  testWidgets('el celular, sin conexión', (tester) async {
    PedidoPendiente pend(int i) => PedidoPendiente(
          PedidoPuerta(
            id: 'x$i',
            que: QuePide.ingresar,
            personaId: idInvitadoPuerta(_id(i), 0),
          ),
          marcado: horaDeIngreso,
        );
    final c = ClienteDePrueba()
      ..e = EstadoDelPuesto.sinConexion
      ..p = _lista(adentro: {1, 2, 3})
      ..pend = [pend(2), pend(3)]
      ..marcas = {
        idInvitadoPuerta(_id(1), 0): 'Juli',
        idInvitadoPuerta(_id(2), 0): kPorMandar,
        idInvitadoPuerta(_id(3), 0): kPorMandar,
      };
    final clave = await celular(tester, c);
    await _guardar(tester, clave, 'Celulares_5_celular_sin_conexion.png', carpeta);
  });

  testWidgets('el celular, ya ingresó', (tester) async {
    final c = ClienteDePrueba()
      ..p = _lista(adentro: {4})
      ..marcas = {idInvitadoPuerta(_id(4), 0): 'Juli'};
    final clave = await celular(tester, c);
    await tester.enterText(find.byType(TextField), 'garcia');
    await tester.pump();
    c.avisosDePrueba.add('GARCÍA, BRUNO ya ingresó a las 22:41 · Juli.');
    await _asentar(tester);
    await _guardar(tester, clave, 'Celulares_6_celular_ya_ingreso.png', carpeta);
  });
}
