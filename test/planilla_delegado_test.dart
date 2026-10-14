// El Excel que completa el delegado: acompañantes (hasta 2) y música.
//
// Lo que pidió el usuario el 13-oct-2026: se exporta por institución con todos
// los alumnos menos los de baja, se completa solo eso, y al importar se carga
// solo eso, sin que una institución pise a otra.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado_bloqueo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _normal = 'e0000000-0000-4000-8000-000000000001';
const _nacional = 'e0000000-0000-4000-8000-000000000002';

/// Un id con forma de UUID que empieza con [principio].
String _id(String principio) =>
    '${principio.padRight(8, '0')}-0000-4000-8000-000000000000';

ContratoAlumno _alumno(
  String principio,
  String nombre, {
  String division = '6° A',
  List<String> acomp = const [],
  String? musica,
  String evento = _normal,
}) =>
    ContratoAlumno(
      id: _id(principio),
      eventoId: evento,
      nombreAlumno: nombre,
      cantidadAcompanantes: acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: division,
      musicaElegida: musica,
    );

List<ContratoAlumno> _escuela() => [
      _alumno('a1', 'ACOSTA, BRISA'),
      _alumno('b2', 'BENITEZ, JOAQUIN'),
      _alumno('c3', 'CABRAL, MILAGROS'),
      _alumno('d4', 'DUARTE, TOBIAS', division: '6° B'),
    ];

Uint8List _exportar(List<ContratoAlumno> alumnos, {String evento = _normal}) =>
    PlanillaDelegado.armar(
      eventoId: evento,
      institucion: evento == _normal ? 'NORMAL MARIANO ILOZA' : 'COLEGIO NACIONAL',
      alumnos: alumnos,
    );

/// Lo que hace el delegado: escribe en los casilleros de un alumno. [cambios]
/// va por nombre del alumno; cada valor es (acompañantes, música, y si hace
/// falta otro nombre u otra división para ese renglón).
Uint8List _completar(
  Uint8List bytes,
  Map<String, ({String? acomp, String? musica, String? nombre, String? division})>
      cambios,
) {
  final excel = Excel.decodeBytes(bytes);
  final hoja = excel.tables.values.first;
  CellIndex en(int c, int f) =>
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: f);
  for (var f = PlanillaDelegado.filaEncabezados + 1; f < hoja.maxRows; f++) {
    final nombre = hoja.cell(en(1, f)).value?.toString();
    final c = cambios[nombre];
    if (c == null) continue;
    if (c.acomp != null) {
      hoja.cell(en(PlanillaDelegado.columnaAcompanantes, f)).value =
          TextCellValue(c.acomp!);
    }
    if (c.musica != null) {
      hoja.cell(en(PlanillaDelegado.columnaMusica, f)).value =
          TextCellValue(c.musica!);
    }
    if (c.nombre != null) hoja.cell(en(1, f)).value = TextCellValue(c.nombre!);
    if (c.division != null) {
      hoja.cell(en(2, f)).value = TextCellValue(c.division!);
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

({String? acomp, String? musica, String? nombre, String? division}) _pone({
  String? acomp,
  String? musica,
  String? nombre,
  String? division,
}) =>
    (acomp: acomp, musica: musica, nombre: nombre, division: division);

ResultadoPlanilla _importar(
  Uint8List bytes,
  List<ContratoAlumno> alumnos, {
  String evento = _normal,
}) =>
    PlanillaDelegado.comparar(
      lectura: PlanillaDelegado.leer(bytes),
      alumnos: alumnos,
      eventoId: evento,
      institucion: evento == _normal ? 'NORMAL MARIANO ILOZA' : 'COLEGIO NACIONAL',
    );

String _xml(Uint8List bytes, String nombre) => utf8.decode(
      ZipDecoder().decodeBytes(bytes).files.firstWhere((f) => f.name == nombre).content
          as List<int>,
    );

void main() {
  group('los nombres de un casillero de acompañantes', () {
    test('se separan con barra', () {
      expect(
        PlanillaDelegado.separarAcompanantes('Marta Acosta / Hugo Ríos'),
        ['Marta Acosta', 'Hugo Ríos'],
      );
    });

    test('también con punto y coma, "+", "&", un renglón nuevo o " y "', () {
      for (final casillero in [
        'Marta Acosta; Hugo Ríos',
        'Marta Acosta + Hugo Ríos',
        'Marta Acosta & Hugo Ríos',
        'Marta Acosta\nHugo Ríos',
        'Marta Acosta y Hugo Ríos',
        'Marta Acosta Y Hugo Ríos',
        '  Marta   Acosta  /  Hugo Ríos  ',
        'Marta Acosta / / Hugo Ríos',
      ]) {
        expect(
          PlanillaDelegado.separarAcompanantes(casillero),
          ['Marta Acosta', 'Hugo Ríos'],
          reason: casillero,
        );
      }
    });

    test('la coma no separa: los nombres del sistema son APELLIDO, NOMBRE', () {
      expect(
        PlanillaDelegado.separarAcompanantes('ACOSTA, MARTA'),
        ['ACOSTA, MARTA'],
      );
      expect(
        PlanillaDelegado.separarAcompanantes('ACOSTA, MARTA / RIOS, HUGO'),
        ['ACOSTA, MARTA', 'RIOS, HUGO'],
      );
    });

    test('una "y" adentro de una palabra no separa', () {
      expect(
        PlanillaDelegado.separarAcompanantes('Yamila Reyes'),
        ['Yamila Reyes'],
      );
    });

    test('vacío, o solo espacios, es nadie', () {
      expect(PlanillaDelegado.separarAcompanantes(''), isEmpty);
      expect(PlanillaDelegado.separarAcompanantes('   '), isEmpty);
      expect(PlanillaDelegado.separarAcompanantes(' / '), isEmpty);
    });
  });

  group('quiénes van a la planilla', () {
    test('todos los activos, y ninguno de baja', () {
      final van = PlanillaDelegado.alumnosDeLaPlanilla([
        ..._escuela(),
        _alumno('e5', '[BAJA] ESPINOLA, LUZ'),
      ]);
      expect(van.map((a) => a.nombreAlumno), [
        'ACOSTA, BRISA',
        'BENITEZ, JOAQUIN',
        'CABRAL, MILAGROS',
        'DUARTE, TOBIAS',
      ]);
    });

    test('por división y, adentro, por apellido; sin división, al final', () {
      final van = PlanillaDelegado.alumnosDeLaPlanilla([
        _alumno('a1', 'ZARATE, ANA', division: '6° B'),
        _alumno('b2', 'ÁLVAREZ, LEO', division: '6° B'),
        _alumno('c3', 'MEZA, IAN', division: ''),
        _alumno('d4', 'VERA, SOL', division: '6° A'),
      ]);
      expect(van.map((a) => a.nombreAlumno), [
        'VERA, SOL',
        'ÁLVAREZ, LEO',
        'ZARATE, ANA',
        'MEZA, IAN',
      ]);
    });
  });

  group('el código de cada alumno', () {
    test('empieza con letra: ningún programa lo toma por número ni fecha', () {
      final codigos = PlanillaDelegado.codigos([
        _alumno('12345678', 'A'),
        _alumno('1234e567', 'B'),
      ]);
      expect(codigos.values, ['K12345678', 'K1234E567']);
    });

    test('si dos alumnos empiezan igual, se alarga para todos', () {
      final a = ContratoAlumno(
        id: 'aaaaaaaa-1111-4000-8000-000000000000',
        eventoId: _normal,
        nombreAlumno: 'A',
        cantidadAcompanantes: 0,
        montoTotalPactado: 1,
        saldoDeudor: 0,
      );
      final b = ContratoAlumno(
        id: 'aaaaaaaa-2222-4000-8000-000000000000',
        eventoId: _normal,
        nombreAlumno: 'B',
        cantidadAcompanantes: 0,
        montoTotalPactado: 1,
        saldoDeudor: 0,
      );
      final codigos = PlanillaDelegado.codigos([a, b]);
      expect(codigos.values.toSet(), hasLength(2));
      expect(codigos[a.id], 'KAAAAAAAA1111');
    });
  });

  group('exportar y volver a leer', () {
    test('salen todos los alumnos, con su nombre tal cual y su división', () {
      final leido = PlanillaDelegado.leer(_exportar(_escuela()));
      expect(leido.problema, isNull);
      expect(leido.eventoId, _normal);
      expect(leido.institucion, 'NORMAL MARIANO ILOZA');
      expect(leido.renglones.map((r) => r.alumno), [
        'ACOSTA, BRISA',
        'BENITEZ, JOAQUIN',
        'CABRAL, MILAGROS',
        'DUARTE, TOBIAS',
      ]);
      expect(leido.renglones.first.codigo, 'KA1000000');
      expect(leido.renglones.every((r) => r.acompanantes.isEmpty), isTrue);
    });

    test('un alumno de baja no sale, y el nombre va sin la marca', () {
      final leido = PlanillaDelegado.leer(
        _exportar([
          _alumno('a1', 'ACOSTA, BRISA'),
          _alumno('e5', '[BAJA] ESPINOLA, LUZ'),
        ]),
      );
      expect(leido.renglones.map((r) => r.alumno), ['ACOSTA, BRISA']);
    });

    test('lo que ya está cargado sale escrito', () {
      final leido = PlanillaDelegado.leer(
        _exportar([
          _alumno(
            'a1',
            'ACOSTA, BRISA',
            acomp: ['Marta Acosta', 'Hugo Ríos'],
            musica: 'Viva la vida',
          ),
        ]),
      );
      expect(leido.renglones.single.acompanantes, 'Marta Acosta / Hugo Ríos');
      expect(leido.renglones.single.musica, 'Viva la vida');
    });

    test('sin tocar nada, importar no carga nada', () {
      final r = _importar(_exportar(_escuela()), _escuela());
      expect(r.rechazo, isNull);
      expect(r.cambios, isEmpty);
      expect(r.vacios, 4);
      expect(r.iguales, 0);
      expect(r.revisar, isEmpty);
      expect(r.sePuedeImportar, isFalse);
    });

    test('lo ya cargado, exportado y vuelto a importar, queda igual', () {
      final escuela = [
        _alumno('a1', 'ACOSTA, BRISA', acomp: ['Marta Acosta'], musica: 'X'),
        _alumno('b2', 'BENITEZ, JOAQUIN'),
      ];
      final r = _importar(_exportar(escuela), escuela);
      expect(r.cambios, isEmpty);
      expect(r.iguales, 1);
      expect(r.vacios, 1);
    });
  });

  group('importar lo que completó el delegado', () {
    test('se cargan acompañantes y música, y nada más del alumno', () {
      final bytes = _completar(_exportar(_escuela()), {
        'ACOSTA, BRISA':
            _pone(acomp: 'Marta Acosta / Hugo Ríos', musica: 'Viva la vida'),
        'BENITEZ, JOAQUIN': _pone(acomp: 'Raúl Benítez'),
        'DUARTE, TOBIAS': _pone(musica: 'Titanium'),
      });
      final r = _importar(bytes, _escuela());
      expect(r.rechazo, isNull);
      expect(r.revisar, isEmpty);
      expect(r.vacios, 1);
      expect(r.cambios.map((c) => c.alumno.nombreAlumno), [
        'ACOSTA, BRISA',
        'BENITEZ, JOAQUIN',
        'DUARTE, TOBIAS',
      ]);

      final acosta = r.cambios[0];
      expect(acosta.datos, {
        'nombres_acompanantes': ['Marta Acosta', 'Hugo Ríos'],
        'cantidad_acompanantes': 2,
        'musica_elegida': 'Viva la vida',
      });
      expect(acosta.leido, 'Marta Acosta · Hugo Ríos · Música: Viva la vida');
      expect(acosta.pisaAlgo, isFalse);

      // Solo lo que cambia: al que no le pusieron música no se le toca.
      expect(r.cambios[1].datos, {
        'nombres_acompanantes': ['Raúl Benítez'],
        'cantidad_acompanantes': 1,
      });
      expect(r.cambios[2].datos, {'musica_elegida': 'Titanium'});
    });

    test('con 3 acompañantes ese alumno no se carga, y lo dice', () {
      final bytes = _completar(_exportar(_escuela()), {
        'DUARTE, TOBIAS':
            _pone(acomp: 'Silvia / Omar / Tía Nora', musica: 'Titanium'),
        'ACOSTA, BRISA': _pone(acomp: 'Marta Acosta'),
      });
      final r = _importar(bytes, _escuela());
      expect(r.cambios.map((c) => c.alumno.nombreAlumno), ['ACOSTA, BRISA']);
      expect(r.revisar.single.quien, 'DUARTE, TOBIAS');
      expect(
        r.revisar.single.motivo,
        'trae 3 acompañantes y el máximo es 2. No se carga.',
      );
    });

    test('un casillero con coma se toma como una persona, y queda marcado', () {
      final bytes = _completar(_exportar(_escuela()), {
        'ACOSTA, BRISA': _pone(acomp: 'ACOSTA, MARTA'),
        'BENITEZ, JOAQUIN': _pone(acomp: 'Raúl Benítez'),
      });
      final r = _importar(bytes, _escuela());
      expect(r.cambios[0].acompanantes, ['ACOSTA, MARTA']);
      expect(r.cambios[0].conComa, isTrue);
      expect(r.cambios[1].conComa, isFalse);
    });

    test('un casillero vacío nunca borra lo que ya estaba', () {
      final escuela = [
        _alumno(
          'a1',
          'ACOSTA, BRISA',
          acomp: ['Marta Acosta'],
          musica: 'Viva la vida',
        ),
      ];
      // El delegado borró los dos casilleros.
      final bytes = _completar(_exportar(escuela), {
        'ACOSTA, BRISA': _pone(acomp: '', musica: ''),
      });
      final r = _importar(bytes, escuela);
      expect(r.cambios, isEmpty);
      expect(r.vacios, 1);
    });

    test('borrar solo la música deja la música, y cambia los acompañantes', () {
      final escuela = [
        _alumno('a1', 'ACOSTA, BRISA', acomp: ['Marta Acosta'], musica: 'X'),
      ];
      final bytes = _completar(_exportar(escuela), {
        'ACOSTA, BRISA': _pone(acomp: 'Hugo Ríos', musica: ''),
      });
      final c = _importar(bytes, escuela).cambios.single;
      expect(c.datos, {
        'nombres_acompanantes': ['Hugo Ríos'],
        'cantidad_acompanantes': 1,
      });
      // Tenía otro acompañante: hay que mostrarlo antes de guardar.
      expect(c.pisaAlgo, isTrue);
      expect(c.tenia, 'Marta Acosta');
      expect(c.leido, 'Hugo Ríos');
    });

    test('cambiar el nombre o la división en el Excel no cambia nada de eso',
        () {
      final bytes = _completar(_exportar(_escuela()), {
        'DUARTE, TOBIAS': _pone(division: '9° Z', musica: 'Titanium'),
      });
      final r = _importar(bytes, _escuela());
      // Solo viaja la música: la división del Excel se ignora.
      expect(r.cambios.single.datos, {'musica_elegida': 'Titanium'});
      expect(r.cambios.single.alumno.cursoDivision, '6° B');
    });

    test('si el nombre no coincide con el código, ese renglón no se carga', () {
      // Renglones corridos al pegar: el código de ACOSTA con otro nombre.
      final bytes = _completar(_exportar(_escuela()), {
        'ACOSTA, BRISA': _pone(nombre: 'GOMEZ, LUCIA', acomp: 'Marta Acosta'),
      });
      final r = _importar(bytes, _escuela());
      expect(r.cambios, isEmpty);
      expect(r.revisar.single.quien, 'GOMEZ, LUCIA');
      expect(
        r.revisar.single.motivo,
        'el Excel dice "GOMEZ, LUCIA" y ese código es de "ACOSTA, BRISA". '
        'No se carga.',
      );
    });

    test('un acento o una mayúscula de más en el nombre no lo frena', () {
      final bytes = _completar(_exportar(_escuela()), {
        'BENITEZ, JOAQUIN':
            _pone(nombre: 'Benítez,  Joaquín', acomp: 'Raúl Benítez'),
      });
      final r = _importar(bytes, _escuela());
      expect(r.revisar, isEmpty);
      expect(r.cambios.single.alumno.nombreAlumno, 'BENITEZ, JOAQUIN');
    });

    test('un alumno que hoy está de baja no se carga', () {
      final bytes = _completar(_exportar(_escuela()), {
        'CABRAL, MILAGROS': _pone(acomp: 'Ana Cabral'),
      });
      final hoy = [
        for (final a in _escuela())
          a.nombreAlumno == 'CABRAL, MILAGROS'
              ? a.copyWith(nombreAlumno: '[BAJA] CABRAL, MILAGROS')
              : a,
      ];
      final r = _importar(bytes, hoy);
      expect(r.cambios, isEmpty);
      expect(r.revisar.single.toString(),
          'CABRAL, MILAGROS: está dado de baja. No se carga.');
    });

    test('quien ya tiene más de 2 no se toca desde el Excel; su música sí', () {
      final escuela = [
        _alumno('a1', 'ACOSTA, BRISA', acomp: ['Uno', 'Dos', 'Tres']),
        _alumno('b2', 'BENITEZ, JOAQUIN', acomp: ['Uno', 'Dos', 'Tres']),
      ];
      final exportado = _exportar(escuela);
      // Tal como salió, con sus 3 escritos, no molesta: es lo que ya tienen.
      final sinTocar = _importar(exportado, escuela);
      expect(sinTocar.revisar, isEmpty);
      expect(sinTocar.iguales, 2);

      final bytes = _completar(exportado, {
        'ACOSTA, BRISA': _pone(acomp: 'Marta Acosta'),
        'BENITEZ, JOAQUIN': _pone(musica: 'Thunderstruck'),
      });
      final r = _importar(bytes, escuela);
      expect(r.revisar.single.quien, 'ACOSTA, BRISA');
      expect(r.revisar.single.motivo, contains('ya tiene 3 acompañantes'));
      expect(r.cambios.single.datos, {'musica_elegida': 'Thunderstruck'});
    });
  });

  group('una institución no pisa a otra', () {
    final nacional = [
      _alumno('f6', 'FERNANDEZ, IVAN', evento: _nacional),
      _alumno('a7', 'ACOSTA, BRISA', evento: _nacional),
    ];

    test('el Excel de otra institución no entra, y dice de cuál es', () {
      final bytes = _completar(_exportar(nacional, evento: _nacional), {
        'ACOSTA, BRISA': _pone(acomp: 'Marta Acosta'),
      });
      final r = _importar(bytes, _escuela());
      expect(
        r.rechazo,
        'Este Excel es de COLEGIO NACIONAL y estás en NORMAL MARIANO ILOZA. '
        'No se importó nada.',
      );
      expect(r.cambios, isEmpty);
      expect(r.sePuedeImportar, isFalse);
    });

    test('tampoco entra si le borraron el renglón que dice de cuál es', () {
      final excel = Excel.decodeBytes(_exportar(nacional, evento: _nacional));
      excel.tables.values.first.removeRow(2);
      final bytes = Uint8List.fromList(excel.encode()!);
      expect(PlanillaDelegado.leer(bytes).eventoId, isNull);

      final r = _importar(bytes, _escuela());
      // Hay una ACOSTA, BRISA en las dos, pero el código es de la otra.
      expect(r.rechazo, contains('No se importó nada.'));
      expect(r.cambios, isEmpty);
    });

    test('un renglón pegado de otra institución no se carga; el resto sí', () {
      final excel = Excel.decodeBytes(
        _completar(_exportar(_escuela()), {
          'ACOSTA, BRISA': _pone(acomp: 'Marta Acosta'),
        }),
      );
      final hoja = excel.tables.values.first;
      final f = hoja.maxRows;
      void pegar(int c, String texto) => hoja
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: f))
          .value = TextCellValue(texto);
      pegar(1, 'FERNANDEZ, IVAN');
      pegar(PlanillaDelegado.columnaAcompanantes, 'Rita Fernández');
      pegar(5, 'KF6000000');

      final r = _importar(Uint8List.fromList(excel.encode()!), _escuela());
      expect(r.rechazo, isNull);
      expect(r.cambios.single.alumno.nombreAlumno, 'ACOSTA, BRISA');
      expect(r.revisar.single.toString(),
          'FERNANDEZ, IVAN: su código no es de esta institución. No se carga.');
    });
  });

  group('un Excel que no salió tal cual', () {
    /// Una planilla armada a mano, con las columnas en otro orden.
    Uint8List aMano(List<List<String>> filas) {
      final excel = Excel.createExcel();
      final hoja = excel[excel.getDefaultSheet()!];
      for (var f = 0; f < filas.length; f++) {
        for (var c = 0; c < filas[f].length; c++) {
          hoja
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: f))
              .value = TextCellValue(filas[f][c]);
        }
      }
      return Uint8List.fromList(excel.encode()!);
    }

    test('las columnas se buscan por su nombre, no por su lugar', () {
      final bytes = aMano([
        ['Música', 'Código', 'Acompañantes (hasta 2)', 'Alumno'],
        ['Titanium', 'KD4000000', 'Silvia / Omar', 'DUARTE, TOBIAS'],
      ]);
      final r = _importar(bytes, _escuela());
      expect(r.cambios.single.datos, {
        'nombres_acompanantes': ['Silvia', 'Omar'],
        'cantidad_acompanantes': 2,
        'musica_elegida': 'Titanium',
      });
    });

    test('sin la columna Código se empareja por el nombre exacto', () {
      final bytes = aMano([
        ['Alumno', 'Acompañantes', 'Música'],
        ['duarte, tobías', 'Silvia', ''],
        ['GOMEZ, LUCIA', 'Ana', ''],
      ]);
      final r = _importar(bytes, _escuela());
      expect(r.cambios.single.alumno.nombreAlumno, 'DUARTE, TOBIAS');
      expect(r.revisar.single.motivo, contains('no hay un alumno con ese nombre'));
    });

    test('sin código y con dos alumnos del mismo nombre, no se adivina', () {
      final escuela = [
        _alumno('a1', 'GOMEZ, LUIS'),
        _alumno('b2', 'GOMEZ, LUIS', division: '6° B'),
      ];
      final bytes = aMano([
        ['Alumno', 'Acompañantes'],
        ['GOMEZ, LUIS', 'Ana'],
      ]);
      final r = _importar(bytes, escuela);
      expect(r.cambios, isEmpty);
      expect(r.revisar.single.motivo, contains('hay 2 alumnos con ese nombre'));
    });

    test('el mismo alumno dos veces con datos distintos no se carga', () {
      final bytes = aMano([
        ['Alumno', 'Acompañantes', 'Código'],
        ['ACOSTA, BRISA', 'Marta', 'KA1000000'],
        ['ACOSTA, BRISA', 'Hugo', 'KA1000000'],
        ['BENITEZ, JOAQUIN', 'Raúl', 'KB2000000'],
        ['BENITEZ, JOAQUIN', 'Raúl', 'KB2000000'],
      ]);
      final r = _importar(bytes, _escuela());
      // BENITEZ está repetido igual: vale una vez.
      expect(r.cambios.single.alumno.nombreAlumno, 'BENITEZ, JOAQUIN');
      expect(r.revisar.single.quien, 'ACOSTA, BRISA');
      expect(r.revisar.single.motivo, contains('aparece dos veces'));
    });

    test('un archivo que no es un Excel se dice en palabras', () {
      final r = _importar(Uint8List.fromList(utf8.encode('hola')), _escuela());
      expect(r.rechazo, contains('No se pudo abrir el archivo'));
      expect(r.sePuedeImportar, isFalse);
    });

    test('un Excel sin las columnas se dice en palabras', () {
      final r = _importar(
        aMano([
          ['Nombre', 'DNI'],
          ['ACOSTA, BRISA', '1'],
        ]),
        _escuela(),
      );
      expect(r.rechazo, contains('no tiene las columnas Alumno y Acompañantes'));
    });
  });

  group('el Excel cerrado', () {
    test('se cierra, y se lee igual que sin cerrar', () {
      final cerrado = exportarPlanillaDelegado(
        eventoId: _normal,
        institucion: 'NORMAL MARIANO ILOZA',
        alumnos: _escuela(),
      );
      expect(cerrado.cerrada, isTrue);
      final a = PlanillaDelegado.leer(cerrado.bytes);
      final b = PlanillaDelegado.leer(_exportar(_escuela()));
      expect(a.eventoId, b.eventoId);
      expect(a.institucion, b.institucion);
      expect(
        a.renglones.map((r) => '${r.codigo}|${r.alumno}'),
        b.renglones.map((r) => '${r.codigo}|${r.alumno}'),
      );
    });

    test('la hoja queda protegida y solo los dos casilleros se dejan escribir',
        () {
      final bytes = exportarPlanillaDelegado(
        eventoId: _normal,
        institucion: 'NORMAL MARIANO ILOZA',
        alumnos: _escuela(),
      ).bytes;
      final hoja = _xml(bytes, 'xl/worksheets/sheet1.xml');
      expect(hoja, contains('<sheetProtection password="'));
      expect(hoja, contains(' sheet="1"'));
      // La protección va antes de las celdas combinadas: es el orden que
      // exige el formato, y Excel da el archivo por dañado si no.
      expect(
        hoja.indexOf('<sheetProtection'),
        greaterThan(hoja.indexOf('</sheetData>')),
      );
      expect(
        hoja.indexOf('<mergeCells'),
        greaterThan(hoja.indexOf('<sheetProtection')),
      );

      final estilos = _xml(bytes, 'xl/styles.xml');
      // Un solo estilo queda sin bloquear: el amarillo.
      expect('<protection locked="0"/>'.allMatches(estilos), hasLength(1));
      final sinBloquear = RegExp(r'<xf [^>]*applyProtection="1"[^>]*>')
          .firstMatch(estilos)!
          .group(0)!;
      final amarillo = RegExp(r'<fill>.*?</fill>')
          .allMatches(estilos)
          .toList()
          .indexWhere((m) => m.group(0)!.contains(kColorCasilleroDelegado));
      expect(sinBloquear, contains('fillId="$amarillo"'));
    });

    test('la regla del máximo cubre a todos los alumnos, del primero al último',
        () {
      final bytes = exportarPlanillaDelegado(
        eventoId: _normal,
        institucion: 'NORMAL MARIANO ILOZA',
        alumnos: _escuela(),
      ).bytes;
      final hoja = _xml(bytes, 'xl/worksheets/sheet1.xml');
      // Cuatro alumnos, desde la fila 6.
      expect(hoja, contains('sqref="D6:D9"'));
      expect(hoja, contains('errorTitle="Máximo 2 acompañantes"'));
      expect(
        hoja,
        contains('<formula1>LEN(D6)-LEN(SUBSTITUTE(D6,"/",""))&lt;=1</formula1>'),
      );
      expect(
        hoja.indexOf('<dataValidations'),
        greaterThan(hoja.indexOf('</mergeCells>')),
      );
      expect(
        hoja.indexOf('<pageMargins'),
        greaterThan(hoja.indexOf('</dataValidations>')),
      );
    });

    test('la columna Código va escondida, y se sigue leyendo', () {
      final bytes = exportarPlanillaDelegado(
        eventoId: _normal,
        institucion: 'NORMAL MARIANO ILOZA',
        alumnos: _escuela(),
      ).bytes;
      final hoja = _xml(bytes, 'xl/worksheets/sheet1.xml');
      // La sexta columna, y solo esa.
      final escondidas = RegExp(r'<col [^>]*hidden="1"[^>]*/>')
          .allMatches(hoja)
          .map((m) => m.group(0)!)
          .toList();
      expect(escondidas, hasLength(1));
      expect(escondidas.single, contains('min="6"'));
      expect(escondidas.single, contains('max="6"'));
      // El delegado no la ve, pero es lo que dice de quién es cada renglón.
      expect(
        PlanillaDelegado.leer(bytes).renglones.map((r) => r.codigo),
        ['KA1000000', 'KB2000000', 'KC3000000', 'KD4000000'],
      );
    });

    test('la clave de la hoja se guarda como la guarda Excel', () {
      // Valores conocidos de esa cuenta: son los que escriben Excel y las
      // demás planillas de cálculo para estas claves.
      expect(claveDeHojaExcel('password'), '83AF');
      expect(claveDeHojaExcel(''), 'CE4B');
      // Con la de la app, Excel no la dejó desproteger sin escribirla y sí con
      // ella (probado con Excel 16.0 el 13-oct-2026).
      expect(
        claveDeHojaExcel(kClavePlanillaDelegado),
        matches(RegExp(r'^[0-9A-F]{1,4}$')),
      );
    });

    test('si no se puede cerrar, sale igual, sin cerrar', () {
      // Sin alumnos no hay casilleros para completar: no hay qué cerrar.
      final vacia = exportarPlanillaDelegado(
        eventoId: _normal,
        institucion: 'NORMAL MARIANO ILOZA',
        alumnos: [_alumno('e5', '[BAJA] ESPINOLA, LUZ')],
      );
      expect(vacia.cerrada, isFalse);
      expect(PlanillaDelegado.leer(vacia.bytes).renglones, isEmpty);
      expect(
        () => bloquearPlanilla(Uint8List.fromList([1, 2, 3]), alumnos: 1),
        throwsA(anything),
      );
    });

    // Este archivo lo guardó el Excel de verdad (16.0), el 13-oct-2026: se
    // exportó cerrado, se abrió, se escribieron los casilleros amarillos y se
    // guardó. Es la ida y vuelta completa, con el programa que usa el
    // delegado. Ese día Excel no dejó escribir en el nombre ni en el código.
    test('lo que guarda el Excel de verdad se lee bien', () {
      final bytes = File('test/datos/planilla_guardada_por_excel.xlsx')
          .readAsBytesSync();
      final leido = PlanillaDelegado.leer(bytes);
      expect(leido.problema, isNull);
      expect(leido.eventoId, _normal);
      expect(leido.institucion, 'NORMAL DE PRUEBA');
      expect(
        leido.renglones
            .map((r) => '${r.codigo}|${r.alumno}|${r.acompanantes}|${r.musica}'),
        [
          'KA0000000|ALUMNO, N0|Marta Acosta / Hugo Rios|Viva la vida',
          'KA1000000|ALUMNO, N1|Uno / Dos / Tres|',
          'KA2000000|ALUMNO, N2||Thunderstruck',
        ],
      );

      final alumnos = [
        for (var i = 0; i < 3; i++)
          ContratoAlumno(
            id: 'a${i}000000-0000-4000-8000-00000000000$i',
            eventoId: _normal,
            nombreAlumno: 'ALUMNO, N$i',
            cantidadAcompanantes: 0,
            montoTotalPactado: 1,
            saldoDeudor: 0,
          ),
      ];
      final r = PlanillaDelegado.comparar(
        lectura: leido,
        alumnos: alumnos,
        eventoId: _normal,
        institucion: 'NORMAL DE PRUEBA',
      );
      expect(r.cambios.map((c) => c.leido), [
        'Marta Acosta · Hugo Rios · Música: Viva la vida',
        'Música: Thunderstruck',
      ]);
      expect(r.revisar.single.motivo, contains('trae 3 acompañantes'));
    });

    // Lo mismo, con el Excel como sale ahora: la columna Código escondida. Ese
    // día Excel no dejó volver a mostrarla sin la clave, y al guardar la
    // conservó: es lo que dice de qué alumno es cada renglón.
    test('lo que guarda el Excel de verdad con el código escondido, también',
        () {
      final leido = PlanillaDelegado.leer(
        File('test/datos/planilla_guardada_por_excel_codigo_escondido.xlsx')
            .readAsBytesSync(),
      );
      expect(leido.problema, isNull);
      expect(leido.eventoId, _normal);
      expect(leido.institucion, 'ESCUELA DE MUESTRA');
      expect(leido.renglones, hasLength(12));
      expect(leido.renglones.every((r) => r.codigo.startsWith('K')), isTrue);
      expect(
        leido.renglones
            .take(3)
            .map((r) => '${r.codigo}|${r.alumno}|${r.acompanantes}|${r.musica}'),
        [
          'K000000A1|ACOSTA, BRISA|Marta Acosta / Hugo Rios|Viva la vida',
          'K000000A2|BENITEZ, JOAQUIN||',
          'K000000A3|CABRAL, MILAGROS|Ana Cabral|',
        ],
      );
    });
  });
}
