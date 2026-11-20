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
}
