// Los números del talonario de las entradas vendidas (sección 5.4 del spec del
// 13-nov): son opcionales, se validan con las palabras de la entrega sin cargo,
// y ninguno se repite entre lo entregado y lo vendido.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/cuentas/numeros_de_entradas.dart';
import 'package:arguello_events/features/entradas/cuentas/pedido_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 11, 20, 15);

/// Una venta de entradas sueltas con sus números ("1043-1044").
VentaEntradas _venta(String comprador, String? numeros, {int cantidad = 2}) =>
    VentaEntradas.nueva(
      cajaEntradasId: 'caja',
      eventoId: _fiesta,
      numero: 1,
      compradorNombre: comprador,
      renglones: [
        RenglonEntradas.suelta(
            nombre: 'Entrada', precioLista: 10000, cantidad: cantidad),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 10000.0 * cantidad,
      numeros: numeros,
      ahora: _ahora,
    );

AnulacionEntradas _anulada(VentaEntradas v, {required bool devueltas}) =>
    AnulacionEntradas.de(v, motivo: 'se equivocó', devueltas: devueltas, ahora: _ahora);

ContratoAlumno _alumno(String id, String nombre) => ContratoAlumno(
      id: id,
      eventoId: _fiesta,
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: '12',
      createdAt: DateTime(2026, 2, 1),
    );

/// La entrega sin cargo de [alumnoId], con sus números.
EntradasRetiro _entrega(String alumnoId, List<TramoTalonario> tramos) =>
    EntradasRetiro(
      id: 'r-$alumnoId',
      contratoAlumnoId: alumnoId,
      estado: EstadoRetiro.entregado,
      vip: 1,
      generales: tramos.fold(0, (s, t) => s + t.cantidad),
      tramos: tramos,
      createdAt: _ahora,
      updatedAt: _ahora,
    );

void main() {
  group('lo que se escribe', () {
    test('sin números está bien: son opcionales', () {
      expect(NumerosDeEntradas.error(tramos: const [], cantidad: 5), isNull);
      expect(NumerosDeEntradas.error(tramos: const [], cantidad: 0), isNull);
    });

    test('tienen que ser tantos como entradas lleva la venta', () {
      expect(
        NumerosDeEntradas.error(tramos: const [TramoTalonario(1, 3)], cantidad: 2),
        'Son 3 números y la venta lleva 2 entradas.',
      );
      expect(
        NumerosDeEntradas.error(tramos: const [TramoTalonario(7, 7)], cantidad: 3),
        'Es 1 número y la venta lleva 3 entradas.',
      );
      expect(
        NumerosDeEntradas.error(tramos: const [TramoTalonario(1, 2)], cantidad: 1),
        'Son 2 números y la venta lleva 1 entrada.',
      );
      expect(
        NumerosDeEntradas.error(tramos: const [TramoTalonario(1, 2)], cantidad: 0),
        'La venta no lleva entradas: sacá los números.',
      );
      expect(
        NumerosDeEntradas.error(tramos: const [TramoTalonario(1, 2)], cantidad: 2),
        isNull,
      );
    });

    test('lo demás, con las reglas y las palabras de la entrega', () {
      String? deLaEntrega(List<TramoTalonario> tramos, int cantidad) =>
          RetiroEntradas.errorTramos(tramos: tramos, generales: cantidad);

      const alReves = [TramoTalonario(10, 5)];
      expect(NumerosDeEntradas.error(tramos: alReves, cantidad: 2),
          'El tramo 10 al 5 está al revés.');
      expect(NumerosDeEntradas.error(tramos: alReves, cantidad: 2),
          deLaEntrega(alReves, 2));

      const desdeCero = [TramoTalonario(0, 1)];
      expect(NumerosDeEntradas.error(tramos: desdeCero, cantidad: 2),
          'Los números del talonario empiezan en 1.');

      const pisados = [TramoTalonario(1, 3), TramoTalonario(3, 4)];
      expect(NumerosDeEntradas.error(tramos: pisados, cantidad: 5),
          'Los tramos 1 al 3 y 3 al 4 se pisan.');
      expect(NumerosDeEntradas.error(tramos: pisados, cantidad: 5),
          deLaEntrega(pisados, 5));
    });
  });

  group('no se repiten', () {
    test('contra una entrega sin cargo', () {
      final ocupados = NumerosDeEntradas.ocupados(
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(1040, 1047)],
        },
      );
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(1043, 1044)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        'El 1043 ya se le dio a ALUMNO, UNO (1040 al 1047).',
      );
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(1048, 1049)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        isNull,
      );
    });

    test('contra otra venta', () {
      final ocupados = NumerosDeEntradas.ocupados(
        ventas: [_venta('COMPRADORA, UNA', '200-201')],
      );
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(201, 202)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        'El 201 ya se le dio a COMPRADORA, UNA (200 al 201).',
      );
    });

    test('contra una venta anulada sin devolver: esos quedan anulados para siempre', () {
      final v = _venta('COMPRADORA, UNA', '200-201');
      final ocupados = NumerosDeEntradas.ocupados(
        ventas: [v],
        anulaciones: [_anulada(v, devueltas: false)],
      );
      expect(ocupados.keys.single, 'COMPRADORA, UNA (venta anulada, sin devolver)');
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(200, 200)],
          cantidad: 1,
          ocupados: ocupados,
        ),
        'El 200 ya se le dio a COMPRADORA, UNA (venta anulada, sin devolver) '
        '(200 al 201).',
      );
    });

    test('una venta anulada con las entradas devueltas los libera', () {
      final v = _venta('COMPRADORA, UNA', '200-201');
      final ocupados = NumerosDeEntradas.ocupados(
        ventas: [v],
        anulaciones: [_anulada(v, devueltas: true)],
      );
      expect(ocupados, isEmpty);
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(200, 201)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        isNull,
      );
    });

    test('una venta sin números no ocupa nada, y la propia no se mira', () {
      final sin = _venta('SIN, NUMEROS', null);
      final propia = _venta('COMPRADORA, UNA', '200-201');
      expect(NumerosDeEntradas.deLasVentas([sin], const []), isEmpty);
      expect(
        NumerosDeEntradas.ocupados(ventas: [sin, propia], salvoVenta: propia.id),
        isEmpty,
      );
    });

    test('lo de un mismo nombre va junto, entregado y vendido', () {
      final ocupados = NumerosDeEntradas.ocupados(
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(1, 8)],
        },
        ventas: [
          _venta('ALUMNO, UNO', '20-21'),
          _venta('ALUMNO, UNO', '30', cantidad: 1),
          _venta('OTRA, PERSONA', '40-41'),
        ],
      );
      expect(ocupados, {
        'ALUMNO, UNO': const [
          TramoTalonario(1, 8),
          TramoTalonario(20, 21),
          TramoTalonario(30, 30),
        ],
        'OTRA, PERSONA': const [TramoTalonario(40, 41)],
      });
    });

    test('la entrega sin cargo tampoco deja repetir uno vendido', () {
      final alumnos = [_alumno('a', 'ALUMNO, UNO'), _alumno('b', 'ALUMNO, DOS')];
      final retiros = {
        'a': _entrega('a', const [TramoTalonario(1, 7)]),
      };
      final vendida = _venta('COMPRADORA, UNA', '100-101');

      // Lo que la entrega de "b" tiene que mirar: lo de las otras familias
      // (como hoy) más lo vendido.
      final ocupados = NumerosDeEntradas.ocupados(
        entregados: RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: 'b'),
        ventas: [vendida],
      );
      expect(
        RetiroEntradas.errorTramos(
          tramos: const [TramoTalonario(95, 101)],
          generales: 7,
          deOtros: ocupados,
        ),
        'El 100 ya se le dio a COMPRADORA, UNA (100 al 101).',
      );
      expect(
        RetiroEntradas.errorTramos(
          tramos: const [TramoTalonario(5, 11)],
          generales: 7,
          deOtros: ocupados,
        ),
        'El 5 ya se le dio a ALUMNO, UNO (1 al 7).',
      );
      expect(
        RetiroEntradas.errorTramos(
          tramos: const [TramoTalonario(8, 14)],
          generales: 7,
          deOtros: ocupados,
        ),
        isNull,
      );
    });

    test('VENDER lo dice antes de confirmar', () {
      final config = ConfigEntradas.vacia(_fiesta, ahora: _ahora).conPrecios(
        valorEntrada: 10000,
        precioAnticipada: null,
        anticipadaHasta: null,
        descuentoLugaresPct: 50,
        recargoPct: 0,
        descuentoAMano: false,
      );
      final p = PedidoDeEntradas.nuevo(
        config: config,
        hoyAr: DateTime.utc(2026, 11, 20, 12),
        ocupados: NumerosDeEntradas.ocupados(
          ventas: [_venta('COMPRADORA, UNA', '200-201')],
        ),
      ).conComprador('OTRO, COMPRADOR').conSueltas(2);

      expect(p.falta, isNull, reason: 'sin números se puede');
      expect(
        p.conTramos(const [TramoTalonario(201, 202)]).falta,
        'El 201 ya se le dio a COMPRADORA, UNA (200 al 201).',
      );
      expect(p.conTramos(const [TramoTalonario(202, 203)]).falta, isNull);
    });
  });

  group('los que quedaron anotados dos veces', () {
    test('en dos ventas: avisa con los dos nombres', () {
      final repetidos = NumerosDeEntradas.repetidos(
        ventas: [
          _venta('COMPRADORA, UNA', '1040-1043', cantidad: 4),
          _venta('OTRO, COMPRADOR', '1043-1044'),
          _venta('SIN, CRUCE', '2000-2001'),
        ],
        anulaciones: const [],
      );
      expect(repetidos, hasLength(1));
      expect(repetidos.single.numero, 1043);
      expect(repetidos.single.texto,
          'El 1043 está en dos ventas (COMPRADORA, UNA y OTRO, COMPRADOR): revisar.');
    });

    test('en una venta y en una entrega', () {
      final repetidos = NumerosDeEntradas.repetidos(
        ventas: [_venta('COMPRADORA, UNA', '5-6')],
        anulaciones: const [],
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(1, 7)],
        },
      );
      expect(repetidos.single.conUnaEntrega, isTrue);
      expect(repetidos.single.texto,
          'El 5 está en una venta (COMPRADORA, UNA) y en una entrega (ALUMNO, UNO): revisar.');
    });

    test('dos ventas de la misma persona', () {
      final repetidos = NumerosDeEntradas.repetidos(
        ventas: [
          _venta('COMPRADORA, UNA', '5-6'),
          _venta('COMPRADORA, UNA', '6-7'),
        ],
        anulaciones: const [],
      );
      expect(repetidos.single.texto,
          'El 6 está en dos ventas de COMPRADORA, UNA: revisar.');
    });

    test('una anulada con devolución no cuenta; una sin devolver, sí', () {
      final devuelta = _venta('COMPRADORA, UNA', '5-6');
      final sinDevolver = _venta('OTRO, COMPRADOR', '50-51');
      final repetidos = NumerosDeEntradas.repetidos(
        ventas: [
          devuelta,
          sinDevolver,
          _venta('TERCERA, PERSONA', '5-6'),
          _venta('CUARTA, PERSONA', '51-52'),
        ],
        anulaciones: [
          _anulada(devuelta, devueltas: true),
          _anulada(sinDevolver, devueltas: false),
        ],
      );
      expect([for (final r in repetidos) r.texto], [
        'El 51 está en dos ventas (OTRO, COMPRADOR (venta anulada, sin devolver) '
            'y CUARTA, PERSONA): revisar.',
      ]);
    });

    test('sin cruces no avisa, y van del número más bajo al más alto', () {
      expect(
        NumerosDeEntradas.repetidos(
          ventas: [_venta('A, A', '1-2'), _venta('B, B', '3-4')],
          anulaciones: const [],
        ),
        isEmpty,
      );
      final varios = NumerosDeEntradas.repetidos(
        ventas: [
          _venta('A, A', '90-91'),
          _venta('B, B', '91-92'),
          _venta('C, C', '10-11'),
          _venta('D, D', '11-12'),
        ],
        anulaciones: const [],
      );
      expect([for (final r in varios) r.numero], [11, 91]);
    });
  });
}
