// Los números del talonario de las entradas (sección 5.4 del spec del 13-nov):
// son opcionales y se validan con las palabras de la entrega sin cargo. **Son
// dos talonarios** (20-nov): lo vendido es el de las anticipadas y lo entregado
// sin cargo, el de las generales de los alumnos. Cada uno se mira solo consigo
// mismo: un número no se repite entre dos ventas ni entre dos entregas, pero el
// mismo número en una venta y en una entrega no es un repetido.
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

  group('la venta mira solo lo vendido (el talonario de las anticipadas)', () {
    test('contra otra venta', () {
      final ocupados = NumerosDeEntradas.ocupadosDeLaVenta(
        [_venta('COMPRADORA, UNA', '200-201')],
        const [],
      );
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(201, 202)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        'El 201 ya se le dio a COMPRADORA, UNA (200 al 201).',
      );
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(202, 203)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        isNull,
      );
    });

    test('contra una venta anulada sin devolver: esos quedan anulados para siempre', () {
      final v = _venta('COMPRADORA, UNA', '200-201');
      final ocupados = NumerosDeEntradas.ocupadosDeLaVenta(
        [v],
        [_anulada(v, devueltas: false)],
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

    test('una venta anulada con las entradas devueltas libera sus números', () {
      final v = _venta('COMPRADORA, UNA', '200-201');
      final ocupados = NumerosDeEntradas.ocupadosDeLaVenta(
        [v],
        [_anulada(v, devueltas: true)],
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
      expect(NumerosDeEntradas.ocupadosDeLaVenta([sin], const []), isEmpty);
      expect(
        NumerosDeEntradas.ocupadosDeLaVenta([sin, propia], const [], salvo: propia.id),
        isEmpty,
      );
    });

    test('lo vendido a un mismo nombre va junto', () {
      final ocupados = NumerosDeEntradas.ocupadosDeLaVenta(
        [
          _venta('ALUMNO, UNO', '20-21'),
          _venta('ALUMNO, UNO', '30', cantidad: 1),
          _venta('OTRA, PERSONA', '40-41'),
        ],
        const [],
      );
      expect(ocupados, {
        'ALUMNO, UNO': const [TramoTalonario(20, 21), TramoTalonario(30, 30)],
        'OTRA, PERSONA': const [TramoTalonario(40, 41)],
      });
    });

    // Hasta la 6.9.2 los dos talonarios iban juntos y esta venta daba "El 1043
    // ya se le dio a ALUMNO, UNO". Cambió a propósito el 20-nov.
    test('un número ya entregado sin cargo no frena la venta: es otro talonario', () {
      final alumnos = [_alumno('a', 'ALUMNO, UNO')];
      final retiros = {'a': _entrega('a', const [TramoTalonario(1040, 1047)])};
      expect(
        RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: ''),
        isNotEmpty,
        reason: 'la entrega tiene sus números',
      );
      final ocupados = NumerosDeEntradas.ocupadosDeLaVenta(
        [_venta('OTRA, PERSONA', '40-41')],
        const [],
      );
      expect(ocupados.keys, ['OTRA, PERSONA'], reason: 'solo lo vendido');
      expect(
        NumerosDeEntradas.error(
          tramos: const [TramoTalonario(1043, 1044)],
          cantidad: 2,
          ocupados: ocupados,
        ),
        isNull,
      );
    });

    test('VENDER lo dice antes de confirmar, y una anulada con las entradas devueltas '
        'deja volver a vender su número', () {
      final config = ConfigEntradas.vacia(_fiesta, ahora: _ahora).conPrecios(
        valorEntrada: 10000,
        precioAnticipada: null,
        anticipadaHasta: null,
        descuentoLugaresPct: 50,
        recargoPct: 0,
        descuentoAMano: false,
      );
      final vendida = _venta('COMPRADORA, UNA', '200-201');
      PedidoDeEntradas pedido(List<AnulacionEntradas> anulaciones) =>
          PedidoDeEntradas.nuevo(
            config: config,
            hoyAr: DateTime.utc(2026, 11, 20, 12),
            ocupados: NumerosDeEntradas.ocupadosDeLaVenta([vendida], anulaciones),
          ).conComprador('OTRO, COMPRADOR').conSueltas(2);

      final p = pedido(const []);
      expect(p.falta, kTalonarioObligatorio,
          reason: 'desde el 22-nov-2026, sin números no se puede');
      expect(
        p.conTramos(const [TramoTalonario(201, 202)]).falta,
        'El 201 ya se le dio a COMPRADORA, UNA (200 al 201).',
      );
      expect(p.conTramos(const [TramoTalonario(202, 203)]).falta, isNull);

      final devuelta = pedido([_anulada(vendida, devueltas: true)]);
      expect(devuelta.conTramos(const [TramoTalonario(200, 201)]).falta, isNull);
      final sinDevolver = pedido([_anulada(vendida, devueltas: false)]);
      expect(
        sinDevolver.conTramos(const [TramoTalonario(200, 201)]).falta,
        'El 200 ya se le dio a COMPRADORA, UNA (venta anulada, sin devolver) '
        '(200 al 201).',
      );
    });
  });

  group('la entrega mira solo lo entregado (el talonario de las generales)', () {
    // Hasta la 6.9.2 la entrega tampoco dejaba dar un número vendido ("El 100
    // ya se le dio a COMPRADORA, UNA"). Cambió a propósito el 20-nov: lo vendido
    // es el talonario de las anticipadas.
    test('no repite uno ya entregado a otra familia, y sí deja dar uno vendido', () {
      final alumnos = [_alumno('a', 'ALUMNO, UNO'), _alumno('b', 'ALUMNO, DOS')];
      final retiros = {
        'a': _entrega('a', const [TramoTalonario(1, 7)]),
      };
      final vendida = _venta('COMPRADORA, UNA', '100-101');
      expect(NumerosDeEntradas.ocupadosDeLaVenta([vendida], const []), isNotEmpty);

      // Lo que la entrega de "b" tiene que mirar: lo de las otras familias.
      final ocupados = NumerosDeEntradas.ocupadosDeLaEntrega(
        RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: 'b'),
      );
      expect(ocupados, {
        'ALUMNO, UNO': const [TramoTalonario(1, 7)],
      });
      expect(
        RetiroEntradas.errorTramos(
          tramos: const [TramoTalonario(95, 101)],
          generales: 7,
          deOtros: ocupados,
        ),
        isNull,
        reason: 'el 100 vendido es de las anticipadas',
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

    test('es una copia, sin los nombres que no tienen números', () {
      final entregados = {
        'ALUMNO, UNO': [const TramoTalonario(1, 7)],
        'SIN, NUMEROS': <TramoTalonario>[],
      };
      final ocupados = NumerosDeEntradas.ocupadosDeLaEntrega(entregados);
      expect(ocupados.keys, ['ALUMNO, UNO']);
      ocupados['ALUMNO, UNO']!.add(const TramoTalonario(50, 50));
      expect(entregados['ALUMNO, UNO'], const [TramoTalonario(1, 7)],
          reason: 'lo que llega no se toca');
    });
  });

  // Revisión del 20-nov-2026: el número que VENDER propone no tenía test propio.
  group('el número que sigue al último que vendió la caja', () {
    /// La venta [n] de la caja [caja], con sus [numeros] ("1043-1044").
    VentaEntradas venta(int n, String? numeros, {String caja = 'caja', int cantidad = 2}) =>
        VentaEntradas.nueva(
          cajaEntradasId: caja,
          eventoId: _fiesta,
          numero: n,
          compradorNombre: 'COMPRADOR $n',
          renglones: [
            RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: cantidad),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 10000.0 * cantidad,
          numeros: numeros,
          ahora: _ahora,
        );

    test('sin ventas con número, no propone nada', () {
      expect(NumerosDeEntradas.siguienteDeLaCaja('caja', const [], const []), isNull);
      expect(
        NumerosDeEntradas.siguienteDeLaCaja('caja', [venta(1, null)], const []),
        isNull,
      );
    });

    test('el que sigue a la venta más nueva, aunque una vieja tenga números más altos',
        () {
      final ventas = [venta(1, '2000-2001'), venta(2, '1050-1051')];
      expect(NumerosDeEntradas.siguienteDeLaCaja('caja', ventas, const []), 1052);
    });

    test('una venta sin números se saltea: sigue a la anterior con números', () {
      final ventas = [venta(1, '1050-1051'), venta(2, null)];
      expect(NumerosDeEntradas.siguienteDeLaCaja('caja', ventas, const []), 1052);
    });

    test('la última anulada con las entradas devueltas se saltea: sus números '
        'volvieron al talonario', () {
      final ultima = venta(2, '1052-1053');
      final ventas = [venta(1, '1050-1051'), ultima];
      expect(
        NumerosDeEntradas.siguienteDeLaCaja(
          'caja',
          ventas,
          [_anulada(ultima, devueltas: true)],
        ),
        1052,
      );
    });

    test('la última anulada sin devolver cuenta: esos números ya no se usan', () {
      final ultima = venta(2, '1052-1053');
      final ventas = [venta(1, '1050-1051'), ultima];
      expect(
        NumerosDeEntradas.siguienteDeLaCaja(
          'caja',
          ventas,
          [_anulada(ultima, devueltas: false)],
        ),
        1054,
      );
    });

    test('con dos tramos, el mayor + 1', () {
      final ventas = [venta(1, '1043-1044,1100-1101', cantidad: 4)];
      expect(NumerosDeEntradas.siguienteDeLaCaja('caja', ventas, const []), 1102);
    });

    test('solo mira las ventas de esa caja', () {
      final ventas = [venta(1, '1050-1051'), venta(5, '3000-3001', caja: 'otra')];
      expect(NumerosDeEntradas.siguienteDeLaCaja('caja', ventas, const []), 1052);
      expect(NumerosDeEntradas.siguienteDeLaCaja('otra', ventas, const []), 3002);
    });
  });

  group('los que quedaron anotados dos veces', () {
    test('en dos ventas: avisa con los dos nombres', () {
      final repetidos = NumerosDeEntradas.repetidosDeLaVenta(
        [
          _venta('COMPRADORA, UNA', '1040-1043', cantidad: 4),
          _venta('OTRO, COMPRADOR', '1043-1044'),
          _venta('SIN, CRUCE', '2000-2001'),
        ],
        const [],
      );
      expect(repetidos, hasLength(1));
      expect(repetidos.single.numero, 1043);
      expect(repetidos.single.enEntregas, isFalse);
      expect(repetidos.single.texto,
          'El 1043 está en dos ventas (COMPRADORA, UNA y OTRO, COMPRADOR): revisar.');
    });

    // Hasta la 6.9.2 esto avisaba "El 5 está en una venta (…) y en una entrega
    // (…): revisar". Cambió a propósito el 20-nov: son dos talonarios.
    test('el mismo número en una venta y en una entrega no es un repetido', () {
      final alumnos = [_alumno('a', 'ALUMNO, UNO')];
      final retiros = {'a': _entrega('a', const [TramoTalonario(1, 7)])};
      expect(
        NumerosDeEntradas.repetidosDeLaVenta(
          [_venta('COMPRADORA, UNA', '5-6')],
          const [],
        ),
        isEmpty,
      );
      expect(
        NumerosDeEntradas.repetidosDeLaEntrega(
          RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: ''),
        ),
        isEmpty,
      );
    });

    test('dos ventas de la misma persona', () {
      final repetidos = NumerosDeEntradas.repetidosDeLaVenta(
        [
          _venta('COMPRADORA, UNA', '5-6'),
          _venta('COMPRADORA, UNA', '6-7'),
        ],
        const [],
      );
      expect(repetidos.single.texto,
          'El 6 está en dos ventas de COMPRADORA, UNA: revisar.');
    });

    test('una anulada con devolución no cuenta; una sin devolver, sí', () {
      final devuelta = _venta('COMPRADORA, UNA', '5-6');
      final sinDevolver = _venta('OTRO, COMPRADOR', '50-51');
      final repetidos = NumerosDeEntradas.repetidosDeLaVenta(
        [
          devuelta,
          sinDevolver,
          _venta('TERCERA, PERSONA', '5-6'),
          _venta('CUARTA, PERSONA', '51-52'),
        ],
        [
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
        NumerosDeEntradas.repetidosDeLaVenta(
          [_venta('A, A', '1-2'), _venta('B, B', '3-4')],
          const [],
        ),
        isEmpty,
      );
      final varios = NumerosDeEntradas.repetidosDeLaVenta(
        [
          _venta('A, A', '90-91'),
          _venta('B, B', '91-92'),
          _venta('C, C', '10-11'),
          _venta('D, D', '11-12'),
        ],
        const [],
      );
      expect([for (final r in varios) r.numero], [11, 91]);
    });

    // Hasta la 6.9.2 dos entregas sin internet con los mismos números no se
    // avisaban nunca.
    test('en dos entregas: avisa con los dos nombres', () {
      final alumnos = [
        _alumno('a', 'ALUMNO, UNO'),
        _alumno('b', 'ALUMNO, DOS'),
        _alumno('c', 'ALUMNO, TRES'),
      ];
      final retiros = {
        'a': _entrega('a', const [TramoTalonario(1, 7)]),
        'b': _entrega('b', const [TramoTalonario(5, 11)]),
        'c': _entrega('c', const [TramoTalonario(20, 26)]),
      };
      final repetidos = NumerosDeEntradas.repetidosDeLaEntrega(
        RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: ''),
      );
      expect(repetidos, hasLength(1));
      expect(repetidos.single.numero, 5);
      expect(repetidos.single.enEntregas, isTrue);
      expect(repetidos.single.texto,
          'El 5 está en dos entregas (ALUMNO, UNO y ALUMNO, DOS): revisar.');
    });

    test('dos entregas a alumnos del mismo nombre también se avisan', () {
      final alumnos = [_alumno('a', 'GÓMEZ, ANA'), _alumno('b', 'GÓMEZ, ANA')];
      final retiros = {
        'a': _entrega('a', const [TramoTalonario(1, 7)]),
        'b': _entrega('b', const [TramoTalonario(3, 9)]),
      };
      final repetidos = NumerosDeEntradas.repetidosDeLaEntrega(
        RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: ''),
      );
      expect([for (final r in repetidos) r.texto],
          ['El 3 está en dos entregas de GÓMEZ, ANA: revisar.']);
    });

    test('entregas sin cruces no avisan, y van del número más bajo al más alto', () {
      expect(
        NumerosDeEntradas.repetidosDeLaEntrega({
          'A, A': const [TramoTalonario(1, 7), TramoTalonario(20, 21)],
          'B, B': const [TramoTalonario(8, 14)],
          'SIN, NUMEROS': const [],
        }),
        isEmpty,
      );
      final varios = NumerosDeEntradas.repetidosDeLaEntrega({
        'A, A': const [TramoTalonario(90, 96)],
        'B, B': const [TramoTalonario(96, 102)],
        'C, C': const [TramoTalonario(10, 16)],
        'D, D': const [TramoTalonario(16, 22)],
      });
      expect([for (final r in varios) r.numero], [16, 96]);
    });
  });
}
