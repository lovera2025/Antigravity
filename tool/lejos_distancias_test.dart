// Medición: a cuántos lugares queda una mesa marcada "lejos", con cada opción. 1.000
// sorteos por salón, con 20 familias "1 lejos" en cada uno. No toca la base ni la nube.
//
//   flutter test tool/lejos_distancias_test.dart
//
// "Sin decir" es lo de antes de la opción, y da lo mismo que "bien lejos".

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import '../test/helpers/salon_puerto_viejo.dart';

ContratoAlumno _familia(String id, {int extras = 0, String division = '5° A'}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 1,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      cursoDivision: division,
    );

void medir(
  String salon,
  ArmadoSalon a,
  int mesas,
  int lejos,
  ModoSorteo modo, {
  int sorteos = 1000,
}) {
  final divisiones = ['5° A', '5° B'];
  final alumnos = [
    for (var i = 0; i < lejos; i++)
      _familia('l$i', extras: 1, division: divisiones[i % 2]),
    for (var i = 0; i < mesas - 2 * lejos; i++)
      _familia('s$i', division: divisiones[i % 2]),
  ];
  for (final d in <DistanciaLejos?>[null, ...DistanciaLejos.values]) {
    final entrada = EntradaSorteoPlano(
      armado: a,
      alumnos: alumnos,
      modo: modo,
      separaciones: {for (var i = 0; i < lejos; i++) 'l$i': 1},
      distancias: d == null
          ? const {}
          : {for (var i = 0; i < lejos; i++) 'l$i': d},
    );
    final todas = <double>[];
    var tocan = 0;
    var conAviso = 0;
    for (var s = 0; s < sorteos; s++) {
      final r = SorteoConPlano.sortear(entrada, random: Random(s));
      conAviso += r.avisosLejos.length;
      for (var i = 0; i < lejos; i++) {
        final nums = r.asignaciones['l$i']!;
        if (!SorteoConPlano.lejosEnElSalon(a, nums, 1)) tocan++;
        todas.add(SorteoConPlano.lugaresDeLaSuelta(a, nums) ?? 0);
      }
    }
    todas.sort();
    final finitas = todas.where((x) => x.isFinite).toList();
    double p(double q) => finitas[(finitas.length * q).floor()];
    print('$salon | ${modo.name.padRight(7)} | '
        '${(d?.rotulo ?? 'sin decir').padRight(12)} | '
        'mediana ${p(0.5).toStringAsFixed(1).padLeft(5)} | '
        '5 % ${p(0.05).toStringAsFixed(1).padLeft(5)} | '
        '95 % ${p(0.95).toStringAsFixed(1).padLeft(5)} | '
        'cerca ${(100 * finitas.where((x) => x <= 3).length / todas.length).toStringAsFixed(1).padLeft(5)} % | '
        'a unas ${(100 * finitas.where((x) => x >= 3 && x <= 6).length / todas.length).toStringAsFixed(1).padLeft(5)} % | '
        'tocan $tocan | avisos $conAviso');
    expect(tocan, 0);
  }
}

void main() {
  final normal = ArmarAMedida.armar(
    const OpcionesAMedida(
      playon: PlayonReal.costaSurubi,
      cantidad: 138,
      lugarM: 2.5,
    ),
  ).armado;
  final tecnica = ArmadosPredefinidos.tecnica1a1b();
  final puertoViejo = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;

  test('la medición', () {
    medir('Normal 138  ', normal, 120, 20, ModoSorteo.entera);
    medir('Técnica     ', tecnica, 100, 20, ModoSorteo.entera);
    medir('Puerto Viejo', puertoViejo, 32, 6, ModoSorteo.entera);
    medir('Normal 138  ', normal, 120, 20, ModoSorteo.bloques, sorteos: 200);
    medir('Puerto Viejo', puertoViejo, 32, 6, ModoSorteo.bloques, sorteos: 200);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
