// El filtro "Mesas y sillas" de la grilla de masivos: para llegar al sorteo
// sabiendo quién tiene qué y quién lo pagó.
import 'package:arguello_events/features/eventos/services/filtro_mesas_sillas.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';

ContratoAlumno _alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  String? mesa,
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: baja ? '[BAJA] $id' : id,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
    );

Set<FiltroExtras> _enCuales(ContratoAlumno a, PagoAlumno pago,
    {bool avisos = false}) {
  final e = ExtrasSegunPago.de(a, pago);
  return {
    for (final f in FiltroExtras.values)
      if (f.activo && cumpleFiltroExtras(a, e, f, tieneAvisos: avisos)) f,
  };
}

void main() {
  test('"Todos" deja pasar a cualquiera, también a los de baja', () {
    final baja = _alumno('b', baja: true);
    expect(cumpleFiltroExtras(baja, null, FiltroExtras.todos), isTrue);
  });

  test('solo la del contrato y al día: no entra en ningún filtro', () {
    expect(_enCuales(_alumno('a'), const PagoAlumno(base: 30000)), isEmpty);
  });

  test('sin pago de la base', () {
    expect(_enCuales(_alumno('a'), PagoAlumno.nada), {FiltroExtras.sinPagoBase});
  });

  test('mesa agregada: sin pagar, en cuotas y pagada', () {
    final a = _alumno('a', extras: 1);
    expect(
      _enCuales(a, const PagoAlumno(base: 30000)),
      {FiltroExtras.conMesaAgregada, FiltroExtras.mesaSinPagar},
    );
    expect(
      _enCuales(a, const PagoAlumno(base: 30000, mesas: 10000)),
      {FiltroExtras.conMesaAgregada, FiltroExtras.mesaEnCuotas},
    );
    expect(
      _enCuales(a, const PagoAlumno(base: 30000, mesas: 70000)),
      {FiltroExtras.conMesaAgregada, FiltroExtras.mesaPagada},
    );
  });

  test('sillas: sin pagar, en cuotas y pagadas', () {
    final a = _alumno('a', sillas: 3);
    expect(
      _enCuales(a, const PagoAlumno(base: 30000)),
      {FiltroExtras.conSillas, FiltroExtras.sillasSinPagar},
    );
    expect(
      _enCuales(a, const PagoAlumno(base: 30000, sillas: 8000)),
      {FiltroExtras.conSillas, FiltroExtras.sillasEnCuotas},
    );
    expect(
      _enCuales(a, const PagoAlumno(base: 30000, sillas: 24000)),
      {FiltroExtras.conSillas, FiltroExtras.sillasPagadas},
    );
  });

  test('"Para revisar" sale de los avisos, no de los pagos', () {
    final a = _alumno('a');
    expect(
      _enCuales(a, const PagoAlumno(base: 30000), avisos: true),
      {FiltroExtras.revisar},
    );
    // Aunque todavía no se hayan leído sus pagos.
    expect(
      cumpleFiltroExtras(a, null, FiltroExtras.revisar, tieneAvisos: true),
      isTrue,
    );
    expect(cumpleFiltroExtras(a, null, FiltroExtras.conSillas), isFalse);
  });

  test('los de baja no entran en ningún filtro, igual que en el sorteo', () {
    final baja = _alumno('b', extras: 1, sillas: 2, baja: true);
    expect(_enCuales(baja, PagoAlumno.nada, avisos: true), isEmpty);
    expect(
      tieneAlgoPendienteDeExtras(
        baja,
        ExtrasSegunPago.de(baja, PagoAlumno.nada),
        tieneAvisos: true,
      ),
      isFalse,
    );
  });

  test('cada opción con filtro tiene su grupo, y "Todos" no', () {
    for (final f in FiltroExtras.values) {
      expect(f.grupo == null, f == FiltroExtras.todos, reason: f.name);
    }
  });

  test('lo pendiente antes del sorteo: base, mesa o sillas sin pagar, o un aviso',
      () {
    bool pendiente(ContratoAlumno a, PagoAlumno p, {bool avisos = false}) =>
        tieneAlgoPendienteDeExtras(
          a,
          ExtrasSegunPago.de(a, p),
          tieneAvisos: avisos,
        );
    const alDia = PagoAlumno(base: 30000, mesas: 10000, sillas: 8000);
    expect(pendiente(_alumno('a', extras: 1, sillas: 2), alDia), isFalse);
    expect(pendiente(_alumno('a'), PagoAlumno.nada), isTrue);
    expect(
      pendiente(_alumno('a', extras: 1), const PagoAlumno(base: 30000)),
      isTrue,
    );
    expect(
      pendiente(_alumno('a', sillas: 2), const PagoAlumno(base: 30000)),
      isTrue,
    );
    expect(pendiente(_alumno('a'), alDia, avisos: true), isTrue);
  });

  test('los totales: lo cargado y lo que daría hoy el sorteo, sin las bajas', () {
    final alumnos = [
      _alumno('alDia', extras: 1, sillas: 2),
      _alumno('extraSinPago', extras: 2),
      _alumno('nada', sillas: 1),
      _alumno('baja', extras: 3, sillas: 4, baja: true),
    ];
    final extras = extrasPorAlumno(alumnos, {
      'alDia': const PagoAlumno(base: 30000, mesas: 10000, sillas: 16000),
      'extraSinPago': const PagoAlumno(base: 30000),
    });
    final t = totalesDeExtras(alumnos, extras);
    // 2 + 3 + 1 cargadas; el sorteo daría 2 + 1 + 0.
    expect(t.mesas, 6);
    expect(t.agregadas, 3);
    expect(t.conLoPagado, 3);
    expect(t.sillas, 3);
  });
}
