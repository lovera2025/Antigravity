import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/common/services/planilla_sorteo_pdf.dart';
import 'package:arguello_events/features/common/services/planilla_tema.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/nota_operativa_contrato.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

import 'helpers/leer_pdf.dart';

/// Un renglón de 10 puntos de alto que avisa cuando lo dibujan.
class _Renglon extends pw.Widget {
  _Renglon(this.alDibujar);

  final void Function() alDibujar;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    box = PdfRect.fromPoints(
      PdfPoint.zero,
      constraints.constrain(const PdfPoint(10, 10)),
    );
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    alDibujar();
  }
}

/// Cuántos de tres renglones apilados se dibujan cuando el alto disponible
/// queda una millonésima por debajo de lo que miden.
int _renglonesDibujados(pw.Widget Function(pw.Widget columna) envolver) {
  var dibujados = 0;
  final doc = pw.Document();
  final pagina = PdfPage(doc.document);
  final contexto = pw.Context(document: doc.document)
      .copyWith(page: pagina, canvas: pagina.getGraphics());
  final celda = envolver(
    pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [for (var i = 0; i < 3; i++) _Renglon(() => dibujados++)],
    ),
  );
  celda
    ..layout(
      contexto,
      const pw.BoxConstraints(maxWidth: 100, maxHeight: 29.999999),
    )
    ..paint(contexto);
  return dibujados;
}

ContratoAlumno _alumno(
  String id, {
  String nombre = 'PÉREZ, JUAN',
  String? curso = '5° A',
  List<int> mesas = const [],
  int extras = 0,
  int sillas = 0,
  List<String> acompanantes = const [],
  int cantidadAcompanantes = -1,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes:
          cantidadAcompanantes >= 0 ? cantidadAcompanantes : acompanantes.length,
      nombresAcompanantes: acompanantes,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      cursoDivision: curso,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      telefono: '370 4000000',
      musicaElegida: 'Cumbia',
    );

SillasReparto _elegido(ContratoAlumno a, {required int principal}) =>
    SillasReparto(
      id: 'r${a.id}',
      contratoAlumnoId: a.id,
      sillasPrincipal: principal,
      sillasExtra: SalonMesas.sillasExtra(a),
      mesas: SalonMesas.mesas(a),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

NotaOperativaContrato _nota(String contrato, String texto, {bool resuelto = false}) =>
    NotaOperativaContrato(
      id: 'n$contrato',
      contratoAlumnoId: contrato,
      texto: texto,
      resuelto: resuelto,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

const _pagoTodo = PagoAlumno(base: 30000, mesas: 10000, sillas: 8000);

void main() {
  group('mesa principal y adicional', () {
    test('un bloque: la primera es la principal y el resto la adicional', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [12, 13, 14], extras: 2));
      expect(f.mesaPrincipal, '12');
      expect(f.adicional, '13-14');
      expect(f.alertaMesas, isNull);
      expect(f.sinMesa, isFalse);
    });

    test('una mesa separada se dice separada', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [12, 13, 40], extras: 2));
      expect(f.mesaPrincipal, '12');
      expect(f.adicional, '13 · 40 (separada)');
    });

    test('sin mesa extra, la adicional es un guion', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [7]));
      expect(f.adicional, '-');
    });

    test('sin nada pagado de la base y sin mesa: fila roja', () {
      final f = PlanillaSorteo.fila(_alumno('a'), pago: PagoAlumno.nada);
      expect(f.mesaPrincipal, 'sin mesa (sin pagar)');
      expect(f.sinMesa, isTrue);
      expect(f.ocupacionPrincipal, isNull);
    });

    test('antes del sorteo, con algo pagado: sin asignar y no es fila roja', () {
      final f = PlanillaSorteo.fila(_alumno('a'), pago: _pagoTodo);
      expect(f.mesaPrincipal, 'sin asignar');
      expect(f.sinMesa, isFalse);
    });

    test('mesas extra todavía sin número, y "(sin pagar)" si están en \$0', () {
      expect(PlanillaSorteo.fila(_alumno('a', extras: 1)).adicional, '1 mesa extra');
      expect(
        PlanillaSorteo.fila(
          _alumno('a', extras: 2),
          pago: const PagoAlumno(base: 30000),
        ).adicional,
        '2 mesas extra (sin pagar)',
      );
    });

    test('si le falta una mesa lo avisa, con "(sin pagar)" si no la pagó', () {
      expect(
        PlanillaSorteo.fila(_alumno('a', mesas: [12], extras: 1)).alertaMesas,
        '(!) le falta 1 mesa',
      );
      expect(
        PlanillaSorteo.fila(
          _alumno('a', mesas: [12], extras: 1),
          pago: const PagoAlumno(base: 30000),
        ).alertaMesas,
        '(!) le falta 1 mesa (sin pagar)',
      );
    });
  });

  group('con cena y generales', () {
    test('egresado y dos acompañantes, con 2 sillas en la principal', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', mesas: [12], sillas: 2, acompanantes: ['MAMÁ', 'PAPÁ']),
      );
      expect(f.conCena, 3);
      expect(f.ocupacionPrincipal, '3 con cena · 7 generales');
    });

    test('una sola general va en singular', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', mesas: [3], acompanantes: List.filled(6, 'X')),
      );
      expect(f.ocupacionPrincipal, '7 con cena · 1 general');
    });

    test('si no entran en la principal, lo marca', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', mesas: [3], acompanantes: List.filled(11, 'X')),
      );
      expect(f.ocupacionPrincipal, '12 con cena · (!) faltan 4 lugares');
    });
  });

  group('sillas extra', () {
    test('de a 2 por mesa, la principal primero: 2P · 1A', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', mesas: [12, 13], extras: 1, sillas: 3),
      );
      expect(f.sillas, '2P · 1A');
      expect(f.reparto, RepartoSillas.pendiente);
    });

    test('antes del sorteo, solo la cantidad', () {
      expect(PlanillaSorteo.fila(_alumno('a', sillas: 3)).sillas, '3');
    });

    test('sin sillas extra no hay reparto', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [5]));
      expect(f.sillas, '-');
      expect(f.reparto, RepartoSillas.noAplica);
    });

    test('las que no entran se marcan, y "(sin pagar)" si están en \$0', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', mesas: [5], sillas: 3),
        pago: const PagoAlumno(base: 30000),
      );
      expect(f.sillas, '2P · (!) 1 sin lugar (sin pagar)');
    });

    test('con el reparto que eligió la familia: 1P · 2A y confirmado', () {
      final a = _alumno('a', mesas: [12, 13], extras: 1, sillas: 3);
      final f = PlanillaSorteo.fila(a, repartoElegido: _elegido(a, principal: 1));
      expect(f.sillas, '1P · 2A');
      expect(f.reparto, RepartoSillas.confirmado);
      // Con 1 silla en la principal: 9 lugares, 1 con cena, 8 generales.
      expect(f.ocupacionPrincipal, '1 con cena · 8 generales');
    });

    test('si eligió para otra cuenta, vuelve a pendiente y al reparto de siempre',
        () {
      final antes = _alumno('a', mesas: [12, 13], extras: 1, sillas: 3);
      final despues = _alumno('a', mesas: [12, 13], extras: 1, sillas: 4);
      final f = PlanillaSorteo.fila(
        despues,
        repartoElegido: _elegido(antes, principal: 1),
      );
      // 4 sillas en 2 mesas tiene una sola forma: 2P · 2A, confirmado solo.
      expect(f.sillas, '2P · 2A');
      expect(f.reparto, RepartoSillas.confirmado);

      final g = PlanillaSorteo.fila(
        _alumno('a', mesas: [12, 13], extras: 1, sillas: 2),
        repartoElegido: _elegido(antes, principal: 1),
      );
      expect(g.sillas, '2P');
      expect(g.reparto, RepartoSillas.pendiente);
    });

    test('con una sola forma posible no hay que llamar a nadie', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [7], sillas: 2));
      expect(f.sillas, '2P');
      expect(f.reparto, RepartoSillas.confirmado);
    });

    test('antes del sorteo, si ya eligió, dice cómo', () {
      final a = _alumno('a', extras: 1, sillas: 3);
      expect(
        PlanillaSorteo.fila(a, repartoElegido: _elegido(a, principal: 1)).sillas,
        '1P · 2A',
      );
    });
  });

  group('acompañantes y observaciones', () {
    test('uno por renglón, y los que no tienen nombre se cuentan', () {
      final f = PlanillaSorteo.fila(
        _alumno('a', acompanantes: ['MAMÁ'], cantidadAcompanantes: 3),
      );
      expect(f.acompanantes, ['MAMÁ', '2 acompañantes sin nombre']);
    });

    test('sin acompañantes cargados, la lista va vacía', () {
      expect(PlanillaSorteo.fila(_alumno('a')).acompanantes, isEmpty);
    });

    // "Avisar" (la fila amarilla) se sacó el 25-sep a pedido del usuario: se
    // deducía de cualquier nota sin resolver, que suelen ser de cobro. La nota
    // sigue saliendo en Observaciones.
    test('la nota sin resolver es la observación', () {
      final f = PlanillaSorteo.fila(
        _alumno('a'),
        nota: _nota('a', ' Vianda sin sal '),
      );
      expect(f.observaciones, 'Vianda sin sal');
    });

    test('la nota resuelta no aparece', () {
      final f = PlanillaSorteo.fila(
        _alumno('a'),
        nota: _nota('a', 'Ya está', resuelto: true),
      );
      expect(f.observaciones, isEmpty);
    });
  });

  group('divisiones y resumen', () {
    final alumnos = [
      _alumno('b1', nombre: 'ZARATE, EMMA', curso: '5° B', mesas: [7]),
      _alumno('a2', nombre: 'LÓPEZ, IVÁN', mesas: [2, 3], extras: 1, sillas: 2),
      _alumno('a1', nombre: 'ACOSTA, LUCÍA', mesas: [1]),
      _alumno('s1', nombre: 'RÍOS, BRUNO', curso: null),
      _alumno('x', nombre: '[BAJA] VERA, DANTE', mesas: [9]),
      _alumno('a3', nombre: 'MEDINA, SOFÍA'),
    ];
    final pagos = {
      for (final a in alumnos) a.id: _pagoTodo,
      'a3': PagoAlumno.nada,
    };
    final notas = {'a1': _nota('a1', 'Silla de ruedas')};

    test('una hoja por división, en orden, "Sin curso asignado" al final y sin bajas', () {
      final d = PlanillaSorteo.porDivision(alumnos, pagos: pagos, notas: notas);
      expect(d.keys, ['5° A', '5° B', PlanillaSorteo.sinDivision]);
      expect(
        d['5° A']!.map((f) => f.egresado),
        ['ACOSTA, LUCÍA', 'LÓPEZ, IVÁN', 'MEDINA, SOFÍA'],
      );
      expect(d.values.expand((f) => f).any((f) => f.egresado.contains('BAJA')), isFalse);
    });

    test('el resumen cuenta la noche y dice a quién llamar', () {
      final r = PlanillaSorteo.resumen(alumnos, pagos: pagos, notas: notas);
      expect(r.egresados, 5);
      expect(r.mesas, 6);
      expect(r.mesasAsignadas, 4);
      expect(r.sinMesa, 1);
      expect(r.repartosPendientes, 1);
      expect(r.aLlamar.single.fila.egresado, 'LÓPEZ, IVÁN');
      expect(r.divisiones.first.numeros, '1-3');
      expect(r.divisiones.first.sinMesa, 1);
    });

    test('los números de una división van de a tramos', () {
      expect(PlanillaSorteo.numerosEnTramos([7, 1, 3, 2]), '1-3 · 7');
      expect(PlanillaSorteo.numerosEnTramos(const []), '-');
    });
  });

  group('el pasto y los bloques del plano', () {
    test('la mesa principal en el pasto se marca para avisar', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [131]), pasto: {131, 132});
      expect(f.mesaPrincipal, '131');
      expect(f.principalEnPasto, isTrue);
      expect(f.mesasEnPasto, 1);
      expect(f.adicional, '-');
    });

    test('la adicional dice cuáles de sus mesas son del pasto', () {
      // Solo la última es del pasto: se parte el tramo.
      final parte = PlanillaSorteo.fila(
        _alumno('a', mesas: [129, 130, 131], extras: 2),
        pasto: {131, 132},
      );
      expect(parte.mesaPrincipal, '129');
      expect(parte.principalEnPasto, isFalse);
      expect(parte.adicional, '130 · 131 (pasto)');
      expect(parte.mesasEnPasto, 1);
      expect(parte.todasLasMesas, '129 + 130 · 131 (pasto)');

      // Todas en el pasto.
      final todas = PlanillaSorteo.fila(
        _alumno('a', mesas: [131, 132, 133], extras: 2),
        pasto: {131, 132, 133},
      );
      expect(todas.principalEnPasto, isTrue);
      expect(todas.adicional, '132-133 (pasto)');
      expect(todas.mesasEnPasto, 3);

      // Una separada y en el pasto.
      final separada = PlanillaSorteo.fila(
        _alumno('a', mesas: [12, 13, 140], extras: 2),
        pasto: {140},
      );
      expect(separada.adicional, '13 · 140 (separada, pasto)');
    });

    test('sin plano, la fila dice lo mismo que antes', () {
      final f = PlanillaSorteo.fila(_alumno('a', mesas: [12, 13, 40], extras: 2));
      expect(f.adicional, '13 · 40 (separada)');
      expect(f.principalEnPasto, isFalse);
      expect(f.mesasEnPasto, 0);
      expect(f.todasLasMesas, '12 + 13 · 40 (separada)');
    });

    final alumnos = [
      _alumno('a1', nombre: 'ACOSTA, LUCÍA', mesas: [1]),
      _alumno('a2', nombre: 'LÓPEZ, IVÁN', mesas: [2, 3], extras: 1),
      _alumno('b1', nombre: 'ZARATE, EMMA', curso: '5° b', mesas: [131]),
      _alumno('b2', nombre: 'VERA, DANTE', curso: '5° b', mesas: [20, 132], extras: 1),
      _alumno('s1', nombre: 'RÍOS, BRUNO', curso: null, mesas: [40]),
    ];
    const bloques = [BloqueDivision('5A', 1, 10), BloqueDivision('5B', 11, 131)];

    test('el resumen dice a quién avisar por el pasto', () {
      final r = PlanillaSorteo.resumen(alumnos, pasto: {131, 132}, bloques: bloques);
      expect(r.hayPasto, isTrue);
      expect(r.mesasEnPasto, 2);
      expect(
        r.aAvisarPasto.map((x) => x.fila.egresado),
        ['VERA, DANTE', 'ZARATE, EMMA'],
      );
      expect(r.aAvisarPasto.first.division, '5° b');
    });

    test('cada división lleva su bloque, se escriba como se escriba', () {
      final r = PlanillaSorteo.resumen(alumnos, pasto: {131, 132}, bloques: bloques);
      expect(r.hayBloques, isTrue);
      expect(
        {for (final d in r.divisiones) d.division: d.bloque},
        {'5° A': '1-10', '5° b': '11-131', PlanillaSorteo.sinDivision: null},
      );
    });

    test('sin plano, el resumen no habla de pasto ni de bloques', () {
      final r = PlanillaSorteo.resumen(alumnos);
      expect(r.hayPasto, isFalse);
      expect(r.hayBloques, isFalse);
      expect(r.mesasEnPasto, 0);
      expect(r.aAvisarPasto, isEmpty);
    });

    test('un salón con pasto que nadie usa: cero, y nadie a quien avisar', () {
      final r = PlanillaSorteo.resumen(alumnos, pasto: {200, 201});
      expect(r.hayPasto, isTrue);
      expect(r.mesasEnPasto, 0);
      expect(r.aAvisarPasto, isEmpty);
    });
  });

  group('papel', () {
    test('una celda dibuja todos sus renglones aunque el alto quede justo', () {
      // El paquete deja afuera el último renglón de una columna si lo que
      // mide pasa del tope por un redondeo: así se perdía "PASTO · avisar".
      // Si esta línea falla es que el paquete lo arregló: [AltoLibre] deja de
      // hacer falta, pero no molesta.
      expect(_renglonesDibujados((columna) => columna), 2);
      expect(_renglonesDibujados((columna) => AltoLibre(child: columna)), 3);
    });

    test('el aviso del pasto y todos los acompañantes salen escritos', () async {
      final evento = Evento(
        id: 'e',
        clienteId: 'c',
        tipo: 'Recepción',
        fechaEvento: DateTime(2026, 12, 5),
        estado: EstadoEvento.planificacion,
        modalidad: 'masivo',
        cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE PRUEBA'),
      );
      final alumnos = [
        _alumno('a', nombre: 'ACOSTA, LUCÍA', mesas: [133]),
        _alumno('b', nombre: 'LÓPEZ, IVÁN', mesas: [130, 131, 132], extras: 2),
        _alumno(
          'c',
          nombre: 'MEDINA, SOFÍA',
          mesas: [5],
          acompanantes: ['PRIMERA', 'SEGUNDA', 'TERCERA', 'CUARTA', 'QUINTA'],
        ),
      ];
      for (final version in VersionPlanillaSorteo.values) {
        // Sin las letras de la app, para poder leer lo que escribió.
        final bytes = await PlanillaSorteoPdf.construir(
          evento: evento,
          alumnos: alumnos,
          pasto: {131, 132, 133},
          bloques: const [BloqueDivision('5A', 1, 132)],
          version: version,
          generada: DateTime(2026, 11, 12, 21, 30),
        );
        // El paquete escribe palabra por palabra, cada una entre paréntesis.
        final texto = contenidoDelPdf(bytes);
        for (final palabra in [
          // "PASTO · avisar", en la mesa principal.
          '(avisar)',
          // "132 (pasto)", en la adicional.
          r'[(\(pasto\))]',
          '(BLOQUE)',
          '(1-132)',
          '(PRIMERA)',
          '(SEGUNDA)',
          '(TERCERA)',
          '(CUARTA)',
          '(QUINTA)',
        ]) {
          expect(texto.contains(palabra), isTrue, reason: '$version: $palabra');
        }
      }
    });

    test('la versión para repartir no lleva teléfonos ni observaciones', () {
      expect(
        PlanillaSorteoPdf.columnas(VersionPlanillaSorteo.interna),
        containsAll(['Teléfono', 'Observaciones']),
      );
      final repartir = PlanillaSorteoPdf.columnas(VersionPlanillaSorteo.paraRepartir);
      expect(repartir, isNot(contains('Teléfono')));
      expect(repartir, isNot(contains('Observaciones')));
      // Las columnas del Excel del jefe van primero y en su orden.
      expect(
        repartir.take(5),
        ['Egresado', 'Acompañantes', 'Mesa principal', 'Adicional', 'Sillas'],
      );
    });

    test('se arma en las cuatro variantes con las fuentes de la app', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final evento = Evento(
        id: 'e',
        clienteId: 'c',
        tipo: 'Recepción',
        fechaEvento: DateTime(2026, 12, 5),
        estado: EstadoEvento.planificacion,
        modalidad: 'masivo',
        cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE PRUEBA'),
      );
      final alumnos = [
        for (var i = 0; i < 40; i++)
          _alumno(
            'a$i',
            nombre: 'ALUMNO $i',
            curso: i < 30 ? '5° A' : '5° B',
            mesas: [i + 1],
            sillas: i % 5 == 0 ? 2 : 0,
            acompanantes: i % 3 == 0 ? ['MAMÁ', 'PAPÁ'] : const [],
          ),
      ];
      for (final version in VersionPlanillaSorteo.values) {
        for (final bn in [false, true]) {
          final bytes = await PdfService.construirPlanillaSorteoPdf(
            evento,
            alumnos,
            version: version,
            blancoYNegro: bn,
            generada: DateTime(2026, 11, 12, 21, 30),
          );
          expect(bytes.length, greaterThan(1000), reason: '$version bn=$bn');
        }
      }
    });
  });
}
