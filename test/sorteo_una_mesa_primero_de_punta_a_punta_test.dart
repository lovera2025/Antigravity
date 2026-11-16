// De punta a punta, como lo pidió el usuario el 16-nov-2026: "al darle a la
// tilde en el cartel del sorteo y darle a SORTEAR, se va al plano y todo queda
// según lo previsto".
//
// 1. Se abre **el cartel del SORTEO de verdad**, se toca el tilde "Primero las
//    familias de una sola mesa" (y lo que se combine) y se lee lo que anuncia.
// 2. Se aprieta SORTEAR, y lo elegido pasa por **el mismo camino que la app**
//    (`SorteoDelCartel`): sortear y el control final.
// 3. Se monta **la pantalla del PLANO de verdad** con lo sorteado y se mira lo
//    que dibuja: quién quedó en cada mesa.
//
// Las filas se miden en el dibujo (`MesasDelPaso`), no por el número de mesa.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_del_cartel.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesas_del_paso.dart';
import 'package:arguello_events/features/plano/services/mesas_juntas.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/plano_en_memoria.dart';

const _eventoId = 'e0000000-0000-4000-8000-000000000016';

final _evento = Evento(
  id: _eventoId,
  clienteId: 'c0000000-0000-4000-8000-000000000001',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 12),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
);

final _ahora = DateTime.utc(2026, 11, 16, 18);

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  String division = '5° A',
  String? mesa,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _eventoId,
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000 + 70000.0 * extras,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      totalCuotas: 9,
      numeroMesa: mesa,
      cursoDivision: division,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

/// 15 familias de una sola mesa, tres con una adicional, una con dos y una
/// con cuatro (que el cartel trae tildada "lejos"). 29 mesas.
List<ContratoAlumno> _escuela() => [
      _familia('a1', extras: 1),
      _familia('a2', extras: 1),
      _familia('a3', extras: 1, division: '5° B'),
      _familia('b1', extras: 2),
      _familia('c1', extras: 4, division: '5° B'),
      for (var i = 0; i < 15; i++)
        _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
    ];

const _conAdicional = {'a1', 'a2', 'a3', 'b1', 'c1'};

Map<String, PagoAlumno> _pagos(List<ContratoAlumno> alumnos) => {
      for (final a in alumnos)
        a.id: PagoAlumno(base: 1000, mesas: a.mesaExtraPrecio),
    };

/// Los pagos uno por uno, con cumplimientos distintos, para "Cumplimiento
/// debido". Todas con sus adicionales pagas.
Map<String, List<Map<String, dynamic>>> _pagosCrudos(
  List<ContratoAlumno> alumnos,
) {
  var n = 0;
  Map<String, dynamic> pago(int mes, int dia, double monto,
      {String concepto = 'Cuota Base'}) {
    n++;
    final fecha = DateTime.utc(2026, mes, dia, 15);
    return {
      'id': 'p$n',
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'fecha_pago': fecha.toIso8601String(),
      'created_at': fecha.add(Duration(seconds: n)).toIso8601String(),
      'anulado': 0,
    };
  }

  return {
    for (var i = 0; i < alumnos.length; i++)
      alumnos[i].id: [
        ...switch (i % 3) {
          0 => [pago(4, 3 + i, 270000)],
          1 => [pago(4, 30, 30000 * 7)],
          _ => [pago(5, 1 + i, 30000), pago(5, 31, 30000 * 6)],
        },
        if (alumnos[i].mesaExtraPrecio > 0)
          pago(6, 1, alumnos[i].mesaExtraPrecio, concepto: 'Mesa extra (1/1)'),
      ],
  };
}

PlanoEvento _plano({FinNumeracion fin = FinNumeracion.filas}) =>
    PlanoEvento.nuevo(
      eventoId: _eventoId,
      armado: ArmarAMedida.armar(
        OpcionesAMedida(
          playon: const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
          cantidad: 40,
          fin: fin,
        ),
      ).armado,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.entera,
      ahora: _ahora,
    ).copyWith(
      config: ConfigPlano.vacia.copyWith(numeracion: fin),
      ahora: _ahora,
    );

/// Lo elegido en el cartel.
class _Elegir {
  final bool alFinal;
  final bool cumplimiento;
  final RecorridoDelOrden recorrido;
  const _Elegir({
    this.alFinal = false,
    this.cumplimiento = false,
    this.recorrido = RecorridoDelOrden.filas,
  });

  @override
  String toString() => [
        alFinal ? 'Al final' : 'Con su familia',
        if (cumplimiento) 'Cumplimiento debido ${recorrido.rotulo}',
      ].join(', ');
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Abre el cartel de verdad, elige [e], lee lo que anuncia y aprieta SORTEAR.
Future<({SorteoMesasDialogResult elegido, String anuncia})> _cartel(
  WidgetTester tester, {
  required List<ContratoAlumno> alumnos,
  required PlanoEvento plano,
  required _Elegir e,
  bool tildar = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SorteoMesasDialogResult? r;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => r = await showDialog<SorteoMesasDialogResult>(
              context: context,
              builder: (_) => SorteoMesasDialog(
                tituloInstitucion: 'ESCUELA DE PRUEBA',
                alumnos: alumnos,
                avisos: const [],
                pagos: _pagos(alumnos),
                plano: plano,
                eventoId: _eventoId,
                pagosCrudos: _pagosCrudos(alumnos),
                hoyAr: DateTime(2026, 11, 16),
              ),
            ),
            child: const Text('ABRIR'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ABRIR'));
  await tester.pumpAndSettle();
  if (e.cumplimiento) {
    await _tocar(tester, find.byKey(const Key('por_cumplimiento')));
    await _tocar(tester, find.byKey(Key('cumplimiento_${e.recorrido.clave}')));
  }
  if (e.alFinal) {
    await _tocar(tester, find.byKey(const Key('adicionales_al_final')));
  }
  if (tildar) {
    await _tocar(tester, find.byKey(const Key('primero_una_sola_mesa')));
  }
  expect(tester.takeException(), isNull);
  final rangos = find.byKey(const Key('una_mesa_rangos'));
  final anuncia = rangos.evaluate().isEmpty
      ? ''
      : tester.widget<Text>(rangos).data!;
  await _tocar(tester, find.text('SORTEAR'));
  expect(r, isNotNull, reason: 'SORTEAR no cerró el cartel');
  return (elegido: r!, anuncia: anuncia);
}

/// Lo mismo que hace la pantalla de la fiesta al confirmar, por el mismo
/// camino. Devuelve las familias con sus mesas y el plano como se guarda.
({
  List<ContratoAlumno> alumnos,
  PlanoEvento plano,
  SorteoDelCartel delCartel,
  ResultadoSorteoPlano resultado,
}) _sortearComoLaApp(
  List<ContratoAlumno> alumnos,
  PlanoEvento plano,
  SorteoMesasDialogResult elegido, {
  required int semilla,
}) {
  final pagos = _pagos(alumnos);
  final exclusion = exclusionSorteo(
    candidatos: candidatosPorPago(alumnos, pagos),
    soloPagado: elegido.soloPagado,
    incluirBase: elegido.incluirBase,
    incluirExtras: elegido.incluirExtras,
  );
  final delCartel = SorteoDelCartel.armar(
    eventoId: _eventoId,
    plano: plano,
    alumnos: alumnos,
    config: elegido,
    exclusion: exclusion,
    pagos: pagos,
    pagosCrudos: _pagosCrudos(alumnos),
    hoyAr: DateTime(2026, 11, 16),
    ahora: _ahora,
    por: 'Prueba',
  );
  expect(delCartel.sePuede, isTrue, reason: delCartel.problema);
  final r = delCartel.sortear(random: Random(semilla));
  expect(delCartel.controlFinal(r), isNull, reason: 'semilla $semilla');
  final conMesa = [
    for (final a in alumnos)
      r.asignaciones.containsKey(a.id)
          ? a.copyWith(
              numeroMesa:
                  MesasExtraUtils.formatearAsignacionMesas(r.asignaciones[a.id]!),
            )
          : a,
  ];
  return (
    alumnos: conMesa,
    plano: plano.copyWith(
      armado: delCartel.nuevas?.armado,
      config: delCartel.configDelPlano!,
      ahora: _ahora,
    ),
    delCartel: delCartel,
    resultado: r,
  );
}

/// Las mesas de cada familia, según lo que dibuja el plano.
Map<String, List<int>> _porFamilia(Map<int, List<String>> dibujado) {
  final r = <String, List<int>>{};
  for (final e in dibujado.entries) {
    for (final id in e.value) {
      r.putIfAbsent(id, () => []).add(e.key);
    }
  }
  for (final l in r.values) {
    l.sort();
  }
  return r;
}

/// Las comprobaciones de lo que se ve en el plano.
void _comprobarElPlano(
  PlanoEvento plano,
  Map<String, List<int>> dibujado,
  ResultadoSorteoPlano resultado, {
  required _Elegir e,
  required String anuncia,
  required SorteoDelCartel delCartel,
}) {
  final armado = plano.armado;
  // El plano dibuja exactamente lo sorteado.
  expect(dibujado.keys.toSet(), resultado.asignaciones.keys.toSet());
  for (final id in dibujado.keys) {
    expect(dibujado[id], resultado.asignaciones[id], reason: id);
  }
  final paso = MesasDelPaso.de(
    armado,
    recorrido: e.cumplimiento ? e.recorrido : RecorridoDelOrden.filas,
  )!;
  final filas = MesasDelPaso.de(armado, recorrido: RecorridoDelOrden.filas)!;
  final unas = [
    for (final x in dibujado.entries)
      if (!_conAdicional.contains(x.key)) ...x.value,
  ];
  // Las de adelante de cada familia con adicional (con "Al final", la
  // principal) y las del final.
  final alFinal = SorteoConPlano.delFinal(delCartel.entrada!, resultado);
  final principalesDelOrden = {
    for (final l in plano.config.frente?.lugares ?? const <LugarPorOrden>[])
      l.alumnoId: l.mesas,
  };
  final adelante = <int>[];
  final delFinal = <int>[];
  for (final id in _conAdicional) {
    final suyas = dibujado[id]!;
    expect(suyas, hasLength(_mesasDe(id)), reason: id);
    final atras = e.cumplimiento
        ? (e.alFinal ? principalesDelOrden[id]!.skip(1).toList() : <int>[])
        : (alFinal[id] ?? const <int>[]);
    delFinal.addAll(atras);
    adelante.addAll(suyas.where((n) => !atras.contains(n)));
  }
  expect(unas, hasLength(15));
  // 1. Por el recorrido que se usó: ninguna con adicional antes que una de una
  //    sola mesa.
  int puesto(int mesa) => paso.enOrden.indexOf(mesa);
  expect(
    adelante.map(puesto).reduce(min),
    greaterThan(unas.map(puesto).reduce(max)),
    reason: '$e: una familia con adicional quedó antes',
  );
  if (delFinal.isNotEmpty) {
    expect(delFinal.map(puesto).reduce(min),
        greaterThan(adelante.map(puesto).reduce(max)),
        reason: '$e: una del final quedó antes que una principal');
  }
  // 2. En el dibujo, recorriendo por filas: las de una sola mesa en las filas
  //    de adelante.
  if (!e.cumplimiento || e.recorrido == RecorridoDelOrden.filas) {
    final filaMaxUna = unas.map((n) => filas.lugar(n)!.fila).reduce(max);
    final filaMinCon =
        adelante.map((n) => filas.lugar(n)!.fila).reduce(min);
    expect(filaMinCon, greaterThanOrEqualTo(filaMaxUna),
        reason: '$e: en el dibujo');
  }
  // 3. Cada familia junta (sus mesas de adelante, y las del final entre sí).
  for (final id in _conAdicional) {
    final suyas = dibujado[id]!;
    final atras = suyas.where(delFinal.contains).toList();
    final suyasAdelante = suyas.where((n) => !atras.contains(n)).toList();
    final separadas = e.cumplimiento || e.alFinal ? 0 : (id == 'c1' ? 2 : 0);
    if (e.cumplimiento) {
      // Con Cumplimiento debido la adicional va detrás de su principal, en la
      // misma fila: juntas en el dibujo, aunque los números no sean seguidos.
      expect(SorteoConPlano.gruposEnElSalon(armado, suyasAdelante),
          hasLength(1),
          reason: '$e: $id quedó partida: $suyas');
      // "Por columnas", la zona del final arranca en la tercera columna desde
      // la pasarela: ahí cada fila tiene 3 mesas por lado, y 4 adicionales no
      // entran juntas. Pasa igual sin el tilde (es el Cumplimiento debido de
      // la 6.7.1): se mira solo "Por filas".
      if (atras.length > 1 && e.recorrido == RecorridoDelOrden.filas) {
        expect(SorteoConPlano.gruposEnElSalon(armado, atras), hasLength(1),
            reason: '$e: las del final de $id quedaron partidas: $atras');
      }
    } else if (separadas == 0) {
      expect(SorteoConPlano.tramosPegados(armado, suyasAdelante), hasLength(1),
          reason: '$e: $id no quedó junta: $suyas');
    } else {
      expect(SorteoConPlano.lejosEnElSalon(armado, suyas, separadas), isTrue,
          reason: '$e: las "lejos" de $id');
    }
    if (atras.isNotEmpty && !e.cumplimiento) {
      expect(SorteoConPlano.tramosPegados(armado, atras), hasLength(1),
          reason: '$e: las del final de $id');
    }
  }
  // 4. Lo que anunció el cartel es lo que quedó.
  if (!e.cumplimiento) {
    final m = RegExp(r'Una sola mesa: de la (\d+) a la (\d+)').firstMatch(anuncia);
    expect(m, isNotNull, reason: 'anuncio: "$anuncia"');
    expect(unas.reduce(min), int.parse(m!.group(1)!));
    expect(unas.reduce(max), int.parse(m.group(2)!));
    final segunda = RegExp(
      e.alFinal
          ? r'Principales de las demás: de la (\d+) a la (\d+)'
          : r'Con adicionales: de la (\d+) a la (\d+)',
    ).firstMatch(anuncia);
    expect(segunda, isNotNull, reason: 'anuncio: "$anuncia"');
    expect(adelante.reduce(min), greaterThanOrEqualTo(int.parse(segunda!.group(1)!)));
    expect(adelante.reduce(max), lessThanOrEqualTo(int.parse(segunda.group(2)!)));
    if (e.alFinal) {
      final fin =
          RegExp(r'Al final: de la (\d+) a la (\d+)').firstMatch(anuncia);
      expect(fin, isNotNull, reason: 'anuncio: "$anuncia"');
      expect(delFinal.reduce(min), greaterThanOrEqualTo(int.parse(fin!.group(1)!)));
      expect(delFinal.reduce(max), lessThanOrEqualTo(int.parse(fin.group(2)!)));
    }
  } else {
    // 5. Con Cumplimiento debido, dentro de cada grupo, de la que mejor
    //    cumplió a la que peor: su mesa principal en el orden del recorrido.
    //    Las de una sola mesa, siempre así. Entre las que tienen adicional, una
    //    que cumplió peor solo queda antes si es más chica: tomó el hueco que
    //    dejó una más grande que no entraba entera en esa fila.
    final lugares = plano.config.frente!.lugares;
    expect(plano.config.frente!.unaMesaPrimero, isTrue);
    final unasEnOrden = [
      for (final l in lugares)
        if (!_conAdicional.contains(l.alumnoId)) puesto(l.mesas.first),
    ];
    expect(unasEnOrden, [...unasEnOrden]..sort(),
        reason: '$e: el orden por cumplimiento de las de una sola mesa');
    final conEnOrden = [
      for (final l in lugares)
        if (_conAdicional.contains(l.alumnoId)) l,
    ];
    for (var i = 0; i < conEnOrden.length; i++) {
      for (var j = i + 1; j < conEnOrden.length; j++) {
        final mejor = conEnOrden[i];
        final peor = conEnOrden[j];
        if (puesto(peor.mesas.first) < puesto(mejor.mesas.first)) {
          expect(
            _mesasDe(peor.alumnoId),
            lessThan(_mesasDe(mejor.alumnoId)),
            reason: '$e: ${peor.alumnoId} cumplió peor que '
                '${mejor.alumnoId} y quedó antes sin ser más chica',
          );
        }
      }
    }
  }
}

/// Cuántas mesas tiene cada familia de la escuela.
int _mesasDe(String id) => switch (id) {
      'a1' || 'a2' || 'a3' => 2,
      'b1' => 3,
      'c1' => 5,
      _ => 1,
    };

void main() {
  const combinaciones = [
    _Elegir(),
    _Elegir(alFinal: true),
    _Elegir(cumplimiento: true, recorrido: RecorridoDelOrden.filas),
    _Elegir(cumplimiento: true, recorrido: RecorridoDelOrden.columnas),
    _Elegir(alFinal: true, cumplimiento: true, recorrido: RecorridoDelOrden.filas),
    _Elegir(
      alFinal: true,
      cumplimiento: true,
      recorrido: RecorridoDelOrden.columnas,
    ),
  ];

  for (final e in combinaciones) {
    testWidgets('tildar, SORTEAR y mirar el plano: $e', (tester) async {
      final alumnos = _escuela();
      final plano = _plano();
      final cartel = await _cartel(tester, alumnos: alumnos, plano: plano, e: e);
      expect(cartel.elegido.unaMesaPrimero, isTrue);
      expect(cartel.elegido.porCumplimiento, e.cumplimiento);
      expect(cartel.elegido.adicionalesAlFinal, e.alFinal);
      if (!e.cumplimiento) {
        expect(cartel.anuncia, startsWith('Una sola mesa: de la 1 a la 15'));
      }
      final hecho = _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: 7);
      // El plano de verdad, con lo sorteado.
      await montarPlanoDeLaFiesta(
        tester,
        evento: _evento,
        plano: hecho.plano,
        alumnos: hecho.alumnos,
      );
      final dibujado = _porFamilia(ocupantesDibujados(tester));
      _comprobarElPlano(
        hecho.plano,
        dibujado,
        hecho.resultado,
        e: e,
        anuncia: cartel.anuncia,
        delCartel: hecho.delCartel,
      );
      // Con otras 39 semillas, sin la pantalla: lo mismo, cada vez.
      for (var semilla = 1; semilla < 40; semilla++) {
        final otro =
            _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: semilla);
        _comprobarElPlano(
          otro.plano,
          otro.resultado.asignaciones,
          otro.resultado,
          e: e,
          anuncia: cartel.anuncia,
          delCartel: otro.delCartel,
        );
      }
    });
  }

  testWidgets('sin tocar el tilde, todo sigue como siempre', (tester) async {
    final alumnos = _escuela();
    final plano = _plano();
    final cartel = await _cartel(
      tester,
      alumnos: alumnos,
      plano: plano,
      e: const _Elegir(),
      tildar: false,
    );
    expect(cartel.elegido.unaMesaPrimero, isFalse);
    expect(find.byKey(const Key('una_mesa_rangos')), findsNothing);
    final hecho = _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: 3);
    expect(hecho.delCartel.entrada!.unaMesaPrimero, isFalse);
    expect(SorteoConPlano.primerGrupo(hecho.delCartel.entrada!), isEmpty);
  });

  testWidgets('en un salón numerado "Junto al escenario" avisa, y el primer '
      'grupo son los primeros números', (tester) async {
    final alumnos = _escuela();
    final plano = _plano(fin: FinNumeracion.escenario);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA',
          alumnos: alumnos,
          avisos: const [],
          pagos: _pagos(alumnos),
          plano: plano,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('una_mesa_aviso')), findsNothing);
    await _tocar(tester, find.byKey(const Key('primero_una_sola_mesa')));
    expect(
      tester.widget<Text>(find.byKey(const Key('una_mesa_aviso'))).data,
      contains('Fila por fila'),
    );
    final cartel = await _cartel(
      tester,
      alumnos: alumnos,
      plano: plano,
      e: const _Elegir(),
    );
    final hecho = _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: 2);
    final unas = [
      for (final x in hecho.resultado.asignaciones.entries)
        if (!_conAdicional.contains(x.key)) ...x.value,
    ]..sort();
    expect(unas, [for (var n = 1; n <= 15; n++) n]);
  });

  testWidgets('en un salón justo deja sortear: la familia con adicional tapa '
      'el hueco junto a la pasarela con sus mesas una detrás de la otra, y el '
      'plano la dibuja junta (16-nov-2026)', (tester) async {
    // La escuela de la ventana de prueba: 24 familias de una sola mesa y 5 con
    // adicional (ninguna de más de 3 mesas: el cartel no trae "lejos"). Con
    // las mesas justas, en mesas seguidas no entran.
    final alumnos = [
      _familia('a1', extras: 1),
      _familia('a2', extras: 1),
      _familia('a3', extras: 1, division: '5° B'),
      _familia('a4', extras: 1),
      _familia('b1', extras: 2, division: '5° B'),
      for (var i = 0; i < 24; i++)
        _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
    ];
    const conAdicional = {'a1', 'a2', 'a3', 'a4', 'b1'};
    PlanoEvento conMesas(int n) => PlanoEvento.nuevo(
          eventoId: _eventoId,
          armado: ArmarAMedida.armar(
            OpcionesAMedida(
              playon:
                  const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
              cantidad: n,
              fin: FinNumeracion.filas,
            ),
          ).armado,
          estilo: EstiloPlano.gala,
          modo: ModoSorteo.entera,
          ahora: _ahora,
        ).copyWith(
          config: ConfigPlano.vacia.copyWith(numeracion: FinNumeracion.filas),
          ahora: _ahora,
        );
    PlanSorteo plan(PlanoEvento p, {required bool tilde}) =>
        SorteoConPlano.preparar(
          EntradaSorteoPlano(
            armado: p.armado,
            config: p.config,
            alumnos: alumnos,
            unaMesaPrimero: tilde,
          ),
        );
    // Un salón justo: sin el tilde entra; con el tilde, solo tapando huecos.
    PlanoEvento? justo;
    for (var n = 30; n <= 38 && justo == null; n++) {
      final p = conMesas(n);
      if (plan(p, tilde: false).entra &&
          plan(p, tilde: true).unaDetrasDeLaOtra > 0) {
        justo = p;
      }
    }
    expect(justo, isNotNull, reason: 'hace falta un salón justo');
    final detras = plan(justo!, tilde: true).unaDetrasDeLaOtra;
    expect(SorteoMesasMotor.pedidos(alumnos), hasLength(29));

    // 1. El cartel: sin rojo, la línea gris, y SORTEAR prendido.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA',
          alumnos: alumnos,
          avisos: const [],
          pagos: _pagos(alumnos),
          plano: justo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tocar(tester, find.byKey(const Key('primero_una_sola_mesa')));
    final rangos =
        tester.widget<Text>(find.byKey(const Key('una_mesa_rangos'))).data!;
    expect(rangos, startsWith('Una sola mesa: de la 1 a la 24'));
    expect(rangos, isNot(contains('Agregá mesas')));
    expect(
      tester.widget<Text>(find.byKey(const Key('una_mesa_detras'))).data,
      contains('una detrás de la otra, junto a la pasarela'),
    );
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SORTEAR'))
          .onPressed,
      isNotNull,
      reason: 'con el salón justo y el tilde, deja sortear',
    );

    // 2. SORTEAR por el camino de la app, con 40 semillas: las de una sola
    //    mesa adelante, cada familia junta, y una detrás de la otra solo las
    //    que dijo el cartel.
    final cartel =
        await _cartel(tester, alumnos: alumnos, plano: justo, e: const _Elegir());
    expect(cartel.elegido.unaMesaPrimero, isTrue);
    late ({
      List<ContratoAlumno> alumnos,
      PlanoEvento plano,
      SorteoDelCartel delCartel,
      ResultadoSorteoPlano resultado,
    }) primero;
    for (var semilla = 0; semilla < 40; semilla++) {
      final hecho =
          _sortearComoLaApp(alumnos, justo, cartel.elegido, semilla: semilla);
      if (semilla == 0) primero = hecho;
      final r = hecho.resultado.asignaciones;
      final unas = [
        for (final x in r.entries)
          if (!conAdicional.contains(x.key)) ...x.value,
      ];
      final con = [
        for (final x in r.entries)
          if (conAdicional.contains(x.key)) ...x.value,
      ];
      expect(unas, hasLength(24));
      expect(con.reduce(min), greaterThan(unas.reduce(max)),
          reason: 'semilla $semilla: ninguna de una sola mesa va atrás');
      for (final id in conAdicional) {
        expect(MesasJuntas.juntas(justo.armado, r[id]!), isTrue,
            reason: 'semilla $semilla: $id ${r[id]}');
      }
      expect(
        conAdicional
            .where((id) => MesasJuntas.usaUnaDetrasDeLaOtra(justo!.armado, r[id]!))
            .length,
        detras,
        reason: 'semilla $semilla',
      );
    }

    // 3. El plano de verdad: ninguna familia separada, y la cápsula pasa por
    //    las dos mesas una detrás de la otra.
    await montarPlanoDeLaFiesta(
      tester,
      evento: _evento,
      plano: primero.plano,
      alumnos: primero.alumnos,
    );
    final familias = tester.widget<VistaPlano>(find.byType(VistaPlano)).familias!;
    expect(familias.haySeparadas, isFalse);
    final r = primero.resultado.asignaciones;
    for (final id in conAdicional) {
      if (!MesasJuntas.usaUnaDetrasDeLaOtra(justo.armado, r[id]!)) continue;
      expect(
        familias.capsulas.any((c) => r[id]!.every(c.contains)),
        isTrue,
        reason: 'la cápsula de $id pasa por ${r[id]}',
      );
    }
  });

  for (final (recorrido, alFinal) in [
    for (final r in RecorridoDelOrden.values) ...[(r, false), (r, true)],
  ]) {
    testWidgets('en un salón justo, con Cumplimiento debido "${recorrido.clave}"'
        '${alFinal ? ' y "Al final"' : ''}: las de una sola mesa primero y cada '
        'familia junta (16-nov-2026)', (tester) async {
      final alumnos = [
        _familia('a1', extras: 1),
        _familia('a2', extras: 1),
        _familia('a3', extras: 1, division: '5° B'),
        _familia('a4', extras: 1),
        _familia('b1', extras: 2, division: '5° B'),
        for (var i = 0; i < 24; i++)
          _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
      ];
      const conAdicional = {'a1', 'a2', 'a3', 'a4', 'b1'};
      // 35 mesas para 35: el salón de la ventana de prueba.
      final justo = PlanoEvento.nuevo(
        eventoId: _eventoId,
        armado: ArmarAMedida.armar(
          OpcionesAMedida(
            playon: const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
            cantidad: 35,
            fin: FinNumeracion.filas,
          ),
        ).armado,
        estilo: EstiloPlano.gala,
        modo: ModoSorteo.entera,
        ahora: _ahora,
      ).copyWith(
        config: ConfigPlano.vacia.copyWith(numeracion: FinNumeracion.filas),
        ahora: _ahora,
      );
      final cartel = await _cartel(
        tester,
        alumnos: alumnos,
        plano: justo,
        e: _Elegir(cumplimiento: true, recorrido: recorrido, alFinal: alFinal),
      );
      final paso = MesasDelPaso.de(justo.armado, recorrido: recorrido)!;
      int puesto(int n) => paso.enOrden.indexOf(n);
      for (var semilla = 0; semilla < 10; semilla++) {
        final hecho =
            _sortearComoLaApp(alumnos, justo, cartel.elegido, semilla: semilla);
        final r = hecho.resultado.asignaciones;
        expect(r.keys, hasLength(29), reason: 'semilla $semilla');
        final unas = [
          for (final x in r.entries)
            if (!conAdicional.contains(x.key)) ...x.value,
        ];
        final con = [
          for (final x in r.entries)
            if (conAdicional.contains(x.key)) ...x.value,
        ];
        expect(con.map(puesto).reduce(min),
            greaterThan(unas.map(puesto).reduce(max)),
            reason: 'semilla $semilla: ninguna de una sola mesa va atrás');
        for (final id in conAdicional) {
          expect(r[id], hasLength(id == 'b1' ? 3 : 2));
          if (!alFinal) {
            expect(MesasJuntas.juntas(justo.armado, r[id]!), isTrue,
                reason: 'semilla $semilla: $id ${r[id]}');
            continue;
          }
          // Con "Al final": la principal adelante y las adicionales al final,
          // juntas entre sí.
          final suyas = [...r[id]!]..sort((x, y) => puesto(x) - puesto(y));
          expect(MesasJuntas.juntas(justo.armado, suyas.sublist(1)), isTrue,
              reason: 'semilla $semilla: las del final de $id ${r[id]}');
        }
      }
    });
  }

  testWidgets('por división el tilde está apagado, con el motivo',
      (tester) async {
    final alumnos = _escuela();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA',
          alumnos: alumnos,
          avisos: const [],
          pagos: _pagos(alumnos),
          plano: _plano()
              .copyWith(modoSorteo: ModoSorteo.bloques, ahora: _ahora),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tilde = tester.widget<CheckboxListTile>(
      find.byKey(const Key('primero_una_sola_mesa')),
    );
    expect(tilde.onChanged, isNull);
    expect(
      tester.widget<Text>(find.byKey(const Key('adicionales_motivo'))).data,
      contains('una sola mesa'),
    );
  });

  testWidgets('con Cumplimiento debido "Por columnas" avisa que no son las '
      'filas de adelante', (tester) async {
    final alumnos = _escuela();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA',
          alumnos: alumnos,
          avisos: const [],
          pagos: _pagos(alumnos),
          plano: _plano(),
          eventoId: _eventoId,
          pagosCrudos: _pagosCrudos(alumnos),
          hoyAr: DateTime(2026, 11, 16),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tocar(tester, find.byKey(const Key('por_cumplimiento')));
    await _tocar(tester, find.byKey(const Key('primero_una_sola_mesa')));
    expect(
      tester.widget<Text>(find.byKey(const Key('una_mesa_aviso'))).data,
      contains('Por filas'),
    );
    await _tocar(tester, find.byKey(const Key('cumplimiento_filas')));
    expect(find.byKey(const Key('una_mesa_aviso')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('adicionales_explica'))).data,
      contains('Primero las de una sola mesa'),
    );
  });

  testWidgets('después del sorteo: deshacer solo lo último deja el plano vacío, '
      'y el registro lleva la marca', (tester) async {
    final alumnos = _escuela();
    final plano = _plano();
    final cartel =
        await _cartel(tester, alumnos: alumnos, plano: plano, e: const _Elegir());
    final hecho = _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: 9);
    final numeros = {
      for (final x in hecho.resultado.asignaciones.entries)
        x.key: MesasExtraUtils.formatearAsignacionMesas(x.value),
    };
    final registro = SorteoMesasRegistro(
      id: 'r1',
      eventoId: _eventoId,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: numeros,
      antes: UltimosSorteados.antesDe(alumnos, numeros),
      unaMesaPrimero: cartel.elegido.unaMesaPrimero,
      createdAt: _ahora,
    );
    final leido = SorteoMesasRegistro.fromMap(registro.toMap());
    expect(leido.unaMesaPrimero, isTrue);
    final ultimos = UltimosSorteados.de([leido], hecho.alumnos)!;
    expect(ultimos.noSeTocan, isEmpty);
    expect(ultimos.aGuardar.values, everyElement(isNull),
        reason: 'nadie tenía mesa antes: todas quedan libres');
    expect(ultimos.aGuardar.keys.toSet(), numeros.keys.toSet());
    // El plano, con lo deshecho: vacío.
    final deshecho = [
      for (final a in hecho.alumnos)
        ultimos.aGuardar.containsKey(a.id) ? a.copyWith(numeroMesa: '') : a,
    ];
    await montarPlanoDeLaFiesta(
      tester,
      evento: _evento,
      plano: hecho.plano,
      alumnos: deshecho,
    );
    expect(
      ocupantesDibujados(tester).values.every((l) => l.isEmpty),
      isTrue,
    );
  });

  testWidgets('"Sortear a los que faltan" con el tilde: nadie se mueve',
      (tester) async {
    final alumnos = _escuela();
    final plano = _plano();
    final cartel =
        await _cartel(tester, alumnos: alumnos, plano: plano, e: const _Elegir());
    final hecho = _sortearComoLaApp(alumnos, plano, cartel.elegido, semilla: 4);
    final conLosNuevos = [
      ...hecho.alumnos,
      _familia('n1'),
      _familia('n2', extras: 1),
    ];
    // El segundo SORTEO: con las mesas que quedan libres del salón.
    final segundo = await _cartel(
      tester,
      alumnos: conLosNuevos,
      plano: hecho.plano,
      e: const _Elegir(),
    );
    final otra = segundo.elegido;
    final sinFondo = SorteoMesasDialogResult(
      capacidadSalon: otra.capacidadSalon,
      soloPagado: otra.soloPagado,
      modo: otra.modo,
      unaMesaPrimero: true,
      separaciones: otra.separaciones,
      distancias: otra.distancias,
    );
    for (var semilla = 0; semilla < 20; semilla++) {
      final r =
          _sortearComoLaApp(conLosNuevos, hecho.plano, sinFondo, semilla: semilla);
      for (final a in hecho.alumnos) {
        final ahora = r.resultado.asignaciones[a.id];
        if (ahora == null) continue;
        expect(
          ahora,
          MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList()..sort(),
          reason: 'semilla $semilla: ${a.id} se movió',
        );
      }
      expect(r.resultado.asignaciones['n1'], hasLength(1));
      expect(r.resultado.asignaciones['n2'], hasLength(2));
    }
  });
}
