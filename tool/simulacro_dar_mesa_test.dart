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
//     [--dart-define=salida=<carpeta fuera de git>]   el plano antes y después y
//                                                     la planilla por número de mesa
//
// El JSON se arma con una consulta a la nube (ver el CONTEXTO de la 6.9.4).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/mesa_que_da_el_jefe.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _datos = String.fromEnvironment('datos');
const _esperado = String.fromEnvironment('esperado');
const _salida = String.fromEnvironment('salida');

/// La fiesta del JSON: el plano, los alumnos (los cinco con sus datos y los
/// demás solo con su número de mesa), sus pagos y las mesas nuevas del registro.
({
  ArmadoSalon armado,
  ConfigPlano config,
  PlanoEvento plano,
  List<ContratoAlumno> alumnos,
  List<ContratoAlumno> cinco,
  Map<String, List<Map<String, dynamic>>> pagos,
  List<SorteoMesasRegistro> registros,
  DateTime ahora,
}) _leerFiesta() {
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
  return (
    armado: armado,
    config: config,
    plano: plano,
    alumnos: alumnos,
    cinco: cinco,
    pagos: pagos,
    registros: registros,
    ahora: ahora,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DAR MESA con los datos de la fiesta', () async {
    if (_datos.isEmpty) {
      print('Falta --dart-define=datos=<el JSON>: no se simula nada.');
      return;
    }
    final f = _leerFiesta();
    final armado = f.armado;
    final config = f.config;
    final plano = f.plano;
    final alumnos = f.alumnos;
    final cinco = f.cinco;
    final pagos = f.pagos;
    final registros = f.registros;
    final ahora = f.ahora;

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

    if (_salida.isNotEmpty) {
      final cuenta = MesaQueDaElJefe.calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        elegidos: {for (final c in cinco) c.id},
        azar: Random(0),
      )!;
      final despues = [
        for (final a in alumnos)
          cuenta.asignaciones.containsKey(a.id)
              ? a.copyWith(
                  numeroMesa: MesasExtraUtils.formatearAsignacionMesas(
                    cuenta.asignaciones[a.id]!,
                  ),
                )
              : a,
      ];
      final evento = Evento(
        id: 'e',
        clienteId: 'c',
        tipo: 'Recepción',
        fechaEvento: DateTime(2026, 12, 4),
        estado: EstadoEvento.planificacion,
        modalidad: 'masivo',
        cliente: Cliente(id: 'c', nombreCompleto: 'LA FIESTA DEL SIMULACRO'),
      );
      Future<void> guardar(String nombre, Future<List<int>> bytes) async {
        final f = File('$_salida${Platform.pathSeparator}$nombre')
          ..writeAsBytesSync(await bytes);
        print('── en: ${f.path}');
      }

      await guardar(
        'Simulacro_plano_ANTES.pdf',
        PdfService.construirPlanoPdf(
          evento,
          PlanoDeLaFiesta.desde(
            armado: armado,
            config: config,
            alumnos: alumnos,
            pagos: pagos,
          ),
          estilo: EstiloPlano.arquitecto,
          generada: ahora,
        ),
      );
      await guardar(
        'Simulacro_plano_DESPUES.pdf',
        PdfService.construirPlanoPdf(
          evento,
          PlanoDeLaFiesta.desde(
            armado: cuenta.nuevas.armado,
            config: cuenta.nuevas.config,
            alumnos: despues,
            pagos: pagos,
          ),
          estilo: EstiloPlano.arquitecto,
          generada: ahora,
        ),
      );
      await guardar(
        'Simulacro_planilla_por_mesa_DESPUES.pdf',
        PdfService.construirPlanillaSorteoPdf(
          evento,
          despues,
          version: VersionPlanillaSorteo.paraRepartir,
          vertical: true,
          orden: OrdenPlanillaSorteo.porMesa,
          generada: ahora,
        ),
      );
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

  testWidgets('el plano antes y después de DAR MESA, en imagen', (tester) async {
    if (_datos.isEmpty || _salida.isEmpty) return;
    await cargarFuentesPlano();
    final f = _leerFiesta();
    final cuenta = MesaQueDaElJefe.calcular(
      plano: f.plano,
      alumnos: f.alumnos,
      pagos: f.pagos,
      registros: f.registros,
      elegidos: {for (final c in f.cinco) c.id},
      azar: Random(0),
    )!;
    final despues = [
      for (final a in f.alumnos)
        cuenta.asignaciones.containsKey(a.id)
            ? a.copyWith(
                numeroMesa: MesasExtraUtils.formatearAsignacionMesas(
                  cuenta.asignaciones[a.id]!,
                ),
              )
            : a,
    ];
    final dadas = {
      for (final c in f.cinco) ...?cuenta.asignaciones[c.id],
    };
    // Los pagos para el dibujo: los de las cinco como están, y a las demás
    // familias (de las que el JSON no trae los pagos) sus adicionales pagas,
    // así no salen "a confirmar" por falta de datos.
    final pagosDelDibujo = {
      ...f.pagos,
      for (final a in f.alumnos)
        if (!f.pagos.containsKey(a.id) && a.mesaExtraCantidad > 0)
          a.id: [
            {
              'concepto': 'Mesa Extra (1/1)',
              'monto': a.mesaExtraPrecio,
              'monto_gross': a.mesaExtraPrecio,
              'anulado': 0,
            },
          ],
    };
    for (final (nombre, armado, config, alumnos, resaltadas) in [
      ('ANTES', f.armado, f.config, f.alumnos, <int>{}),
      ('DESPUES', cuenta.nuevas.armado, cuenta.nuevas.config, despues, dadas),
    ]) {
      final estado = PlanoDeLaFiesta.desde(
        armado: armado,
        config: config,
        alumnos: alumnos,
        pagos: pagosDelDibujo,
      ).estado;
      final clave = GlobalKey();
      tester.view.physicalSize = const Size(2600, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: clave,
              child: VistaPlano(
                armado: armado,
                hoja: 'A',
                tema: TemaPlano.de(EstiloPlano.arquitecto),
                estado: estado,
                resaltadas: resaltadas,
                animar: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await boundary.toImage(pixelRatio: 1);
        final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
        final archivo = File(
          '$_salida${Platform.pathSeparator}Simulacro_plano_$nombre.png',
        )..writeAsBytesSync(datos!.buffer.asUint8List());
        print('── PNG en: ${archivo.path}');
      });
    }
  });
}
