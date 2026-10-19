// Arnés manual: dibuja la pantalla del plano y los tres pasos de "Estilo y
// armado" con familias inventadas, y guarda PNG para mirarlos sin levantar la
// app ni tocar la base.
//
//   flutter test tool/plano_pantalla_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
//   • Pantalla_plano_<estilo>.png: la pantalla con una familia elegida;
//   • Pantalla_plano_faltan.png: un armado donde la fiesta no entra;
//   • Pantalla_plano_operario.png: la pantalla sin modo jefe;
//   • Pantalla_plano_aviso.png: el aviso de lo que pasó, al lado de los botones;
//   • Pantalla_plano_vacio.png: el salón vacío, antes de poner las mesas;
//   • Pasos_plano.png: la primera vez, con todo ya elegido (el salón vacío);
//   • Pasos_plano_trabado.png: con familias ya sentadas;
//   • Personalizar_*.png: una familia elegida con lo que se le puede hacer, el
//     momento de tocar a dónde se muda, la pestaña Medidas (como abre, y con
//     una distancia escrita sin guardar, en una notebook), la de Colores y
//     textos (con un color y un título probándose) y la de Acomodar (una mesa
//     agregada y corrida, con la regla; y la vista previa de separar);
//   • Acomodar_sector_manijas.png y Acomodar_playon_manijas.png: las manijas
//     del salón primero (6.1.0), sobre el salón vacío;
//   • Acomodar_mesas_puestas.png, Acomodar_faltan.png y Salon_vaciado.png:
//     ACOMODAR LAS MESAS y VACIAR EL SALÓN (6.1.0);
//   • Confirmar_cambio.png e Historial_mesas.png: los diálogos de un cambio.
//
// Los nombres son inventados: la muestra nunca usa datos reales.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/historial_sorteo.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/cambio_de_mesa_dialogs.dart';
import 'package:arguello_events/features/plano/widgets/elegir_plano_dialog.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'BENÍTEZ', 'CASTRO', 'DOMÍNGUEZ', 'ESPÍNDOLA', 'FERREYRA', 'GÓMEZ',
  'HERRERA', 'IBARRA', 'JUÁREZ', 'LEDESMA', 'MOLINA', 'NÚÑEZ', 'ORTIZ',
  'PAREDES', 'QUIROGA', 'RAMÍREZ', 'SOSA', 'TORRES', 'VEGA',
];
const _nombres = [
  'VALENTINA', 'JOAQUÍN', 'MÍA', 'BRUNO', 'CAMILA', 'LUCAS', 'SOFÍA', 'TOMÁS',
];

/// Una escuela inventada que llena [mesas] mesas en tres divisiones, con
/// familias de una y de dos mesas y algunas sillas extra. Con [sorteada] en
/// false nadie tiene mesa todavía.
List<ContratoAlumno> _escuela(int mesas, {bool sorteada = true}) {
  final r = Random(11);
  final alumnos = <ContratoAlumno>[];
  var n = 1;
  var k = 0;
  while (n <= mesas) {
    final dos = n < mesas && r.nextInt(6) == 0;
    final sillas = r.nextInt(14) == 0 ? 1 + r.nextInt(2) : 0;
    final numeros = dos ? [n, n + 1] : [n];
    alumnos.add(ContratoAlumno(
      id: 'f$k',
      eventoId: 'e',
      nombreAlumno: '${_apellidos[k % _apellidos.length]}, '
          '${_nombres[(k * 3) % _nombres.length]}',
      cantidadAcompanantes: 2 + r.nextInt(6),
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: dos ? 70000 : 0,
      mesaExtraCantidad: dos ? 1 : 0,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          sorteada ? MesasExtraUtils.formatearAsignacionMesas(numeros) : null,
      cursoDivision: n <= mesas / 3
          ? '5° A'
          : n <= 2 * mesas / 3
              ? '5° B'
              : '5° C',
    ));
    n += numeros.length;
    k++;
  }
  return alumnos;
}

late String _carpeta;

Future<void> _guardar(
  WidgetTester tester,
  Widget pantalla,
  Size tam,
  String archivo, {
  Future<void> Function()? antes,
}) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: FuentesPlano.linea,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: RepaintBoundary(key: clave, child: pantalla),
    ),
  );
  await tester.pump();
  // Lo que haya que tocar antes de la foto (prender Personalizar, elegir).
  if (antes != null) {
    await antes();
    await tester.pump();
    // Un botón que se prende cambia de color de a poco: se espera a que
    // termine, para que la foto no salga a mitad de camino.
    await tester.pump(const Duration(milliseconds: 400));
  }
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_carpeta${Platform.pathSeparator}$archivo')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

Widget _pantalla(
  ArmadoSalon armado,
  List<ContratoAlumno> alumnos,
  EstiloPlano estilo, {
  String? resaltar,
  AccionesPlano? acciones,
  ConfigPlano config = ConfigPlano.vacia,
  bool soloJefe = false,
  AvisoDelPlano? aviso,
}) =>
    Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plano del salón'),
            Text(
              'Escuela Normal (datos inventados)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: PlanoEventoCuerpo(
        plano: PlanoDeLaFiesta.desde(
          armado: armado,
          config: config,
          alumnos: alumnos,
        ),
        estilo: estilo,
        alumnos: alumnos,
        resaltarAlumnoId: resaltar,
        onEstiloYArmado: soloJefe ? null : () {},
        acciones: soloJefe ? null : acciones,
        onImprimir: soloJefe || aviso != null ? () {} : null,
        onHistorial: () {},
        soloJefe: soloJefe,
        aviso: aviso,
      ),
    );

/// Acciones que no hacen nada: la muestra solo dibuja.
final _sinHacer = AccionesPlano(
  onFijarEnMesa: (_) {},
  onFijar: (_, _) {},
  onQuitarFijadas: (_) {},
  onQuitarFijadaDeMesa: (_) {},
  onDejarLibre: (_) {},
  onVolverAUsar: (_) {},
  onCambiar: (_, _) {},
  onMover: (_, _) {},
  onGuardarMedidas: (_, _) {},
  onGuardarColoresYTextos: (_, _) {},
  onGuardarArmado: (_, _, _, _) {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await cargarFuentesPlano();
    // Los íconos de Material, que `flutter test` tampoco carga solo.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    _carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('plano_pantalla').path;
  });

  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
  ).armado;
  final escuela = _escuela(132);
  // Una familia con dos mesas y sillas extra, para ver su tarjeta.
  final elegida = escuela.firstWhere(
    (a) => a.mesaExtraCantidad > 0 && a.sillasExtraCantidad > 0,
    orElse: () => escuela.firstWhere((a) => a.mesaExtraCantidad > 0),
  );

  for (final e in EstiloPlano.values) {
    testWidgets('la pantalla del plano, en ${e.nombre}', (tester) async {
      await _guardar(
        tester,
        _pantalla(aMedida, escuela, e, resaltar: elegida.id),
        const Size(1440, 900),
        'Pantalla_plano_${e.name}.png',
      );
      // Queda corriendo el pulso de la familia resaltada.
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('la pantalla del plano, sin modo jefe', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        aMedida,
        escuela,
        EstiloPlano.arquitecto,
        resaltar: elegida.id,
        soloJefe: true,
      ),
      const Size(1440, 900),
      'Pantalla_plano_operario.png',
    );
    // Queda corriendo el pulso de la familia resaltada.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la pantalla con el aviso de lo que pasó', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        aMedida,
        escuela,
        EstiloPlano.arquitecto,
        acciones: _sinHacer,
        aviso: AvisoDelPlano(
          'ACOSTA pasó a la 60 y la 61.',
          accion: 'DESHACER',
          onAccion: () {},
        ),
      ),
      const Size(1366, 768),
      'Pantalla_plano_aviso.png',
    );
  });

  testWidgets('la pantalla cuando la fiesta no entra en el armado',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        ArmadosPredefinidos.normal2aPaginas45(),
        _escuela(132, sorteada: false),
        EstiloPlano.arquitecto,
      ),
      const Size(1440, 900),
      'Pantalla_plano_faltan.png',
    );
  });

  // 6.1.0, "el salón primero": lo que queda al tocar LISTO la primera vez.
  testWidgets('la pantalla con el salón vacío', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        ArmarAMedida.vacio(PlayonReal.costaSurubi),
        _escuela(132, sorteada: false),
        EstiloPlano.arquitecto,
        acciones: _sinHacer,
      ),
      const Size(1440, 900),
      'Pantalla_plano_vacio.png',
    );
  });

  testWidgets('los tres pasos, la primera vez', (tester) async {
    await _guardar(
      tester,
      const Scaffold(
        backgroundColor: Color(0xFF5F6368),
        body: ElegirPlanoDialog(
          mesasNecesarias: 132,
          medidas: MedidasPlano(),
        ),
      ),
      const Size(1200, 1000),
      'Pasos_plano.png',
    );
  });

  testWidgets('personalizar: una familia elegida y lo que se le puede hacer',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        aMedida,
        escuela,
        EstiloPlano.arquitecto,
        resaltar: elegida.id,
        acciones: _sinHacer,
      ),
      const Size(1440, 900),
      'Personalizar_familia.png',
      antes: () => tester.tap(find.byKey(const Key('personalizar'))),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: la pestaña Medidas', (tester) async {
    await _guardar(
      tester,
      _pantalla(aMedida, escuela, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1440, 900),
      'Personalizar_medidas.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('pestana_medidas')));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Medidas con una distancia sin guardar, en una '
      'notebook', (tester) async {
    await _guardar(
      tester,
      _pantalla(aMedida, escuela, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1366, 768),
      'Personalizar_medidas_probando.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('pestana_medidas')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('medida_lugar')), '2,3');
        await tester.pump();
        // Querer salir sin guardar: la franja dice qué falta.
        await tester.tap(find.byKey(const Key('salir_personalizar')));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final e in [EstiloPlano.arquitecto, EstiloPlano.gala]) {
    testWidgets('personalizar: Colores y textos, en ${e.nombre}',
        (tester) async {
      await _guardar(
        tester,
        _pantalla(aMedida, escuela, e, acciones: _sinHacer),
        const Size(1440, 900),
        'Personalizar_colores_${e.name}.png',
        antes: () async {
          await tester.tap(find.byKey(const Key('personalizar')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('pestana_colores')));
          await tester.pump();
          final division = tester
              .widgetList<InkWell>(find.byWidgetPredicate((w) =>
                  w is InkWell &&
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('color_') &&
                  (w.key! as ValueKey<String>).value.endsWith('_4')))
              .first;
          await tester.tap(find.byKey(division.key!));
          await tester.pump();
          await tester.enterText(
              find.byKey(const Key('texto_titulo')), 'Egresados 2026');
          await tester.pump();
          await tester.enterText(find.byKey(const Key('texto_subtitulo')),
              'Predio Costa Surubí');
        },
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('personalizar: Acomodar, con una mesa agregada y corrida',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(aMedida, escuela, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1440, 900),
      'Personalizar_acomodar.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('pestana_acomodar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('acomodar_agregar')));
        await tester.pump();
        // Se la corre un poco, como con el mouse: queda con la regla.
        final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
        final caja = tester.getRect(find.byType(VistaPlano));
        final m = vista.armado.mesas.last;
        final encuadre =
            EncuadrePlano.de(vista.armado.hoja(m.hoja)!.caja, caja.size);
        final gesto = await tester.startGesture(
          caja.topLeft + encuadre.aPantalla(Offset(m.x, m.y)),
        );
        await tester.pump();
        await gesto.moveBy(
          const Offset(0.5, 2.5) * vista.armado.aUnidades(1) * encuadre.escala,
        );
        await tester.pump();
        await gesto.up();
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  // 6.1.0, "el salón primero": las manijas, sobre el salón vacío.
  Future<void> abrirAcomodar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('personalizar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pestana_acomodar')));
    await tester.pump();
  }

  /// Dónde cae en la pantalla un punto del plano (hoja A, sin zoom).
  Offset enPantalla(WidgetTester tester, Offset p) {
    final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
    final caja = tester.getRect(find.byType(VistaPlano));
    return caja.topLeft +
        EncuadrePlano.de(vista.armado.hoja('A')!.caja, caja.size).aPantalla(p);
  }

  /// Arrastra desde un punto del plano [metros] para un lado.
  Future<void> arrastrar(WidgetTester tester, Offset desde, Offset metros) async {
    final vista = tester.widget<VistaPlano>(find.byType(VistaPlano));
    final caja = tester.getRect(find.byType(VistaPlano));
    final escala =
        EncuadrePlano.de(vista.armado.hoja('A')!.caja, caja.size).escala;
    final gesto = await tester.startGesture(enPantalla(tester, desde));
    await tester.pump();
    final total = metros * vista.armado.aUnidades(1) * escala;
    for (var i = 0; i < 4; i++) {
      await gesto.moveBy(total / 4);
      await tester.pump();
    }
    await gesto.up();
    await tester.pump();
  }

  final vacio = ArmarAMedida.vacio(PlayonReal.costaSurubi);
  final sinSortear = _escuela(132, sorteada: false);

  testWidgets('personalizar: Acomodar, un sector con sus manijas',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(vacio, sinSortear, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1440, 900),
      'Acomodar_sector_manijas.png',
      antes: () async {
        await abrirAcomodar(tester);
        final a = tester.widget<VistaPlano>(find.byType(VistaPlano)).armado;
        final c = a.sectores
            .firstWhere((s) => s.tipo == TipoSector.escenario)
            .caja;
        await tester.tapAt(enPantalla(tester, Offset(c.centroX, c.centroY)));
        await tester.pump();
        // Se lo achica de un lado, como con el mouse: el rótulo dice cuánto
        // mide.
        await arrastrar(
            tester, Offset(c.derecha, c.centroY), const Offset(-6, 0));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Acomodar, el playón con sus manijas',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(vacio, sinSortear, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1440, 900),
      'Acomodar_playon_manijas.png',
      antes: () async {
        await abrirAcomodar(tester);
        final a = tester.widget<VistaPlano>(find.byType(VistaPlano)).armado;
        final p = a.hoja('A')!.contorno!.puntos;
        // Se toca el piso, y la esquina de abajo a la derecha se corre: un
        // predio que no es parejo.
        await tester.tapAt(enPantalla(
          tester,
          Offset(p[3].x * 0.7 + p[2].x * 0.3, p[3].y - a.aUnidades(4)),
        ));
        await tester.pump();
        await arrastrar(tester, Offset(p[2].x, p[2].y), const Offset(-4, -3));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  // 6.1.0, etapa 4: ACOMODAR LAS MESAS y VACIAR EL SALÓN.
  Future<void> tocar(WidgetTester tester, String clave) async {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.pump();
    await tester.tap(find.byKey(Key(clave)));
    await tester.pump();
  }

  /// El salón vacío con una pista de 10 × 10 m en el medio.
  final conPista = () {
    final b = vacio.hojas.first.contorno!.puntos;
    final cx = (b[0].x + b[1].x) / 2;
    return vacio.copyWith(sectores: [
      ...vacio.sectores,
      SectorPlano(
        tipo: TipoSector.pista,
        texto: 'Pista',
        hoja: 'A',
        caja: RectPlano(
          cx - vacio.aUnidades(5),
          b[0].y + vacio.aUnidades(20),
          vacio.aUnidades(10),
          vacio.aUnidades(10),
        ),
      ),
    ]);
  }();

  testWidgets('personalizar: Acomodar, las mesas puestas alrededor de la pista',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(conPista, sinSortear, EstiloPlano.arquitecto,
          acciones: _sinHacer),
      const Size(1440, 900),
      'Acomodar_mesas_puestas.png',
      antes: () async {
        await abrirAcomodar(tester);
        await tocar(tester, 'acomodar_mesas');
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Acomodar, en un playón chico faltan mesas',
      (tester) async {
    const playonChico = PlayonReal(frenteM: 22, fondoM: 26, profundidadM: 24);
    final chico = ArmarAMedida.vacio(playonChico);
    await _guardar(
      tester,
      _pantalla(
        chico,
        sinSortear,
        EstiloPlano.arquitecto,
        acciones: _sinHacer,
        config: const ConfigPlano(medidas: MedidasPlano(playon: playonChico)),
      ),
      const Size(1440, 900),
      'Acomodar_faltan.png',
      antes: () async {
        await abrirAcomodar(tester);
        await tocar(tester, 'acomodar_mesas');
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Acomodar, el salón vaciado, con lo que se quita '
      'al guardar', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        aMedida,
        sinSortear,
        EstiloPlano.arquitecto,
        acciones: _sinHacer,
        config: ConfigPlano(
          fijadas: {5: MesaFijada(alumnoId: sinSortear.first.id)},
          libres: const {40: MesaLibre()},
        ),
      ),
      const Size(1440, 900),
      'Salon_vaciado.png',
      antes: () async {
        await abrirAcomodar(tester);
        await tocar(tester, 'vaciar_salon');
        // El panel baja hasta "Antes de guardar".
        await tester.ensureVisible(find.textContaining('Al guardar se quitan'));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Acomodar, la vista previa de separar',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(aMedida, escuela, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1366, 768),
      'Personalizar_separar.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('pestana_acomodar')));
        await tester.pump();
        tester
            .widget<Slider>(find.byKey(const Key('separar_paso')))
            .onChanged!(2.4);
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: Acomodar, los avisos antes de guardar, en una '
      'notebook', (tester) async {
    await _guardar(
      tester,
      _pantalla(aMedida, escuela, EstiloPlano.arquitecto, acciones: _sinHacer),
      const Size(1366, 768),
      'Personalizar_acomodar_avisos.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('pestana_acomodar')));
        await tester.pump();
        // Se separa todo el salón: algunas mesas ya no entran en el hormigón.
        tester
            .widget<Slider>(find.byKey(const Key('separar_paso')))
            .onChanged!(2.6);
        await tester.pump();
        await tester.tap(find.byKey(const Key('separar_aplicar')));
        await tester.pump();
        // Se toca el aviso: va a la primera de esas mesas.
        await tester.ensureVisible(find.byKey(const Key('aviso_acomodar_0')));
        await tester.pump();
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('personalizar: tocar a dónde se muda la familia', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        aMedida,
        escuela,
        EstiloPlano.arquitecto,
        resaltar: elegida.id,
        acciones: _sinHacer,
      ),
      const Size(1440, 900),
      'Personalizar_mover.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('personalizar')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('accion_mover')));
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el diálogo que confirma un cambio', (tester) async {
    await _guardar(
      tester,
      const Scaffold(
        backgroundColor: Color(0xFF5F6368),
        body: ConfirmarCambioDialog(
          titulo: 'ACOSTA y BENÍTEZ cambian de lugar',
          renglones: [
            'ACOSTA: 44, 45 → 12, 13',
            'BENÍTEZ: 12, 13 → 44, 45',
          ],
          avisos: [
            'Son de divisiones distintas: 5° B y 5° A.',
            'BENÍTEZ ya retiró sus entradas: hay que avisarle y reimprimir la '
                'planilla de entrega.',
          ],
          sugerencias: motivosParaCambiar,
          hayQueAvisarALaFamilia: true,
          textoConfirmar: 'CAMBIAR',
        ),
      ),
      const Size(760, 620),
      'Confirmar_cambio.png',
    );
  });

  testWidgets('el Historial de las mesas', (tester) async {
    final sorteo = DateTime.utc(2026, 11, 13, 0, 40);
    final a = escuela[0];
    final b = escuela[1];
    final c = escuela[2];
    final historial = HistorialSorteo.armar(
      registros: [
        SorteoMesasRegistro(
          id: 's1',
          eventoId: 'e',
          tipo: TipoRegistroSorteo.sorteo,
          resultado: {
            for (final x in escuela)
              x.id: x.id == a.id
                  ? '90'
                  : x.id == c.id
                      ? '77'
                      : (x.numeroMesa ?? ''),
          },
          hechoPor: 'Jefe',
          createdAt: sorteo,
        ),
      ],
      movimientos: [
        MovimientoMesas(
          id: 'm1',
          eventoId: 'e',
          tipo: TipoMovimientoMesas.mover,
          antes: {a.id: '90'},
          despues: {a.id: a.numeroMesa},
          motivo: 'Movilidad reducida',
          hechoPor: 'Operador',
          createdAt: sorteo.add(const Duration(days: 2, hours: 14)),
        ),
      ],
      config: ConfigPlano(
        fijadas: {
          for (final n in CambiosDeMesa.numerosDe(b))
            n: MesaFijada(
              alumnoId: b.id,
              motivo: 'Cerca del ingreso',
              por: 'Jefe',
              cuando: sorteo.subtract(const Duration(days: 3)),
            ),
        },
        libres: {
          120: MesaLibre(
            motivo: 'Columna',
            por: 'Jefe',
            cuando: sorteo.subtract(const Duration(days: 3, hours: 1)),
          ),
        },
      ),
      alumnos: escuela,
    );
    await _guardar(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF5F6368),
        body: HistorialSorteoDialog(historial: historial, onDeshacer: (_) {}),
      ),
      const Size(820, 760),
      'Historial_mesas.png',
    );
  });

  testWidgets('los tres pasos, con familias ya sentadas', (tester) async {
    final plano = PlanoEvento.nuevo(
      eventoId: 'e0000000-0000-4000-8000-000000000001',
      armado: aMedida,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.bloques,
      ahora: DateTime.utc(2026, 10, 1),
    );
    await _guardar(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF5F6368),
        body: ElegirPlanoDialog(
          mesasNecesarias: 132,
          medidas: const MedidasPlano(),
          actual: plano,
          ocupantes: PlanoDeLaFiesta.ocupantes(escuela, const {}),
          armadoTrabado: 'Ya hay familias con mesa: para cambiar el armado hay '
              'que deshacer el sorteo. El estilo se cambia siempre.',
        ),
      ),
      const Size(1200, 1000),
      'Pasos_plano_trabado.png',
    );
  });
}
