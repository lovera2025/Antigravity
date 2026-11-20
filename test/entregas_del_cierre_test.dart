// ENTREGAS SIN CARGO en Cierre de caja → ENTRADAS (pedido del usuario,
// 20-nov-2026): la caja de entregas por quién entregó, el detalle de cada una y
// IMPRIMIR. La cuenta es `CajaDeEntregas` (test/caja_de_entregas_test.dart); acá
// se mira la pantalla, con la caja en memoria y el papel que no abre nada.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/cierre_caja/providers/caja_de_entregas_provider.dart';
import 'package:arguello_events/features/cierre_caja/widgets/entregas_del_cierre.dart';
import 'package:arguello_events/features/eventos/services/caja_de_entregas.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';
import 'package:arguello_events/models/evento.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';
const _ana = 'c0000000-0000-4000-8000-00000000000a';
const _beto = 'c0000000-0000-4000-8000-00000000000b';

ContratoAlumno _alumno(String id, String nombre, int mesa) => ContratoAlumno(
      id: id,
      eventoId: _evento,
      nombreAlumno: nombre,
      cantidadAcompanantes: 2,
      nombresAcompanantes: const ['MAMÁ', 'PAPÁ'],
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([mesa]),
      createdAt: DateTime(2026, 2, 1),
    );

DateTime _h(int hora, [int minuto = 0]) => DateTime.utc(2026, 11, 20, hora, minuto);

var _n = 0;
String _id() => 'd0000000-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';

EntregaEntradas _entrega(String alumno, ParteEntrega parte, DateTime at, String quien,
        {List<TramoTalonario> tramos = const []}) =>
    EntregaEntradas.entrega(
      id: _id(),
      contratoAlumnoId: alumno,
      eventoId: _evento,
      parte: parte,
      cantidad: parte == ParteEntrega.pulseras ? 3 : 5,
      tramos: tramos,
      parentesco: ParentescoRetiro.madre,
      nombre: 'MARTA ACOSTA',
      escribioEnPlanilla: true,
      hechoPor: quien,
      deviceId: 'tablet-1',
      ahora: at,
    );

/// Carla dio las pulseras y las generales de GÓMEZ (las generales, dos veces:
/// el jefe anuló la primera). Maxi dio las pulseras de LÓPEZ.
CajaDeEntregas _noche() {
  final todos = [_alumno(_ana, 'GÓMEZ, ANA', 12), _alumno(_beto, 'LÓPEZ, BETO', 13)];
  return CajaDeEntregas.de(
    alumnos: todos,
    todos: todos,
    retiros: const {},
    renglones: [
      _entrega(_ana, ParteEntrega.pulseras, _h(13, 2), 'Carla'),
      _entrega(_ana, ParteEntrega.generales, _h(13, 4), 'Carla',
          tramos: const [TramoTalonario(5001, 5005)]),
      EntregaEntradas.anulacion(
        id: _id(),
        contratoAlumnoId: _ana,
        eventoId: _evento,
        parte: ParteEntrega.generales,
        cantidad: 0,
        motivo: 'se anotaron mal los números',
        hechoPor: 'Jefe',
        deviceId: 'pc-1',
        ahora: _h(13, 30),
      ),
      _entrega(_ana, ParteEntrega.generales, _h(13, 41), 'Carla',
          tramos: const [TramoTalonario(5101, 5105)]),
      _entrega(_beto, ParteEntrega.pulseras, _h(14), 'Maxi'),
    ],
  );
}

final _fiesta = Evento(
  id: _evento,
  clienteId: 'cliente-1',
  tipo: 'Egresados',
  fechaEvento: DateTime(2026, 12, 4),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
  nombreFestejado: 'TÉCNICA PINAROLI',
);

class _Impresiones {
  final pedidos = <String?>[];
}

Future<_Impresiones> _montar(
  WidgetTester tester, {
  CajaDeEntregas? caja,
  Size tamano = const Size(1100, 1400),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final impresiones = _Impresiones();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cajaDeEntregasDeLaFiestaProvider.overrideWith((ref, id) async => caja ?? _noche()),
      imprimirEntregasSinCargoProvider.overrideWithValue(
        (c, {required fiesta, fechaFiesta, soloDe}) async => impresiones.pedidos.add(soloDe),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: EntregasDelCierre(fiesta: _fiesta, isDark: false),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return impresiones;
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

void main() {
  testWidgets('arriba lo que se dio de lo que tiene que llegar, y una fila por quién '
      'entregó con el total', (tester) async {
    await _montar(tester);
    expect(_texto(tester, 'cierre_entregas_pulseras_valor'), '6 de 6');
    expect(_texto(tester, 'cierre_entregas_generales_valor'), '5 de 10');
    expect(_texto(tester, 'cierre_entregas_familias_valor'), '1 de 2');
    expect(_texto(tester, 'cierre_entregas_anuladas_valor'), '1');
    expect(find.byKey(const Key('cierre_entregas_persona_Carla')), findsOneWidget);
    expect(find.byKey(const Key('cierre_entregas_persona_Maxi')), findsOneWidget);
    expect(find.byKey(const Key('cierre_entregas_persona_Jefe')), findsNothing,
        reason: 'el jefe anuló: no es una fila de quien entregó');
    expect(_texto(tester, 'cierre_entregas_total_pulseras'), '6');
    expect(_texto(tester, 'cierre_entregas_total_generales'), '5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('abre con lo de la primera; tocar a otro muestra lo suyo', (tester) async {
    await _montar(tester);
    expect(_texto(tester, 'cierre_entregas_detalle_titulo'), 'Carla · lo que entregó');
    // Las 3 de Carla, en orden, con la anulada marcada.
    expect(find.byKey(const Key('cierre_entregas_renglon_2')), findsOneWidget);
    expect(find.textContaining('ANULADA el'), findsOneWidget);
    expect(find.textContaining('por Jefe: se anotaron mal los números'), findsOneWidget);
    expect(find.text('del 5101 al 5105'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cierre_entregas_persona_Maxi')));
    await tester.pumpAndSettle();
    expect(_texto(tester, 'cierre_entregas_detalle_titulo'), 'Maxi · lo que entregó');
    expect(find.text('LÓPEZ, BETO'), findsOneWidget);
    expect(find.textContaining('ANULADA el'), findsNothing);
  });

  testWidgets('IMPRIMIR saca todo; IMPRIMIR LO DE… solo lo de esa persona', (tester) async {
    final i = await _montar(tester);
    await tester.tap(find.byKey(const Key('cierre_entregas_imprimir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cierre_entregas_persona_Maxi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cierre_entregas_imprimir_persona')));
    await tester.pumpAndSettle();
    expect(i.pedidos, [null, 'Maxi']);
  });

  testWidgets('sin entregas lo dice, e IMPRIMIR sigue', (tester) async {
    await _montar(
      tester,
      caja: CajaDeEntregas.de(
        alumnos: [_alumno(_ana, 'GÓMEZ, ANA', 12)],
        todos: [_alumno(_ana, 'GÓMEZ, ANA', 12)],
        retiros: const {},
        renglones: const [],
      ),
    );
    expect(find.byKey(const Key('cierre_entregas_vacio')), findsOneWidget);
    expect(_texto(tester, 'cierre_entregas_pulseras_valor'), '0 de 3');
    expect(find.byKey(const Key('cierre_entregas_imprimir')), findsOneWidget);
  });

  testWidgets('en un celular: una debajo de la otra, sin salirse', (tester) async {
    await _montar(tester, tamano: const Size(360, 1800));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('cierre_entregas_persona_Maxi')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('LA ÚLTIMA'), findsNothing, reason: 'en el celular esa columna no va');
  });

  // ── Los arreglos de la revisión independiente del 20-nov-2026 ──────────────

  testWidgets('1. el TOTAL de familias cuenta una vez a la que recibió cada parte de otra '
      'persona, y lo aclara', (tester) async {
    final todos = [_alumno(_ana, 'GÓMEZ, ANA', 12), _alumno(_beto, 'LÓPEZ, BETO', 13)];
    await _montar(
      tester,
      caja: CajaDeEntregas.de(alumnos: todos, todos: todos, retiros: const {}, renglones: [
        _entrega(_ana, ParteEntrega.pulseras, _h(13), 'Carla'),
        _entrega(_ana, ParteEntrega.generales, _h(14), 'Maxi'),
        _entrega(_beto, ParteEntrega.pulseras, _h(15), 'Maxi'),
      ]),
    );
    expect(_texto(tester, 'cierre_entregas_total_familias'), '2', reason: 'la columna suma 3');
    expect(_texto(tester, 'cierre_entregas_total_pulseras'), '6');
    expect(_texto(tester, 'cierre_entregas_total_generales'), '5');
    expect(find.byKey(const Key('cierre_entregas_nota_familias')), findsOneWidget);
  });

  testWidgets('2. las 8 juntas con cada parte por su lado: se tacha solo lo que ya no cuenta y '
      'el total suma lo de la tarjeta', (tester) async {
    final todos = [_alumno(_ana, 'GÓMEZ, ANA', 12)];
    await _montar(
      tester,
      caja: CajaDeEntregas.de(
        alumnos: todos,
        todos: todos,
        retiros: {_ana: _filaDeLaVieja(entregadoAt: _h(10))},
        renglones: [_entrega(_ana, ParteEntrega.pulseras, _h(11), 'Carla')],
      ),
    );
    expect(_texto(tester, 'cierre_entregas_total_pulseras'), '3');
    expect(_texto(tester, 'cierre_entregas_total_generales'), '5', reason: 'hoy daba 0');
    await tester.tap(find.byKey(const Key('cierre_entregas_persona_Marta')));
    await tester.pumpAndSettle();
    expect(find.text('Pulseras VIP: NO CUENTA: se volvió a entregar el 20/11 08:00 por Carla'),
        findsOneWidget);
    final hojas = _hojas(tester, 'Pulseras y generales (las 8 juntas)');
    expect(hojas['Pulseras']?.decoration, TextDecoration.lineThrough);
    expect(hojas['generales']?.decoration, isNot(TextDecoration.lineThrough));
    final cant = _hojas(tester, '3 + 5');
    expect(cant['3']?.decoration, TextDecoration.lineThrough);
    expect(cant['5']?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('3. una anulación de una entrega anterior se cuenta y se ve aparte',
      (tester) async {
    final todos = [_alumno(_ana, 'GÓMEZ, ANA', 12)];
    await _montar(
      tester,
      caja: CajaDeEntregas.de(
        alumnos: todos,
        todos: todos,
        retiros: {_ana: _filaDeLaVieja(entregadoAt: _h(13, 20), anuladoAt: _h(13, 10))},
        renglones: const [],
      ),
    );
    expect(_texto(tester, 'cierre_entregas_anuladas_valor'), '1', reason: 'hoy daba 0');
    expect(find.byKey(const Key('cierre_entregas_anulaciones_anteriores')), findsOneWidget);
    expect(
      _texto(tester, 'cierre_entregas_anulacion_anterior_0'),
      '20/11 10:10 · GÓMEZ, ANA · Anulación de una entrega anterior, por Jefe: se equivocó de familia',
    );
  });

  testWidgets('4. lo de una familia hoy de baja va en el total, marcado, con la línea que lo '
      'dice', (tester) async {
    final ana = _alumno(_ana, 'GÓMEZ, ANA', 12);
    final baja = _alumno(_beto, '[BAJA] LÓPEZ, BETO', 13);
    await _montar(
      tester,
      caja: CajaDeEntregas.de(alumnos: [ana], todos: [ana, baja], retiros: const {}, renglones: [
        _entrega(_ana, ParteEntrega.pulseras, _h(13), 'Carla'),
        _entrega(_beto, ParteEntrega.pulseras, _h(13, 5), 'Carla'),
      ]),
    );
    expect(_texto(tester, 'cierre_entregas_pulseras_valor'), '3 de 3');
    expect(_texto(tester, 'cierre_entregas_total_pulseras'), '6');
    expect(_texto(tester, 'cierre_entregas_bajas'),
        'Incluye 3 pulseras de 1 familia hoy de baja (LÓPEZ, BETO): arriba no cuentan.');
    expect(find.textContaining('hoy de baja', findRichText: true), findsWidgets);
  });

  testWidgets('7. una entrega que se volvió a dar sin anularla dice que no cuenta y por qué, y '
      'sigue diciendo quién la retiró', (tester) async {
    final todos = [_alumno(_ana, 'GÓMEZ, ANA', 12)];
    await _montar(
      tester,
      caja: CajaDeEntregas.de(alumnos: todos, todos: todos, retiros: const {}, renglones: [
        _entrega(_ana, ParteEntrega.generales, _h(13, 2), 'Carla',
            tramos: const [TramoTalonario(5001, 5005)]),
        _entrega(_ana, ParteEntrega.generales, _h(13, 7), 'Sofi',
            tramos: const [TramoTalonario(5101, 5105)]),
      ]),
    );
    expect(_texto(tester, 'cierre_entregas_detalle_titulo'), 'Carla · lo que entregó');
    expect(find.text('NO CUENTA: se volvió a entregar el 20/11 10:07 por Sofi'), findsOneWidget);
    expect(find.text('Madre · MARTA ACOSTA'), findsOneWidget,
        reason: 'ese material salió: el jefe tiene que saber quién lo tiene');
    expect(find.textContaining('ANULADA el'), findsNothing);
    expect(_texto(tester, 'cierre_entregas_total_generales'), '5');
  });
}

/// La fila de una entrega de las 8 juntas hecha con una 6.9.x, por Marta.
EntradasRetiro _filaDeLaVieja({required DateTime entregadoAt, DateTime? anuladoAt}) =>
    EntradasRetiro(
      id: 'f0000000-0000-4000-8000-00000000000a',
      contratoAlumnoId: _ana,
      estado: EstadoRetiro.entregado,
      vip: 3,
      generales: 5,
      tramos: const [TramoTalonario(1001, 1005)],
      menores10: 0,
      parentesco: ParentescoRetiro.padre,
      retiroNombre: 'PADRE, UNO',
      escribioEnPlanilla: true,
      entregadoPor: 'Marta',
      entregadoAt: entregadoAt,
      anuladoPor: anuladoAt == null ? null : 'Jefe',
      anuladoAt: anuladoAt,
      anuladoMotivo: anuladoAt == null ? null : 'se equivocó de familia',
      createdAt: entregadoAt,
      updatedAt: entregadoAt,
    );

/// Los pedazos de texto del `Text.rich` que dice [completo], con su estilo.
Map<String, TextStyle?> _hojas(WidgetTester tester, String completo) {
  final rich = tester
      .widgetList<RichText>(find.byType(RichText))
      .firstWhere((r) => r.text.toPlainText() == completo);
  final out = <String, TextStyle?>{};
  rich.text.visitChildren((s) {
    if (s is TextSpan && s.text != null) out[s.text!] = s.style;
    return true;
  });
  return out;
}
