import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/recepcion/services/lista_del_locutor.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/reservados_de_la_puerta.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/puerta_en_memoria.dart';

/// **La lista del locutor** (28-nov-2026, etapa D): lo que ve en su celular, armado con la
/// misma lista de la puerta que ve Recepción. Nombres inventados.
const _a1 = 'a0000000-0000-4000-8000-000000000001';
const _a2 = 'a0000000-0000-4000-8000-000000000002';
const _a3 = 'a0000000-0000-4000-8000-000000000003';
const _baja = 'a0000000-0000-4000-8000-000000000004';

void main() {
  final ahora = DateTime.utc(2026, 12, 5, 1, 30);

  PuertaDelEvento puerta({Map<String, ComoLoNombran> nombres = const {}, List<ReservadoPuerta> reservados = const []}) =>
      PuertaDelEvento.masivo(
        alumnos: [
          alumnoDePrueba(_a2, 'SAUCE, PEDRO', institucion: 'ESCUELA NORMAL', division: '5° A'),
          alumnoDePrueba(_a1, 'CEIBO, ANA',
              acomp: ['ULMO, CELIA', 'ROBLE, TITO'], institucion: 'ESCUELA NORMAL', division: '5° A', cantidad: 3),
          alumnoDePrueba(_a3, 'TALA, LUIS', institucion: 'INSTITUTO SUR', division: '6° B'),
          alumnoDePrueba(_baja, '[BAJA] ALAMO, RITA', institucion: 'ESCUELA NORMAL', division: '5° A'),
        ],
        invitados: const [],
        nombres: nombres,
        reservados: reservados,
      );

  ComoLoNombran juani({String alumno = 'Ani'}) => ComoLoNombran.para(
        eventoId: eventoMasivo,
        contratoAlumnoId: _a1,
        alumno: alumno,
        alumnoCargado: 'CEIBO, ANA',
        acompanantes: const [
          NombreDeAcompanante(lugar: 2, cargado: 'ROBLE, TITO', nombre: 'el Tano'),
          NombreDeAcompanante(lugar: 3, cargado: '', nombre: 'la abuela Tita'),
        ],
        cambiadoPor: 'Juli',
        ahora: ahora,
      );

  test('va por institución y división, cada familia por apellido; sin bajas', () {
    final l = ListaDelLocutor.de([puerta()]);
    expect([for (final i in l.instituciones) i.nombre], ['ESCUELA NORMAL', 'INSTITUTO SUR']);
    final normal = l.instituciones.first.divisiones.single;
    expect(normal.nombre, '5° A');
    expect([for (final f in normal.familias) f.alumno.cargado], ['CEIBO, ANA', 'SAUCE, PEDRO'],
        reason: 'la baja no va');
    final ana = normal.familias.first;
    expect(ana.alumno.nombre, 'ANA CEIBO', reason: 'sin cambio, de corrido');
    expect(ana.alumno.cambiado, isFalse);
    expect([for (final a in ana.acompanantes) a.nombre], ['CELIA ULMO', 'TITO ROBLE']);
    expect(ana.sinNombre, 1);
    expect(ana.cambiadoAt, isNull);
    expect(l.cambiadas, 0);
  });

  test('lo nombrado gana, con lo cargado al lado; y un lugar sin nombre que nombraron va también', () {
    final ana = ListaDelLocutor.de([puerta(nombres: {_a1: juani()})]).familias.first;
    expect(ana.alumno.nombre, 'Ani');
    expect(ana.alumno.cargado, 'CEIBO, ANA');
    expect(ana.alumno.cambiado, isTrue);
    expect([for (final a in ana.acompanantes) (a.nombre, a.cambiado)],
        [('CELIA ULMO', false), ('el Tano', true), ('la abuela Tita', true)]);
    expect(ana.sinNombre, 0);
    expect(ana.cambiadoAt, ahora.millisecondsSinceEpoch);
  });

  test('los profes de una mesa reservada no van', () {
    final l = ListaDelLocutor.de([
      puerta(reservados: const [ReservadoPuerta(id: 'r1', nombre: 'GARCÍA, ANA', mesa: 9, para: 'Profes')]),
    ]);
    expect(l.familias.map((f) => f.alumno.cargado), isNot(contains('GARCÍA, ANA')));
    expect(l.familias, hasLength(3));
  });

  test('una fiesta particular no suma nada', () {
    final particular = PuertaDelEvento.particular(const []);
    expect(ListaDelLocutor.de([particular]).estaVacia, isTrue);
  });

  test('con las dos escuelas de la tele, una sola lista', () {
    final otra = PuertaDelEvento.masivo(
      alumnos: [alumnoDePrueba(_a1, 'MOLLE, EVA', institucion: 'COLEGIO ESTE', evento: 'otra')],
      invitados: const [],
    );
    final l = ListaDelLocutor.de([puerta(), otra]);
    expect([for (final i in l.instituciones) i.nombre], ['COLEGIO ESTE', 'ESCUELA NORMAL', 'INSTITUTO SUR']);
  });

  test('ida y vuelta por el wifi; sin cambio no viaja el nombre (sale de lo cargado)', () {
    final l = ListaDelLocutor.de([puerta(nombres: {_a1: juani()})]);
    final texto = jsonEncode(l.toJson());
    expect(texto, isNot(contains('PEDRO SAUCE')), reason: 'sin cambio no se manda de corrido');
    final vuelta = ListaDelLocutor.fromJson(jsonDecode(texto));
    expect(vuelta.firma, l.firma);
    final pedro = vuelta.familias.firstWhere((f) => f.alumno.cargado == 'SAUCE, PEDRO');
    expect(pedro.alumno.nombre, 'PEDRO SAUCE');
    expect(ListaDelLocutor.fromJson('roto').estaVacia, isTrue);
    expect(ListaDelLocutor.fromJson([{'n': 'X', 'd': 'roto'}]).estaVacia, isTrue);
  });

  test('la firma: un ingreso no la cambia; un nombre sí', () {
    final antes = ListaDelLocutor.de([puerta()]).firma;
    expect(ListaDelLocutor.de([puerta()]).firma, antes);
    expect(ListaDelLocutor.de([puerta(nombres: {_a1: juani()})]).firma, isNot(antes));
    expect(ListaDelLocutor.de([puerta(nombres: {_a1: juani(alumno: 'Anita')})]).firma,
        isNot(ListaDelLocutor.de([puerta(nombres: {_a1: juani()})]).firma));
  });

  test('buscar: por lo nombrado, por lo cargado y por un acompañante, sin acentos', () {
    final l = ListaDelLocutor.de([puerta(nombres: {_a1: juani()})]);
    expect(l.buscar('tano').single.id, _a1);
    expect(l.buscar('ceibo').single.id, _a1);
    expect(l.buscar('ulmo celia').single.id, _a1);
    expect(l.buscar('TALA').single.alumno.cargado, 'TALA, LUIS');
    expect(l.buscar('nadie'), isEmpty);
    expect(l.buscar('  '), hasLength(3));
  });
}
