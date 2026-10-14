// Lo que el tótem muestra del salón cuando llega una familia de un evento masivo
// (`PlanoDeLaLlegada`, sección 4 de la 6.0.0): la hoja de su mesa, con su mesa
// encendida y la familia como único ocupante.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/totem/services/plano_de_la_llegada.dart';

void main() {
  final salon = ArmadosPredefinidos.normal2aPagina3();
  final dosHojas = ArmadosPredefinidos.normal2a2b();

  test('una mesa: esa hoja, esa mesa encendida y la familia', () {
    final g = PlanoDeLaLlegada.para(salon, mesa: '12', nombre: 'PÉREZ, JUAN')!;
    expect(g.mesas, {12});
    expect(g.principal, 12);
    expect(g.hoja, salon.mesa(12)!.hoja);
    final info = g.estado.info(12);
    expect(info.estado, EstadoMesa.ocupada);
    expect(info.principal, isTrue);
    expect(info.ocupante!.apellido, 'PÉREZ');
    // Va en la única división: la que el tema del tótem pinta con el color
    // del evento.
    expect(info.division, 0);
    expect(g.estado.divisiones, hasLength(1));
    // Las demás, vacías.
    expect(g.estado.info(13).estado, EstadoMesa.vacia);
  });

  test('dos mesas: las dos encendidas, la principal es la primera', () {
    final g =
        PlanoDeLaLlegada.para(salon, mesa: '14-15', nombre: 'ACOSTA, LUCÍA')!;
    expect(g.mesas, {14, 15});
    expect(g.principal, 14);
    for (final n in [14, 15]) {
      expect(g.estado.info(n).estado, EstadoMesa.ocupada, reason: '$n');
    }
    // Una familia es un solo ocupante: nunca "conflicto".
    expect(
      g.estado.mesas.where((i) => i.estado == EstadoMesa.conflicto),
      isEmpty,
    );
  });

  test('sin plano, sin mesa o con un número que el plano no tiene: nada', () {
    expect(PlanoDeLaLlegada.para(null, mesa: '12', nombre: 'X'), isNull);
    expect(PlanoDeLaLlegada.para(salon, mesa: null, nombre: 'X'), isNull);
    expect(PlanoDeLaLlegada.para(salon, mesa: '', nombre: 'X'), isNull);
    expect(PlanoDeLaLlegada.para(salon, mesa: '999', nombre: 'X'), isNull);
  });

  test('un número que no está no tapa a los que sí', () {
    final g = PlanoDeLaLlegada.para(
      salon,
      mesa: MesasExtraUtils.formatearAsignacionMesas([12, 999]),
      nombre: 'X',
    )!;
    expect(g.mesas, {12});
  });

  test('mesas en dos hojas: se ve la de la principal, con sus mesas', () {
    final a = dosHojas.mesas.firstWhere((m) => m.hoja == dosHojas.hojas[0].id);
    final otras = dosHojas.mesas
        .where((m) => m.hoja == dosHojas.hojas[1].id)
        .map((m) => m.numero)
        .toList()
      ..sort();
    // Dos seguidas en la segunda hoja y una suelta en la primera: la principal
    // es la del tramo más largo.
    final numeros = [a.numero, otras[0], otras[1]];
    final g = PlanoDeLaLlegada.para(
      dosHojas,
      mesa: MesasExtraUtils.formatearAsignacionMesas(numeros),
      nombre: 'X',
    )!;
    expect(g.principal, otras[0]);
    expect(g.hoja, dosHojas.hojas[1].id);
    expect(g.mesas, {otras[0], otras[1]});
  });
}
