import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/cliente_locutor.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/central_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart' show alumnoDePrueba;

/// **El celular del locutor** (28-nov-2026, etapa D) contra la central de la puerta de
/// verdad, en esta PC. Nombres inventados.
const _evento = eventoDeLaCentral;
const _codigo = '4821';
const _codigoLocutor = '7391';
const _ana = 'a0000000-0000-4000-8000-000000000001';

class _Navegador implements GuardadoDelCelular {
  final datos = <String, String>{};

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> guardar(String clave, String? valor) async {
    if (valor == null) {
      datos.remove(clave);
    } else {
      datos[clave] = valor;
    }
  }
}

Future<void> hasta(bool Function() listo, {String? que}) async {
  final fin = DateTime.now().add(const Duration(seconds: 6));
  while (!listo()) {
    if (DateTime.now().isAfter(fin)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late PcEnMemoria pc;
  late CentralPuerta central;
  late int puerto;
  late DateTime ahora;
  final clientes = <ClienteLocutor>[];

  Future<void> prender({int desde = 0}) async {
    central = CentralPuerta(
      eventoId: _evento,
      codigo: _codigo,
      codigoLocutor: _codigoLocutor,
      pc: pc,
      ahora: () => ahora,
    );
    puerto = await central.arrancar(desde: desde, en: InternetAddress.loopbackIPv4);
  }

  PuertaDelEvento lista({ComoLoNombran? nombre}) => PuertaDelEvento.masivo(
        alumnos: pc.alumnos,
        invitados: const [],
        nombres: {if (nombre != null) _ana: nombre},
      );

  ClienteLocutor locutor(_Navegador navegador, {DateTime Function()? reloj}) {
    final c = ClienteLocutor(
      servidor: Uri.parse('http://127.0.0.1:$puerto/'),
      guardado: navegador,
      latido: const Duration(milliseconds: 40),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 40),
      ahora: reloj,
    );
    clientes.add(c);
    return c;
  }

  setUp(() async {
    ahora = DateTime.now().toUtc();
    pc = PcEnMemoria();
    pc.alumnos
      ..add(alumnoDePrueba(_ana, 'CEIBO, ANA', acomp: ['ULMO, CELIA'], institucion: 'ESCUELA NORMAL', evento: _evento))
      ..add(alumnoDePrueba('a0000000-0000-4000-8000-000000000002', 'SAUCE, PEDRO',
          institucion: 'ESCUELA NORMAL', evento: _evento));
    await prender();
    central.ponerPuerta(lista());
  });

  tearDown(() async {
    for (final c in clientes) {
      c.dispose();
    }
    clientes.clear();
    await central.cerrar();
  });

  test('con el código del QR entra sin preguntar y ve la lista', () async {
    final c = locutor(_Navegador());
    await c.iniciar(codigoDelEnlace: _codigoLocutor);
    await hasta(() => c.conectado && c.hayLista, que: 'la lista');
    expect(c.lista.familias.map((f) => f.alumno.nombre), ['ANA CEIBO', 'PEDRO SAUCE']);
    expect(central.locutoresConectados, 1);
    expect(central.puestos, isEmpty, reason: 'no es un puesto');
  });

  test('sin código lo pide; con uno equivocado lo dice', () async {
    final c = locutor(_Navegador());
    await c.iniciar();
    expect(c.estado, EstadoDelLocutor.pideCodigo);
    await c.ponerCodigo('1111');
    await hasta(() => c.estado == EstadoDelLocutor.codigoMal, que: 'código mal');
    await c.ponerCodigo(_codigoLocutor);
    await hasta(() => c.conectado && c.hayLista);
  });

  test('el código de los celulares no le sirve', () async {
    final c = locutor(_Navegador());
    await c.iniciar(codigoDelEnlace: _codigo);
    await hasta(() => c.estado == EstadoDelLocutor.codigoMal);
  });

  test('se corta la notebook: sigue con la lista a la vista y vuelve sola', () async {
    final c = locutor(_Navegador());
    await c.iniciar(codigoDelEnlace: _codigoLocutor);
    await hasta(() => c.conectado && c.hayLista);
    final viejo = puerto;
    await central.cerrar();
    await hasta(() => c.estado == EstadoDelLocutor.sinConexion, que: 'sin conexión');
    expect(c.lista.familias, hasLength(2), reason: 'lo último sigue a la vista');
    expect(c.sinConexionDesde, isNotNull);
    await prender(desde: viejo);
    central.ponerPuerta(lista());
    await hasta(() => c.conectado, que: 'que vuelva sola');
    expect(c.sinConexionDesde, isNull);
  });

  test('al recargar la página, lo último guardado se ve antes de conectarse', () async {
    final navegador = _Navegador();
    final primero = locutor(navegador);
    await primero.iniciar(codigoDelEnlace: _codigoLocutor);
    await hasta(() => primero.hayLista);
    primero.dispose();
    clientes.remove(primero);
    await central.cerrar();
    final segundo = locutor(navegador);
    await segundo.iniciar();
    expect(segundo.hayLista, isTrue);
    expect(segundo.lista.familias, hasLength(2));
    expect(segundo.estado, isNot(EstadoDelLocutor.pideCodigo), reason: 'recuerda el código');
    await prender();
  });

  test('lo cambiado llega solo, avisa y queda NUEVO hasta tocarlo; con la hora de la central', () async {
    // El celular va 3 horas atrasado: el NUEVO sale de la hora de la central.
    final c = locutor(_Navegador(), reloj: () => DateTime.now().subtract(const Duration(hours: 3)));
    await c.iniciar(codigoDelEnlace: _codigoLocutor);
    await hasta(() => c.conectado && c.hayLista);
    final avisos = <List<String>>[];
    final escucha = c.cambios.listen((f) => avisos.add([for (final x in f) x.alumno.nombre]));
    central.ponerPuerta(lista(
      nombre: ComoLoNombran.para(
        eventoId: _evento,
        contratoAlumnoId: _ana,
        alumno: 'Ani',
        alumnoCargado: 'CEIBO, ANA',
        cambiadoPor: 'Juli',
        ahora: ahora,
      ),
    ));
    await hasta(() => c.lista.familias.first.alumno.nombre == 'Ani', que: 'el nombre nuevo');
    await hasta(() => avisos.isNotEmpty);
    expect(avisos.single, ['Ani']);
    final ani = c.lista.familias.first;
    expect(c.esNueva(ani), isTrue);
    expect(c.esNueva(c.lista.familias.last), isFalse);
    c.visto(ani);
    expect(c.esNueva(ani), isFalse);
    await escucha.cancel();
  });

  test('una pestaña de puesto y otra de locutor en el mismo navegador no se sacan entre sí', () async {
    final navegador = _Navegador();
    final puesto = ClienteCentral(
      servidor: Uri.parse('http://127.0.0.1:$puerto/'),
      guardado: navegador,
      latido: const Duration(milliseconds: 40),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 40),
    );
    addTearDown(puesto.dispose);
    await puesto.iniciar(codigoDelEnlace: _codigo);
    await puesto.ponerDatos(nombre: 'Juli');
    final c = locutor(navegador);
    await c.iniciar(codigoDelEnlace: _codigoLocutor);
    await hasta(() => c.conectado && central.puestos.any((p) => p.conectado), que: 'los dos conectados');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(c.conectado, isTrue);
    expect(central.puestos.single.conectado, isTrue);
    expect(central.locutoresConectados, 1);
  });
}
