// La entrega de entradas en dos partes (20-nov-2026), sin base ni pantalla: lo
// que le toca a cada familia, el estado de cada parte con los renglones de
// `entradas_entregas` y la fila de `entradas_retiro`, la cuenta de la fiesta, el
// grupo del filtro de VENDER y los números de las generales.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

/// Un alumno con la base de $300.000 en 9 cuotas, y lo que se le cargue encima
/// (el mismo de `retiro_entradas_test.dart`).
ContratoAlumno _alumno({
  String id = 'c0000000-0000-4000-8000-000000000001',
  String nombre = 'BENÍTEZ, JOAQUÍN',
  int extras = 0,
  int sillas = 0,
  List<String> acompanantes = const [],
  int? cantidadAcompanantes,
  List<int> mesas = const [12],
  double saldo = 0,
  int cuotasPagadas = 9,
}) {
  final mesaExtra = 70000.0 * extras;
  final sillasTotal = 8000.0 * sillas;
  return ContratoAlumno(
    id: id,
    eventoId: _evento,
    nombreAlumno: nombre,
    cantidadAcompanantes: cantidadAcompanantes ?? acompanantes.length,
    nombresAcompanantes: acompanantes,
    montoTotalPactado: 300000 + mesaExtra + sillasTotal,
    saldoDeudor: saldo,
    totalCuotas: 9,
    cuotasPagadas: cuotasPagadas,
    mesaExtraPrecio: mesaExtra,
    mesaExtraCantidad: extras,
    mesaExtraCuotas: 1,
    mesaExtraCuotasPagadas: extras > 0 ? 1 : 0,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: sillasTotal,
    sillasExtraCuotas: 1,
    sillasExtraCuotasPagadas: sillas > 0 ? 1 : 0,
    numeroMesa:
        mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    createdAt: DateTime(2026, 2, 1),
  );
}

Map<String, dynamic> _pago(double monto, String concepto) => {
      'monto': monto,
      'monto_gross': monto,
      'concepto': concepto,
      'anulado': 0,
      'fecha_pago': '2026-08-10',
    };

/// Pagos que cubren todo lo que se le cargó a [a].
List<Map<String, dynamic>> _pagosCompletos(ContratoAlumno a) => [
      _pago(300000, 'Cuota Base (9/9)'),
      if (a.mesaExtraPrecio > 0) _pago(a.mesaExtraPrecio, 'Mesa Extra 1'),
      if (a.sillasExtraPrecioTotal > 0) _pago(a.sillasExtraPrecioTotal, 'Sillas Extra'),
    ];

DeudaAlumno _deuda(ContratoAlumno a, List<Map<String, dynamic>> pagos) =>
    RetiroEntradas.deudaDe(
      a,
      pagos: pagos,
      moraCobradaHistorial: 0,
      ahoraAr: DateTime(2026, 11, 20),
    );

DateTime _h(int hora, [int minuto = 0]) => DateTime.utc(2026, 11, 20, hora, minuto);

var _n = 0;

/// Un id de renglón que ordena como se pide: el número va al final.
String _id([int? n]) =>
    'd0000000-0000-4000-8000-${(n ?? ++_n).toString().padLeft(12, '0')}';

EntregaEntradas _entrega(
  ParteEntrega parte,
  int cantidad,
  DateTime at, {
  ContratoAlumno? alumno,
  List<TramoTalonario> tramos = const [],
  String nombre = 'MADRE, UNA',
  ParentescoRetiro parentesco = ParentescoRetiro.madre,
  String hechoPor = 'Carla',
  int menores10 = 0,
  String? id,
}) =>
    EntregaEntradas.entrega(
      id: id ?? _id(),
      contratoAlumnoId: (alumno ?? _alumno()).id,
      eventoId: _evento,
      parte: parte,
      cantidad: cantidad,
      tramos: tramos,
      menores10: menores10,
      parentesco: parentesco,
      nombre: nombre,
      escribioEnPlanilla: true,
      hechoPor: hechoPor,
      deviceId: 'pc-1',
      ahora: at,
    );

EntregaEntradas _anulacion(
  ParteEntrega parte,
  DateTime at, {
  ContratoAlumno? alumno,
  int cantidad = 0,
  String motivo = 'se cargó mal',
  String? id,
}) =>
    EntregaEntradas.anulacion(
      id: id ?? _id(),
      contratoAlumnoId: (alumno ?? _alumno()).id,
      eventoId: _evento,
      parte: parte,
      cantidad: cantidad,
      motivo: motivo,
      hechoPor: 'Jefe',
      deviceId: 'pc-1',
      ahora: at,
    );

/// La fila de `entradas_retiro` de una entrega de las 8 juntas (la 6.9.x).
EntradasRetiro _filaVieja({
  ContratoAlumno? alumno,
  EstadoRetiro estado = EstadoRetiro.entregado,
  int vip = 3,
  int generales = 5,
  List<TramoTalonario> tramos = const [TramoTalonario(1043, 1047)],
  DateTime? entregadoAt,
  DateTime? anuladoAt,
  String nombre = 'PADRE, UNO',
}) {
  final a = alumno ?? _alumno();
  final entrego = entregadoAt ?? _h(10);
  return EntradasRetiro(
    id: UuidUtils.entradasRetiroId(a.id),
    contratoAlumnoId: a.id,
    estado: estado,
    vip: vip,
    generales: generales,
    tramos: tramos,
    menores10: 1,
    parentesco: ParentescoRetiro.padre,
    retiroNombre: nombre,
    escribioEnPlanilla: true,
    entregadoPor: 'Marta',
    entregadoAt: entrego,
    anuladoPor: anuladoAt == null ? null : 'Jefe',
    anuladoAt: anuladoAt,
    anuladoMotivo: anuladoAt == null ? null : 'se equivocó de familia',
    createdAt: entrego,
    updatedAt: anuladoAt ?? entrego,
  );
}

/// Con 2 acompañantes: 3 pulseras VIP y 5 generales.
final _dos = _alumno(acompanantes: ['MAMÁ', 'PAPÁ']);

EstadoDeLaEntrega _estado({
  ContratoAlumno? alumno,
  EntradasRetiro? retiro,
  List<EntregaEntradas> renglones = const [],
}) =>
    EstadoDeLaEntrega.deAlumno(
      alumno ?? _dos,
      retiro: retiro,
      renglones: renglones,
    );

void main() {
  group('lo que le toca: el egresado y sus acompañantes con cena, y las generales '
      'que completan 8', () {
    for (final (acompanantes, vip, generales) in [
      (<String>[], 1, 7),
      (['MAMÁ'], 2, 6),
      (['MAMÁ', 'PAPÁ'], 3, 5),
      // Más de 2: la entrega avisa que lo confirme el jefe, pero la cuenta es esta.
      (['MAMÁ', 'PAPÁ', 'TÍA'], 4, 4),
    ]) {
      test('con ${acompanantes.length} acompañantes: $vip VIP y $generales generales',
          () {
        final e = _estado(alumno: _alumno(acompanantes: acompanantes));
        expect(e.pulseras.leToca, vip);
        expect(e.generales.leToca, generales);
        expect(e.pulseras.falta, isTrue);
        expect(e.generales.falta, isTrue);
      });
    }

    test('acompañantes sin nombre: cuenta el mayor entre la cantidad y los nombres',
        () {
      final e = _estado(
        alumno: _alumno(acompanantes: ['MAMÁ'], cantidadAcompanantes: 2),
      );
      expect(e.pulseras.leToca, 3);
      expect(e.generales.leToca, 5);
    });

    test('más de 8 con cena y una mesa adicional: no hay generales, y la parte '
        'cuenta como hecha', () {
      final grande = _alumno(
        acompanantes: List.generate(9, (i) => 'ACOMPAÑANTE $i'),
        extras: 1,
        mesas: const [12, 13],
      );
      final entradas = RetiroEntradas.entradasDe(grande);
      expect(entradas.vip, 10);
      expect(entradas.generales, 0);
      // Los 2 de más ocupan lugares de la mesa adicional: bajan las de A PAGAR.
      expect(entradas.conDescuento, 6);
      final e = _estado(alumno: grande);
      expect(e.generales.leToca, 0);
      expect(e.generales.hecha, isTrue);
      expect(e.generales.entregada, isFalse);
      expect(e.todoEntregado, isFalse, reason: 'faltan las pulseras');
      final conPulseras = _estado(
        alumno: grande,
        renglones: [_entrega(ParteEntrega.pulseras, 10, _h(11), alumno: grande)],
      );
      expect(conPulseras.todoEntregado, isTrue);
    });

    test('no entran: más con cena que lugares', () {
      final noEntran = _alumno(acompanantes: List.generate(9, (i) => 'A $i'));
      expect(RetiroEntradas.entradasDe(noEntran).entran, isFalse);
      expect(
        EntregaPorPartes.grupoDe(
          noEntran,
          deuda: _deuda(noEntran, _pagosCompletos(noEntran)),
          estado: _estado(alumno: noEntran),
        ),
        GrupoDeRetiro.revisar,
      );
    });
  });

  group('el estado de cada parte: manda su última novedad', () {
    test('sin nada: las dos faltan', () {
      final e = _estado();
      expect(e.pulseras.entregada, isFalse);
      expect(e.generales.entregada, isFalse);
      expect(e.algoEntregado, isFalse);
      expect(e.todoEntregado, isFalse);
    });

    test('solo las pulseras: se ve quién, cuándo y quién lo anotó', () {
      final e = _estado(renglones: [
        _entrega(ParteEntrega.pulseras, 3, _h(11), menores10: 2),
      ]);
      expect(e.pulseras.entregada, isTrue);
      expect(e.pulseras.cantidad, 3);
      expect(e.pulseras.retiroNombre, 'MADRE, UNA');
      expect(e.pulseras.parentesco, ParentescoRetiro.madre);
      expect(e.pulseras.entregadaAt, _h(11));
      expect(e.pulseras.anotadoPor, 'Carla');
      expect(e.pulseras.menores10, 2);
      expect(e.pulseras.deLaFila, isFalse);
      expect(e.generales.falta, isTrue);
      expect(e.algoEntregado, isTrue);
      expect(e.todoEntregado, isFalse);
    });

    test('las dos partes, cada una un día: todo entregado', () {
      final e = _estado(renglones: [
        _entrega(ParteEntrega.generales, 5, _h(15),
            tramos: const [TramoTalonario(1, 5)], nombre: 'PADRE, UNO'),
        _entrega(ParteEntrega.pulseras, 3, _h(11)),
      ]);
      expect(e.todoEntregado, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(1, 5)]);
      expect(e.generales.retiroNombre, 'PADRE, UNO');
      expect(e.pulseras.retiroNombre, 'MADRE, UNA');
    });

    test('entregar, anular y volver a entregar: vale lo último', () {
      final entregada = _entrega(ParteEntrega.pulseras, 3, _h(11));
      final anulada = _anulacion(ParteEntrega.pulseras, _h(12), cantidad: 3);
      var e = _estado(renglones: [anulada, entregada]);
      expect(e.pulseras.entregada, isFalse);
      expect(e.pulseras.anulada, isTrue);
      expect(e.pulseras.anuladaPor, 'Jefe');
      expect(e.pulseras.motivoAnulacion, 'se cargó mal');
      e = _estado(renglones: [
        anulada,
        entregada,
        _entrega(ParteEntrega.pulseras, 3, _h(13), nombre: 'TÍA, OTRA'),
      ]);
      expect(e.pulseras.entregada, isTrue);
      expect(e.pulseras.retiroNombre, 'TÍA, OTRA');
    });

    test('a la misma hora, ordena por id: dos equipos lo ven igual', () {
      final antes = _anulacion(ParteEntrega.pulseras, _h(11), id: _id(100));
      final despues = _entrega(ParteEntrega.pulseras, 3, _h(11), id: _id(200));
      expect(_estado(renglones: [despues, antes]).pulseras.entregada, isTrue);
      expect(_estado(renglones: [antes, despues]).pulseras.entregada, isTrue);
    });

    test('la cuenta cambió después de entregar una parte', () {
      final e = _estado(renglones: [_entrega(ParteEntrega.pulseras, 2, _h(11))]);
      expect(e.pulseras.cambioLaCuenta, isTrue);
      expect(e.pulseras.leToca, 3);
    });

    test('un renglón que esta versión no conoce se ignora', () {
      final raro = EntregaEntradas.fromMap({
        ..._entrega(ParteEntrega.pulseras, 3, _h(11)).toMap(),
        'parte': 'vasos',
      });
      final e = _estado(renglones: [raro]);
      expect(e.pulseras.entregada, isFalse);
      expect(e.generales.entregada, isFalse);
    });
  });

  group('con la fila de entradas_retiro', () {
    test('una entrega vieja (las 8 juntas, de la 6.9.x) cuenta como las dos partes',
        () {
      final e = _estado(retiro: _filaVieja());
      expect(e.todoEntregado, isTrue);
      expect(e.pulseras.cantidad, 3);
      expect(e.generales.cantidad, 5);
      expect(e.generales.tramos, const [TramoTalonario(1043, 1047)]);
      expect(e.pulseras.tramos, isEmpty);
      expect(e.pulseras.retiroNombre, 'PADRE, UNO');
      expect(e.pulseras.anotadoPor, 'Marta');
      expect(e.pulseras.deLaFila, isTrue);
      expect(e.generales.deLaFila, isTrue);
    });

    test('una fila anulada sin renglones: nada entregado', () {
      final e = _estado(retiro: _filaVieja(
        estado: EstadoRetiro.anulado,
        anuladoAt: _h(12),
      ));
      expect(e.algoEntregado, isFalse);
      expect(e.pulseras.anulada, isTrue);
      expect(e.pulseras.motivoAnulacion, 'se equivocó de familia');
    });

    // La regla: si el jefe anuló desde una 6.9.x la fila completa, con la
    // anulación posterior a los renglones de una parte, esa parte queda sin
    // entregar. La que se entregó después de la anulación sigue entregada.
    test('el jefe anuló desde una 6.9.x: la parte entregada antes queda sin entregar',
        () {
      final pulseras = _entrega(ParteEntrega.pulseras, 3, _h(11));
      final generales = _entrega(ParteEntrega.generales, 5, _h(15));
      final anuladaEn69 = _filaVieja(
        estado: EstadoRetiro.anulado,
        entregadoAt: _h(13), // la 6.9.x había vuelto a entregar todo junto
        anuladoAt: _h(14),
      );
      final e = _estado(retiro: anuladaEn69, renglones: [pulseras, generales]);
      expect(e.pulseras.entregada, isFalse);
      expect(e.pulseras.anulada, isTrue);
      expect(e.pulseras.deLaFila, isTrue);
      expect(e.generales.entregada, isTrue, reason: 'se entregó después');
      expect(e.generales.deLaFila, isFalse);
    });

    test('y si después la 6.9.x volvió a entregar todo junto, están las dos', () {
      final e = _estado(
        retiro: _filaVieja(entregadoAt: _h(16), anuladoAt: _h(14), nombre: 'ABUELA, UNA'),
        renglones: [_entrega(ParteEntrega.pulseras, 3, _h(11))],
      );
      expect(e.todoEntregado, isTrue);
      expect(e.pulseras.retiroNombre, 'ABUELA, UNA', reason: 'lo último es la fila');
      expect(e.pulseras.deLaFila, isTrue);
    });

    test('la fila que escribe esta versión es el reflejo de su renglón: no cuenta',
        () {
      final pulseras = _entrega(ParteEntrega.pulseras, 3, _h(11));
      final generales =
          _entrega(ParteEntrega.generales, 5, _h(15), nombre: 'PADRE, UNO');
      final reflejo = EntregaPorPartes.filaCompleta(
        alumno: _dos,
        anterior: null,
        estado: _estado(renglones: [pulseras, generales]),
        ahora: _h(15, 1),
      )!;
      expect(reflejo.entregadoAt, _h(15));
      final e = _estado(retiro: reflejo, renglones: [pulseras, generales]);
      expect(e.todoEntregado, isTrue);
      expect(e.pulseras.deLaFila, isFalse);
      expect(e.pulseras.retiroNombre, 'MADRE, UNA',
          reason: 'quién se llevó las pulseras lo dice su renglón, no la fila');
      expect(e.generales.deLaFila, isFalse);
    });

    test('anular solo las generales con esta versión deja las pulseras entregadas',
        () {
      final pulseras = _entrega(ParteEntrega.pulseras, 3, _h(11));
      final generales = _entrega(ParteEntrega.generales, 5, _h(15));
      final completa = EntregaPorPartes.filaCompleta(
        alumno: _dos,
        anterior: null,
        estado: _estado(renglones: [pulseras, generales]),
        ahora: _h(15),
      )!;
      final anulada = RetiroEntradas.anular(
        completa,
        motivo: 'Solo las entradas generales: mal los números',
        quien: 'Jefe',
        ahora: _h(16),
      );
      final e = _estado(retiro: anulada, renglones: [
        pulseras,
        generales,
        _anulacion(ParteEntrega.generales, _h(16), cantidad: 5),
      ]);
      expect(e.pulseras.entregada, isTrue);
      expect(e.generales.entregada, isFalse);
      expect(e.generales.anulada, isTrue);
    });

    test('una entrega vieja con las pulseras anuladas por esta versión: las '
        'generales siguen entregadas por la fila', () {
      final e = _estado(
        retiro: _filaVieja(
          estado: EstadoRetiro.anulado,
          entregadoAt: _h(10),
          anuladoAt: _h(12),
        ),
        renglones: [_anulacion(ParteEntrega.pulseras, _h(12), cantidad: 3)],
      );
      expect(e.pulseras.entregada, isFalse);
      expect(e.generales.entregada, isTrue);
      expect(e.generales.deLaFila, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(1043, 1047)]);
    });

    test('relojes que no coinciden: lo último es lo que dice el estado de la fila',
        () {
      // Anulada en un equipo con el reloj atrasado: la hora de la anulación
      // quedó antes que la de la entrega.
      final e = _estado(retiro: _filaVieja(
        estado: EstadoRetiro.anulado,
        entregadoAt: _h(12),
        anuladoAt: _h(11),
      ));
      expect(e.algoEntregado, isFalse);
    });
  });

  group('las copias y la fila completa', () {
    test('las copias de una entrega vieja: un renglón por parte, con la hora y '
        'los datos de la fila, y el mismo id en cualquier equipo', () {
      final fila = _filaVieja();
      final estado = _estado(retiro: fila);
      final copias = EntregaPorPartes.copiasDeLaFila(
        alumno: _dos,
        retiro: fila,
        estado: estado,
        deviceId: 'tablet-1',
        ahora: _h(18),
      );
      expect(copias, hasLength(2));
      final pulseras = copias.firstWhere((c) => c.parte == ParteEntrega.pulseras);
      final generales = copias.firstWhere((c) => c.parte == ParteEntrega.generales);
      expect(pulseras.esEntrega, isTrue);
      expect(pulseras.cantidad, 3);
      expect(pulseras.tramos, isEmpty);
      expect(generales.cantidad, 5);
      expect(generales.tramos, const [TramoTalonario(1043, 1047)]);
      expect(generales.createdAt, _h(10));
      expect(generales.hechoPor, 'Marta');
      expect(generales.motivo, EntregaEntradas.kCopiaDeLaFila);
      final otraVez = EntregaPorPartes.copiasDeLaFila(
        alumno: _dos,
        retiro: fila,
        estado: estado,
        deviceId: 'pc-2',
        ahora: _h(19),
      );
      expect([for (final c in otraVez) c.id], [for (final c in copias) c.id]);
      // Con las copias, el estado es el mismo y ya no depende de la fila.
      final conCopias = _estado(retiro: fila, renglones: copias);
      expect(conCopias.todoEntregado, isTrue);
      expect(conCopias.pulseras.deLaFila, isFalse);
      expect(conCopias.generales.tramos, const [TramoTalonario(1043, 1047)]);
    });

    test('sin nada que dependa de la fila, no hay copias', () {
      final pulseras = _entrega(ParteEntrega.pulseras, 3, _h(11));
      expect(
        EntregaPorPartes.copiasDeLaFila(
          alumno: _dos,
          retiro: null,
          estado: _estado(renglones: [pulseras]),
          deviceId: 'pc-1',
          ahora: _h(12),
        ),
        isEmpty,
      );
    });

    test('la fila completa: lo que se llevó, quién retiró la última parte y su hora',
        () {
      final anterior = _filaVieja(
        estado: EstadoRetiro.anulado,
        entregadoAt: _h(8),
        anuladoAt: _h(9),
      );
      final pulseras = _entrega(ParteEntrega.pulseras, 3, _h(11), menores10: 2);
      final generales = _entrega(
        ParteEntrega.generales,
        5,
        _h(15),
        tramos: const [TramoTalonario(2001, 2005)],
        nombre: '  hermano   mayor ',
        parentesco: ParentescoRetiro.hermanoMayor,
        hechoPor: 'Sofi',
      );
      final fila = EntregaPorPartes.filaCompleta(
        alumno: _dos,
        anterior: anterior,
        estado: _estado(retiro: anterior, renglones: [pulseras, generales]),
        ahora: _h(15, 2),
      )!;
      expect(fila.id, UuidUtils.entradasRetiroId(_dos.id));
      expect(fila.entregado, isTrue);
      expect(fila.vip, 3);
      expect(fila.generales, 5);
      expect(fila.tramos, const [TramoTalonario(2001, 2005)]);
      expect(fila.menores10, 2);
      expect(fila.retiroNombre, 'HERMANO MAYOR');
      expect(fila.parentesco, ParentescoRetiro.hermanoMayor);
      expect(fila.entregadoPor, 'Sofi');
      expect(fila.entregadoAt, _h(15));
      expect(fila.updatedAt, _h(15, 2));
      // Conserva la anulación de antes y cuándo nació la fila.
      expect(fila.anuladoAt, _h(9));
      expect(fila.anuladoMotivo, 'se equivocó de familia');
      expect(fila.createdAt, anterior.createdAt);
      // Una 6.9.x la lee "Retiró", sin "cambió la cuenta".
      expect(
        RetiroEntradas.cambioLaCuenta(fila, RetiroEntradas.entradasDe(_dos)),
        isFalse,
      );
    });

    test('si falta una parte, no hay fila completa', () {
      expect(
        EntregaPorPartes.filaCompleta(
          alumno: _dos,
          anterior: null,
          estado: _estado(renglones: [_entrega(ParteEntrega.pulseras, 3, _h(11))]),
          ahora: _h(12),
        ),
        isNull,
      );
    });

    test('si la cuenta cambió entre una parte y la otra, la fila lleva lo que se '
        'llevó: la 6.9.x lo ve como "cambió la cuenta"', () {
      final fila = EntregaPorPartes.filaCompleta(
        alumno: _dos,
        anterior: null,
        estado: _estado(renglones: [
          _entrega(ParteEntrega.pulseras, 2, _h(11)),
          _entrega(ParteEntrega.generales, 5, _h(15)),
        ]),
        ahora: _h(15),
      )!;
      expect(fila.vip, 2);
      expect(fila.generales, 5);
      expect(
        RetiroEntradas.cambioLaCuenta(fila, RetiroEntradas.entradasDe(_dos)),
        isTrue,
      );
    });

    test('con 8 o más con cena, la fila completa sale con las pulseras solas', () {
      final grande = _alumno(
        acompanantes: List.generate(9, (i) => 'ACOMPAÑANTE $i'),
        extras: 1,
        mesas: const [12, 13],
      );
      final fila = EntregaPorPartes.filaCompleta(
        alumno: grande,
        anterior: null,
        estado: _estado(
          alumno: grande,
          renglones: [_entrega(ParteEntrega.pulseras, 10, _h(11), alumno: grande)],
        ),
        ahora: _h(11),
      )!;
      expect(fila.vip, 10);
      expect(fila.generales, 0);
      expect(fila.tramos, isEmpty);
    });
  });

  group('los números de las generales', () {
    final ana = _alumno(id: 'c0000000-0000-4000-8000-00000000000a', nombre: 'ANA');
    final beto = _alumno(id: 'c0000000-0000-4000-8000-00000000000b', nombre: 'BETO');
    final caro = _alumno(id: 'c0000000-0000-4000-8000-00000000000c', nombre: 'CARO');
    final dani = _alumno(id: 'c0000000-0000-4000-8000-00000000000d', nombre: 'DANI');

    test('los de la fila vieja y los de los renglones, sin los anulados ni los '
        'propios', () {
      final otros = EntregaPorPartes.numerosDeOtros(
        [ana, beto, caro, dani],
        {beto.id: _filaVieja(alumno: beto, tramos: const [TramoTalonario(100, 106)])},
        [
          _entrega(ParteEntrega.generales, 7, _h(11),
              alumno: caro, tramos: const [TramoTalonario(200, 206)]),
          // Las de DANI se anularon: sus números quedan libres.
          _entrega(ParteEntrega.generales, 7, _h(11),
              alumno: dani, tramos: const [TramoTalonario(300, 306)]),
          _anulacion(ParteEntrega.generales, _h(12), alumno: dani),
          // Las de ANA, que es quien recibe: no se cuentan.
          _entrega(ParteEntrega.generales, 7, _h(11),
              alumno: ana, tramos: const [TramoTalonario(400, 406)]),
          // Generales sin número: no ocupan nada.
          _entrega(ParteEntrega.pulseras, 1, _h(11), alumno: dani),
        ],
        salvo: ana.id,
      );
      expect(otros, {
        'BETO': const [TramoTalonario(100, 106)],
        'CARO': const [TramoTalonario(200, 206)],
      });
    });

    test('un alumno de baja sigue teniendo sus números, y dos con el mismo nombre '
        'los juntan', () {
      final mismoNombre =
          _alumno(id: 'c0000000-0000-4000-8000-00000000000e', nombre: 'CARO');
      final otros = EntregaPorPartes.numerosDeOtros(
        [ana, caro, mismoNombre],
        const {},
        [
          _entrega(ParteEntrega.generales, 7, _h(11),
              alumno: caro, tramos: const [TramoTalonario(200, 206)]),
          _entrega(ParteEntrega.generales, 7, _h(11),
              alumno: mismoNombre, tramos: const [TramoTalonario(500, 506)]),
        ],
        salvo: ana.id,
      );
      expect(otros['CARO'], const [TramoTalonario(200, 206), TramoTalonario(500, 506)]);
    });

    test('son opcionales; si se escriben, la cantidad justa y sin repetir', () {
      String? error(ParteEntrega p, List<TramoTalonario> t,
              [Map<String, List<TramoTalonario>> deOtros = const {}]) =>
          EntregaPorPartes.errorDeLosNumeros(
            parte: p,
            tramos: t,
            cantidad: 5,
            deOtros: deOtros,
          );
      expect(error(ParteEntrega.generales, const []), isNull);
      expect(error(ParteEntrega.generales, const [TramoTalonario(1, 5)]), isNull);
      expect(error(ParteEntrega.generales, const [TramoTalonario(1, 4)]),
          'Son 4 números y tiene que llevar 5 generales.');
      expect(
        error(ParteEntrega.generales, const [TramoTalonario(1, 5)], {
          'BETO': const [TramoTalonario(5, 9)],
        }),
        'El 5 ya se le dio a BETO (5 al 9).',
      );
      expect(error(ParteEntrega.pulseras, const []), isNull);
      expect(error(ParteEntrega.pulseras, const [TramoTalonario(1, 3)]),
          'Las pulseras van sin número: sacá los números.');
    });
  });

  group('la cuenta de la fiesta', () {
    test('cuántas pulseras y generales tienen que llegar, cuántas se entregaron y '
        'cuántas familias tienen todo', () {
      final solo = _alumno(id: 'c0000000-0000-4000-8000-000000000101', nombre: 'SOLO');
      final conDos = _alumno(
        id: 'c0000000-0000-4000-8000-000000000102',
        nombre: 'CON DOS',
        acompanantes: ['MAMÁ', 'PAPÁ'],
      );
      final conUno = _alumno(
        id: 'c0000000-0000-4000-8000-000000000103',
        nombre: 'CON UNO',
        acompanantes: ['MAMÁ'],
      );
      final viejo = _alumno(
        id: 'c0000000-0000-4000-8000-000000000104',
        nombre: 'VIEJO',
        acompanantes: ['MAMÁ', 'PAPÁ'],
      );
      final grande = _alumno(
        id: 'c0000000-0000-4000-8000-000000000105',
        nombre: 'GRANDE',
        acompanantes: List.generate(9, (i) => 'A $i'),
        extras: 1,
        mesas: const [20, 21],
      );
      final r = ResumenPorPartes.de(
        alumnos: [solo, conDos, conUno, viejo, grande],
        retiros: {viejo.id: _filaVieja(alumno: viejo)},
        renglones: [
          _entrega(ParteEntrega.pulseras, 3, _h(11), alumno: conDos),
          _entrega(ParteEntrega.pulseras, 2, _h(11), alumno: conUno),
          _entrega(ParteEntrega.generales, 6, _h(12), alumno: conUno),
          _entrega(ParteEntrega.pulseras, 10, _h(13), alumno: grande),
        ],
      );
      expect(r.familias, 5);
      expect(r.pulserasTotales, 1 + 3 + 2 + 3 + 10);
      expect(r.generalesTotales, 7 + 5 + 6 + 5 + 0);
      expect(r.pulserasEntregadas, 3 + 2 + 3 + 10);
      expect(r.generalesEntregadas, 6 + 5);
      expect(r.familiasConPulseras, 4);
      expect(r.familiasConGenerales, 2);
      expect(r.familiasConTodo, 3, reason: 'CON UNO, VIEJO y GRANDE');
    });
  });

  group('el grupo de cada alumno en el filtro de VENDER', () {
    GrupoDeRetiro grupo(
      ContratoAlumno a, {
      List<Map<String, dynamic>>? pagos,
      DeudaAlumno? deuda,
      List<EntregaEntradas> renglones = const [],
      EntradasRetiro? retiro,
    }) =>
        EntregaPorPartes.grupoDe(
          a,
          deuda: deuda ?? _deuda(a, pagos ?? _pagosCompletos(a)),
          estado: EstadoDeLaEntrega.deAlumno(a, retiro: retiro, renglones: renglones),
        );

    test('pagó todo y le falta algo: puede retirar', () {
      expect(grupo(_dos), GrupoDeRetiro.puedeRetirar);
      expect(
        grupo(_dos, renglones: [_entrega(ParteEntrega.pulseras, 3, _h(11))]),
        GrupoDeRetiro.puedeRetirar,
      );
    });

    test('debe una cuota: a caja', () {
      final debe = _alumno(saldo: 33333.33, cuotasPagadas: 8);
      expect(
        grupo(debe, pagos: [_pago(266666.67, 'Cuota Base (8/9)')]),
        GrupoDeRetiro.debe,
      );
    });

    test('debe solo mora: a caja', () {
      expect(
        grupo(_dos,
            deuda: const DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 4500)),
        GrupoDeRetiro.debe,
      );
    });

    test('debe un extra (la mesa adicional): a caja', () {
      final conMesa = _alumno(extras: 1, mesas: const [12, 13], saldo: 70000);
      expect(
        grupo(conMesa, pagos: [_pago(300000, 'Cuota Base (9/9)')]),
        GrupoDeRetiro.debe,
      );
    });

    test('la ficha dice que pagó y los pagos no: lo revisa el jefe', () {
      expect(grupo(_dos, pagos: const []), GrupoDeRetiro.revisar);
    });

    test('sin mesa o con las mesas que no coinciden: lo revisa el jefe', () {
      final sinMesa = _alumno(mesas: const []);
      expect(grupo(sinMesa), GrupoDeRetiro.revisar);
      final faltaMesa = _alumno(extras: 1, mesas: const [12]);
      expect(grupo(faltaMesa), GrupoDeRetiro.revisar);
    });

    test('con las dos partes: ya retiró, aunque hoy deba algo', () {
      final renglones = [
        _entrega(ParteEntrega.pulseras, 3, _h(11)),
        _entrega(ParteEntrega.generales, 5, _h(12)),
      ];
      expect(grupo(_dos, renglones: renglones), GrupoDeRetiro.yaRetiro);
      expect(
        grupo(_dos,
            renglones: renglones,
            deuda: const DeudaAlumno(saldoFicha: 0, saldoPagos: 0, mora: 4500)),
        GrupoDeRetiro.yaRetiro,
      );
      expect(grupo(_dos, retiro: _filaVieja()), GrupoDeRetiro.yaRetiro);
    });

    test('ninguno que debe cae en "puede retirar"', () {
      final casos = <(ContratoAlumno, List<Map<String, dynamic>>)>[
        (_alumno(saldo: 33333.33, cuotasPagadas: 8), [_pago(266666.67, 'Cuota Base (8/9)')]),
        (_alumno(extras: 1, mesas: const [12, 13], saldo: 70000),
            [_pago(300000, 'Cuota Base (9/9)')]),
        (_alumno(sillas: 2, saldo: 16000), [_pago(300000, 'Cuota Base (9/9)')]),
        (_dos, const []),
      ];
      for (final (a, pagos) in casos) {
        expect(grupo(a, pagos: pagos), isNot(GrupoDeRetiro.puedeRetirar),
            reason: '${a.nombreAlumno} ${a.saldoDeudor}');
      }
    });
  });
}
