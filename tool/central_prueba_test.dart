// Una central de la puerta de prueba, con un evento masivo inventado y sin
// abrir la base: para mirar la página del celular en un navegador de verdad.
//
//   flutter build web -t lib/puesto_main.dart --no-web-resources-cdn -o <ruta absoluta>\build\puesto
//   flutter test tool/central_prueba_test.dart --dart-define=minutos=10
//
// Se abre http://127.0.0.1:8799/?c=4821. Con --dart-define=red=si escucha en
// todas las conexiones de la PC (para un celular en el mismo wifi; Windows
// pregunta por el cortafuegos) y escribe las direcciones.
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/direcciones_red.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _minutos = int.fromEnvironment('minutos', defaultValue: 10);
const _puerto = int.fromEnvironment('puerto', defaultValue: 8799);
const _red = String.fromEnvironment('red') == 'si';

final _nombres = [
  ('PÉREZ, JUAN MARTÍN', ['GÓMEZ, ANA', 'PÉREZ, LUIS'], 'Tusa · Karol G'),
  ('ACOSTA, LUCÍA', <String>[], 'Despechá · Rosalía'),
  ('BENÍTEZ, TOMÁS', ['BENÍTEZ, SOL'], null),
  ('FERNÁNDEZ, MÍA', ['FERNÁNDEZ, JUAN'], 'Ella · Callejero Fino'),
  ('GARCÍA, BRUNO', <String>[], null),
  ('LÓPEZ, VALENTINA', ['LÓPEZ, CARLA'], null),
  ('MARTÍNEZ, LAUTARO', <String>[], 'Quevedo · Bizarrap'),
  ('RODRÍGUEZ, CAMILA', ['RODRÍGUEZ, ANDREA', 'SOSA, PABLO'], null),
  ('SÁNCHEZ, THIAGO', <String>[], null),
  ('TORRES, MARTINA', ['TORRES, JULIO'], null),
  ('VERA, BENJAMÍN', <String>[], null),
  ('ZAPATA, ABRIL', ['ZAPATA, NORA'], 'Mon Amour · Zzoilo'),
];

class _PcDePrueba implements PuertaDeEstaPc {
  _PcDePrueba(this.alumnos);
  final List<ContratoAlumno> alumnos;
  final filas = <String, Invitado>{};
  void Function()? alCambiar;

  PuertaDelEvento lista() => PuertaDelEvento.masivo(
        alumnos: alumnos,
        invitados: filas.values.toList(),
      );

  @override
  Future<Invitado?> fila(String id) async => filas[id];

  @override
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  }) async {
    filas[persona.id] = Invitado(
      id: persona.id,
      eventoId: eventoId,
      nombreCompleto: persona.nombre,
      dni: '',
      numeroMesa: persona.mesa,
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: DateTime.now().toUtc(),
    );
    // ignore: avoid_print
    print('INGRESÓ ${persona.nombre}${saludar ? '' : ' (sin saludar)'}');
    alCambiar?.call();
  }

  @override
  Future<void> deshacer(String id) async {
    filas[id] = filas[id]!.copyWith(
      estadoIngreso: EstadoIngreso.pendiente,
      updatedAt: DateTime.now().toUtc(),
    );
    // ignore: avoid_print
    print('DESHIZO ${filas[id]!.nombreCompleto}');
    alCambiar?.call();
  }
}

void main() {
  test('central de prueba', () async {
    final alumnos = [
      for (var i = 0; i < _nombres.length; i++)
        alumnoDePrueba(
          'c${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
          _nombres[i].$1,
          mesas: [10 + i],
          sillas: i.isEven ? 2 : 0,
          acomp: _nombres[i].$2,
          musica: _nombres[i].$3,
          division: i < 6 ? '5° A' : '5° B',
        ),
    ];
    final pc = _PcDePrueba(alumnos);
    // Dos ya adentro.
    for (final a in alumnos.take(2)) {
      final id = idInvitadoPuerta(a.id, 0);
      pc.filas[id] = Invitado(
        id: id,
        eventoId: eventoMasivo,
        nombreCompleto: a.nombreAlumno,
        dni: '',
        estadoIngreso: EstadoIngreso.ingresado,
        updatedAt: DateTime.now().toUtc(),
      );
    }

    final pagina = Directory('build${Platform.pathSeparator}puesto');
    final central = CentralPuerta(
      eventoId: eventoMasivo,
      codigo: '4821',
      pc: pc,
      paginaDelCelular: pagina.existsSync() ? pagina : null,
    )..ponerTitulo('ESCUELA DE MUESTRA — Egresados (12/12) · masivo');
    pc.alCambiar = () => central.ponerPuerta(pc.lista());
    final puerto = await central.arrancar(
      desde: _puerto,
      en: _red ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
    );
    central.ponerPuerta(pc.lista());
    central.cambiosDePuestos.listen((p) {
      // ignore: avoid_print
      print('PUESTOS: ${[for (final x in p) '${x.nombre}${x.conectado ? '' : ' (sin señal)'} ${x.marcados}']}');
    });

    // ignore: avoid_print
    print('CENTRAL en http://127.0.0.1:$puerto/?c=4821'
        '${pagina.existsSync() ? '' : '  (SIN la página: armar build/puesto)'}');
    if (_red) {
      for (final d in await direccionesDeEstaPc()) {
        // ignore: avoid_print
        print('  en el wifi: http://$d:$puerto/?c=4821');
      }
    }
    await Future<void>.delayed(const Duration(minutes: _minutos));
    await central.cerrar();
  }, timeout: const Timeout(Duration(minutes: _minutos + 1)));
}
