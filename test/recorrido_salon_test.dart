// El recorrido entero del plano antes del sorteo (etapa 7 de
// docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md), con las mismas cuentas que usan las
// pantallas: Puerto Viejo como está en la nube → guardar (se ordena) → sortear con dos
// familias "lejos" → juntas, lejos y números en orden → deshacer → barra a 3 m →
// sortear de nuevo. Sin base ni nube.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

/// Lo que hay guardado: el salón y lo configurado, como una fila de `planos_evento`.
class _Guardado {
  ArmadoSalon armado;
  ConfigPlano config;
  _Guardado(this.armado, this.config);
}

ContratoAlumno _familia(String id, {int extras = 0, List<int>? mesas}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas == null ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// La escuela sin sortear: dos familias "lejos", tres con adicional, el resto con una.
List<ContratoAlumno> _sinMesa() => [
      _familia('cerca', extras: 1),
      _familia('lejana', extras: 1),
      _familia('dos', extras: 1),
      _familia('tres', extras: 2),
      _familia('otra', extras: 1),
      for (var i = 0; i < 20; i++) _familia('s$i'),
    ];

List<ContratoAlumno> _sentadas(Map<String, List<int>> asignaciones) => [
      for (final a in _sinMesa())
        _familia(
          a.id,
          extras: a.mesaExtraCantidad,
          mesas: asignaciones[a.id],
        ),
    ];

void main() {
  /// Guarda lo acomodado en [s], como GUARDAR EL SALÓN.
  void guardar(
    _Guardado g,
    SesionAcomodo s,
    List<ContratoAlumno> alumnos,
  ) {
    final c = EditarArmado.paraGuardar(
      base: s.base,
      nuevo: s.actual,
      fresco: g.armado,
      config: g.config,
      alumnos: alumnos,
      enUsoVisto: EditarArmado.enUso(alumnos, g.config),
      rehecho: s.rehecho,
      lugarBarraM: s.lugarDeLaBarra,
    );
    expect(c.sePuede, isTrue, reason: c.problema);
    g.armado = c.armado ?? g.armado;
    g.config = c.config!;
  }

  ResultadoSorteoPlano sortear(_Guardado g, int semilla) {
    final entrada = EntradaSorteoPlano(
      armado: g.armado,
      config: g.config,
      alumnos: _sinMesa(),
      separaciones: const {'cerca': 1, 'lejana': 1},
      distancias: const {
        'cerca': DistanciaLejos.cerca,
        'lejana': DistanciaLejos.bienLejos,
      },
    );
    final plan = SorteoConPlano.preparar(entrada);
    expect(plan.entra, isTrue, reason: plan.avisos.join(' '));
    final r = SorteoConPlano.sortear(entrada, random: Random(semilla));
    expect(SorteoConPlano.validar(entrada, r), isNull);
    return r;
  }

  void todoEnOrden(ArmadoSalon a, ResultadoSorteoPlano r) {
    expect(a.numeros, [for (var n = 1; n <= a.mesas.length; n++) n]);
    expect(
      {for (final l in r.asignaciones.values) ...l}.length,
      r.asignaciones.values.fold<int>(0, (s, l) => s + l.length),
      reason: 'ninguna mesa dos veces',
    );
    // Con adicional, juntas. Las "lejos", sin tocarse.
    for (final id in ['dos', 'tres', 'otra']) {
      expect(
        SorteoConPlano.tramosPegados(a, r.asignaciones[id]!),
        hasLength(1),
        reason: '$id quedó partida',
      );
    }
    expect(r.asignaciones['tres'], hasLength(3));
    for (final id in ['cerca', 'lejana']) {
      expect(
        SorteoConPlano.lejosEnElSalon(a, r.asignaciones[id]!, 1),
        isTrue,
        reason: '$id quedó tocándose',
      );
    }
    for (var i = 0; i < 20; i++) {
      expect(r.asignaciones['s$i'], hasLength(1));
    }
  }

  test('de punta a punta, varias veces', () {
    for (var semilla = 0; semilla < 25; semilla++) {
      final g = _Guardado(armadoDePuertoViejo(), ConfigPlano.vacia);
      final alumnos = _sinMesa();

      // 1. Como está en la nube: mezclado. El plano lo avisa.
      expect(g.armado.cortes, hasLength(13));
      final hoy = PlanoDeLaFiesta.desde(
        armado: g.armado,
        config: g.config,
        alumnos: alumnos,
      );
      expect(
        hoy.avisos.where((a) => a.texto.startsWith('Los números no siguen')),
        hasLength(1),
      );

      // 2. Abrir y guardar: se ordena, sin mover ninguna mesa.
      final lugares = {for (final m in g.armado.mesas) '${m.x} ${m.y}'};
      final abierta = SesionAcomodo(base: g.armado);
      expect(abierta.puedeGuardar, isTrue);
      guardar(g, abierta, alumnos);
      expect(g.armado.cortes, {17});
      expect({for (final m in g.armado.mesas) '${m.x} ${m.y}'}, lugares);

      // 3. Sortear, con una familia "cerca" y una "bien lejos".
      final primero = sortear(g, semilla);
      todoEnOrden(g.armado, primero);

      // 4. Con el sorteo hecho, los números no se tocan, y la barra estira.
      final sentadas = _sentadas(primero.asignaciones);
      final conFamilias = SesionAcomodo(base: g.armado, haySorteo: true);
      expect(conFamilias.barraReacomoda, isFalse);
      expect(conFamilias.faltaOrdenar, isFalse);
      final antes = g.armado.numeros;
      final corrida = g.armado.mesa(1)!;
      conFamilias.empezarArrastre();
      conFamilias.arrastrarMesa(1, corrida.x, corrida.y + g.armado.aUnidades(0.5));
      conFamilias.terminarArrastre();
      final guardadoAntes = g.armado;
      guardar(g, conFamilias, sentadas);
      expect(g.armado.numeros, antes);
      expect(g.armado.mesa(1)!.y, isNot(guardadoAntes.mesa(1)!.y));

      // 5. Lo que marca el plano sale de lo sorteado.
      final familias = PlanoDeLaFiesta.desde(
        armado: g.armado,
        config: g.config,
        alumnos: sentadas,
      ).familias;
      expect(familias.hayJuntas, isTrue);
      expect(familias.haySeparadas, isTrue);

      // 6. Deshacer: la escuela queda sin mesa. La barra vuelve a reacomodar, y al
      //    soltarla la distancia queda en Medidas.
      final barra = SesionAcomodo(base: g.armado, medidas: g.config.medidas);
      expect(barra.barraReacomoda, isTrue);
      final r = barra.moverLaBarra(35, 3.0)!;
      expect(r.faltan, 0);
      barra.soltarLaBarra();
      guardar(g, barra, alumnos);
      expect(g.config.medidas.lugarMesaM, 3.0);
      expect(g.armado.distanciaM(1, 2), closeTo(3.0, 1e-6));
      expect(ArmadoSalon.fromJson(g.armado.toJson()).numeros, g.armado.numeros);

      // 7. Sortear de nuevo, sobre el salón a 3 m.
      todoEnOrden(g.armado, sortear(g, semilla + 1000));
    }
  });
}
