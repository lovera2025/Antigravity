import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/evento.dart';

/// Un alumno con la base de $300.000 en 9 cuotas, y lo que se le cargue encima.
ContratoAlumno _alumno({
  String id = 'a',
  String nombre = 'BENÍTEZ, JOAQUÍN',
  int extras = 0,
  int sillas = 0,
  double precioSillas = -1,
  List<String> acompanantes = const [],
  List<int> mesas = const [12],
  double saldo = 0,
  int cuotasPagadas = 9,
  double moraTracked = 0,
}) {
  final mesaExtra = 70000.0 * extras;
  final sillasTotal = precioSillas >= 0 ? precioSillas : 8000.0 * sillas;
  return ContratoAlumno(
    id: id,
    eventoId: 'e',
    nombreAlumno: nombre,
    cantidadAcompanantes: acompanantes.length,
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
    moraPendienteTracked: moraTracked,
    createdAt: DateTime(2026, 2, 1),
  );
}

Map<String, dynamic> _pago(double monto, String concepto, {bool anulado = false}) =>
    {
      'monto': monto,
      'monto_gross': monto,
      'concepto': concepto,
      'anulado': anulado ? 1 : 0,
      'fecha_pago': '2026-08-10',
    };

/// Pagos que cubren todo lo que se le cargó a [a].
List<Map<String, dynamic>> _pagosCompletos(ContratoAlumno a) => [
      _pago(300000, 'Cuota Base (9/9)'),
      if (a.mesaExtraPrecio > 0) _pago(a.mesaExtraPrecio, 'Mesa Extra 1'),
      if (a.sillasExtraPrecioTotal > 0)
        _pago(a.sillasExtraPrecioTotal, 'Sillas Extra'),
    ];

final _hoy = DateTime(2026, 11, 20);

DeudaAlumno _deuda(ContratoAlumno a, List<Map<String, dynamic>> pagos) =>
    RetiroEntradas.deudaDe(
      a,
      pagos: pagos,
      moraCobradaHistorial: 0,
      ahoraAr: _hoy,
    );

void main() {
  group('entradas', () {
    test('2 mesas y 3 sillas: 19 lugares, 3 VIP y 16 generales', () {
      final e = RetiroEntradas.entradasDe(
        _alumno(extras: 1, sillas: 3, acompanantes: ['MAMÁ', 'PAPÁ']),
      );
      expect(e.lugares, 19);
      expect(e.vip, 3);
      expect(e.generales, 16);
      expect(e.entran, isTrue);
    });

    test('las sillas sin precio no suman lugares', () {
      final e = RetiroEntradas.entradasDe(_alumno(sillas: 2, precioSillas: 0));
      expect(e.lugares, 8);
      expect(e.generales, 7);
    });

    test('más personas con cena que lugares: no entran', () {
      final e = RetiroEntradas.entradasDe(
        _alumno(acompanantes: List.filled(8, 'X')),
      );
      expect(e.vip, 9);
      expect(e.entran, isFalse);
      expect(e.generales, 0);
    });
  });

  group('pagó todo', () {
    test('con todo pagado y sin mora, se entrega', () {
      final a = _alumno(extras: 1, sillas: 3, mesas: [12, 13]);
      final d = _deuda(a, _pagosCompletos(a));
      expect(d.pagoTodo, isTrue);
      expect(d.noCoincide, isFalse);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.ninguno);
    });

    test('con mora pendiente no se entrega, aunque las cuotas estén pagas', () {
      final a = _alumno(moraTracked: 3500);
      final d = _deuda(a, _pagosCompletos(a));
      expect(d.mora, 3500);
      expect(d.pagoTodo, isFalse);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.debe);
      expect(d.total, 3500);
    });

    test('debiendo una cuota no se entrega', () {
      final a = _alumno(saldo: 33333.33, cuotasPagadas: 8);
      final d = _deuda(a, [_pago(266666.67, 'Cuota Base (8/9)')]);
      expect(d.pagoTodo, isFalse);
      expect(d.noCoincide, isFalse);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.debe);
      expect(d.total, greaterThanOrEqualTo(33333.33));
    });

    test('una mesa extra sin pagar también es deuda', () {
      final a = _alumno(extras: 1, mesas: [12, 13], saldo: 70000);
      final d = _deuda(a, [_pago(300000, 'Cuota Base (9/9)')]);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.debe);
    });

    test('un cobro anulado no cuenta como pagado', () {
      final a = _alumno(saldo: 0);
      final d = _deuda(a, [
        _pago(270000, 'Cuota Base (8/9)'),
        _pago(30000, 'Cuota Base (9/9)', anulado: true),
      ]);
      expect(d.saldoPagos, 30000);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.cuentaNoCoincide);
    });

    test('la ficha dice pagado y los pagos no: revisar (caso ARGUELLO)', () {
      final a = _alumno(saldo: 0);
      final d = _deuda(a, [_pago(270000, 'Cuota Base (8/9)')]);
      expect(d.noCoincide, isTrue);
      expect(RetiroEntradas.bloqueo(a, d), BloqueoRetiro.cuentaNoCoincide);
    });

    test('centavos de redondeo no traban la entrega', () {
      final a = _alumno(saldo: 0.004);
      final d = _deuda(a, _pagosCompletos(a));
      expect(d.pagoTodo, isTrue);
    });
  });

  group('mesas', () {
    test('sin mesa asignada no se entrega', () {
      final a = _alumno(mesas: const []);
      expect(
        RetiroEntradas.bloqueo(a, _deuda(a, _pagosCompletos(a))),
        BloqueoRetiro.sinMesa,
      );
    });

    test('si le falta una mesa del sorteo no se entrega', () {
      final a = _alumno(extras: 1, mesas: [12]);
      expect(
        RetiroEntradas.bloqueo(a, _deuda(a, _pagosCompletos(a))),
        BloqueoRetiro.mesasNoCoinciden,
      );
    });

    test('si no entran no se entrega', () {
      final a = _alumno(acompanantes: List.filled(8, 'X'));
      expect(
        RetiroEntradas.bloqueo(a, _deuda(a, _pagosCompletos(a))),
        BloqueoRetiro.noEntran,
      );
    });
  });

  group('talonario', () {
    const t = TramoTalonario.new;

    test('un tramo justo', () {
      expect(
        RetiroEntradas.errorTramos(tramos: [t(1043, 1058)], generales: 16),
        isNull,
      );
    });

    test('dos tramos si cambia de talonario', () {
      expect(
        RetiroEntradas.errorTramos(
          tramos: [t(1043, 1050), t(1101, 1108)],
          generales: 16,
        ),
        isNull,
      );
    });

    test('si no suman las generales, lo dice', () {
      expect(
        RetiroEntradas.errorTramos(tramos: [t(1043, 1050)], generales: 16),
        'Son 8 números y tiene que llevar 16 generales.',
      );
    });

    test('dos tramos que se pisan', () {
      expect(
        RetiroEntradas.errorTramos(
          tramos: [t(1043, 1052), t(1050, 1055)],
          generales: 16,
        ),
        'Los tramos 1043 al 1052 y 1050 al 1055 se pisan.',
      );
    });

    test('un número que ya se le dio a otra familia', () {
      expect(
        RetiroEntradas.errorTramos(
          tramos: [t(1043, 1058)],
          generales: 16,
          deOtros: {
            'PÉREZ, JUAN': [t(1050, 1060)],
          },
        ),
        'El 1050 ya se le dio a PÉREZ, JUAN (1050 al 1060).',
      );
    });

    test('sin generales no van números', () {
      expect(RetiroEntradas.errorTramos(tramos: const [], generales: 0), isNull);
      expect(
        RetiroEntradas.errorTramos(tramos: [t(1, 1)], generales: 0),
        isNotNull,
      );
    });

    test('sin números cuando hacen falta', () {
      expect(
        RetiroEntradas.errorTramos(tramos: const [], generales: 5),
        'Escribí el primer número de las entradas que le das.',
      );
    });

    test('se guardan y se leen igual', () {
      final tramos = [t(1043, 1050), t(1101, 1108)];
      final texto = TramoTalonario.aTexto(tramos);
      expect(texto, '1043-1050,1101-1108');
      expect(TramoTalonario.deTexto(texto), tramos);
      expect(TramoTalonario.legible(tramos), '1043 al 1050 y 1101 al 1108');
    });

    test('lo que no se entiende no inventa números', () {
      expect(TramoTalonario.deTexto('abc, 9-3'), isEmpty);
      expect(TramoTalonario.deTexto('7'), [t(7, 7)]);
      expect(TramoTalonario.deTexto(null), isEmpty);
    });
  });

  group('quién retira', () {
    test('falta todo', () {
      final e = RetiroEntradas.erroresQuienRetira(
        parentesco: null,
        nombre: 'Laura',
        escribioEnPlanilla: false,
      );
      expect(e.keys, containsAll(['parentesco', 'nombre', 'planilla']));
    });

    test('un familiar directo con nombre y apellido', () {
      expect(
        RetiroEntradas.erroresQuienRetira(
          parentesco: ParentescoRetiro.madre,
          nombre: '  Laura   Benítez ',
          escribioEnPlanilla: true,
        ),
        isEmpty,
      );
    });

    test('otra persona necesita motivo y autorización firmada', () {
      final e = RetiroEntradas.erroresQuienRetira(
        parentesco: ParentescoRetiro.otraPersona,
        nombre: 'Carlos Gómez',
        escribioEnPlanilla: true,
      );
      expect(e.keys, containsAll(['motivo', 'autorizacion']));
      expect(
        RetiroEntradas.erroresQuienRetira(
          parentesco: ParentescoRetiro.otraPersona,
          nombre: 'Carlos Gómez',
          motivo: 'La familia está de viaje',
          autorizacionFirmada: true,
          escribioEnPlanilla: true,
        ),
        isEmpty,
      );
    });
  });

  group('entregar y anular', () {
    final ahora = DateTime.utc(2026, 11, 12, 21, 40);
    final a = _alumno(extras: 1, sillas: 3, acompanantes: ['MAMÁ', 'PAPÁ']);
    final entradas = RetiroEntradas.entradasDe(a);

    EntradasRetiro entregar({EntradasRetiro? anterior, DateTime? cuando}) =>
        RetiroEntradas.nuevaEntrega(
          alumno: a,
          entradas: entradas,
          tramos: const [TramoTalonario(1043, 1058)],
          menores10: 1,
          parentesco: ParentescoRetiro.madre,
          nombre: '  laura   benítez ',
          quien: 'Operador',
          ahora: cuando ?? ahora,
          anterior: anterior,
        );

    test('la entrega guarda lo que se llevó y quién', () {
      final r = entregar();
      expect(r.entregado, isTrue);
      expect(r.vip, 3);
      expect(r.generales, 16);
      expect(r.entradas, 19);
      expect(r.retiroNombre, 'LAURA BENÍTEZ');
      expect(r.escribioEnPlanilla, isTrue);
      expect(r.otraPersonaMotivo, isNull);
      expect(r.entregadoPor, 'Operador');
      expect(r.contratoAlumnoId, 'a');
    });

    test('anular no borra: deja quién, cuándo y por qué', () {
      final r = RetiroEntradas.anular(
        entregar(),
        motivo: ' Compró otra silla ',
        quien: 'Jefe',
        ahora: ahora.add(const Duration(days: 2)),
      );
      expect(r.entregado, isFalse);
      expect(r.anuladoMotivo, 'Compró otra silla');
      expect(r.anuladoPor, 'Jefe');
      expect(r.entregadoPor, 'Operador');
      expect(r.tramos, const [TramoTalonario(1043, 1058)]);
    });

    test('volver a entregar conserva la anulación anterior', () {
      final anulada = RetiroEntradas.anular(
        entregar(),
        motivo: 'Error',
        quien: 'Jefe',
        ahora: ahora.add(const Duration(hours: 1)),
      );
      final otraVez = entregar(
        anterior: anulada,
        cuando: ahora.add(const Duration(hours: 2)),
      );
      expect(otraVez.entregado, isTrue);
      expect(otraVez.anuladoMotivo, 'Error');
      expect(otraVez.createdAt, ahora);
      expect(otraVez.id, anulada.id);
    });

    test('va y vuelve de la base igual', () {
      final r = entregar();
      final vuelta = EntradasRetiro.fromMap(r.toMap());
      expect(vuelta.toMap(), r.toMap());
      // Así llega de la nube: booleanos de verdad.
      final nube = Map<String, dynamic>.from(r.toMap())
        ..['escribio_en_planilla'] = true
        ..['autorizacion_firmada'] = false;
      expect(EntradasRetiro.fromMap(nube).escribioEnPlanilla, isTrue);
    });

    test('si después compró otra silla, falta entregar una general', () {
      final r = entregar();
      final hoy = RetiroEntradas.entradasDe(
        _alumno(extras: 1, sillas: 4, acompanantes: ['MAMÁ', 'PAPÁ']),
      );
      expect(RetiroEntradas.cambioLaCuenta(r, hoy), isTrue);
      expect(RetiroEntradas.diferencia(r, hoy), (vip: 0, generales: 1));
      expect(RetiroEntradas.cambioLaCuenta(r, entradas), isFalse);
    });
  });

  group('planilla en papel', () {
    test('sin retirar: van las entradas y el nombre queda en blanco', () {
      final a = _alumno(extras: 1, sillas: 3, mesas: [13, 14], acompanantes: ['MAMÁ', 'PAPÁ']);
      final f = RetiroEntradas.filaPlanilla(a, deuda: _deuda(a, _pagosCompletos(a)));
      expect(f.mesa, '13-14');
      expect(f.vip, 3);
      expect(f.generales, 16);
      expect(f.delAl, isEmpty);
      expect(f.parentesco, isEmpty);
      expect(f.noEntregar, isNull);
      expect(f.entregado, isFalse);
    });

    test('si debe, la planilla lo dice', () {
      final a = _alumno(moraTracked: 3500);
      final f = RetiroEntradas.filaPlanilla(a, deuda: _deuda(a, _pagosCompletos(a)));
      expect(f.noEntregar, 'Debe: no entregar');
    });

    test('ya retirado: sus números, sus menores y el parentesco', () {
      final a = _alumno(extras: 1, sillas: 3, mesas: [13, 14], acompanantes: ['MAMÁ', 'PAPÁ']);
      final r = RetiroEntradas.nuevaEntrega(
        alumno: a,
        entradas: RetiroEntradas.entradasDe(a),
        tramos: const [TramoTalonario(1043, 1058)],
        menores10: 2,
        parentesco: ParentescoRetiro.abuelo,
        nombre: 'Rosa Gómez',
        quien: 'Operador',
        ahora: DateTime.utc(2026, 11, 12),
      );
      final f = RetiroEntradas.filaPlanilla(
        a,
        retiro: r,
        deuda: _deuda(a, _pagosCompletos(a)),
      );
      expect(f.delAl, '1043 al 1058');
      expect(f.menores, '2');
      expect(f.parentesco, 'Abuelo/a');
      expect(f.entregado, isTrue);
      expect(f.noEntregar, isNull);
    });

    test('se arma en color y en blanco y negro con las fuentes de la app',
        () async {
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
            id: 'a$i',
            nombre: 'ALUMNO $i',
            mesas: [i + 1],
          ).copyWith(cursoDivision: i < 30 ? '5° A' : '5° B'),
      ];
      final deudas = {
        for (final a in alumnos) a.id: _deuda(a, _pagosCompletos(a)),
      };
      for (final bn in [false, true]) {
        final bytes = await PdfService.construirPlanillaEntregaPdf(
          evento,
          alumnos,
          retiros: const {},
          deudas: deudas,
          blancoYNegro: bn,
          generada: DateTime(2026, 11, 12, 21, 30),
        );
        expect(bytes.length, greaterThan(1000), reason: 'bn=$bn');
      }
    });
  });

  group('en el evento', () {
    final ahora = DateTime.utc(2026, 11, 12);
    final a = _alumno(id: 'a', nombre: 'ACOSTA, VALENTINA');
    final b = _alumno(id: 'b', nombre: 'BENÍTEZ, JOAQUÍN');
    final c = _alumno(id: 'c', nombre: 'CASTRO, MÍA', saldo: 30000);
    EntradasRetiro entrega(ContratoAlumno x, TramoTalonario t) =>
        RetiroEntradas.nuevaEntrega(
          alumno: x,
          entradas: RetiroEntradas.entradasDe(x),
          tramos: [t],
          menores10: 0,
          parentesco: ParentescoRetiro.padre,
          nombre: 'Hugo Pérez',
          quien: 'Operador',
          ahora: ahora,
        );

    test('los números de otros cuentan solo si la entrega está vigente', () {
      final retiros = {
        'b': entrega(b, const TramoTalonario(1, 7)),
        'c': RetiroEntradas.anular(
          entrega(c, const TramoTalonario(8, 14)),
          motivo: 'Error',
          quien: 'Jefe',
          ahora: ahora,
        ),
      };
      final otros = RetiroEntradas.tramosDeOtros(
        [a, b, c],
        retiros,
        salvo: 'a',
      );
      expect(otros.keys, ['BENÍTEZ, JOAQUÍN']);
      expect(
        RetiroEntradas.tramosDeOtros([a, b, c], retiros, salvo: 'b'),
        isEmpty,
      );
    });

    test('el resumen cuenta retiros, deudas y entradas', () {
      final retiros = {'b': entrega(b, const TramoTalonario(1, 7))};
      final deudas = {
        'a': _deuda(a, _pagosCompletos(a)),
        'b': _deuda(b, _pagosCompletos(b)),
        'c': _deuda(c, [_pago(270000, 'Cuota Base (8/9)')]),
      };
      final r = RetiroEntradas.resumen([a, b, c], retiros, deudas);
      expect(r.alumnos, 3);
      expect(r.retiraron, 1);
      expect(r.faltan, 2);
      expect(r.conDeuda, 1);
      expect(r.entradasEntregadas, 8);
      expect(r.entradasTotales, 24);
    });
  });
}
