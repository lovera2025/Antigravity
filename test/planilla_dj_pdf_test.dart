// La hoja para el DJ (PLANILLAS → "Para el DJ", 22-nov-2026): cada egresado
// con sus acompañantes y su música, y nada más. Armada con la letra de fábrica
// para poder leer cada palabra (`palabrasDelPdf`). Los nombres son inventados:
// el repositorio es público.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/planilla_dj_pdf.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

import 'helpers/leer_pdf.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

var _siguiente = 0;

ContratoAlumno _alumno(
  String nombre, {
  String? division,
  int cantidad = 0,
  List<String> acompanantes = const [],
  String? musica,
}) =>
    ContratoAlumno(
      id: 'c0000000-0000-4000-8000-${(++_siguiente).toString().padLeft(12, '0')}',
      eventoId: _evento,
      nombreAlumno: nombre,
      cursoDivision: division,
      cantidadAcompanantes: cantidad,
      nombresAcompanantes: acompanantes,
      musicaElegida: musica,
      // Lo que la hoja no tiene que mostrar nunca.
      telefono: '3777123456',
      numeroMesa: '17',
      montoTotalPactado: 300000,
      saldoDeudor: 120000,
      sillasExtraCantidad: 2,
      createdAt: DateTime(2026, 2, 1),
    );

/// Una fiesta chica: dos divisiones, uno sin división y uno de baja.
List<ContratoAlumno> _fiesta() => [
      _alumno(
        'ALUMNOB, PRUEBA',
        division: '5° A',
        cantidad: 2,
        acompanantes: const ['MADREB, UNA', 'PADREB, UNO'],
        musica: 'Cumbia del recuerdo',
      ),
      _alumno(
        'ALUMNOA, PRUEBA',
        division: '5° A',
        cantidad: 3,
        acompanantes: const ['ÑANDÚ, JOSÉ'],
        musica: 'Rock nacional',
      ),
      _alumno(
        'ALUMNOC, PRUEBA',
        division: '5° B',
        cantidad: 1,
      ),
      _alumno('ALUMNOD, PRUEBA', musica: 'Reggaetón viejo'),
      _alumno(
        '[BAJA] ALUMNOE, PRUEBA',
        division: '5° A',
        cantidad: 2,
        acompanantes: const ['MADREE, UNA'],
        musica: 'Lo de la baja',
      ),
    ];

Future<Uint8List> _hoja(List<ContratoAlumno> alumnos) => PlanillaDjPdf.construir(
      institucion: 'COLEGIO DE PRUEBA',
      alumnos: alumnos,
      fechaFiesta: DateTime(2026, 12, 4),
      generada: DateTime.utc(2026, 11, 22, 15),
    );

Future<String> _texto(List<ContratoAlumno> alumnos) async =>
    palabrasDelPdf(await _hoja(alumnos)).map((p) => p.texto).join(' ');

void main() {
  test('trae a cada egresado con sus acompañantes y su música, por división', () async {
    final texto = await _texto(_fiesta());
    for (final esperado in [
      'ALUMNOA, PRUEBA',
      'ALUMNOB, PRUEBA',
      'ALUMNOC, PRUEBA',
      'ALUMNOD, PRUEBA',
      'MADREB, UNA',
      'PADREB, UNO',
      'ÑANDÚ, JOSÉ',
      'Cumbia del recuerdo',
      'Rock nacional',
      'Reggaetón viejo',
      '5° A · 2 egresados',
      '5° B · 1 egresado',
      'Sin curso asignado · 1 egresado',
    ]) {
      expect(texto, contains(esperado), reason: esperado);
    }
    // Por división y por nombre; sin división, al final.
    final orden = [
      '5° A · 2 egresados',
      'ALUMNOA, PRUEBA',
      'ALUMNOB, PRUEBA',
      '5° B · 1 egresado',
      'ALUMNOC, PRUEBA',
      'Sin curso asignado',
      'ALUMNOD, PRUEBA',
    ].map(texto.indexOf).toList();
    expect(orden, orderedEquals([...orden]..sort()), reason: 'el orden: $orden');
  });

  test('el encabezado dice la institución, el día de la fiesta y qué lleva', () async {
    final texto = await _texto(_fiesta());
    for (final esperado in [
      'PARA EL DJ',
      'COLEGIO DE PRUEBA',
      'FIESTA DEL 04/12/2026',
      'Egresados, acompañantes y música · 4 egresados',
      'EGRESADO ACOMPAÑANTES MÚSICA',
      'Hoja 1 de 1',
    ]) {
      expect(texto, contains(esperado), reason: esperado);
    }
  });

  test('los de baja no salen, ni sus acompañantes ni su música', () async {
    final texto = await _texto(_fiesta());
    for (final w in ['ALUMNOE,', 'MADREE,', 'BAJA', '[BAJA]', 'baja']) {
      expect(texto.split(' '), isNot(contains(w)), reason: w);
    }
  });

  test('no dice nada más: ni DNI, ni teléfono, ni mesas, ni sillas, ni plata', () async {
    final palabras = {
      for (final p in palabrasDelPdf(await _hoja(_fiesta()))) p.texto.toLowerCase(),
    };
    for (final w in [
      'dni',
      'teléfono',
      'tel',
      'tel.',
      'mesa',
      'mesas',
      'silla',
      'sillas',
      'entradas',
      'pulseras',
      'saldo',
      'cuota',
      'cuotas',
      '3777123456',
    ]) {
      expect(palabras, isNot(contains(w)), reason: w);
    }
    expect(palabras.where((p) => p.contains(r'$')), isEmpty);
  });

  test('"2 sin nombre" si la cuenta dice más de los que tienen nombre, y "-" si '
      'viene solo o no eligió música', () async {
    final filas = {
      for (final d in PlanillaDjPdf.divisiones(_fiesta()))
        for (final f in d.filas) f.egresado: f,
    };
    expect(filas['ALUMNOA, PRUEBA']!.acompanantes, ['ÑANDÚ, JOSÉ', '2 sin nombre']);
    expect(filas['ALUMNOC, PRUEBA']!.acompanantes, ['1 sin nombre']);
    expect(filas['ALUMNOD, PRUEBA']!.acompanantes, isEmpty);
    expect(filas['ALUMNOC, PRUEBA']!.musica, isEmpty);

    final texto = await _texto(_fiesta());
    expect(texto, contains('ÑANDÚ, JOSÉ 2 sin nombre Rock nacional'));
    expect(texto, contains('ALUMNOC, PRUEBA 1 sin nombre -'));
    expect(texto, contains('ALUMNOD, PRUEBA - Reggaetón viejo'));
  });

  test('una música muy larga baja de renglón y no se sale de la hoja', () async {
    final larga = [
      'Empezar con',
      for (var i = 0; i < 30; i++) 'tema$i',
      'https://musica.example.com/lista/abcdefghijklmnopqrstuvwxyz0123456789abcdefghij',
      'y terminar con el vals',
    ].join(' ');
    final alumnos = [
      _alumno(
        'ALUMNOLARGO CON UN APELLIDO MUY LARGO, PRUEBA NOMBRE TAMBIÉN LARGO',
        division: 'EXT PAGO REDONDO TURNO NOCHE',
        cantidad: 2,
        acompanantes: const [
          'ACOMPAÑANTE CON UN NOMBRE MUY LARGO, PRIMERO',
          'ACOMPAÑANTE CON UN NOMBRE MUY LARGO, SEGUNDO',
        ],
        musica: larga,
      ),
    ];
    final palabras = palabrasDelPdf(await _hoja(alumnos));
    final derecha = PdfPageFormat.a4.width - 20 + 1;
    for (final p in palabras) {
      expect(p.x + p.ancho, lessThanOrEqualTo(derecha), reason: '"${p.texto}" se sale');
      expect(p.x, greaterThanOrEqualTo(19), reason: '"${p.texto}" se sale por la izquierda');
    }
    final texto = palabras.map((p) => p.texto).join(' ');
    expect(texto, contains('Empezar con tema0'));
    expect(texto, contains('tema29'));
    expect(texto, contains('y terminar con el vals'));
    expect(texto, contains('SEGUNDO'));
    // La música larga ocupa varios renglones: no se cortó en uno.
    final yDeLaMusica = {
      for (final p in palabras)
        if (p.texto.startsWith('tema')) p.y.round(),
    };
    expect(yDeLaMusica.length, greaterThan(2));
  });

  test('con muchas divisiones se parte en varias hojas y no pierde a nadie', () async {
    final alumnos = [
      for (var d = 1; d <= 8; d++)
        for (var i = 1; i <= 25; i++)
          _alumno(
            'ALUMNO${d}X$i, PRUEBA',
            division: '$d° A',
            cantidad: 2,
            acompanantes: ['PRIMERO${d}X$i, UNO', 'ULTIMO${d}X$i, DOS'],
            musica: i.isEven ? 'Música$d.$i de la fiesta' : null,
          ),
    ];
    final bytes = await _hoja(alumnos);
    final hojas = paginasDelPdf(bytes);
    expect(hojas, greaterThan(2));
    final palabras = [for (final p in palabrasDelPdf(bytes)) p.texto];
    for (var d = 1; d <= 8; d++) {
      for (var i = 1; i <= 25; i++) {
        expect(palabras, contains('ALUMNO${d}X$i,'), reason: 'el egresado $d.$i');
        // El último renglón de la celda: el que se perdía sin `AltoLibre`.
        expect(palabras, contains('ULTIMO${d}X$i,'), reason: 'el último acompañante de $d.$i');
      }
    }
    final texto = palabras.join(' ');
    expect(texto, contains('Hoja 1 de $hojas'));
    expect(texto, contains('Hoja $hojas de $hojas'));
  });

  test('una división que no entra en una hoja repite su título y el de las columnas',
      () async {
    final alumnos = [
      for (var i = 1; i <= 120; i++)
        _alumno(
          'ALUMNO$i, PRUEBA',
          division: '5° A',
          cantidad: 2,
          acompanantes: ['MADRE$i, UNA', 'PADRE$i, UNO'],
          musica: 'Tema $i',
        ),
    ];
    final bytes = await _hoja(alumnos);
    final hojas = paginasDelPdf(bytes);
    expect(hojas, greaterThan(2));
    final palabras = [for (final p in palabrasDelPdf(bytes)) p.texto];
    expect(palabras.where((p) => p == 'MÚSICA').length, hojas);
    expect(
      RegExp('5° A · 120 egresados').allMatches(palabras.join(' ')).length,
      hojas,
    );
    expect(palabras, contains('PADRE120,'));
  });

  test('sin egresados activos lo dice', () async {
    final texto = await _texto([_alumno('[BAJA] ALUMNOE, PRUEBA', division: '5° A')]);
    expect(texto, contains('No hay egresados activos en esta fiesta.'));
    expect(texto, contains('Egresados, acompañantes y música · 0 egresados'));
  });

  test('el nombre del archivo lleva la institución, sin lo que Windows no deja', () {
    expect(
      PlanillaDjPdf.nombreDelArchivo('COLEGIO SAN JOSÉ'),
      'Para el DJ - COLEGIO SAN JOSÉ.pdf',
    );
    expect(
      PlanillaDjPdf.nombreDelArchivo('E.P.E.T. N° 3 / Turno: "noche".'),
      'Para el DJ - E.P.E.T. N° 3 Turno noche.pdf',
    );
    expect(PlanillaDjPdf.nombreDelArchivo('  '), 'Para el DJ - Evento.pdf');
  });
}
