// Arnés manual: arma la hoja para el DJ (PLANILLAS → "Para el DJ") con
// egresados inventados y la letra de la app, para mirar el papel sin levantar
// la app ni tocar la base.
//
//   flutter test tool/planilla_dj_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sin `salida`, va a build/muestras_dj. Salen:
//   Para el DJ - COLEGIO DE PRUEBA.pdf — cuatro divisiones de 24 a 30
//     egresados y algunos sin división: con acompañantes sin nombre, sin
//     música, con una música larga que baja de renglón y uno de baja (que no
//     tiene que aparecer);
//   Para el DJ - sin egresados.pdf — una fiesta sin nadie activo.
//
// Lo que se mira: que se lea de un vistazo quién es, con quién viene y qué
// música pidió; que el título de la división y el de las columnas se repitan
// en la hoja que sigue; y cuántas hojas salen. Las cuentas y lo que no tiene
// que aparecer los vigila test/planilla_dj_pdf_test.dart.
//
// No vive en test/ a propósito: guarda un PDF, y eso no tiene que pasar en cada
// corrida de la suite. Los nombres son inventados: el repositorio es público.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/common/services/planilla_dj_pdf.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

import '../test/helpers/leer_pdf.dart';

const _salida = String.fromEnvironment('salida', defaultValue: 'build/muestras_dj');

const _apellidos = [
  'ACOSTA', 'AGUIRRE', 'AQUINO', 'ARANDA', 'BARRIOS', 'BENÍTEZ', 'CABRAL',
  'DUARTE', 'ESCOBAR', 'FERNÁNDEZ', 'GIMÉNEZ', 'GÓMEZ', 'HERRERA', 'JARA',
  'LEDESMA', 'MEDINA', 'NÚÑEZ', 'OJEDA', 'PEREYRA', 'QUIROGA', 'ROMERO',
  'SOSA', 'TOLEDO', 'VALLEJOS', 'ZARATE',
];

const _musicas = [
  'Cumbia santafesina para entrar',
  'Rock nacional',
  '',
  'Cuarteto, y al final el vals de siempre',
  'Reggaetón de los 2000',
  '',
  'Que suene "La bestia pop" cuando entramos con mi familia, después cumbia '
      'para bailar con mis primos, algo de cuarteto para mis tíos y, si se '
      'puede, el vals con mi papá antes del brindis. Gracias por todo',
  'Electrónica',
];

var _siguiente = 0;

ContratoAlumno _alumno(String division, int i) {
  final apellido = _apellidos[(i * 7 + division.length) % _apellidos.length];
  final cantidad = i % 5 == 0 ? 0 : (i % 7 == 0 ? 3 : 2);
  // Algunos con la cuenta y sin los nombres: salen como "N sin nombre".
  final conNombre = i % 6 == 0 ? 0 : (i % 7 == 0 ? 1 : cantidad);
  final codigo = division.isEmpty ? 'SD' : division.replaceAll(' ', '');
  return ContratoAlumno(
    id: 'c0000000-0000-4000-8000-${(++_siguiente).toString().padLeft(12, '0')}',
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    nombreAlumno: '${i == 4 ? '[BAJA] ' : ''}$apellido, ALUMNO $codigo-$i',
    cursoDivision: division,
    cantidadAcompanantes: cantidad,
    nombresAcompanantes: [
      if (conNombre > 0) '$apellido, MAMÁ $i',
      if (conNombre > 1) '$apellido, PAPÁ $i',
    ],
    musicaElegida: _musicas[i % _musicas.length],
    montoTotalPactado: 300000,
    saldoDeudor: 0,
    createdAt: DateTime(2026, 2, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = Directory(_salida)..createSync(recursive: true);

  Future<void> guardar(String nombre, List<ContratoAlumno> alumnos) async {
    final fuentes = await PdfService.fuentesOutfit();
    expect(fuentes, isNotNull, reason: 'la muestra va con la letra de la app');
    final bytes = await PlanillaDjPdf.construir(
      institucion: nombre,
      alumnos: alumnos,
      fechaFiesta: DateTime(2026, 12, 4),
      regular: fuentes!.$1,
      negrita: fuentes.$2,
    );
    final f = File(
      '${carpeta.path}${Platform.pathSeparator}${PlanillaDjPdf.nombreDelArchivo(nombre)}',
    )..writeAsBytesSync(bytes);
    print('── ${paginasDelPdf(bytes)} hoja(s) · PDF en: ${f.absolute.path}');
  }

  test('la hoja para el DJ de una fiesta de cuatro divisiones', () async {
    final alumnos = [
      for (final (d, cuantos) in [('5° A', 30), ('5° B', 27), ('5° C', 24), ('EXT TURNO NOCHE', 26)])
        for (var i = 1; i <= cuantos; i++) _alumno(d, i),
      for (var i = 1; i <= 3; i++) _alumno('', i + 100),
    ];
    await guardar('COLEGIO DE PRUEBA', alumnos);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('la hoja para el DJ sin egresados activos', () async {
    await guardar('sin egresados', [_alumno('5° A', 4)]);
  });
}
