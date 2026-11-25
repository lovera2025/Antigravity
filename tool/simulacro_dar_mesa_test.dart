// Simulacro de DAR MESA (6.9.4) con los datos de verdad de una fiesta, leídos
// de la nube en solo lectura y guardados en un JSON fuera de git (llevan
// nombres): el plano, los números de mesa de todos, las familias a las que el
// jefe les da la mesa, sus pagos y las mesas nuevas al fondo del registro.
//
// Hace lo mismo que la app al tocar DAR MESA A TODOS (`MesaQueDaElJefe`) y DAR
// MESA a una sola, pasa cada resultado por el control final del sorteo y
// comprueba que nadie más cambie y que ninguna mesa quede repetida. No guarda
// nada.
//
//   flutter test tool/simulacro_dar_mesa_test.dart
//     --dart-define=datos=<el JSON>
//     [--dart-define=esperado=<id>:<mesas>;<id>:<mesas>]   lo que tiene que dar
//
// El JSON se arma con una consulta a la nube (ver el CONTEXTO de la 6.9.4).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/mesa_que_da_el_jefe.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _datos = String.fromEnvironment('datos');
const _esperado = String.fromEnvironment('esperado');

void main() {
  test('DAR MESA con los datos de la fiesta', () {
    if (_datos.isEmpty) {
      print('Falta --dart-define=datos=<el JSON>: no se simula nada.');
      return;
    }
    final d = jsonDecode(File(_datos).readAsStringSync()) as Map<String, dynamic>;

    final a = Map<String, dynamic>.from(d['armado'] as Map);
    a['mesas'] = [
      for (final m in a.remove('mesas_compactas') as List)
        {'n': m[0], 'h': 'A', 'x': m[1], 'y': m[2]},
    ];
    final armado = ArmadoSalon.fromJson(a);
    final config = ConfigPlano.fromJson(jsonEncode(d['config']));
    final ahora = DateTime.utc(2026, 11, 26, 12);
    final plano = PlanoEvento.nuevo(
      eventoId: 'e',
      armado: armado,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: ahora,
    ).copyWith(config: config, ahora: ahora);

    ContratoAlumno ficha(
      String id,
      String nombre,
      String? mesa, {
      int extras = 0,
      double precioExtra = 0,
      int cuotasExtra = 1,
      double total = 315000,
      int cuotas = 9,
      String? division,
    }) =>
        ContratoAlumno(
          id: id,
          eventoId: 'e',
          nombreAlumno: nombre,
          cantidadAcompanantes: 0,
          montoTotalPactado: total,
          saldoDeudor: total,
          totalCuotas: cuotas,
          mesaExtraPrecio: precioExtra,
          mesaExtraCantidad: extras,
          mesaExtraCuotas: cuotasExtra,
          numeroMesa: mesa,
          cursoDivision: division,
        );

    var i = 0;
    final otros = [
      for (final t in (d['otros'] as String).split('|'))
        () {
          final p = t.split('#');
          i++;
          return ficha(
            'otro$i',
            p[2] == 'B' ? '[BAJA] OTRO $i' : 'OTRO $i',
            p[0].isEmpty ? null : p[0],
            extras: int.parse(p[1]),
            precioExtra: 70000.0 * int.parse(p[1]),
          );
        }(),
    ];
    final cinco = [
      for (final c in d['cinco'] as List)
        ficha(
          c['id'] as String,
          c['n'] as String,
          c['mesa'] as String?,
          extras: c['extras'] as int,
          precioExtra: (c['precioExtra'] as num).toDouble(),
          cuotasExtra: c['cuotasExtra'] as int,
          total: (c['total'] as num).toDouble(),
          cuotas: c['cuotas'] as int,
          division: c['div'] as String?,
        ),
    ];
    final alumnos = [...otros, ...cinco];
    final pagos = <String, List<Map<String, dynamic>>>{};
    for (final p in d['pagos'] as List) {
      pagos.putIfAbsent(p['c'] as String, () => []).add(
            Map<String, dynamic>.from(p as Map),
          );
    }
    final registros = [
      for (final e in (d['nuevas'] as Map).entries)
        SorteoMesasRegistro(
          id: 'auto-${e.key}',
          eventoId: 'e',
          tipo: TipoRegistroSorteo.sorteo,
          resultado: {e.key as String: e.value as String},
          nuevas: {e.key as String: e.value as String},
          automatico: true,
          createdAt: DateTime.utc(2026, 11, 11),
        ),
    ];

    final vacias = MesasNuevasAlFondo.vaciasDelFondo(
      armado: armado,
      config: config,
      alumnos: alumnos,
      registros: registros,
    );
    print('Mesas del fondo vacías: ${vacias.toList()..sort()}');
    final aQuienes = MesaQueDaElJefe.aQuienes(alumnos);
    print('A quiénes se les puede dar: '
        '${[for (final x in aQuienes) x.nombreAlumno].join(' · ')}');
    expect({for (final x in aQuienes) x.id}, {for (final c in cinco) c.id});

    final antesOcupadas = SorteoMesasMotor.ocupadas(alumnos);
    String? quedo;
    for (var semilla = 0; semilla < 50; semilla++) {
      final cuenta = MesaQueDaElJefe.calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        elegidos: {for (final c in cinco) c.id},
        azar: Random(semilla),
        por: 'Jefe',
        ahora: ahora,
      )!;
      // Nadie más cambia.
      expect(cuenta.asignaciones.keys.toSet(), {for (final c in cinco) c.id});
      // Ninguna mesa repetida, y las que se dan estaban libres.
      final dadas = [for (final v in cuenta.dadas.values) ...v];
      expect(dadas.toSet().length, dadas.length);
      expect(dadas.toSet().intersection(antesOcupadas), isEmpty);
      // La principal sigue primera.
      for (final c in cinco) {
        final p = SalonMesas.principal(c);
        if (p != null) expect(cuenta.asignaciones[c.id]!.first, p);
      }
      final texto = [
        for (final c in cinco)
          '${c.nombreAlumno}: '
              '${MesasExtraUtils.formatearAsignacionMesas(cuenta.asignaciones[c.id]!)}',
      ].join(' | ');
      if (quedo == null) {
        quedo = texto;
        print('DAR MESA A TODOS → $texto');
        print('Mesas nuevas agregadas al salón: '
            '${cuenta.nuevas.armado.mesas.length - armado.mesas.length}');
      } else {
        // Con una sola vacía y una sola familia que la puede usar, el azar no
        // cambia nada.
        expect(texto, quedo, reason: 'semilla $semilla');
      }
    }

    if (_esperado.isNotEmpty) {
      final cuenta = MesaQueDaElJefe.calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        elegidos: {for (final c in cinco) c.id},
        azar: Random(0),
      )!;
      for (final par in _esperado.split(';')) {
        final p = par.split(':');
        expect(
          MesasExtraUtils.formatearAsignacionMesas(cuenta.asignaciones[p[0]]!),
          p[1],
          reason: p[0],
        );
      }
    }

    // De a una: cada familia recibe lo mismo que con todas juntas.
    for (final c in cinco) {
      final sola = MesaQueDaElJefe.calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        elegidos: {c.id},
        azar: Random(0),
      )!;
      print('Sola, ${c.nombreAlumno}: '
          '${MesasExtraUtils.formatearAsignacionMesas(sola.asignaciones[c.id]!)}');
      expect(sola.asignaciones.keys, [c.id]);
    }
  });
}
