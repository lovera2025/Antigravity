import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/services/divisiones.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

ContratoAlumno _a(String id, String? division) => ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 0,
      saldoDeudor: 0,
      cursoDivision: division,
    );

void main() {
  test('la misma división escrita distinto es la misma', () {
    for (final d in [
      '5° A', '5° a', '5ºA', '5 A', ' 5°a ', '5.A', '5-A', '5ª A', "5° 'A'",
      '5° "A"', '5_A', '5/A',
    ]) {
      expect(Divisiones.clave(d), '5A', reason: d);
    }
    expect(Divisiones.clave('6° Ñ'), '6N');
    expect(Divisiones.clave('7° Ú'), '7U');
    expect(Divisiones.clave(null), '');
    expect(Divisiones.clave('   '), '');
  });

  test('se muestra la forma más usada', () {
    final n = Divisiones.nombres([
      _a('1', '5° A'),
      _a('2', '5° a'),
      _a('3', '5° A'),
      _a('4', null),
    ]);
    expect(n['5A'], '5° A');
    expect(n[''], Divisiones.sinDivision);
  });

  test('orden natural: por número y después por letra, sin división al final',
      () {
    expect(
      Divisiones.ordenNatural(['10A', '', '5B', '5A', 'X']),
      ['5A', '5B', '10A', 'X', ''],
    );
  });

  test('avisa las que parecen la misma escrita distinto', () {
    final p = Divisiones.parecidas(['1', '1RA', '5A', '5AA', '5B', '7']);
    // Exactamente esos dos pares: ni uno de más.
    expect(p.toSet(), {('1', '1RA'), ('5A', '5AA')});
  });

  test('"5to A" y "5 A" se parecen: el ordinal escrito', () {
    final claves = [Divisiones.clave('5to A'), Divisiones.clave('5° A')];
    expect(claves, ['5TOA', '5A']);
    expect(Divisiones.parecidas(claves).toSet(), {('5A', '5TOA')});
    // Pero dos divisiones distintas del mismo año no.
    expect(Divisiones.parecidas(['5A', '5B', '5C']), isEmpty);
    expect(Divisiones.parecidas(['5TOA', '5TOB']), isEmpty);
  });

  test('las que no tienen número no se comparan, y van antes de "sin división"',
      () {
    expect(Divisiones.parecidas(['TURNOTARDE', 'TURNOMANANA', '']), isEmpty);
    expect(
      Divisiones.ordenNatural(['TARDE', 'MANANA', '', '3A']),
      ['3A', 'MANANA', 'TARDE', ''],
    );
  });

  test('a igual uso, se muestra la primera forma en orden alfabético', () {
    final n = Divisiones.nombres([_a('1', '5° a'), _a('2', '5° A')]);
    expect(n['5A'], '5° A');
  });
}
