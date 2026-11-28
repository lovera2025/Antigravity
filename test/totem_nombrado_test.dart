import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/totem/services/puente_ficha.dart';
import 'package:arguello_events/features/totem/services/totem_sigue_los_nombres.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

/// **El tótem saluda con lo nombrado** (el locutor, 28-nov-2026, etapa 5): con un cambio,
/// con eso; sin cambio, con lo cargado (nunca "de corrido"); y al instante, por el aviso
/// `ficha_cambio` entre las ventanas.
void main() {
  final supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  final contratos = ContratosEnMemoria(supabase, alumnosDeLaFicha());
  final sillas = SillasEnMemoria();
  final eventos = {eventoMasivo: eventoDePrueba(eventoMasivo, 'masivo')};

  ComoLoNombran juani() => ComoLoNombran.para(
        eventoId: eventoMasivo,
        contratoAlumnoId: 'perez',
        alumno: "Juani 'el Tano' Pérez",
        alumnoCargado: 'PÉREZ, JUAN MARTÍN',
        acompanantes: const [NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, ANA', nombre: 'la Negra')],
        ahora: DateTime.utc(2026, 12, 5, 1),
      );

  Future<dynamic> armar({Future<Map<String, ComoLoNombran>> Function(String)? leerNombres}) => armarFichaTotem(
        eventoMasivo,
        leerEvento: (id) async => eventos[id],
        leerAlumnos: (id) => leerAlumnosDeLaPuerta(contratos, sillas, id),
        leerNombres: leerNombres,
      );

  test('con un cambio saluda con eso, también a quien acompaña; sin cambio, con lo cargado', () async {
    final ficha = await armar(leerNombres: (_) async => {'perez': juani()});
    final personas = ficha.personas.values.toList();
    final alumno = personas.firstWhere((p) => p.familia == personas.firstWhere((x) => x.esAlumno && x.nombre.contains('Tano')).familia && p.esAlumno);
    expect(alumno.nombre, "Juani 'el Tano' Pérez");
    final ana = personas.firstWhere((p) => p.nombre == 'la Negra');
    expect(ana.titular, "Juani 'el Tano' Pérez", reason: '"acompaña a" con el apodo');
    expect(personas.any((p) => p.nombre == 'PÉREZ, LUIS'), isTrue, reason: 'el acompañante sin cambio, como está cargado');
    expect(personas.any((p) => p.nombre == 'ACOSTA, LUCÍA'), isTrue, reason: 'la otra familia, como siempre');
    expect(personas.any((p) => p.nombre == 'LUCÍA ACOSTA'), isFalse, reason: 'nunca de corrido');
  });

  test('si no se pueden leer los nombres, la ficha sale igual, con lo cargado', () async {
    final ficha = await armar(leerNombres: (_) async => throw StateError('base cerrada'));
    expect(ficha.personas.values.any((p) => p.nombre == 'PÉREZ, JUAN MARTÍN'), isTrue);
  });

  test('varios cambios seguidos de una fiesta dan un solo aviso al tótem', () async {
    final cambios = StreamController<String>();
    final avisados = <String>[];
    final sigue = TotemSigueLosNombres(
      cambios: cambios.stream,
      avisar: (id) async => avisados.add(id),
      espera: const Duration(milliseconds: 50),
    )..arrancar();
    cambios
      ..add(eventoMasivo)
      ..add(eventoMasivo)
      ..add(eventoMasivo)
      ..add('otra');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(avisados..sort(), [eventoMasivo, 'otra']..sort());
    await sigue.parar();
    await cambios.close();
  });

  test('la ventana del tótem atiende "ficha_cambio": solo su fiesta, no pausada, y pide la ficha', () {
    final codigo = File('lib/features/totem/totem_display.dart').readAsStringSync();
    final i = codigo.indexOf("case 'ficha_cambio':");
    expect(i, greaterThan(0));
    final rama = codigo.substring(i, codigo.indexOf('return null;', i));
    expect(rama, contains('avisoEsDeEsteEvento(call.arguments, _eventoId)'));
    expect(rama, contains('!_pausado'));
    expect(rama, contains('_pedirFicha()'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('TotemSigueLosNombres('));
    expect(main, contains('leerNombres:'));
  });
}
