// La mesa adicional "a confirmar" en el PLANO (6.9.2; pedido del jefe,
// 16-nov-2026): la que no está paga entera se ve punteada y apagada; en modo
// jefe se la cobra (el plano se cierra y devuelve a quién) o se la anula (la
// familia deja esa mesa y la adicional se baja de su contrato, por el camino
// de Editar alumno).
//
// Va de abajo hacia arriba: la cuenta del plano con los pagos, el dibujo, las
// dos reglas sin pantalla (soltar una mesa, bajar la adicional), la tarjeta de
// la familia y la pantalla entera montada en memoria.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/eventos/services/edicion_de_alumno.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/plano_evento_screen.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/historial_sorteo.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/plano_en_memoria.dart';

const _eventoId = 'e0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 11, 18, 15);

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  String division = '5° A',
  dynamic estadoMesas,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _eventoId,
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 70000.0 * extras,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      mesasExtraEstadoRaw: estadoMesas,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

Map<String, dynamic> _pagoDeMesa(double monto) => {
      'concepto': 'Mesa extra (1/1)',
      'monto': monto,
      'monto_gross': monto,
      'anulado': 0,
    };

/// GÓMEZ tiene la 8 y la 9 (la adicional, sin pagar); RUIZ, la 25 y la 26 (la
/// adicional paga); SOSA, una sola.
List<ContratoAlumno> _alumnos() => [
      _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8, 9]),
      _alumno('ruiz', 'RUIZ, TOMÁS', extras: 1, mesas: [25, 26]),
      _alumno('sosa', 'SOSA, LUZ', mesas: [20], division: '5° B'),
    ];

Map<String, List<Map<String, dynamic>>> _pagos({double gomez = 0}) => {
      'gomez': [if (gomez > 0) _pagoDeMesa(gomez)],
      'ruiz': [_pagoDeMesa(70000)],
      'sosa': const [],
    };

ArmadoSalon _armado() => ArmarAMedida.armar(
      const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 40),
    ).armado;

PlanoDeLaFiesta _fiesta({
  List<ContratoAlumno>? alumnos,
  Map<String, List<Map<String, dynamic>>>? pagos,
  bool sinPagos = false,
  ConfigPlano config = ConfigPlano.vacia,
}) =>
    PlanoDeLaFiesta.desde(
      armado: _armado(),
      config: config,
      alumnos: alumnos ?? _alumnos(),
      pagos: sinPagos ? null : (pagos ?? _pagos()),
    );

final _evento = Evento(
  id: _eventoId,
  clienteId: 'c0000000-0000-4000-8000-000000000001',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 12),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
);

PlanoEvento _plano({ConfigPlano config = ConfigPlano.vacia}) => PlanoEvento.nuevo(
      eventoId: _eventoId,
      armado: _armado(),
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: _ahora,
    ).copyWith(config: config, ahora: _ahora);

/// Lo que se dijo al lado de los botones del pie.
String _dicho(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('aviso_del_pie_texto')))
    .data!;

bool _prendido(WidgetTester tester, String clave) =>
    tester.widget<OutlinedButton>(find.byKey(Key(clave))).onPressed != null;

/// Todo lo que está escrito en la pantalla, en minúsculas.
String _todoLoEscrito(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ].join('\n').toLowerCase();

Future<void> _mostrarCuerpo(
  WidgetTester tester, {
  required PlanoDeLaFiesta plano,
  List<ContratoAlumno>? alumnos,
  String? resaltar = 'gomez',
  AccionesPlano? acciones,
  bool soloJefe = false,
  bool ocupado = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
      home: Scaffold(
        body: PlanoEventoCuerpo(
          plano: plano,
          estilo: EstiloPlano.arquitecto,
          alumnos: alumnos ?? _alumnos(),
          resaltarAlumnoId: resaltar,
          acciones: acciones,
          soloJefe: soloJefe,
          ocupado: ocupado,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

AccionesPlano _acciones(List<String> tocados) => AccionesPlano(
      onFijarEnMesa: (_) {},
      onFijar: (_, _) {},
      onQuitarFijadas: (_) {},
      onQuitarFijadaDeMesa: (_) {},
      onDejarLibre: (_) {},
      onVolverAUsar: (_) {},
      onCambiar: (_, _) {},
      onMover: (_, _) {},
      onCobrarAConfirmar: (a) => tocados.add('cobrar a $a'),
      onAnularAConfirmar: (a, m) => tocados.add('anular la $m de $a'),
    );

/// El plano pintado como imagen, para mirar los puntos de una mesa.
Future<({ByteData bytes, int ancho, EncuadrePlano encuadre})> _pintar(
  WidgetTester tester,
  PlanoDeLaFiesta fiesta,
  TemaPlano tema,
) async {
  const tam = Size(2400, 1600);
  final armado = fiesta.armado;
  final hoja = armado.hojas.first;
  final grabador = ui.PictureRecorder();
  final canvas = Canvas(grabador);
  canvas.drawRect(Offset.zero & tam, Paint()..color = tema.fondo);
  PintorPlano(
    armado: armado,
    hoja: hoja.id,
    tema: tema,
    estado: fiesta.estado,
  ).paint(canvas, tam);
  final dibujo = grabador.endRecording();
  final bytes = await tester.runAsync(() async {
    final imagen = await dibujo.toImage(tam.width.toInt(), tam.height.toInt());
    return imagen.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  return (
    bytes: bytes!,
    ancho: tam.width.toInt(),
    encuadre: EncuadrePlano.de(hoja.caja, tam),
  );
}

Color _punto(ByteData bytes, int ancho, Offset p) {
  final i = (p.dy.round() * ancho + p.dx.round()) * 4;
  return Color.fromARGB(
    bytes.getUint8(i + 3),
    bytes.getUint8(i),
    bytes.getUint8(i + 1),
    bytes.getUint8(i + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(cargarFuentesPlano);

  group('el plano con los pagos', () {
    test('la adicional sin pagar está a confirmar; la paga y la principal, no',
        () {
      final p = _fiesta();
      expect(p.aConfirmar.keys, [9]);
      expect(p.aConfirmar[9]!.alumnoId, 'gomez');
      expect(p.aConfirmar[9]!.adicional.aPagar, 70000);
      expect(p.aConfirmar[9]!.adicional.sePuedeAnular, isTrue);
      expect(p.estado.info(9).aConfirmar, isTrue);
      expect(p.estado.info(8).aConfirmar, isFalse);
      expect(p.estado.info(25).aConfirmar, isFalse);
      expect(p.estado.info(26).aConfirmar, isFalse);
      // Sigue siendo de su familia: se la busca, se la toca y se la mueve
      // como cualquier otra.
      expect(p.estado.info(9).estado, EstadoMesa.ocupada);
      expect(p.estado.info(9).ocupante?.id, 'gomez');
    });

    test('pagada en parte sigue a confirmar, y ya no se anula', () {
      final p = _fiesta(pagos: _pagos(gomez: 30000));
      expect(p.aConfirmar[9]!.adicional.aPagar, 40000);
      expect(p.aConfirmar[9]!.adicional.sePuedeAnular, isFalse);
    });

    test('cuando la familia paga, vuelve sola a la normalidad', () {
      final p = _fiesta(pagos: _pagos(gomez: 70000));
      expect(p.aConfirmar, isEmpty);
      expect(p.estado.info(9).aConfirmar, isFalse);
    });

    test('sin los pagos (no se pudieron leer) no se marca ninguna', () {
      final p = _fiesta(sinPagos: true);
      expect(p.aConfirmar, isEmpty);
      expect(p.estado.mesas.where((i) => i.aConfirmar), isEmpty);
    });

    test('la familia de baja conserva su mesa, pero no hay nada que confirmar',
        () {
      final p = _fiesta(alumnos: [
        _alumno('gomez', '[BAJA] GÓMEZ, SOFÍA', extras: 1, mesas: [8, 9]),
      ], pagos: const {'gomez': []});
      expect(p.aConfirmar, isEmpty);
    });

    test('una mesa que tienen dos familias no se dibuja a confirmar: primero '
        'hay que resolver de quién es', () {
      final p = _fiesta(alumnos: [
        ..._alumnos(),
        _alumno('vega', 'VEGA, ANA', mesas: [9]),
      ], pagos: {..._pagos(), 'vega': const []});
      expect(p.estado.info(9).estado, EstadoMesa.conflicto);
      expect(p.estado.info(9).aConfirmar, isFalse);
      expect(p.aConfirmar, isEmpty);
    });

    test('una mesa que no está en este armado no entra', () {
      final p = _fiesta(alumnos: [
        _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8, 999]),
      ], pagos: const {'gomez': []});
      expect(p.aConfirmar, isEmpty);
    });
  });

  group('el dibujo', () {
    for (final estilo in EstiloPlano.values) {
      testWidgets('${estilo.name}: va apagada, como una vacía', (tester) async {
        final fiesta = _fiesta();
        final tema = fiesta.tema(estilo);
        final r = await _pintar(tester, fiesta, tema);
        final radio = radioDibujo(fiesta.armado, tema) * r.encuadre.escala;

        Offset centro(int n) {
          final m = fiesta.armado.mesa(n)!;
          return r.encuadre.aPantalla(Offset(m.x, m.y));
        }

        // El relleno, lejos del número y del relojito: abajo a la derecha.
        Color relleno(int n) => _punto(
              r.bytes,
              r.ancho,
              centro(n) + Offset(radio * 0.45, radio * 0.55),
            );
        // Una vacía cualquiera, para comparar.
        const vacia = 30;
        expect(fiesta.estado.info(vacia).estado, EstadoMesa.vacia);
        expect(
          _lejos(relleno(9), relleno(vacia)),
          isFalse,
          reason: 'apagada como una vacía',
        );
        expect(
          _lejos(relleno(26), relleno(25)),
          isFalse,
          reason: 'la adicional paga se pinta como la principal',
        );
        // En los estilos que rellenan la mesa con familia, la que está a
        // confirmar no va rellena.
        if (_lejos(relleno(8), relleno(vacia))) {
          expect(_lejos(relleno(9), relleno(8)), isTrue);
        }
      });

      test('${estilo.name}: el borde va punteado, con su relojito', () {
        // Lo que el pintor dibuja de más cuando la 9 está a confirmar: las
        // catorce rayas del borde alrededor de esa mesa, y las dos agujas.
        List<RecordedInvocation> dibujado(PlanoDeLaFiesta fiesta) {
          final canvas = TestRecordingCanvas();
          PintorPlano(
            armado: fiesta.armado,
            hoja: fiesta.armado.hojas.first.id,
            tema: fiesta.tema(estilo),
            estado: fiesta.estado,
          ).paint(canvas, const Size(2400, 1600));
          return canvas.invocations.toList();
        }

        List<Rect> rayas(PlanoDeLaFiesta fiesta) => [
              for (final i in dibujado(fiesta))
                if (i.invocation.memberName == #drawArc)
                  i.invocation.positionalArguments.first as Rect,
            ];
        int agujas(PlanoDeLaFiesta fiesta) => dibujado(fiesta)
            .where((i) => i.invocation.memberName == #drawLine)
            .length;

        final paga = _fiesta(pagos: _pagos(gomez: 70000));
        final aConfirmar = _fiesta();
        final m = aConfirmar.armado.mesa(9)!;
        final deLa9 = [
          for (final r in rayas(aConfirmar))
            if ((r.center - Offset(m.x, m.y)).distance < 0.5) r,
        ];
        expect(deLa9, hasLength(14));
        expect(rayas(aConfirmar).length - rayas(paga).length, 14);
        expect(agujas(aConfirmar) - agujas(paga), 2);
        // Sin los pagos, nada de eso.
        expect(rayas(_fiesta(sinPagos: true)), hasLength(rayas(paga).length));
      });
    }
  });

  group('soltar una mesa (CambiosDeMesa.soltarUna)', () {
    CambioDeMesas soltar(
      List<ContratoAlumno> alumnos, {
      String de = 'gomez',
      int mesa = 9,
      ConfigPlano config = ConfigPlano.vacia,
      Set<String> yaRetiraron = const {},
    }) =>
        CambiosDeMesa.soltarUna(
          config: config,
          alumnos: alumnos,
          alumnoId: de,
          mesa: mesa,
          yaRetiraron: yaRetiraron,
        );

    test('la familia deja esa mesa y conserva la otra', () {
      final c = soltar(_alumnos());
      expect(c.sePuede, isTrue);
      expect(c.antes, {'gomez': '8, 9'});
      expect(c.despues, {'gomez': '8'});
      expect(c.config, isNull);
      expect(c.textoHecho((_) => 'GÓMEZ'), 'GÓMEZ dejó la 9.');
      expect(c.avisos, contains('La mesa 9 queda vacía: se le puede dar a otra familia.'));
      expect(c.avisos, contains('Esa mesa adicional se baja del contrato de GÓMEZ.'));
    });

    test('no es un tipo de movimiento nuevo: una versión anterior lo lee como '
        'un "mover" y lo aplica igual', () {
      final c = soltar(_alumnos());
      expect(c.tipo, TipoMovimientoMesas.mover);
      final renglon = c.movimiento(
        id: 'm1',
        eventoId: _eventoId,
        motivo: CambiosDeMesa.motivoAnulada,
        hechoPor: 'Jefe',
        ahora: _ahora,
      );
      expect(renglon.tipo.clave, 'mover');
      expect(renglon.motivo, 'Mesa adicional anulada');
      // Ni el motivo ni los avisos, que cualquiera ve en el Historial, hablan
      // de plata.
      for (final texto in [renglon.motivo, ...renglon.avisos]) {
        expect(texto.toLowerCase(), isNot(contains('pag')));
        expect(texto.toLowerCase(), isNot(contains('debe')));
        expect(texto, isNot(contains(r'$')));
      }
    });

    test('no se puede: no es su mesa, es la única que tiene, o está de baja',
        () {
      expect(soltar(_alumnos(), mesa: 20).problema,
          'GÓMEZ ya no tiene la mesa 20.');
      expect(soltar(_alumnos(), de: 'sosa', mesa: 20).problema,
          'SOSA tiene una sola mesa: no se le saca desde acá.');
      expect(
        soltar([
          _alumno('gomez', '[BAJA] GÓMEZ, SOFÍA', extras: 1, mesas: [8, 9]),
        ]).problema,
        'Esa familia ya no está en la fiesta.',
      );
      expect(soltar(_alumnos(), de: 'nadie').sePuede, isFalse);
    });

    test('si esa mesa era una fijada suya, la fijada se va con la mesa: si '
        'quedara, el sorteo se la volvería a dar', () {
      final fijada = MesaFijada(alumnoId: 'gomez', motivo: 'Abuela', cuando: _ahora);
      final c = soltar(
        _alumnos(),
        config: ConfigPlano(fijadas: {8: fijada, 9: fijada}),
      );
      expect(c.config!.fijadas.keys, [8]);
    });

    test('avisa si ya retiró sus entradas y si tiene sillas extra', () {
      final c = soltar(
        [_alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 2, mesas: [8, 9])],
        yaRetiraron: {'gomez'},
      );
      expect(c.hayQueAvisarALaFamilia, isTrue);
      expect(c.avisos.join(' '), contains('ya retiró sus entradas'));
      expect(c.avisos.join(' '), contains('la mesa que conserva'));
    });

    test('lo que dejó, sin tomar ninguna', () {
      expect(CambioDeMesas.mesasQueDejo('8, 9', '8'), [9]);
      expect(CambioDeMesas.mesasQueDejo('8, 9, 10', '9'), [8, 10]);
      // Tomó una: no es "dejó".
      expect(CambioDeMesas.mesasQueDejo('8, 9', '8, 30'), isNull);
      expect(CambioDeMesas.mesasQueDejo('8, 9', '8, 9'), isNull);
    });

    group('deshacerlo', () {
      MovimientoMesas renglon() => soltar(_alumnos()).movimiento(
            id: 'm1',
            eventoId: _eventoId,
            motivo: CambiosDeMesa.motivoAnulada,
            hechoPor: 'Jefe',
            ahora: _ahora,
          );

      test('con la adicional ya bajada del contrato, no: quedaría sentada en '
          'una mesa que no contrató', () {
        final r = renglon();
        final hoy = [
          _alumno('gomez', 'GÓMEZ, SOFÍA', mesas: [8]),
          ..._alumnos().skip(1),
        ];
        final d = CambiosDeMesa.deshacer(
          movimiento: r,
          movimientos: [r],
          alumnos: hoy,
        );
        expect(
          d.problema,
          'GÓMEZ ya no tiene esa mesa en su contrato. Para devolvérsela, '
          'agregale la mesa en Editar alumno.',
        );
      });

      test('si la adicional sigue en su contrato (no se llegó a bajar), sí: '
          'vuelve a su mesa', () {
        final r = renglon();
        final hoy = [
          _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8]),
          ..._alumnos().skip(1),
        ];
        final d = CambiosDeMesa.deshacer(
          movimiento: r,
          movimientos: [r],
          alumnos: hoy,
        );
        expect(d.sePuede, isTrue);
        expect(d.despues, {'gomez': '8, 9'});
      });

      test('un mover común se sigue deshaciendo como siempre', () {
        final mover = CambiosDeMesa.moverUna(
          armado: _armado(),
          config: ConfigPlano.vacia,
          alumnos: _alumnos(),
          alumnoId: 'gomez',
          mesa: 9,
          aMesa: 30,
        ).movimiento(
          id: 'm2',
          eventoId: _eventoId,
          motivo: 'Prueba',
          hechoPor: 'Jefe',
          ahora: _ahora,
        );
        final hoy = [
          _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8, 30]),
          ..._alumnos().skip(1),
        ];
        expect(
          CambiosDeMesa.deshacer(
            movimiento: mover,
            movimientos: [mover],
            alumnos: hoy,
          ).sePuede,
          isTrue,
        );
      });
    });

    test('el Historial dice que dejó la mesa, no que "pasó a otras"', () {
      final r = soltar(_alumnos()).movimiento(
        id: 'm1',
        eventoId: _eventoId,
        motivo: CambiosDeMesa.motivoAnulada,
        hechoPor: 'Jefe',
        ahora: _ahora,
      );
      final hoy = [
        _alumno('gomez', 'GÓMEZ, SOFÍA', mesas: [8]),
        ..._alumnos().skip(1),
      ];
      final historial = HistorialSorteo.armar(
        registros: const [],
        movimientos: [r],
        config: ConfigPlano.vacia,
        alumnos: hoy,
        yaRetiraron: const {},
      );
      final renglon =
          historial.renglones.firstWhere((x) => x.movimiento?.id == 'm1');
      expect(renglon.titulo, contains('dejó la 9'));
      expect(renglon.titulo, isNot(contains('pasó a otras mesas')));
      expect(renglon.detalle, contains('Motivo: Mesa adicional anulada'));
      expect(renglon.noSeDeshacePorque, contains('ya no tiene esa mesa'));
    });
  });

  group('bajar la adicional del contrato (BajaDeAdicional)', () {
    test('con una sola adicional: queda sin ninguna, y el total y el saldo '
        'bajan lo que valía', () {
      final a = _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8]);
      final b = BajaDeAdicional.de(a);
      expect(b.sePuede, isTrue);
      final e = b.editado!;
      expect(e.mesaExtraCantidad, 0);
      expect(e.mesaExtraPrecio, 0);
      expect(e.montoTotalPactado, a.montoTotalPactado - 70000);
      expect(e.saldoDeudor, a.saldoDeudor - 70000);
      expect(e.mesasExtraEstadoRaw, isEmpty);
    });

    test('con dos: queda la primera, con lo que tenía pagado', () {
      final a = _alumno(
        'gomez',
        'GÓMEZ, SOFÍA',
        extras: 2,
        mesas: [8, 9],
        estadoMesas: [
          {'n': 1, 'precio': 70000.0, 'pagado': 70000.0, 'liquidada': true},
          {'n': 2, 'precio': 70000.0, 'pagado': 0.0},
        ],
      );
      final e = BajaDeAdicional.de(a).editado!;
      expect(e.mesaExtraCantidad, 1);
      expect(e.mesaExtraPrecio, 70000);
      expect(e.montoTotalPactado, a.montoTotalPactado - 70000);
      final mesas = e.mesasExtraParsed;
      expect(mesas, hasLength(1));
      expect(mesas.single.n, 1);
      expect(mesas.single.pagado, 70000);
    });

    test('lo demás de la ficha no cambia: al guardar no viajan la mesa, los '
        'acompañantes, la música ni la mora', () {
      final a = _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, mesas: [8]);
      final e = BajaDeAdicional.de(a).editado!;
      expect(e.nombreAlumno, a.nombreAlumno);
      expect(e.numeroMesa, a.numeroMesa);
      expect(e.sillasExtraCantidad, a.sillasExtraCantidad);
      final datos = datosEdicionAlumno(
        antes: a,
        editado: e,
        numeroMesaEscrito: a.numeroMesa ?? '',
      );
      expect(datos.containsKey('numero_mesa'), isFalse);
      expect(datos.containsKey('nombres_acompanantes'), isFalse);
      expect(datos.containsKey('musica_elegida'), isFalse);
      for (final campo in camposMoraDelAlumno) {
        expect(datos.containsKey(campo), isFalse, reason: campo);
      }
      expect(datos['mesa_extra_cantidad'], 0);
    });

    test('no se puede: sin adicional, con pagos anotados en esa mesa, o con '
        'sillas que ya no entran', () {
      expect(
        BajaDeAdicional.de(_alumno('sosa', 'SOSA, LUZ', mesas: [20])).problema,
        'Ya no tiene una mesa adicional en su contrato.',
      );
      final conPagos = _alumno(
        'gomez',
        'GÓMEZ, SOFÍA',
        extras: 1,
        mesas: [8],
        estadoMesas: [
          {'n': 1, 'precio': 70000.0, 'pagado': 20000.0},
        ],
      );
      expect(BajaDeAdicional.de(conPagos).problema, contains('pagos anotados'));
      final conSillas =
          _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 3, mesas: [8]);
      expect(
        BajaDeAdicional.de(conSillas).problema,
        'Tiene 3 sillas extra, y con una mesa menos entran hasta 2: primero '
        'bajale las sillas en Editar alumno.',
      );
    });
  });

  group('la tarjeta de la familia', () {
    testWidgets('sin modo jefe: dice "a confirmar" y nada de plata; los dos '
        'botones se ven apagados, con el motivo', (tester) async {
      await _mostrarCuerpo(tester, plano: _fiesta(), soloJefe: true);
      expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);
      expect(find.byKey(const Key('a_pagar_9')), findsNothing);
      expect(_prendido(tester, 'cobrar_a_confirmar_9'), isFalse);
      expect(_prendido(tester, 'anular_a_confirmar_9'), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('motivo_a_confirmar_9'))).data,
        kSoloEnModoJefe,
      );
      final escrito = _todoLoEscrito(tester);
      for (final palabra in [r'$', 'debe', 'sin pagar', 'a pagar', 'pagado']) {
        expect(escrito, isNot(contains(palabra)), reason: palabra);
      }
      // La otra mesa, la paga, dice sus sillas como siempre.
      expect(find.byKey(const Key('sillas_mesa_8')), findsOneWidget);
      expect(find.byKey(const Key('sillas_mesa_9')), findsNothing);
    });

    testWidgets('en modo jefe: cuánto falta, COBRAR y ANULAR', (tester) async {
      final tocados = <String>[];
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(),
        acciones: _acciones(tocados),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('a_pagar_9'))).data,
        r'A pagar: $ 70.000',
      );
      expect(find.byKey(const Key('motivo_a_confirmar_9')), findsNothing);
      await tester.tap(find.byKey(const Key('cobrar_a_confirmar_9')));
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      expect(tocados, ['cobrar a gomez', 'anular la 9 de gomez']);
    });

    testWidgets('con algo pagado: se cobra lo que falta, y ANULAR queda '
        'apagado con el porqué', (tester) async {
      final tocados = <String>[];
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(pagos: _pagos(gomez: 30000)),
        acciones: _acciones(tocados),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('a_pagar_9'))).data,
        r'A pagar: $ 40.000',
      );
      expect(_prendido(tester, 'cobrar_a_confirmar_9'), isTrue);
      expect(_prendido(tester, 'anular_a_confirmar_9'), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('motivo_a_confirmar_9'))).data,
        r'Tiene $ 30.000 pagado: esta noche no se anula. Decidilo en la '
        'oficina.',
      );
      await tester.tap(
        find.byKey(const Key('anular_a_confirmar_9')),
        warnIfMissed: false,
      );
      expect(tocados, isEmpty);
    });

    testWidgets('mientras se guarda otro cambio, los dos esperan',
        (tester) async {
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(),
        acciones: _acciones([]),
        ocupado: true,
      );
      expect(_prendido(tester, 'cobrar_a_confirmar_9'), isFalse);
      expect(_prendido(tester, 'anular_a_confirmar_9'), isFalse);
    });

    testWidgets('la adicional paga y la familia sin adicional no tienen nada '
        'de esto', (tester) async {
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(),
        resaltar: 'ruiz',
        acciones: _acciones([]),
      );
      expect(find.textContaining('a confirmar'), findsNothing);
      expect(find.byKey(const Key('sillas_mesa_26')), findsOneWidget);
    });
    testWidgets('la leyenda dice cuántas hay, y cada toque lleva a la '
        'siguiente', (tester) async {
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(
          alumnos: [
            ..._alumnos(),
            _alumno('vega', 'VEGA, ANA', extras: 1, mesas: [30, 31]),
          ],
          pagos: {..._pagos(), 'vega': const []},
        ),
        alumnos: [
          ..._alumnos(),
          _alumno('vega', 'VEGA, ANA', extras: 1, mesas: [30, 31]),
        ],
        resaltar: null,
      );
      expect(find.text('A confirmar: 2 mesas adicionales'), findsOneWidget);
      expect(find.byKey(const Key('elegido')), findsNothing);
      await tester.tap(find.byKey(const Key('leyenda_a_confirmar')));
      await tester.pump();
      expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leyenda_a_confirmar')));
      await tester.pump();
      expect(find.text('Mesa adicional 31 · a confirmar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leyenda_a_confirmar')));
      await tester.pump();
      expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);
    });

    testWidgets('con una sola, en singular; sin ninguna, la leyenda no está',
        (tester) async {
      await _mostrarCuerpo(tester, plano: _fiesta(), resaltar: null);
      expect(find.text('A confirmar: 1 mesa adicional'), findsOneWidget);
      await _mostrarCuerpo(
        tester,
        plano: _fiesta(pagos: _pagos(gomez: 70000)),
        resaltar: null,
      );
      expect(find.byKey(const Key('leyenda_a_confirmar')), findsNothing);
    });
  });

  group('la pantalla del plano entera', () {
    Future<MundoDelPlano> abrir(
      WidgetTester tester, {
      Map<String, List<Map<String, dynamic>>>? pagos,
      bool esJefe = true,
      ConfigPlano config = ConfigPlano.vacia,
    }) =>
        montarPlanoDeLaFiesta(
          tester,
          evento: _evento,
          plano: _plano(config: config),
          alumnos: _alumnos(),
          pagos: pagos ?? _pagos(),
          esJefe: esJefe,
        );

    /// Busca a la familia y la elige: se abre su tarjeta.
    Future<void> elegir(WidgetTester tester, String id, String apellido) async {
      await tester.enterText(find.byKey(const Key('buscar')), apellido);
      await asentar(tester);
      await tester.tap(find.byKey(Key('resultado_$id')));
      await asentar(tester);
    }

    bool aConfirmar(WidgetTester tester, int mesa) => tester
        .widget<VistaPlano>(find.byType(VistaPlano))
        .estado
        .info(mesa)
        .aConfirmar;

    testWidgets('lee los pagos y dibuja la 9 a confirmar', (tester) async {
      await abrir(tester);
      expect(aConfirmar(tester, 9), isTrue);
      expect(aConfirmar(tester, 8), isFalse);
      expect(aConfirmar(tester, 26), isFalse);
    });

    testWidgets('si baja el pago de la otra PC, la mesa vuelve sola a la '
        'normalidad', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);

      mundo.contratos.pagos['gomez'] = [_pagoDeMesa(70000)];
      mundo.bajo({'pagos_contrato_alumno'});
      await asentar(tester);
      expect(aConfirmar(tester, 9), isFalse);
      expect(find.text('Mesa adicional 9 · a confirmar'), findsNothing);
      expect(find.byKey(const Key('sillas_mesa_9')), findsOneWidget);
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('COBRAR: el plano se cierra y devuelve a quién cobrarle; no '
        'guarda nada', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('cobrar_a_confirmar_9')));
      await asentar(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(mundo.cerrada, isTrue);
      expect(mundo.alCerrar, isA<CobrarDesdeElPlano>());
      expect((mundo.alCerrar! as CobrarDesdeElPlano).alumnoId, 'gomez');
      expect(find.text('La fiesta'), findsOneWidget);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
      expect(mundo.planos.guardados, isEmpty);
    });

    testWidgets('salir con la flecha no devuelve a nadie', (tester) async {
      final mundo = await abrir(tester);
      await tester.pageBack();
      await asentar(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(mundo.cerrada, isTrue);
      expect(mundo.alCerrar, isNull);
    });

    testWidgets('ANULAR: la familia deja la 9, que queda vacía, y la adicional '
        'se baja de su contrato por el camino de Editar alumno', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);

      // Antes de guardar, dice qué va a pasar. Sin pedir un motivo.
      expect(find.text('Anular la mesa 9 de GÓMEZ'), findsOneWidget);
      expect(find.textContaining('8, 9 → 8'), findsOneWidget);
      expect(find.byKey(const Key('motivo')), findsNothing);
      expect(mundo.contratos.asignaciones, isEmpty);
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);

      // 1. La mesa, con su renglón.
      expect(mundo.contratos.asignaciones, [
        {'gomez': '8'},
      ]);
      final renglon = mundo.contratos.movimientos.single;
      expect(renglon.tipo, TipoMovimientoMesas.mover);
      expect(renglon.motivo, 'Mesa adicional anulada');
      expect(renglon.antes, {'gomez': '8, 9'});
      expect(renglon.despues, {'gomez': '8'});
      // La puerta sigue al salón.
      expect(mundo.puerta.alDia, [_eventoId]);

      // 2. El contrato: una adicional menos, y la cuenta rehecha.
      final gomez = mundo.contratos.actualizados.single;
      expect(gomez.mesaExtraCantidad, 0);
      expect(gomez.mesaExtraPrecio, 0);
      expect(gomez.montoTotalPactado, 300000);
      expect(gomez.numeroMesa, '8', reason: 'la mesa no la escribe la ficha');
      expect(mundo.contratos.mandado.single.containsKey('numero_mesa'), isFalse);
      expect(mundo.contratos.recalculados, ['gomez']);
      expect(mundo.contratos.reconciliados, ['gomez']);

      // Antes de guardar se bajó lo último de la nube.
      expect(mundo.bajadas, 1);

      // Lo que se ve: la 9 vacía, y lo que pasó, sin DESHACER.
      expect(ocupantesDibujados(tester)[9], isEmpty);
      expect(ocupantesDibujados(tester)[8], ['gomez']);
      expect(aConfirmar(tester, 9), isFalse);
      expect(
        _dicho(tester),
        'GÓMEZ dejó la 9. La mesa adicional se bajó de su contrato.',
      );
      expect(find.byKey(const Key('aviso_del_pie_accion')), findsNothing);
      expect(find.text('Mesa adicional 9 · a confirmar'), findsNothing);
    });

    testWidgets('ANULAR y arrepentirse en el cartel no cambia nada',
        (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      await tester.tap(find.text('CANCELAR'));
      await asentar(tester);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
      expect(mundo.bajadas, 0);
      expect(aConfirmar(tester, 9), isTrue);
    });

    testWidgets('sin internet no se anula, y dice por qué', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      mundo.sinInternet();
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.textContaining('hace falta internet'), findsOneWidget);
      // No pregunta "¿seguir igual?": frena.
      expect(find.text('SEGUIR'), findsNothing);
      await tester.tap(find.text('ENTENDIDO'));
      await asentar(tester);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
      expect(aConfirmar(tester, 9), isTrue);
    });

    testWidgets('si no se puede bajar lo último de la nube, tampoco',
        (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      // La nube contesta por las mesas y por el plano, pero la bajada falla.
      mundo.sinBajada();
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);
      expect(find.textContaining('hace falta internet'), findsOneWidget);
      await tester.tap(find.text('ENTENDIDO'));
      await asentar(tester);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
    });

    testWidgets('si la pagaron en la otra PC mientras se confirmaba, no se '
        'anula: la mesa sigue siendo suya', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      // Lo que trae la bajada de antes de guardar.
      mundo.alBajar =
          () => mundo.contratos.pagos['gomez'] = [_pagoDeMesa(70000)];
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);

      expect(find.text('Ya no se puede'), findsOneWidget);
      expect(find.text('La mesa 9 ya no está a confirmar.'), findsOneWidget);
      await tester.tap(find.text('ENTENDIDO'));
      await asentar(tester);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
      expect(ocupantesDibujados(tester)[9], ['gomez']);
      expect(aConfirmar(tester, 9), isFalse, reason: 'ya está paga');
    });

    testWidgets('si entró una parte del pago, tampoco: con algo pagado esa '
        'noche no se anula', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      mundo.alBajar =
          () => mundo.contratos.pagos['gomez'] = [_pagoDeMesa(30000)];
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);
      expect(find.textContaining('esta noche no se anula'), findsOneWidget);
      await tester.tap(find.text('ENTENDIDO'));
      await asentar(tester);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
    });

    testWidgets('si la mesa se suelta y el contrato no se puede bajar, se dice '
        'qué falta, en rojo', (tester) async {
      final mundo = await abrir(tester);
      await elegir(tester, 'gomez', 'GÓMEZ');
      mundo.contratos.fallaAlActualizar = true;
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      await tester.tap(find.byKey(const Key('confirmar')));
      await asentar(tester);

      expect(mundo.contratos.asignaciones, [
        {'gomez': '8'},
      ]);
      expect(mundo.contratos.actualizados, isEmpty);
      expect(
        _dicho(tester),
        'GÓMEZ dejó la 9. Pero no se pudo bajar la mesa adicional de su '
        'contrato: bajala en Editar alumno.',
      );
      expect(find.byKey(const Key('aviso_del_pie_accion')), findsNothing);
    });

    testWidgets('con sillas que ya no entrarían, no suelta la mesa: lo dice '
        'antes de preguntar', (tester) async {
      final mundo = await montarPlanoDeLaFiesta(
        tester,
        evento: _evento,
        plano: _plano(),
        alumnos: [
          _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 3, mesas: [8, 9]),
        ],
        pagos: const {'gomez': []},
      );
      await elegir(tester, 'gomez', 'GÓMEZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
      await asentar(tester);
      expect(find.text('No se puede'), findsOneWidget);
      expect(find.textContaining('primero bajale las sillas'), findsOneWidget);
      expect(find.byKey(const Key('confirmar')), findsNothing);
      expect(mundo.contratos.asignaciones, isEmpty);
    });

    testWidgets('sin modo jefe: se ve "a confirmar", y ni se cobra ni se anula',
        (tester) async {
      final mundo = await abrir(tester, esJefe: false);
      expect(aConfirmar(tester, 9), isTrue);
      await elegir(tester, 'gomez', 'GÓMEZ');
      expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);
      expect(find.byKey(const Key('a_pagar_9')), findsNothing);
      expect(_prendido(tester, 'cobrar_a_confirmar_9'), isFalse);
      expect(_prendido(tester, 'anular_a_confirmar_9'), isFalse);
      await tester.tap(
        find.byKey(const Key('cobrar_a_confirmar_9')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const Key('anular_a_confirmar_9')),
        warnIfMissed: false,
      );
      await asentar(tester);
      expect(mundo.cerrada, isFalse);
      expect(mundo.contratos.asignaciones, isEmpty);
      expect(mundo.contratos.actualizados, isEmpty);
    });
  });
}

/// Dos colores que se ven distintos (no dos tonos pegados del mismo borde
/// suavizado).
bool _lejos(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db) > 24;
}
