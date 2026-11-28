import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/recepcion/services/como_lo_nombran.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/puerta_en_memoria.dart';

/// **"Cómo lo nombran"** (el locutor, v85, 28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`):
/// las reglas puras. La ficha de la oficina no cambia; lo nombrado va aparte.
const _alumno = 'a0000000-0000-4000-8000-000000000001';

void main() {
  final ahora = DateTime.utc(2026, 12, 5, 1, 30);

  group('cómo lo lee el locutor si nadie lo cambió', () {
    test('APELLIDO, NOMBRES se lee de corrido', () {
      expect(deCorrido('PÉREZ, JUAN IGNACIO'), 'JUAN IGNACIO PÉREZ');
      expect(deCorrido('PÉREZ JUAN'), 'PÉREZ JUAN', reason: 'sin coma, como está');
      expect(deCorrido('A, B, C'), 'A, B, C', reason: 'con dos comas, como está');
      expect(deCorrido('  PÉREZ ,   JUAN  [BAJA] '), 'JUAN PÉREZ');
    });
  });

  group('lo que se guarda de lo que se escribió', () {
    test('sin espacios de más, saltos, emojis ni letras raras; con acentos, ñ y comillas', () {
      expect(limpiarNombre("  Juani   'el Tano'\nPérez 🎉 "), "Juani 'el Tano' Pérez");
      expect(limpiarNombre('Ñoño “el Rulo” ¡Gómez!'), 'Ñoño “el Rulo” ¡Gómez!');
      expect(limpiarNombre('Лена Ivanova'), 'Ivanova', reason: 'el cirílico no lo tiene la tele');
    });

    test('se corta en 60 letras', () {
      expect(limpiarNombre('x' * 80)!.length, kTopeNombre);
    });

    test('vacío, o igual a lo cargado o a como se lee de corrido, no es un cambio', () {
      expect(limpiarNombre('   '), isNull);
      expect(limpiarNombre('🎉🎉'), isNull);
      expect(limpiarNombre('Pérez, Juan Ignacio', cargado: 'PÉREZ, JUAN IGNACIO'), isNull);
      expect(limpiarNombre('juan ignacio perez', cargado: 'PÉREZ, JUAN IGNACIO'), isNull);
      expect(limpiarNombre('Juani', cargado: 'PÉREZ, JUAN IGNACIO'), 'Juani');
    });
  });

  group('los lugares de la familia', () {
    test('los con nombre con el número de la lista de la puerta, después los sin nombre', () {
      final a = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA', '', 'PÉREZ, TITO'], cantidad: 5);
      final lugares = lugaresDe(a);
      expect([for (final l in lugares) '${l.lugar}:${l.cargado}'],
          ['1:GÓMEZ, LAURA', '2:PÉREZ, TITO', '3:', '4:', '5:']);
      // El mismo número que la fila de la puerta.
      final filas = filasPuertaDesdeAlumnos([a]).where((f) => !f.esAlumno).toList();
      expect(filas[1].id, idInvitadoPuerta(_alumno, 2));
    });

    test('nunca más que los que tiene, y con tope', () {
      final a = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['A, B'], cantidad: 1);
      expect(lugaresDe(a), hasLength(1));
      final muchos = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', cantidad: 80);
      expect(lugaresDe(muchos), hasLength(kMaxLugaresPorAlumno - 1));
    });
  });

  group('lo guardado, cruzado con la lista de hoy', () {
    final a = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA', 'PÉREZ, TITO'], cantidad: 3);

    ComoLoNombran fila({String? alumno, List<NombreDeAcompanante> acomp = const [], String cargado = 'PÉREZ, JUAN'}) =>
        ComoLoNombran.para(
          eventoId: eventoMasivo,
          contratoAlumnoId: _alumno,
          alumno: alumno,
          alumnoCargado: cargado,
          acompanantes: acomp,
          cambiadoPor: 'Juli',
          ahora: ahora,
        );

    test('cada uno con lo suyo, también el sin nombre por su lugar', () {
      final f = NombresDeLaFamilia.delAlumno(
        a,
        fila(alumno: "Juani 'el Tano'", acomp: const [
          NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, LAURA', nombre: 'Lau'),
          NombreDeAcompanante(lugar: 3, cargado: '', nombre: 'la abuela Tita'),
        ]),
      );
      expect(f.alumno, "Juani 'el Tano'");
      expect(f.porLugar, {1: 'Lau', 3: 'la abuela Tita'});
      expect(f.sobrantes, isEmpty);
      expect(f.cambiadoPor, 'Juli');
    });

    test('si la oficina reordenó, el nombre sigue a su persona', () {
      final reordenado = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['PÉREZ, TITO', 'GÓMEZ, LAURA'], cantidad: 3);
      final f = NombresDeLaFamilia.delAlumno(reordenado, fila(acomp: const [
        NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, LAURA', nombre: 'Lau'),
      ]));
      expect(f.porLugar, {2: 'Lau'}, reason: 'Laura pasó al lugar 2');
    });

    test('si la oficina corrigió el nombre, lo nombrado no se aplica a otra persona', () {
      final corregido = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GOMEZ, LAURA BEATRIZ', 'PÉREZ, TITO'], cantidad: 2);
      final f = NombresDeLaFamilia.delAlumno(corregido, fila(acomp: const [
        NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, LAURA', nombre: 'Lau'),
      ]));
      expect(f.porLugar, isEmpty);
      expect(f.sobrantes.single, contains('Lau'));
      // Y si le corrigieron el nombre al egresado, tampoco.
      final otro = NombresDeLaFamilia.delAlumno(
          alumnoDePrueba(_alumno, 'PÉREZ, JUAN MARTÍN', acomp: const [], cantidad: 0), fila(alumno: 'Juani'));
      expect(otro.alumno, isNull);
      expect(otro.sobrantes.single, contains('Juani'));
    });

    test('la firma cambia con cualquier cosa, y sin fila o con la fila vacía da lo mismo', () {
      final base = NombresDeLaFamilia.delAlumno(a, null);
      expect(NombresDeLaFamilia.delAlumno(a, fila()).firma, base.firma);
      expect(NombresDeLaFamilia.delAlumno(a, fila(alumno: 'Juani')).firma, isNot(base.firma));
      final otraLista = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA'], cantidad: 3);
      expect(NombresDeLaFamilia.delAlumno(otraLista, null).firma, isNot(base.firma));
      // Lo mismo con otro updated_at: la misma firma.
      final una = fila(alumno: 'Juani');
      final mapa = {...una.toMap(), 'updated_at': '2030-01-01T00:00:00.000Z'};
      expect(NombresDeLaFamilia.delAlumno(a, ComoLoNombran.fromMap(mapa)).firma,
          NombresDeLaFamilia.delAlumno(a, una).firma);
    });

    test('la fila nueva: limpia, solo lo cambiado, y nada si queda igual', () {
      final f = NombresDeLaFamilia.delAlumno(a, null);
      final nueva = f.filaCon(
        DatosNombres(alumno: ' Juani 🎉', lugares: const {1: 'Lau', 2: 'PÉREZ, TITO', 7: 'nadie'}, antes: f.firma),
        eventoId: eventoMasivo,
        contratoId: _alumno,
        por: 'Juli',
        ahora: ahora,
      )!;
      expect(nueva.alumno, 'Juani');
      expect(nueva.alumnoCargado, 'PÉREZ, JUAN');
      expect([for (final x in nueva.acompanantes) '${x.lugar}:${x.nombre}'], ['1:Lau'],
          reason: 'el 2 quedó como en la lista y el 7 no es de la familia');
      expect(nueva.cambiadoPor, 'Juli');
      final ya = f.conFila(nueva);
      expect(
        ya.filaCon(DatosNombres(alumno: 'Juani', lugares: const {1: 'Lau'}, antes: ya.firma),
            eventoId: eventoMasivo, contratoId: _alumno, por: 'Juli', ahora: ahora),
        isNull,
      );
    });

    test('ida y vuelta por la red', () {
      final f = NombresDeLaFamilia.delAlumno(a, fila(alumno: 'Juani', acomp: const [
        NombreDeAcompanante(lugar: 2, cargado: 'PÉREZ, TITO', nombre: 'Tito'),
      ]));
      final vuelta = NombresDeLaFamilia.fromJson(f.toJson())!;
      expect(vuelta.firma, f.firma);
      expect(vuelta.alumno, 'Juani');
      expect(vuelta.porLugar, {2: 'Tito'});
      expect([for (final l in vuelta.lugares) l.cargado], ['GÓMEZ, LAURA', 'PÉREZ, TITO', '']);
      final d = DatosNombres(alumno: 'Juani', lugares: const {2: 'Tito'}, antes: f.firma);
      expect(DatosNombres.fromJson(d.toJson()), d);
      expect(DatosNombres.fromJson({'antes': 'x', 'l': [[99, 'no'], [-1, 'no'], 'roto']})!.lugares, isEmpty);
    });

    test('un JSON roto de los acompañantes se lee como ninguno', () {
      final m = {...fila(alumno: 'Juani').toMap(), 'acompanantes': '{roto'};
      expect(ComoLoNombran.fromMap(m).acompanantes, isEmpty);
      expect(ComoLoNombran.fromMap(m).alumno, 'Juani');
    });
  });

  group('en la puerta', () {
    test('la familia lleva lo nombrado y la institución; el nombre sigue siendo el cargado', () {
      final a = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA'], institucion: 'ESCUELA NORMAL', cantidad: 2);
      final puerta = PuertaDelEvento.masivo(
        alumnos: [a],
        invitados: const [],
        nombres: {
          _alumno: ComoLoNombran.para(
            eventoId: eventoMasivo,
            contratoAlumnoId: _alumno,
            alumno: 'Juani',
            alumnoCargado: 'PÉREZ, JUAN',
            acompanantes: const [NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, LAURA', nombre: 'Lau')],
            ahora: ahora,
          ),
        },
      );
      final g = puerta.grupos.single;
      expect(g.institucion, 'ESCUELA NORMAL');
      expect(g.titular.nombre, 'PÉREZ, JUAN');
      expect(g.titular.nombrado, 'Juani');
      expect(g.acompanantes.single.nombrado, 'Lau');
      expect(g.nombres!.lugares, hasLength(2));
      // Se busca por los dos.
      expect(puerta.buscar('juani').single, g);
      expect(puerta.buscar('lau').single, g);
      expect(puerta.buscar('gomez').single, g);
      // Ida y vuelta a un celular.
      final vuelta = PuertaDelEvento.fromJson(puerta.toJson(), eventoId: eventoMasivo).grupos.single;
      expect(vuelta.titular.nombrado, 'Juani');
      expect(vuelta.institucion, 'ESCUELA NORMAL');
      expect(vuelta.nombres!.firma, g.nombres!.firma);
    });

    test('una central vieja (sin lo nuevo) se lee igual', () {
      final a = alumnoDePrueba(_alumno, 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA']);
      final json = PuertaDelEvento.masivo(alumnos: [a], invitados: const []).toJson();
      for (final g in json['grupos'] as List) {
        (g as Map).remove('nombres');
        g.remove('institucion');
      }
      final g = PuertaDelEvento.fromJson(json, eventoId: eventoMasivo).grupos.single;
      expect(g.nombres, isNull);
      expect(g.titular.nombrado, isNull);
    });
  });

  test('nada de esto toca la ficha de la oficina ni la lista de la puerta', () {
    for (final ruta in [
      'lib/models/como_lo_nombran.dart',
      'lib/features/recepcion/services/como_lo_nombran.dart',
      'lib/features/recepcion/repositories/como_lo_nombran_repository.dart',
    ]) {
      final codigo = File(ruta).readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      for (final prohibido in ["'contratos_alumnos'", "'invitados'", 'guardarEdicionDeAlumno']) {
        expect(codigo, isNot(contains(prohibido)), reason: '$ruta nombra $prohibido');
      }
    }
  });
}
