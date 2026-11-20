// La caja de entregas del cierre de caja (pedido del usuario, 20-nov-2026): lo
// entregado sin cargo, por quién, con cada entrega y las anuladas. Puro: sin
// pantalla ni base. Lo que tiene que llegar y lo entregado sale de
// `ResumenPorPartes`, y si cada entrega sigue en pie, de `EstadoDeLaEntrega`.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
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
}
