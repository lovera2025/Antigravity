// Arnés manual: dibuja el plano en los tres estilos, con familias inventadas,
// y guarda PNG para mirarlos sin levantar la app ni tocar la base.
//
//   flutter test tool/plano_muestra_test.dart
//   flutter test tool/plano_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen:
//   • Plano_3_estilos.png: la página 3 en Gala, Arquitecto y Neón, lado a lado;
//   • un PNG por estilo y armado (página 3, páginas 4-5, 2A+2B y Técnica);
//   • con una familia resaltada, mesas libres, una fijada y el pasto.
//
// Los nombres son inventados: la muestra nunca usa datos reales.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'BENÍTEZ', 'CASTRO', 'DOMÍNGUEZ', 'ESPÍNDOLA', 'FERREYRA', 'GÓMEZ',
  'HERRERA', 'IBARRA', 'JUÁREZ', 'LEDESMA', 'MOLINA', 'NÚÑEZ', 'ORTIZ',
  'PAREDES', 'QUIROGA', 'RAMÍREZ', 'SOSA', 'TORRES', 'VEGA',
];
const _nombres = [
  'VALENTINA', 'JOAQUÍN', 'MÍA', 'BRUNO', 'CAMILA', 'LUCAS', 'SOFÍA', 'TOMÁS',
];

/// Familias inventadas que llenan [bloques] (división → rango de mesas), con
/// familias de 1 y de 2 mesas y algunas sillas extra.
List<OcupantePlano> _familias(
  List<(String, int, int)> bloques, {
  Set<int> saltear = const {},
  int semilla = 7,
}) {
  final r = Random(semilla);
  final lista = <OcupantePlano>[];
  var k = 0;
  for (final (division, desde, hasta) in bloques) {
    var n = desde;
    while (n <= hasta) {
      if (saltear.contains(n)) {
        n++;
        continue;
      }
      final dos = n < hasta && !saltear.contains(n + 1) && r.nextInt(5) == 0;
      final numeros = dos ? [n, n + 1] : [n];
      final extras = r.nextInt(6) == 0 ? 1 + r.nextInt(2) : 0;
      lista.add(OcupantePlano(
        id: 'f$k',
        nombre: '${_apellidos[k % _apellidos.length]}, '
            '${_nombres[(k * 3) % _nombres.length]}',
        numeros: numeros,
        division: division,
        sillasExtraPorMesa: extras > 0 ? {n: extras} : const {},
      ));
      k++;
      n += numeros.length;
    }
  }
  return lista;
}

class _Caso {
  final String nombre;
  final ArmadoSalon armado;
  final EstadoPlano estado;
  final Set<int> resaltadas;
  const _Caso(this.nombre, this.armado, this.estado, this.resaltadas);
}

List<_Caso> _casos() {
  final p3 = ArmadosPredefinidos.normal2aPagina3();
  final fija = OcupantePlano(
    id: 'fija',
    nombre: 'RÍOS, MATEO',
    numeros: const [60],
    division: '5° C',
  );
  final familiasP3 = _familias(
    [('5° A', 1, 20), ('5° B', 21, 40), ('5° C', 41, 59), ('5° D', 61, 75)],
  );
  final resaltadaP3 = familiasP3.firstWhere((f) => f.numeros.length == 2);

  final p45 = ArmadosPredefinidos.normal2aPaginas45();
  final familiasP45 = _familias([
    ('5° A', 1, 24),
    ('5° B', 25, 49),
    ('5° C', 52, 54),
    ('5° D', 55, 80),
    ('5° E', 81, 100),
  ]);

  final dosHojas = ArmadosPredefinidos.normal2a2b();
  final familias2b = _familias([
    ('5° A', 1, 24),
    ('5° B', 25, 49),
    ('5° C', 52, 80),
    ('5° D', 81, 100),
    ('5° E', 101, 132),
  ]);

  final tecnica = ArmadosPredefinidos.tecnica1a1b();
  // Entera: las divisiones mezcladas, como sale hoy el sorteo sin bloques.
  final r = Random(3);
  final mezcla = _familias([('X', 1, 98)], semilla: 11)
      .map((f) => OcupantePlano(
            id: f.id,
            nombre: f.nombre,
            numeros: f.numeros,
            division: ['6° A', '6° B', '6° C', '6° D'][r.nextInt(4)],
            sillasExtraPorMesa: f.sillasExtraPorMesa,
          ))
      .toList();

  return [
    _Caso(
      'normal_p3',
      p3,
      EstadoPlano.desde(
        armado: p3,
        ocupantes: familiasP3,
        libres: {76, 77, 78},
        fijadas: {60: fija},
      ),
      resaltadaP3.numeros.toSet(),
    ),
    _Caso(
      'normal_p45',
      p45,
      EstadoPlano.desde(armado: p45, ocupantes: familiasP45, libres: {50, 51}),
      const {},
    ),
    _Caso(
      'normal_2a2b',
      dosHojas,
      EstadoPlano.desde(
        armado: dosHojas,
        ocupantes: familias2b,
        libres: {50, 51},
      ),
      const {},
    ),
    _Caso(
      'tecnica',
      tecnica,
      EstadoPlano.desde(armado: tecnica, ocupantes: mezcla),
      const {},
    ),
  ];
}

Future<void> _guardar(
  WidgetTester tester,
  Widget widget,
  Size tam,
  String archivo,
) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam * 2;
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(key: clave, child: widget),
      ),
    ),
  );
  await tester.pump();
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

late String _carpeta;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await cargarFuentesPlano();
    _carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('plano_muestra').path;
  });

  testWidgets('los tres estilos lado a lado (página 3)', (tester) async {
    final caso = _casos().first;
    await _guardar(
      tester,
      Container(
        color: const Color(0xFF202124),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            for (final e in EstiloPlano.values) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.nombre} · ${e.descripcion}',
                      style: const TextStyle(
                        fontFamily: FuentesPlano.linea,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: VistaPlano(
                          armado: caso.armado,
                          hoja: 'A',
                          tema: TemaPlano.de(e),
                          estado: caso.estado,
                          resaltadas: caso.resaltadas,
                          animar: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (e != EstiloPlano.values.last) const SizedBox(width: 16),
            ],
          ],
        ),
      ),
      const Size(2100, 560),
      'Plano_3_estilos.png',
    );
  });

  for (final e in EstiloPlano.values) {
    testWidgets('${e.name}: cada armado y cada hoja', (tester) async {
      for (final caso in _casos()) {
        for (final h in caso.armado.hojas) {
          await _guardar(
            tester,
            VistaPlano(
              armado: caso.armado,
              hoja: h.id,
              tema: TemaPlano.de(e),
              estado: caso.estado,
              resaltadas: caso.resaltadas,
              animar: false,
            ),
            const Size(1400, 980),
            'Plano_${e.name}_${caso.nombre}_${h.id}.png',
          );
        }
      }
    });
  }
}
