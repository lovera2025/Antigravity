// El recibo reimpreso sale con el cobro entero (aviso del jefe del 14-nov-2026:
// "los recibos al reimprimir no tienen tantos datos").
//
// REIMPRIMIR de cada renglón del Estado de cuenta mandaba solo ese renglón: un
// cobro de cuota + mora salía con una línea, y la de la mora caía en "Mora por
// pagar fuera de término", sin cuota ni mes. Ahora los tres caminos juntan el
// cobro con `ReciboDeUnCobro`. Y debajo de la cuota cuya mora se pagó en dos
// partes va una nota, para que la familia entienda el papel sola.
//
// Familias inventadas.
import 'dart:io';

import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/recibo_de_un_cobro.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

var _n = 0;

Map<String, dynamic> _pago(
  String fechaHora,
  String concepto,
  double monto, {
  String medio = 'Efectivo',
  String caja = 'caja-1',
  int anulado = 0,
  double? descuento,
}) {
  final esMora = esPagoInteresMoraPorConcepto(concepto);
  return {
    'id': 'p${_n++}',
    'contrato_alumno_id': 'f1400000-0000-4000-8000-000000000014',
    'concepto': concepto,
    'monto': monto,
    'monto_gross': monto,
    'fecha_pago': '${fechaHora}-03:00',
    'medio_pago': medio,
    'sesion_caja_id': caja,
    'anulado': anulado,
    'descuento_porcentaje': ?descuento,
    if (esMora) 'line_kind': kLineKindInteresMora,
  };
}

ContratoAlumno _contrato({double ajustePerdon = 0}) => ContratoAlumno(
      id: 'f1400000-0000-4000-8000-000000000014',
      eventoId: 'ev',
      nombreAlumno: 'FAMILIA, INVENTADA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 315000,
      totalCuotas: 9,
      cuotasPagadas: 7,
      saldoDeudor: 70000,
      moraTrackedAjuste: ajustePerdon,
      createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
    );

/// La forma del cobro que se reclamó el 14-nov: cuotas de $35.000. La 2 se
/// pagó un día tarde sin su mora; el 12/11 liquidó de la 3 a la 7 y pagó
/// $75.000 de mora (la 2, la 3 y parte de la 4); el 14/11 pagó los $53.800 que
/// quedaban.
({
  List<Map<String, dynamic>> pagos,
  List<Map<String, dynamic>> loteDel12,
  Map<String, dynamic> lineaDel14,
}) _familiaDel14() {
  final loteDel12 = [
    for (var n = 3; n <= 7; n++)
      _pago('2026-11-12T17:40:0$n', 'Cuota Base ($n/9)', 35000),
    _pago(
      '2026-11-12T17:40:08',
      'Interés mora cuotas 3, 4 + mora pendiente cuota 2',
      75000,
    ),
  ];
  final lineaDel14 = _pago(
    '2026-11-14T11:40:00',
    'Mora pendiente cuotas 2, 4, 5, 6 y 7 (no cobrada al pagar)',
    53800,
    caja: 'caja-2',
  );
  return (
    pagos: [
      _pago('2026-04-25T10:00:00', 'Cuota Base (1/9)', 35000),
      _pago('2026-06-01T10:00:00', 'Cuota Base (2/9)', 35000),
      ...loteDel12,
      lineaDel14,
    ],
    loteDel12: loteDel12,
    lineaDel14: lineaDel14,
  );
}

List<FilaMoraPdf> _filasVerdes(
  ContratoAlumno c,
  List<Map<String, dynamic>> pagos,
  Map<String, dynamic> fila,
) {
  final cobro = ReciboDeUnCobro.armar(
    contrato: c,
    lote: ReciboDeUnCobro.lineasDelCobro(pagos, fila),
    historial: pagos,
  );
  return filasMoraCobradaPdf(
    cobro.conceptos,
    conNotas: ReciboDeUnCobro.conNotas(contrato: c, historial: pagos),
  );
}

String _fila(FilaMoraPdf f) =>
    '${f.rotulo} debía ${f.debia?.toStringAsFixed(0) ?? '-'} '
    'pagó ${f.monto.toStringAsFixed(0)} quedó ${f.quedo?.toStringAsFixed(0) ?? '-'}'
    '${f.nota == null ? '' : ' · ${f.nota}'}';

void main() {
  group('lineasDelCobro', () {
    test('todo el cobro del renglón, sin anuladas ni el de otro momento', () {
      final a = _pago('2026-09-01T10:00:00', 'Cuota Base (1/9)', 30000);
      final b = _pago('2026-09-01T10:00:04', 'Interés mora cuota 1 (vto Abr 2026)', 900);
      final anulada = _pago('2026-09-01T10:00:05', 'Cuota Base (2/9)', 30000, anulado: 1);
      final otroCobro = _pago('2026-09-01T10:05:00', 'Cuota Base (2/9)', 30000);
      final otraCaja = _pago('2026-09-01T10:00:02', 'Cuota Base (3/9)', 30000, caja: 'caja-9');
      final historial = [a, b, anulada, otroCobro, otraCaja];
      expect(ReciboDeUnCobro.lineasDelCobro(historial, b).map((p) => p['id']),
          [a['id'], b['id']]);
      expect(ReciboDeUnCobro.lineasDelCobro(historial, a).map((p) => p['id']),
          [a['id'], b['id']]);
    });

    test('se encadena: un cobro largo no se parte según el renglón tocado', () {
      final l1 = _pago('2026-09-01T10:00:00', 'Cuota Base (1/9)', 30000);
      final l2 = _pago('2026-09-01T10:00:08', 'Cuota Base (2/9)', 30000);
      final l3 = _pago('2026-09-01T10:00:16', 'Cuota Base (3/9)', 30000);
      expect(ReciboDeUnCobro.lineasDelCobro([l1, l2, l3], l1).length, 3);
    });

    test('un renglón anulado no reimprime nada', () {
      final anulada = _pago('2026-09-01T10:00:00', 'Cuota Base (1/9)', 30000, anulado: 1);
      expect(ReciboDeUnCobro.lineasDelCobro([anulada], anulada), isEmpty);
    });
  });

  group('armar', () {
    test('un mixto sale mixto, con el descuento, y un anulado no suma', () {
      final c = _contrato();
      final lote = [
        _pago('2026-09-01T10:00:00', 'Cuota Base (1/9)', 20000, descuento: 10),
        _pago('2026-09-01T10:00:01', 'Cuota Base (1/9)', 11500, medio: 'Transferencia', descuento: 10),
        _pago('2026-09-01T10:00:02', 'Cuota Base (2/9)', 31500, anulado: 1),
      ];
      final r = ReciboDeUnCobro.armar(contrato: c, lote: lote, historial: lote);
      expect(r.medioPago, 'Mixto');
      expect(r.montoEfectivo, 20000);
      expect(r.montoTransferencia, 11500);
      expect(r.porcentajeDescuento, 10);
      expect(r.montoPagado, 31500);
      expect(r.fecha, DateTime.parse('2026-09-01T10:00:00-03:00'));
    });
  });

  group('la familia que reclamó el 14-nov', () {
    final c = _contrato();

    test('el recibo del 14/11 nombra las cuotas 4 a 7, con la nota de la 4',
        () {
      final f = _familiaDel14();
      expect(_filasVerdes(c, f.pagos, f.lineaDel14).map(_fila), [
        'Cuota 4 (Jul, 104 d) debía 9000 pagó 9000 quedó 0 · era de \$ 36.400,00: '
            'antes se pagaron \$ 27.400,00, hoy se terminó de pagar',
        'Cuota 5 (Ago, 73 d) debía 25550 pagó 25550 quedó 0',
        'Cuota 6 (Sep, 43 d) debía 15050 pagó 15050 quedó 0',
        'Cuota 7 (Oct, 12 d) debía 4200 pagó 4200 quedó 0',
      ]);
    });

    test('el del 12/11: la 2, la 3 entera y la 4 a medias, con lo que quedó',
        () {
      final f = _familiaDel14();
      final filas = _filasVerdes(c, f.pagos, f.loteDel12.last).map(_fila);
      expect(
        filas,
        unorderedEquals([
          'Cuota 2 (May, 1 d) debía 350 pagó 350 quedó 0',
          'Cuota 3 (135 d) debía 47250 pagó 47250 quedó 0',
          'Cuota 4 (104 d) debía 36400 pagó 27400 quedó 9000 · '
              'pagada parcialmente: quedaron \$ 9.000,00',
        ]),
      );
    });

    test('reimpreso desde el renglón de una cuota trae también la mora', () {
      final f = _familiaDel14();
      final cobro = ReciboDeUnCobro.armar(
        contrato: c,
        lote: ReciboDeUnCobro.lineasDelCobro(f.pagos, f.loteDel12.first),
        historial: f.pagos,
      );
      expect(cobro.montoPagado, 5 * 35000 + 75000);
      expect(
        cobro.conceptos.where((l) => l['esMora'] == true).length,
        3,
      );
    });

    test('con un perdón en la ficha, sin nota', () {
      final f = _familiaDel14();
      final conPerdon = _contrato(ajustePerdon: -1000);
      expect(ReciboDeUnCobro.conNotas(contrato: conPerdon, historial: f.pagos),
          isFalse);
      expect(
        _filasVerdes(conPerdon, f.pagos, f.lineaDel14).every((x) => x.nota == null),
        isTrue,
      );
    });

    test('hoy no debe mora: el recuadro rojo queda vacío', () {
      final f = _familiaDel14();
      final hoy = ReciboDeUnCobro.moraDeHoy(
        contrato: _contrato().copyWith(moraPendienteTracked: 0),
        historial: f.pagos,
      );
      expect(hoy.arrastre, isEmpty);
    });
  });

  test('sin conNotas, el recuadro verde queda como antes', () {
    final f = _familiaDel14();
    final c = _contrato();
    final cobro = ReciboDeUnCobro.armar(
      contrato: c,
      lote: [f.lineaDel14],
      historial: f.pagos,
    );
    expect(filasMoraCobradaPdf(cobro.conceptos).every((x) => x.nota == null),
        isTrue);
  });

  // La revisión final de la 6.9.0 encontró tres papeles que decían algo falso al
  // reimprimir. Ninguno cambia plata: cambia lo que el papel explica.
  group('revisión final de la 6.9.0', () {
    final c = _contrato();
    List<Map<String, dynamic>> antes() => [
          _pago('2026-04-25T10:00:00', 'Cuota Base (1/9)', 35000),
          _pago('2026-05-30T10:00:00', 'Cuota Base (2/9)', 35000),
          _pago('2026-06-29T10:00:00', 'Cuota Base (3/9)', 35000),
        ];

    // Una sola cuota del calendario con su mora cobrada a medias: se guarda sin
    // "(parcial)", y la reimpresión decía "Debía = lo pagado, Quedó $0".
    test('la mora de UNA cuota cobrada a medias: reimpresa dice lo que quedó', () {
      final cuota = _pago('2026-09-10T11:00:00', 'Cuota Base (4/9)', 35000);
      final mora = _pago('2026-09-10T11:00:01', 'Interés mora cuota 4 (vto Jul 2026)', 5000);
      final resto = _pago('2026-09-20T11:00:00', 'Mora pendiente cuota 4', 9000);
      final pagos = [...antes(), cuota, mora, resto];
      final filas = _filasVerdes(c, pagos, mora);
      expect(filas, hasLength(1));
      final f = filas.single;
      expect(f.monto, 5000);
      expect(f.quedo, isNotNull);
      expect(f.quedo!, greaterThan(0.01), reason: 'le quedó mora: ${_fila(f)}');
      expect(f.debia, closeTo(5000 + f.quedo!, 0.01));
      final cobro = ReciboDeUnCobro.armar(
        contrato: c,
        lote: ReciboDeUnCobro.lineasDelCobro(pagos, mora),
        historial: pagos,
      );
      final lineaMora = cobro.conceptos.firstWhere((l) => l['esMora'] == true);
      expect(lineaMora['concepto'], contains('(parcial)'));
    });

    // Revisión del 15-nov: con un perdón en la ficha, la reconstrucción no sabe
    // qué se perdonó y contaba mora de más; el reimpreso decía "a medias" una
    // mora pagada entera. Con un perdón, la línea sale como se guardó.
    test('con un perdón en la ficha, la mora de UNA cuota sale como se guardó', () {
      final conPerdon = c.copyWith(moraTrackedAjuste: -5000);
      final cuota = _pago('2026-09-10T11:00:00', 'Cuota Base (4/9)', 35000);
      final mora = _pago('2026-09-10T11:00:01', 'Interés mora cuota 4 (vto Jul 2026)', 5000);
      final pagos = [...antes(), cuota, mora];
      final cobro = ReciboDeUnCobro.armar(
        contrato: conPerdon,
        lote: ReciboDeUnCobro.lineasDelCobro(pagos, mora),
        historial: pagos,
      );
      final lineaMora = cobro.conceptos.firstWhere((l) => l['esMora'] == true);
      expect(lineaMora['concepto'], isNot(contains('(parcial)')));
      expect(lineaMora['montoPleno'], isNull);
      // Sin el perdón, la misma línea sí se confirma parcial (la cuenta da más).
      final sinPerdon = ReciboDeUnCobro.armar(
        contrato: c,
        lote: ReciboDeUnCobro.lineasDelCobro(pagos, mora),
        historial: pagos,
      );
      expect(
        sinPerdon.conceptos.firstWhere((l) => l['esMora'] == true)['concepto'],
        contains('(parcial)'),
      );
    });

    test('la mora de UNA cuota cobrada entera: reimpresa, debía lo que pagó', () {
      final cuota = _pago('2026-09-10T11:00:00', 'Cuota Base (4/9)', 35000);
      // Más de lo que daba la cuenta: no le quedó nada.
      final mora = _pago('2026-09-10T11:00:01', 'Interés mora cuota 4 (vto Jul 2026)', 90000);
      final pagos = [...antes(), cuota, mora];
      final f = _filasVerdes(c, pagos, mora).single;
      expect(f.debia, 90000);
      expect(f.quedo, 0);
    });

    // Un Mixto con la mora partida en efectivo y transferencia se guarda en dos
    // filas con el mismo concepto. Reimpreso, cada fila se repartía sola y la
    // cuota del arrastre salía dos veces (el doble de lo que debía).
    test('partir la mora en efectivo y transferencia no cambia el papel', () {
      List<String> filasCon(List<Map<String, dynamic>> lineasDeMora) {
        final cuota = _pago('2026-07-20T11:00:00', 'Cuota Base (4/9)', 35000);
        final pagos = [
          _pago('2026-04-25T10:00:00', 'Cuota Base (1/9)', 35000),
          // La 2 se pagó tarde, sin su mora: queda de arrastre.
          _pago('2026-06-20T10:00:00', 'Cuota Base (2/9)', 35000),
          _pago('2026-06-29T10:00:00', 'Cuota Base (3/9)', 35000),
          cuota,
          ...lineasDeMora,
        ];
        return [for (final f in _filasVerdes(c, pagos, cuota)) _fila(f)]..sort();
      }

      const concepto = 'Interés mora cuota 4 (vto Jul 2026) + mora pendiente cuota 2';
      final juntas = filasCon([_pago('2026-07-20T11:00:01', concepto, 10000)]);
      final partidas = filasCon([
        _pago('2026-07-20T11:00:01', concepto, 6000),
        _pago('2026-07-20T11:00:01', concepto, 4000, medio: 'Transferencia'),
      ]);
      expect(partidas, juntas);
      expect(juntas.where((f) => f.startsWith('Cuota 2')), hasLength(1));
    });

    // Reimpreso un recibo que saldó su mora, con la familia debiendo hoy otra
    // mora (de una cuota que entonces no estaba vencida): el título decía
    // "PARCIALMENTE" al lado de una tabla con "Quedó $0".
    test('reimpreso con otra mora de hoy, no dice que aquel pago fue parcial', () {
      // Aquel pago saldó su mora; hoy la familia debe otra (en la reimpresión
      // no hay "total de antes": la mora restante es la de hoy).
      expect(
        tituloMoraCobradaPdf(saldada: false, totalAntes: null, fueParcial: false),
        'MORA ABONADA EN ESTE PAGO',
      );
      expect(
        tituloMoraCobradaPdf(saldada: false, totalAntes: null, fueParcial: true),
        'MORA ABONADA PARCIALMENTE',
        reason: 'si una línea dice que quedó a medias, sí',
      );
      expect(
        tituloMoraCobradaPdf(saldada: false, totalAntes: 12000, fueParcial: false),
        'MORA ABONADA PARCIALMENTE',
        reason: 'al cobrar, lo que quedó se midió en el cobro',
      );
      expect(
        tituloMoraCobradaPdf(saldada: true, totalAntes: null, fueParcial: false),
        'MORA ABONADA EN SU TOTALIDAD',
      );
      // Y el recibo no vuelve a decidir con la mora de hoy.
      final codigo = File('lib/features/common/services/pdf_service.dart')
          .readAsStringSync();
      expect(codigo, isNot(contains('moraSigueDebiendo')));
      expect(codigo, contains('tituloMoraCobradaPdf('));
    });
  });

  test('el pie de las moras a medias concuerda en número', () {
    expect(pieDeMorasParciales(enteras: 0, parciales: 1), 'Se pagó 1 mora parcialmente.');
    expect(pieDeMorasParciales(enteras: 0, parciales: 2), 'Se pagaron 2 moras parcialmente.');
    expect(pieDeMorasParciales(enteras: 1, parciales: 1),
        'Se pagó 1 mora entera y 1 mora parcialmente.');
    expect(pieDeMorasParciales(enteras: 2, parciales: 1),
        'Se pagaron 2 moras enteras y 1 mora parcialmente.');
    expect(pieDeMorasParciales(enteras: 3, parciales: 0), isNull);
  });

  group('el papel de verdad', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory destino;
    setUp(() {
      destino = Directory.systemTemp.createTempSync('recibo_de_un_cobro');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => destino.path,
      );
    });
    tearDown(() {
      if (destino.existsSync()) destino.deleteSync(recursive: true);
    });

    test('el recibo del 14/11 reimpreso, con la nota, entra en media hoja',
        () async {
      final f = _familiaDel14();
      final c = _contrato();
      final cobro = ReciboDeUnCobro.armar(
        contrato: c,
        lote: ReciboDeUnCobro.lineasDelCobro(f.pagos, f.lineaDel14),
        historial: f.pagos,
      );
      final r = await PdfService.generarReciboAlumno(
        alumno: c,
        evento: Evento(
          id: 'ev',
          clienteId: 'cli',
          tipo: 'Egresados',
          fechaEvento: DateTime(2026, 12, 4),
          estado: EstadoEvento.confirmado,
          modalidad: 'masivo',
          cantidadCuotas: 9,
        ),
        montoPagado: cobro.montoPagado,
        saldoPendiente: 70000,
        conceptosPagados: cobro.conceptos,
        fechaManual: cobro.fecha,
        esReimpresion: true,
        moraPendienteRestante: 0,
        medioPago: cobro.medioPago,
        notasMoraPorCuota: true,
      );
      expect(r.alto, lessThanOrEqualTo(PdfPageFormat.a4.height / 2 + 0.5));
      expect(r.ajuste.subtextos, isTrue,
          reason: 'la nota se ve: el papel no tuvo que apagar los subtextos');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
