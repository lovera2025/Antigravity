// La caja de entregas del cierre de caja (pedido del usuario, 20-nov-2026): lo
// entregado sin cargo, por quién, con cada entrega y las anuladas. Puro: sin
// pantalla ni base. Lo que tiene que llegar y lo entregado sale de
// `ResumenPorPartes`, y si cada entrega sigue en pie, de `EstadoDeLaEntrega`.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/features/eventos/services/caja_de_entregas.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';
const _ana = 'c0000000-0000-4000-8000-00000000000a';
const _beto = 'c0000000-0000-4000-8000-00000000000b';
const _caro = 'c0000000-0000-4000-8000-00000000000c';

/// Con 2 acompañantes: 3 pulseras VIP y 5 generales.
ContratoAlumno _alumno(String id, String nombre, {bool baja = false, int mesa = 12}) =>
    ContratoAlumno(
      id: id,
      eventoId: _evento,
      nombreAlumno: baja ? '[BAJA] $nombre' : nombre,
      cantidadAcompanantes: 2,
      nombresAcompanantes: const ['MAMÁ', 'PAPÁ'],
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([mesa]),
      createdAt: DateTime(2026, 2, 1),
    );

final _a = _alumno(_ana, 'GÓMEZ, ANA');
final _b = _alumno(_beto, 'LÓPEZ, BETO', mesa: 13);
final _c = _alumno(_caro, 'PÉREZ, CARO', mesa: 14);

DateTime _h(int hora, [int minuto = 0]) => DateTime.utc(2026, 11, 20, hora, minuto);

var _n = 0;
String _id() => 'd0000000-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';

EntregaEntradas _entrega(
  String alumno,
  ParteEntrega parte,
  DateTime at, {
  required String quien,
  int? cantidad,
  List<TramoTalonario> tramos = const [],
  String nombre = 'MADRE, UNA',
  ParentescoRetiro parentesco = ParentescoRetiro.madre,
}) =>
    EntregaEntradas.entrega(
      id: _id(),
      contratoAlumnoId: alumno,
      eventoId: _evento,
      parte: parte,
      cantidad: cantidad ?? (parte == ParteEntrega.pulseras ? 3 : 5),
      tramos: tramos,
      menores10: 0,
      parentesco: parentesco,
      nombre: nombre,
      escribioEnPlanilla: true,
      hechoPor: quien,
      deviceId: 'tablet-1',
      ahora: at,
    );

EntregaEntradas _anulacion(String alumno, ParteEntrega parte, DateTime at,
        {String motivo = 'se anotaron mal los números'}) =>
    EntregaEntradas.anulacion(
      id: _id(),
      contratoAlumnoId: alumno,
      eventoId: _evento,
      parte: parte,
      cantidad: 0,
      motivo: motivo,
      hechoPor: 'Jefe',
      deviceId: 'pc-1',
      ahora: at,
    );

/// La fila de una entrega de las 8 juntas hecha con una 6.9.x.
EntradasRetiro _filaVieja(
  String alumno, {
  EstadoRetiro estado = EstadoRetiro.entregado,
  DateTime? entregadoAt,
  DateTime? anuladoAt,
  String entregadoPor = 'Marta',
}) {
  final entrego = entregadoAt ?? _h(10);
  return EntradasRetiro(
    id: UuidUtils.entradasRetiroId(alumno),
    contratoAlumnoId: alumno,
    estado: estado,
    vip: 3,
    generales: 5,
    tramos: const [TramoTalonario(1001, 1005)],
    menores10: 0,
    parentesco: ParentescoRetiro.padre,
    retiroNombre: 'PADRE, UNO',
    escribioEnPlanilla: true,
    entregadoPor: entregadoPor,
    entregadoAt: entrego,
    anuladoPor: anuladoAt == null ? null : 'Jefe',
    anuladoAt: anuladoAt,
    anuladoMotivo: anuladoAt == null ? null : 'se equivocó de familia',
    createdAt: entrego,
    updatedAt: anuladoAt ?? entrego,
  );
}

CajaDeEntregas _caja({
  List<ContratoAlumno>? alumnos,
  Map<String, EntradasRetiro> retiros = const {},
  List<EntregaEntradas> renglones = const [],
}) {
  final todos = alumnos ?? [_a, _b, _c];
  return CajaDeEntregas.de(
    alumnos: [for (final a in todos) if (!a.esBajaTemporal) a],
    todos: todos,
    retiros: retiros,
    renglones: renglones,
  );
}

PersonaDeLaCaja _de(CajaDeEntregas c, String quien) =>
    c.personas.firstWhere((p) => p.quien == quien);

void main() {
  test('sin entregas: nada por persona, y lo que tiene que llegar', () {
    final c = _caja();
    expect(c.sinEntregas, isTrue);
    expect(c.personas, isEmpty);
    expect(c.anuladas, 0);
    expect(c.resumen.pulserasTotales, 9);
    expect(c.resumen.generalesTotales, 15);
    expect(c.resumen.pulserasEntregadas, 0);
    expect(c.conUnaSolaParte, 0);
  });

  test('por quién entregó: cada uno con lo suyo, y los totales son los de la fiesta', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: 'Carla'),
      _entrega(_ana, ParteEntrega.generales, _h(11), quien: 'Carla',
          tramos: const [TramoTalonario(5001, 5005)]),
      _entrega(_beto, ParteEntrega.pulseras, _h(12), quien: 'Maxi'),
    ]);
    expect([for (final p in c.personas) p.quien], ['Carla', 'Maxi']);
    final carla = _de(c, 'Carla');
    expect(carla.pulseras, 3);
    expect(carla.generales, 5);
    expect(carla.familias, 1);
    expect(carla.ultima, _h(11));
    expect(carla.entregas, hasLength(2));
    expect(carla.entregas.last.numeros, 'del 5001 al 5005');
    expect(carla.entregas.first.numeros, '', reason: 'las pulseras no llevan número');
    expect(carla.entregas.first.quienRetiro, 'Madre · MADRE, UNA');
    final maxi = _de(c, 'Maxi');
    expect(maxi.pulseras, 3);
    expect(maxi.generales, 0);
    // Lo de las personas suma lo mismo que la cuenta de la fiesta.
    expect(carla.pulseras + maxi.pulseras, c.resumen.pulserasEntregadas);
    expect(carla.generales + maxi.generales, c.resumen.generalesEntregadas);
    expect(c.resumen.familiasConTodo, 1);
    expect(c.conUnaSolaParte, 1, reason: 'LÓPEZ tiene solo las pulseras');
    expect(c.todas.map((e) => e.cuando), [_h(10), _h(11), _h(12)]);
  });

  test('una anulación: la entrega queda tachada con quién y por qué, no cuenta, y la que '
      'se volvió a dar sí', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla',
          tramos: const [TramoTalonario(5001, 5005)]),
      _anulacion(_ana, ParteEntrega.generales, _h(10, 30)),
      _entrega(_ana, ParteEntrega.generales, _h(10, 41), quien: 'Carla',
          tramos: const [TramoTalonario(5101, 5105)]),
    ]);
    expect(c.anuladas, 1);
    expect([for (final p in c.personas) p.quien], ['Carla'],
        reason: 'el jefe anuló, no entregó: no es una fila');
    final carla = _de(c, 'Carla');
    expect(carla.generales, 5, reason: 'solo la que sigue en pie');
    expect(carla.anuladas, 1);
    final primera = carla.entregas.first;
    expect(primera.vigente, isFalse);
    expect(primera.anulada, isTrue);
    expect(primera.anuladaPor, 'Jefe');
    expect(primera.anuladaAt, _h(10, 30));
    expect(primera.motivoAnulacion, 'se anotaron mal los números');
    expect(carla.entregas.last.vigente, isTrue);
    expect(carla.entregas.last.numeros, 'del 5101 al 5105');
  });

  test('una entrega de las 8 juntas de la 6.9.x: una sola entrada, con las dos partes', () {
    final c = _caja(retiros: {_ana: _filaVieja(_ana)});
    final marta = _de(c, 'Marta');
    expect(marta.entregas, hasLength(1));
    final e = marta.entregas.single;
    expect(e.parte, isNull);
    expect(e.deLasOchoJuntas, isTrue);
    expect(e.cantidad, '3 + 5');
    expect(e.que, 'Pulseras y generales');
    expect(e.vigente, isTrue);
    expect(e.numeros, 'del 1001 al 1005');
    expect(marta.pulseras, 3);
    expect(marta.generales, 5);
    expect(c.resumen.familiasConTodo, 1);
  });

  test('la 6.9.x entregó las 8 y esta versión anuló las pulseras: salen las copias, sin '
      'repetir la fila', () {
    final fila = _filaVieja(_ana);
    final estado = EstadoDeLaEntrega.deAlumno(_a, retiro: fila, renglones: const []);
    final copias = EntregaPorPartes.copiasDeLaFila(
      alumno: _a,
      retiro: fila,
      estado: estado,
      deviceId: 'pc-1',
      ahora: _h(15),
    );
    final c = _caja(
      retiros: {_ana: fila},
      renglones: [...copias, _anulacion(_ana, ParteEntrega.pulseras, _h(15))],
    );
    final marta = _de(c, 'Marta');
    expect(marta.entregas, hasLength(2), reason: 'las dos copias, no la fila otra vez');
    expect(marta.entregas.every((e) => e.deLasOchoJuntas), isTrue);
    final pulseras = marta.entregas.firstWhere((e) => e.parte == ParteEntrega.pulseras);
    final generales = marta.entregas.firstWhere((e) => e.parte == ParteEntrega.generales);
    expect(pulseras.anulada, isTrue);
    expect(pulseras.vigente, isFalse);
    expect(generales.vigente, isTrue);
    expect(marta.pulseras, 0);
    expect(marta.generales, 5);
    expect(c.anuladas, 1);
  });

  test('una 6.9.x atrasada anuló las 8 sobre lo que dio esta versión: las dos partes '
      'anuladas, sin una entrada de más', () {
    final c = _caja(
      retiros: {
        _ana: _filaVieja(
          _ana,
          estado: EstadoRetiro.anulado,
          entregadoAt: _h(20, 2),
          anuladoAt: _h(20, 1),
          entregadoPor: 'Carla',
        ),
      },
      renglones: [
        _entrega(_ana, ParteEntrega.pulseras, _h(19, 2), quien: 'Carla'),
        _entrega(_ana, ParteEntrega.generales, _h(20, 2), quien: 'Carla'),
      ],
    );
    final carla = _de(c, 'Carla');
    expect(carla.entregas, hasLength(2), reason: 'la fila es el reflejo de las generales');
    expect(carla.entregas.every((e) => e.anulada && !e.vigente), isTrue);
    expect(carla.entregas.first.motivoAnulacion, 'se equivocó de familia');
    expect(carla.pulseras + carla.generales, 0);
    expect(c.anuladas, 1);
  });

  test('una 6.9.x anuló su propia entrega de las 8: la entrada queda anulada', () {
    final c = _caja(retiros: {
      _ana: _filaVieja(_ana, estado: EstadoRetiro.anulado, anuladoAt: _h(12)),
    });
    final e = _de(c, 'Marta').entregas.single;
    expect(e.anulada, isTrue);
    expect(e.vigente, isFalse);
    expect(e.anuladaPor, 'Jefe');
    expect(c.anuladas, 1);
  });

  test('lo entregado a quien hoy está de baja se ve, pero no cuenta en lo que tiene que '
      'llegar', () {
    final baja = _alumno(_caro, 'PÉREZ, CARO', baja: true, mesa: 14);
    final c = _caja(
      alumnos: [_a, _b, baja],
      renglones: [_entrega(_caro, ParteEntrega.pulseras, _h(10), quien: 'Carla')],
    );
    final e = _de(c, 'Carla').entregas.single;
    expect(e.familia, 'PÉREZ, CARO', reason: 'sin la marca de la baja');
    expect(c.resumen.pulserasTotales, 6, reason: 'sin la baja');
    expect(c.resumen.familias, 2);
  });

  test('quien no dejó su nombre va como "Sin nombre"', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: '  '),
    ]);
    expect([for (final p in c.personas) p.quien], ['Sin nombre']);
  });

  test('las generales sin número y otra persona con autorización', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla',
          nombre: 'TÍA ROSA', parentesco: ParentescoRetiro.otraPersona),
    ]);
    final e = _de(c, 'Carla').entregas.single;
    expect(e.numeros, 'sin número');
    expect(e.quienRetiro, startsWith('Otra persona · TÍA ROSA'));
  });

  // ── Los arreglos de la revisión independiente del 20-nov-2026 ──────────────

  group('la conciliación: lo de las filas, menos lo de las bajas, es la tarjeta de arriba', () {
    for (final (nombre, armar) in _escenarios()) {
      test(nombre, () => _concilia(armar()));
    }
  });

  group('la historia de cada parte termina en lo que dice el estado', () {
    for (final (nombre, datos) in _datosDeLosEscenarios()) {
      test(nombre, () {
        for (final a in [_a, _b, _c]) {
          final rs = EntregaEntradas.porAlumno(datos.renglones)[a.id] ?? const [];
          final f = datos.retiros[a.id];
          final h = HistoriaDeLaEntrega.de(retiro: f, renglones: rs);
          final est = EstadoDeLaEntrega.deAlumno(a, retiro: f, renglones: rs);
          for (final p in ParteEntrega.values) {
            final hist = h.parte(p), e = est.parte(p);
            if (hist.isEmpty) {
              expect(e.entregada || e.anulada, isFalse, reason: '${a.nombreAlumno} $p');
              continue;
            }
            final last = hist.last;
            expect(last.esEntrega, e.entregada, reason: '${a.nombreAlumno} $p');
            expect(last.deLaFila, e.deLaFila, reason: '${a.nombreAlumno} $p');
            expect(last.momento, e.entregada ? e.entregadaAt : e.anuladaAt,
                reason: '${a.nombreAlumno} $p');
          }
        }
      });
    }
  });

  test('1. una familia que recibió cada parte de otra persona cuenta una sola vez en el '
      'TOTAL de familias', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: 'Carla'),
      _entrega(_ana, ParteEntrega.generales, _h(11), quien: 'Maxi'),
      _entrega(_beto, ParteEntrega.pulseras, _h(12), quien: 'Maxi'),
    ]);
    expect(_de(c, 'Carla').familias, 1);
    expect(_de(c, 'Maxi').familias, 2);
    expect(c.familiasConAlgo, 2, reason: 'GÓMEZ está en las dos filas y es una sola');
    expect(c.familiasEnDosFilas, isTrue);
    expect(c.pulserasDeLasFilas, 6);
    expect(c.generalesDeLasFilas, 5);
    _concilia(c);
  });

  test('2. la 6.9.x dio las 8 y una tablet sin internet volvió a dar las pulseras: las '
      'generales siguen siendo de Marta', () {
    final c = _caja(
      retiros: {_ana: _filaVieja(_ana)},
      renglones: [_entrega(_ana, ParteEntrega.pulseras, _h(11), quien: 'Carla')],
    );
    final marta = _de(c, 'Marta');
    final e = marta.entregas.single;
    expect(e.parte, isNull);
    expect(e.partida, isTrue);
    expect(e.pulserasVigentes, isFalse);
    expect(e.generalesVigentes, isTrue);
    expect(e.lasPulseras!.reemplazadaAt, _h(11));
    expect(e.lasPulseras!.reemplazadaPor, 'Carla');
    expect(marta.pulseras, 0);
    expect(marta.generales, 5, reason: 'hoy daba 0: la entrada miraba solo las pulseras');
    expect(_de(c, 'Carla').pulseras, 3);
    final lineas = e.estado(ArTime.formatFechaHora);
    expect(lineas.first.texto, 'Padre · PADRE, UNO');
    expect(lineas.last.texto,
        'Pulseras VIP: NO CUENTA: se volvió a entregar el 20/11/2026 08:00 hs por Carla');
    _concilia(c);
  });

  test('2. la 6.9.x dio las 8 y otra tablet volvió a dar las generales: Marta no suma '
      'las generales dos veces', () {
    final c = _caja(
      retiros: {_ana: _filaVieja(_ana)},
      renglones: [_entrega(_ana, ParteEntrega.generales, _h(11), quien: 'Carla')],
    );
    expect(_de(c, 'Marta').pulseras, 3);
    expect(_de(c, 'Marta').generales, 0, reason: 'hoy daba 5: 10 generales para 5');
    expect(_de(c, 'Carla').generales, 5);
    _concilia(c);
  });

  test('2. una 6.9.x dio las 8 y esta versión anuló solo las pulseras: se tachan las '
      'pulseras y las generales siguen', () {
    final c = _caja(
      retiros: {_ana: _filaVieja(_ana, estado: EstadoRetiro.anulado, anuladoAt: _h(12))},
      renglones: [_anulacion(_ana, ParteEntrega.pulseras, _h(12))],
    );
    final e = _de(c, 'Marta').entregas.single;
    expect(e.partida, isTrue);
    expect(e.lasPulseras!.anulada, isTrue);
    expect(e.lasPulseras!.anuladaPor, 'Jefe');
    expect(e.lasPulseras!.motivoAnulacion, 'se anotaron mal los números');
    expect(e.generalesVigentes, isTrue);
    expect(_de(c, 'Marta').generales, 5);
    expect(c.anuladas, 1, reason: 'la fila es el reflejo del renglón');
    expect(c.anulacionesAnteriores, isEmpty);
    _concilia(c);
  });

  test('3. la 6.9.x anuló y después volvió a entregar las 8: la anulación se cuenta y se ve '
      'como de una entrega anterior', () {
    final c = _caja(retiros: {_ana: _filaVieja(_ana, entregadoAt: _h(14), anuladoAt: _h(12))});
    expect(c.anuladas, 1, reason: 'hoy daba 0');
    final x = c.anulacionesAnteriores.single;
    expect(x.cuando, _h(12));
    expect(x.por, 'Jefe');
    expect(x.motivo, 'se equivocó de familia');
    expect(x.familia, 'GÓMEZ, ANA');
    expect(x.texto, 'Anulación de una entrega anterior, por Jefe: se equivocó de familia');
    final e = _de(c, 'Marta').entregas.single;
    expect(e.vigente && !e.partida, isTrue);
    _concilia(c);
  });

  test('3. la anulación de la 6.9.x ya copiada a un renglón cuenta una vez, aunque la copia '
      'lleve la hora corrida', () {
    // La 6.9.x atrasada: entregó a las 15:00, otra anuló a las 14:00 (anotó antes).
    final fila = _filaVieja(_ana,
        estado: EstadoRetiro.anulado, entregadoAt: _h(15), anuladoAt: _h(14));
    final estado = EstadoDeLaEntrega.deAlumno(_a, retiro: fila, renglones: const []);
    final copias = EntregaPorPartes.copiasDeLaFila(
        alumno: _a, retiro: fila, estado: estado, deviceId: 'pc-1', ahora: _h(16));
    expect(copias.first.createdAt, _h(15).add(const Duration(milliseconds: 1)));
    expect(copias, hasLength(2), reason: 'una copia de la anulación por parte');
    final c = _caja(retiros: {_ana: fila}, renglones: copias);
    expect(c.anuladas, 1, reason: 'las dos copias son la misma anulación, y la fila también');
    expect(c.anulacionesAnteriores, isEmpty, reason: 'tumbó la entrega de la fila, que se ve');
    final e = _de(c, 'Marta').entregas.single;
    expect(e.anulada, isTrue);
    expect(e.anuladaPor, 'Jefe');
    _concilia(c);
  });

  test('3. las copias de la fila no la repiten aunque su hora haya cambiado', () {
    final vieja = _filaVieja(_ana, entregadoAt: _h(14, 59), anuladoAt: _h(15));
    final copias = EntregaPorPartes.copiasDeLaFila(
      alumno: _a,
      retiro: vieja,
      estado: EstadoDeLaEntrega.deAlumno(_a, retiro: vieja, renglones: const []),
      deviceId: 'pc-1',
      ahora: _h(16),
    );
    final fila = RetiroEntradas.anular(vieja,
        motivo: 'Solo las pulseras VIP con cena: se anotaron mal los números',
        quien: 'Jefe',
        ahora: _h(16));
    final c = _caja(
      retiros: {_ana: fila},
      renglones: [...copias, _anulacion(_ana, ParteEntrega.pulseras, _h(16))],
    );
    final marta = _de(c, 'Marta');
    expect(marta.entregas, hasLength(2));
    expect(marta.entregas.every((e) => e.parte != null), isTrue);
    expect(marta.pulseras, 0);
    expect(marta.generales, 5);
    expect(c.anuladas, 1);
    _concilia(c);
  });

  test('4. lo entregado a una familia hoy de baja va en las filas y el TOTAL, marcado, y '
      'una línea dice cuánto es', () {
    final baja = _alumno(_caro, 'PÉREZ, CARO', baja: true, mesa: 14);
    final c = _caja(
      alumnos: [_a, _b, baja],
      renglones: [
        _entrega(_caro, ParteEntrega.pulseras, _h(10), quien: 'Carla'),
        _entrega(_ana, ParteEntrega.pulseras, _h(10, 5), quien: 'Carla'),
        _entrega(_ana, ParteEntrega.generales, _h(11), quien: 'Maxi'),
      ],
    );
    expect(_de(c, 'Carla').pulseras, 6);
    expect(c.pulserasDeLasFilas, 6);
    expect(c.resumen.pulserasEntregadas, 3);
    expect(c.pulserasDeBaja, 3);
    expect(c.familiasDeBaja, ['PÉREZ, CARO']);
    expect(_de(c, 'Carla').entregas.first.deBaja, isTrue);
    expect(c.textoDeLasBajas,
        'Incluye 3 pulseras de 1 familia hoy de baja (PÉREZ, CARO): arriba no cuentan.');
    _concilia(c);
  });

  test('5. una familia de 8 o más con cena no lleva generales: con las pulseras tiene todo, '
      'y "con una sola parte" nunca da negativo', () {
    final grande = ContratoAlumno(
      id: _ana,
      eventoId: _evento,
      nombreAlumno: 'GÓMEZ, ANA',
      cantidadAcompanantes: 7,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([12]),
      createdAt: DateTime(2026, 2, 1),
    );
    expect(RetiroEntradas.entradasDe(grande).generales, 0, reason: 'el caso de la revisión');
    final c = _caja(
      alumnos: [grande, _b, _c],
      renglones: [
        _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: 'Carla',
            cantidad: RetiroEntradas.entradasDe(grande).vip),
      ],
    );
    expect(c.resumen.familiasConTodo, 1);
    expect(c.conUnaSolaParte, 0, reason: 'hoy daba -1');
    _concilia(c);
  });

  test('7. dos tablets sin internet dieron las generales: la primera no cuenta y dice quién '
      'las volvió a dar', () {
    final c = _caja(renglones: [
      _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla',
          tramos: const [TramoTalonario(5001, 5005)]),
      _entrega(_ana, ParteEntrega.generales, _h(10, 5), quien: 'Sofi',
          tramos: const [TramoTalonario(5101, 5105)]),
    ]);
    final e = _de(c, 'Carla').entregas.single;
    expect(e.vigente, isFalse);
    expect(e.anulada, isFalse);
    expect(e.reemplazada, isTrue);
    expect(e.reemplazadaAt, _h(10, 5));
    expect(e.reemplazadaPor, 'Sofi');
    expect(e.numerosApagados, isTrue);
    final lineas = e.estado(ArTime.formatFechaHora);
    expect(lineas.map((l) => l.texto), [
      'Madre · MADRE, UNA',
      'NO CUENTA: se volvió a entregar el 20/11/2026 07:05 hs por Sofi',
    ], reason: 'quién retiró sigue a la vista: ese material salió');
    expect(lineas.first.tono, TonoDeLaLinea.apagado);
    expect(lineas.last.tono, TonoDeLaLinea.noCuenta);
    expect(_de(c, 'Carla').sinEfecto, 1);
    expect(_de(c, 'Carla').generales, 0);
    expect(_de(c, 'Sofi').generales, 5);
    expect(c.anuladas, 0);
    _concilia(c);
  });

  test('7. una PC sin actualizar volvió a dar las 8 sobre lo de esta versión: lo de antes dice '
      'que se volvió a entregar, por Marta', () {
    final c = _caja(
      retiros: {_ana: _filaVieja(_ana, entregadoAt: _h(14, 59), anuladoAt: _h(15))},
      renglones: [
        _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: 'Carla'),
        _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla'),
        _anulacion(_ana, ParteEntrega.pulseras, _h(15)),
      ],
    );
    final carla = _de(c, 'Carla');
    final p = carla.entregas.firstWhere((e) => e.parte == ParteEntrega.pulseras);
    final g = carla.entregas.firstWhere((e) => e.parte == ParteEntrega.generales);
    expect(p.anulada, isTrue);
    expect(p.anuladaAt, _h(15));
    expect(g.reemplazada, isTrue);
    expect(g.reemplazadaPor, 'Marta');
    expect(_de(c, 'Marta').entregas.single.vigente, isTrue);
    expect(c.anuladas, 1);
    _concilia(c);
  });
}

/// Lo de las filas, menos lo de las familias hoy de baja, es lo de la tarjeta de
/// arriba (`ResumenPorPartes`): las pulseras, las generales y las familias.
void _concilia(CajaDeEntregas c) {
  expect(c.pulserasDeLasFilas - c.pulserasDeBaja, c.resumen.pulserasEntregadas,
      reason: 'pulseras');
  expect(c.generalesDeLasFilas - c.generalesDeBaja, c.resumen.generalesEntregadas,
      reason: 'generales');
  expect(c.familiasConAlgo - c.familiasDeBaja.length,
      c.resumen.familiasConTodo + c.resumen.familiasConUnaSolaParte,
      reason: 'familias');
  expect(c.conUnaSolaParte, greaterThanOrEqualTo(0));
}

typedef _Datos = ({Map<String, EntradasRetiro> retiros, List<EntregaEntradas> renglones});

/// Los casos de la fila, los relojes y los equipos sin internet (los de
/// `test/entrega_por_partes_test.dart`, traducidos), sin bajas.
List<(String, _Datos)> _datosDeLosEscenarios() => [
      ('nada entregado', (retiros: const {}, renglones: const [])),
      ('las 8 juntas de la 6.9.x', (retiros: {_ana: _filaVieja(_ana)}, renglones: const [])),
      (
        'la fila anulada sola',
        (
          retiros: {_ana: _filaVieja(_ana, estado: EstadoRetiro.anulado, anuladoAt: _h(12))},
          renglones: const [],
        )
      ),
      (
        'la 6.9.x anuló las 8 sobre lo de esta versión',
        (
          retiros: {
            _ana: _filaVieja(_ana,
                estado: EstadoRetiro.anulado, entregadoAt: _h(13), anuladoAt: _h(14))
          },
          renglones: [
            _entrega(_ana, ParteEntrega.pulseras, _h(11), quien: 'Carla'),
            _entrega(_ana, ParteEntrega.generales, _h(15), quien: 'Carla'),
          ],
        )
      ),
      (
        'la 6.9.x volvió a entregar todo junto',
        (
          retiros: {_ana: _filaVieja(_ana, entregadoAt: _h(16), anuladoAt: _h(14))},
          renglones: [_entrega(_ana, ParteEntrega.pulseras, _h(11), quien: 'Carla')],
        )
      ),
      (
        'relojes: anulada a las 11 y entregada a las 12',
        (
          retiros: {
            _ana: _filaVieja(_ana,
                estado: EstadoRetiro.anulado, entregadoAt: _h(12), anuladoAt: _h(11))
          },
          renglones: const [],
        )
      ),
      (
        'tablet adelantada y 6.9.x atrasada',
        (
          retiros: {
            _ana: _filaVieja(_ana,
                estado: EstadoRetiro.anulado,
                entregadoAt: _h(20, 2),
                anuladoAt: _h(20, 1),
                entregadoPor: 'Carla')
          },
          renglones: [
            _entrega(_ana, ParteEntrega.pulseras, _h(19, 2), quien: 'Carla'),
            _entrega(_ana, ParteEntrega.generales, _h(20, 2), quien: 'Carla'),
          ],
        )
      ),
      (
        'una 6.9.x atrasada volvió a dar las 8',
        (
          retiros: {_ana: _filaVieja(_ana, entregadoAt: _h(14, 59), anuladoAt: _h(15))},
          renglones: [
            _entrega(_ana, ParteEntrega.pulseras, _h(10), quien: 'Carla'),
            _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla'),
            _anulacion(_ana, ParteEntrega.pulseras, _h(15)),
          ],
        )
      ),
      (
        'la fila y una tablet sin internet con las dos partes',
        (
          retiros: {_ana: _filaVieja(_ana)},
          renglones: [
            _entrega(_ana, ParteEntrega.pulseras, _h(10, 30), quien: 'Carla'),
            _entrega(_ana, ParteEntrega.generales, _h(10, 40), quien: 'Carla'),
          ],
        )
      ),
      (
        'dos tablets y familias de a una parte',
        (
          retiros: const {},
          renglones: [
            _entrega(_ana, ParteEntrega.generales, _h(10), quien: 'Carla'),
            _entrega(_ana, ParteEntrega.generales, _h(10, 5), quien: 'Sofi'),
            _entrega(_beto, ParteEntrega.pulseras, _h(11), quien: 'Maxi'),
            _entrega(_caro, ParteEntrega.pulseras, _h(12), quien: 'Carla'),
            _anulacion(_caro, ParteEntrega.pulseras, _h(12, 30)),
          ],
        )
      ),
    ];

List<(String, CajaDeEntregas Function())> _escenarios() => [
      for (final (nombre, d) in _datosDeLosEscenarios())
        (nombre, () => _caja(retiros: d.retiros, renglones: d.renglones)),
      (
        'con una familia de baja',
        () => _caja(
              alumnos: [_a, _b, _alumno(_caro, 'PÉREZ, CARO', baja: true, mesa: 14)],
              retiros: {_caro: _filaVieja(_caro)},
              renglones: [
                _entrega(_caro, ParteEntrega.pulseras, _h(11), quien: 'Carla'),
                _entrega(_ana, ParteEntrega.pulseras, _h(11), quien: 'Carla'),
              ],
            )
      ),
    ];
