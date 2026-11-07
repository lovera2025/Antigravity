import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';

/// Qué dice cada papel de la barra, renglón por renglón, como sale en los 32 lugares de
/// la TP-POS58. Incluida la venta anulada y el cierre.
const _evento = 'e0000000-0000-4000-8000-000000000001';

/// Cómo se vería en el papel: cada línea con sus renglones de 32.
List<String> _papel(List<LineaTicket> lineas) => [
      for (final l in lineas)
        ...switch (l) {
          LogoTicket() => ['[LOGO]'],
          TituloTicket() => ['[TITULO] ${l.texto}'],
          TextoTicket() => [l.texto],
          GrandeTicket() => [
              for (final r in renglonesGrandes(l.texto, soloAlto: l.soloAlto)) '[GRANDE] $r',
            ],
          RenglonTicket() => renglonesDe(l.izquierda, l.derecha),
          SeparadorTicket() => ['-' * 32],
          QrTicket() => ['[QR] ${l.dato}'],
        },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 23:41 en Argentina del 4-dic es 02:41 UTC del 5-dic.
  final vendida = DateTime.utc(2026, 12, 5, 2, 41);
  final caja = CajaBarra.abrir(
    eventoId: _evento,
    operadorNombre: 'Marta',
    numeroCaja: 2,
    cambioInicial: 20000,
    ahora: DateTime.utc(2026, 12, 5, 1),
  );

  VentaBarra venta({
    MedioBarra medio = MedioBarra.efectivo,
    double efectivo = 16000,
    double transferencia = 0,
    double? recibe = 20000,
  }) =>
      VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _evento,
        numero: 17,
        renglones: const [
          RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 2),
          RenglonVenta(productoId: 'b', nombre: 'Fernet con coca', precio: 6000, cantidad: 1),
          RenglonVenta(productoId: 'c', nombre: 'Agua', precio: 1000, cantidad: 3),
        ],
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        recibe: recibe,
        ahora: vendida,
      );

  test('la hora va en Argentina, sea cual sea la del equipo', () {
    expect(ModeloTicket.fechaYHora('2026-12-05T02:41:00.000Z'), '04/12/2026 - 23:41');
    expect(ModeloTicket.fechaYHora('2026-12-04T23:41:00-03:00'), '04/12/2026 - 23:41');
    expect(ModeloTicket.fechaYHora('basura'), '');
  });

  test('el ticket de una venta en efectivo, renglón por renglón', () {
    final v = venta();
    expect(_papel(ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo')), [
      '[TITULO] JUNIOR EVENTOS',
      'BARRA',
      'Puerto Viejo',
      '04/12/2026 - 23:41',
      'Caja 2 - Marta',
      '-' * 32,
      '2 x Cerveza lata         \$ 7.000',
      '1 x Fernet con coca      \$ 6.000',
      '3 x Agua                 \$ 3.000',
      '-' * 32,
      'TOTAL                   \$ 16.000',
      'Efectivo                \$ 16.000',
      'Recibe                  \$ 20.000',
      'Vuelto                   \$ 4.000',
      '-' * 32,
      'Caja 2 · N° 0017',
      '¡Gracias, salud!',
    ]);
    expect(ModeloTicket.deVenta(v, caja: caja, fiesta: 'x').whereType<QrTicket>(), isEmpty,
        reason: 'sin QR: nadie lo lee y son 3 cm de papel');
  });

  test('por transferencia no sale efectivo ni vuelto', () {
    final v = venta(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 16000, recibe: null);
    final papel = _papel(ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo'));
    expect(papel, contains('Transferencia           \$ 16.000'));
    expect(papel.where((r) => r.startsWith('Efectivo') || r.startsWith('Vuelto')), isEmpty);
  });

  test('un mixto dice las dos partes y el vuelto de lo que entregó', () {
    final v = venta(medio: MedioBarra.mixto, efectivo: 10000, transferencia: 6000, recibe: 10000);
    final papel = _papel(ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo'));
    expect(papel, containsAllInOrder([
      'TOTAL                   \$ 16.000',
      'Efectivo                \$ 10.000',
      'Transferencia            \$ 6.000',
      'Recibe                  \$ 10.000',
      'Vuelto                       \$ 0',
    ]));
  });

  test('con recargo por transferencia, el ticket lo dice aparte y suma lo cobrado', () {
    final v = VentaBarra.nueva(
      cajaBarraId: caja.id,
      eventoId: _evento,
      numero: 17,
      renglones: const [
        RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 2),
      ],
      medio: MedioBarra.transferencia,
      transferencia: 7350,
      recargo: 350,
      recargoPct: 5,
      ahora: vendida,
    );
    expect(
      _papel(ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo')),
      containsAllInOrder([
        'TOTAL                    \$ 7.000',
        'Recargo transf.            \$ 350',
        'COBRADO                  \$ 7.350',
        'Transferencia            \$ 7.350',
      ]),
    );
  });

  test('una venta anulada lo dice arriba y abajo, con el motivo, y no da las gracias', () {
    final v = venta();
    final a = AnulacionBarra.de(
      v,
      motivo: 'se cobró dos veces',
      hechoPor: 'Jefe',
      ahora: DateTime.utc(2026, 12, 5, 3),
    );
    final papel = _papel(ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo', anulacion: a));
    expect(papel.where((r) => r == '*** ANULADA ***'), hasLength(2));
    expect(papel.indexOf('*** ANULADA ***'), lessThan(papel.indexOf('TOTAL                   \$ 16.000')));
    expect(papel, contains('Motivo: se cobró dos veces'));
    expect(papel, contains('05/12/2026 - 00:00 - Jefe'));
    expect(papel, isNot(contains('¡Gracias, salud!')));
  });

  test('un nombre de fiesta largo se parte por palabras', () {
    final papel = _papel(ModeloTicket.deVenta(
      venta(),
      caja: caja,
      fiesta: 'Escuela Normal Superior Mariano Acosta Promoción 2026',
    ));
    expect(papel, containsAllInOrder(['Escuela Normal Superior Mariano', 'Acosta Promoción 2026']));
  });

  test('con logo, va primero', () {
    final logo = img.Image(width: 8, height: 8);
    expect(ModeloTicket.deVenta(venta(), caja: caja, fiesta: 'x', logo: logo).first, isA<LogoTicket>());
  });

  group('el vale', () {
    test('todo junto: un solo vale con todas las bebidas, sin logo, sin precios y sin QR', () {
      final v = venta();
      final lineas = ModeloTicket.deVale(Vale.todoJunto(v), venta: v, caja: caja, fiesta: 'Puerto Viejo');
      expect(_papel(lineas), [
        'PUERTO VIEJO',
        'Vie 04/12/2026 - 23:41',
        'Caja 2 · Marta · N° 0017',
        '[GRANDE] 2 CERVEZA LATA',
        '[GRANDE] 1 FERNET CON',
        '[GRANDE] COCA',
        '[GRANDE] 3 AGUA',
        'Vale solo hoy · una sola vez',
        'El barman se queda el vale',
      ]);
      expect(lineas.whereType<LogoTicket>(), isEmpty);
      expect(lineas.whereType<QrTicket>(), isEmpty);
      expect(_papel(lineas).where((r) => r.contains(r'$')), isEmpty, reason: 'sin precios');
    });

    test('por separado: "vale por" y la bebida en grande, y el número del vale en la venta', () {
      final v = venta();
      final vale = Vale.deUnaBebida(v.renglones.first, cantidad: 2, numero: 3);
      expect(_papel(ModeloTicket.deVale(vale, venta: v, caja: caja, fiesta: 'Puerto Viejo')), [
        'PUERTO VIEJO',
        'Vie 04/12/2026 - 23:41',
        'Caja 2 · Marta · N° 0017-3',
        '[GRANDE] VALE POR 2',
        '[GRANDE] CERVEZA LATA',
        'Vale solo hoy · una sola vez',
        'El barman se queda el vale',
      ]);
    });

    test('el de una silla de la noche: va a la recepcionista, no al barman', () {
      final v = VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _evento,
        numero: 17,
        renglones: const [
          RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 2),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 16000,
        ahora: vendida,
      );
      final vale = Vale.deUnaSilla(v.renglones.single, numero: 2);
      expect(vale.esDeSilla, isTrue);
      expect(_papel(ModeloTicket.deVale(vale, venta: v, caja: caja, fiesta: 'Puerto Viejo')), [
        'PUERTO VIEJO',
        'Vie 04/12/2026 - 23:41',
        'Caja 2 · Marta · N° 0017-2',
        '[GRANDE] VALE POR 1',
        '[GRANDE] SILLA EXTRA',
        'Llevá este vale a la',
        'recepcionista',
        'Ella suma la silla y se queda el',
        'vale',
      ]);
    });

    test('una copia lo dice en grande arriba y abajo, con quién, cuándo y por qué', () {
      final v = venta();
      final papel = _papel(ModeloTicket.deVale(
        Vale.todoJunto(v),
        venta: v,
        caja: caja,
        fiesta: 'Puerto Viejo',
        copia: const CopiaDeVale(
          numero: 1,
          createdAt: '2026-12-05T04:30:00.000Z',
          hechoPor: 'Jefe',
          motivo: 'se cortó el papel',
        ),
      ));
      expect(papel.first, '[GRANDE] *** COPIA ***');
      expect(papel.last, '[GRANDE] *** COPIA ***');
      expect(papel, containsAllInOrder(['Copia 1 - Jefe', '05/12/2026 - 01:30']));
      expect(papel, contains('Motivo: se cortó el papel'));
      expect(papel, contains('Se entrega solo con el jefe'));
      expect(papel, isNot(contains('Vale solo hoy · una sola vez')));
    });

    test('la copia ahorra papel igual que el vale: sin logo, sin QR, sin precios, en grande', () {
      final v = venta();
      final lineas = ModeloTicket.deVale(
        Vale.todoJunto(v),
        venta: v,
        caja: caja,
        fiesta: 'Puerto Viejo',
        copia: const CopiaDeVale(numero: 1, createdAt: '2026-12-05T04:30:00.000Z', motivo: 'x'),
      );
      expect(lineas.whereType<LogoTicket>(), isEmpty);
      expect(lineas.whereType<QrTicket>(), isEmpty);
      expect(lineas.whereType<RenglonTicket>(), isEmpty, reason: 'sin precios');
      expect(lineas.whereType<GrandeTicket>(), isNotEmpty);
    });

    test('sin cajera anotada, la caja y el número igual', () {
      final sinNombre = CajaBarra.abrir(eventoId: _evento, numeroCaja: 3, ahora: vendida);
      final v = venta();
      expect(
        _papel(ModeloTicket.deVale(Vale.todoJunto(v), venta: v, caja: sinNombre, fiesta: 'x')),
        contains('Caja 3 · N° 0017'),
      );
    });

    test('en la impresora: lo grande entra en 16 letras, lo demás en 32, y los acentos en la 850', () async {
      final perfil = await CapabilityProfile.load();
      final v = VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _evento,
        numero: 17,
        renglones: const [
          RenglonVenta(productoId: 'a', nombre: 'Champán Chandon Extra Brut', precio: 45000, cantidad: 2),
          RenglonVenta(productoId: 'b', nombre: 'Café', precio: 1000, cantidad: 1),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 91000,
        ahora: vendida,
      );
      final lineas = [
        ...ModeloTicket.deVale(Vale.todoJunto(v), venta: v, caja: caja, fiesta: 'Escuela Normal Promoción 2026'),
        ...ModeloTicket.deVale(
          Vale.deUnaBebida(v.renglones.first, cantidad: 1, numero: 12),
          venta: v,
          caja: caja,
          fiesta: 'Puerto Viejo',
        ),
      ];
      for (final r in _papel(lineas)) {
        if (r.startsWith('[GRANDE] ')) {
          expect(r.length - '[GRANDE] '.length, lessThanOrEqualTo(16), reason: r);
        } else {
          expect(r.length, lessThanOrEqualTo(32), reason: r);
        }
      }
      expect(_papel(lineas), containsAllInOrder([
        '[GRANDE] 2 CHAMPÁN',
        '[GRANDE] CHANDON EXTRA',
        '[GRANDE] BRUT',
      ]));
      final s = bytesComoTexto(TicketEscPos(perfil).armar(lineas));
      expect(s, contains('CAFÉ'));
      expect(s, contains('PROMOCIÓN'));
    });

    test('el día va en Argentina', () {
      expect(ModeloTicket.diaFechaYHora('2026-12-05T02:41:00.000Z'), 'Vie 04/12/2026 - 23:41');
      expect(ModeloTicket.diaFechaYHora('2026-12-05T12:00:00.000Z'), 'Sáb 05/12/2026 - 09:00');
      expect(ModeloTicket.diaFechaYHora('2026-12-07T02:59:00.000Z'), 'Dom 06/12/2026 - 23:59');
      expect(ModeloTicket.diaFechaYHora('basura'), '');
    });
  });

  group('el cierre', () {
    final ventas = [
      venta(),
      venta(medio: MedioBarra.transferencia, efectivo: 0, transferencia: 16000, recibe: null),
    ];

    test('cerrada: lo vendido, lo esperado, lo contado y la diferencia anotada', () {
      final anulada = venta(recibe: null);
      final todas = [...ventas, anulada];
      final anulaciones = [AnulacionBarra.de(anulada, motivo: 'error', ahora: vendida)];
      final cerrada = caja.cerrada(
        efectivoContado: 35500,
        diferencia: -500,
        nota: 'faltó un billete de quinientos',
        ahora: DateTime.utc(2026, 12, 5, 6, 30),
      );
      final papel = _papel(ModeloTicket.deCierre(
        cerrada,
        CierreDeBarra.de(cerrada, todas, anulaciones),
        fiesta: 'Puerto Viejo',
      ));
      expect(papel, [
        '[TITULO] JUNIOR EVENTOS',
        'CIERRE DE CAJA - BARRA',
        'Puerto Viejo',
        'Abrió 04/12/2026 - 22:00',
        'Caja 2 - Marta',
        'Cerró 05/12/2026 - 03:30',
        '-' * 32,
        // Lo vendido por producto, el que más salió primero; sin la anulada.
        '6 x Agua                 \$ 6.000',
        '4 x Cerveza lata        \$ 14.000',
        '2 x Fernet con coca     \$ 12.000',
        '-' * 32,
        'Ventas                         2',
        'Efectivo                \$ 16.000',
        'Transferencia           \$ 16.000',
        'TOTAL VENDIDO           \$ 32.000',
        'Anuladas (no cuentan)          1',
        'Lo anulado              \$ 16.000',
        '-' * 32,
        'Cambio inicial          \$ 20.000',
        'Efectivo esperado       \$ 36.000',
        'Efectivo contado        \$ 35.500',
        r'Faltan $ 500',
        '-' * 32,
        'Nota: faltó un billete de',
        'quinientos',
      ]);
    });

    test('abierta: lo dice, y sale sin lo contado', () {
      final papel = _papel(ModeloTicket.deCierre(
        caja,
        CierreDeBarra.de(caja, ventas, const []),
        fiesta: 'Puerto Viejo',
      ));
      expect(papel, contains('*** CAJA ABIERTA ***'));
      expect(papel.where((r) => r.startsWith('Efectivo contado')), isEmpty);
      expect(papel.where((r) => r.startsWith('Faltan') || r.startsWith('Sobran')), isEmpty);
    });

    test('las sillas de la noche se cuentan aparte, debajo de lo vendido', () {
      final conSillas = VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _evento,
        numero: 18,
        renglones: const [
          RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 3),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 24000,
        ahora: vendida,
      );
      final papel = _papel(ModeloTicket.deCierre(
        caja,
        CierreDeBarra.de(caja, [conSillas], const []),
        fiesta: 'Puerto Viejo',
      ));
      expect(papel, containsAllInOrder([
        '3 x Silla extra         \$ 24.000',
        'Sillas extra vendidas          3',
        'Ventas                         1',
      ]));
    });

    test('con el historial: una línea por venta, por número, con las anuladas marcadas', () {
      VentaBarra otra(int numero, int minuto, {MedioBarra medio = MedioBarra.efectivo}) =>
          VentaBarra.nueva(
            cajaBarraId: caja.id,
            eventoId: _evento,
            numero: numero,
            renglones: const [
              RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 2),
            ],
            medio: medio,
            efectivo: medio == MedioBarra.efectivo ? 7000 : 0,
            transferencia: medio == MedioBarra.transferencia ? 7000 : 0,
            ahora: vendida.add(Duration(minutes: minuto)),
          );
      final dos = otra(2, 11, medio: MedioBarra.transferencia);
      final uno = otra(1, 0);
      final tres = otra(3, 30);
      final otraCaja = VentaBarra.nueva(
        cajaBarraId: 'otra-caja',
        eventoId: _evento,
        numero: 9,
        renglones: const [RenglonVenta(productoId: 'a', nombre: 'x', precio: 1, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 1,
        ahora: vendida,
      );
      final anulaciones = [AnulacionBarra.de(tres, motivo: 'error', ahora: vendida)];
      final papel = _papel(ModeloTicket.deCierre(
        caja,
        CierreDeBarra.de(caja, [dos, uno, tres], anulaciones),
        fiesta: 'Puerto Viejo',
        historial: [dos, otraCaja, uno, tres],
        anulaciones: anulaciones,
      ));
      final i = papel.indexOf('HISTORIAL');
      expect(i, greaterThan(0));
      expect(papel.sublist(i + 1), [
        '0001 23:41 efect.        \$ 7.000',
        '0002 23:52 transf.       \$ 7.000',
        '0003 00:11 ANULADA       \$ 7.000',
      ]);
      expect(
        _papel(ModeloTicket.deCierre(caja, CierreDeBarra.de(caja, [uno], const []), fiesta: 'x')),
        isNot(contains('HISTORIAL')),
        reason: 'por la impresora sale sin historial',
      );
    });
  });

  test('en la impresora: ningún renglón pasa las 32 letras y los acentos van en la 850', () async {
    final perfil = await CapabilityProfile.load();
    final v = venta();
    final a = AnulacionBarra.de(v, motivo: 'se cobró dos veces', ahora: vendida);
    final lineas = [
      ...ModeloTicket.deVenta(v, caja: caja, fiesta: 'Puerto Viejo', anulacion: a),
      ...ModeloTicket.deCierre(caja, CierreDeBarra.de(caja, [v], [a]), fiesta: 'Puerto Viejo'),
    ];
    for (final r in _papel(lineas)) {
      if (r.startsWith('[')) continue;
      expect(r.length, lessThanOrEqualTo(32), reason: r);
    }
    final s = bytesComoTexto(TicketEscPos(perfil).armar(lineas));
    expect(s, contains('Caja 2 · N° 0017'));
    expect(s, contains('Motivo: se cobró dos veces'));
    expect(s, contains('Abrió 04/12/2026 - 22:00'));
  });
}
