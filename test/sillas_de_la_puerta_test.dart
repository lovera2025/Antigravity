// Las sillas que se suman la noche de la fiesta: cuántas entran en cada mesa de
// la familia, adónde va la próxima y el conteo de la noche. Sin pantalla ni base.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/recepcion/services/sillas_de_la_puerta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

const _ev = 'e0000000-0000-4000-8000-000000000001';
const _c = 'c0000000-0000-4000-8000-000000000001';
final _hora = DateTime.utc(2026, 11, 15, 2, 5);

ContratoAlumno _alumno({
  List<int> mesas = const [12],
  int extras = 0,
  int sillas = 0,
}) =>
    ContratoAlumno(
      id: _c,
      eventoId: _ev,
      nombreAlumno: 'PÉREZ, JULIANA',
      cantidadAcompanantes: 0,
      nombresAcompanantes: const [],
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

var _n = 0;
SillaPuerta _silla(
  int mesa,
  String vale, {
  String contrato = _c,
  bool quitada = false,
  int minuto = 0,
}) {
  _n++;
  final cuando = _hora.add(Duration(minutes: minuto));
  final s = SillaPuerta(
    id: 's$_n',
    eventoId: _ev,
    contratoAlumnoId: contrato,
    mesa: mesa,
    vale: vale,
    anotadoPor: 'Pato',
    createdAt: cuando,
    updatedAt: cuando,
  );
  return quitada
      ? s.quitada(
          por: 'Pato',
          motivo: 'devolvieron el vale',
          ahora: cuando.add(const Duration(minutes: 15)),
        )
      : s;
}

void main() {
  group('una mesa', () {
    test('sin extra del contrato: puede agregar hasta 2', () {
      final f = SillasDeLaFamilia.de(_alumno(), null, const []);
      final m = f.mesas.single;
      expect(m.lugar, 2);
      expect(m.estado, EstadoMesaPuerta.conLugar);
      expect(m.texto,
          'Mesa 12: 8 sillas · puede agregar hasta 2 · se cobran en la barra');
    });

    test('con 1 extra del contrato: puede agregar 1 más', () {
      final m = SillasDeLaFamilia.de(_alumno(sillas: 1), null, const []).mesas.single;
      expect(m.lugar, 1);
      expect(m.texto,
          'Mesa 12: 8 sillas + 1 extra · puede agregar 1 más · se cobran en la barra');
    });

    test('con 2 extra del contrato: ya no puede agregar', () {
      final m = SillasDeLaFamilia.de(_alumno(sillas: 2), null, const []).mesas.single;
      expect(m.puedeAgregar, isFalse);
      expect(m.estado, EstadoMesaPuerta.llena);
      expect(m.texto, 'Mesa 12: 8 sillas + 2 extra · ya no puede agregar');
    });

    test('una sumada esa noche cuenta en la mesa que dice su fila', () {
      final m = SillasDeLaFamilia.de(_alumno(sillas: 1), null, [_silla(12, '0012')])
          .mesas
          .single;
      expect(m.extra, 2);
      expect(m.texto, 'Mesa 12: 8 sillas + 2 extra (1 esta noche) · ya no puede agregar');
    });

    test('de más (dos notebooks a la vez): revisar', () {
      final m = SillasDeLaFamilia.de(
        _alumno(sillas: 1),
        null,
        [_silla(12, '0012'), _silla(12, '0015')],
      ).mesas.single;
      expect(m.deMas, 1);
      expect(m.estado, EstadoMesaPuerta.revisar);
      expect(m.texto, 'Mesa 12: 8 sillas + 3 extra (2 esta noche) · 1 de más: revisar');
    });

    test('una quitada no cuenta', () {
      final m = SillasDeLaFamilia.de(
        _alumno(sillas: 1),
        null,
        [_silla(12, '0012', quitada: true)],
      ).mesas.single;
      expect(m.lugar, 1);
    });

    test('la sumada de otra familia no cuenta', () {
      final m = SillasDeLaFamilia.de(
        _alumno(),
        null,
        [_silla(12, '0012', contrato: 'otra')],
      ).mesas.single;
      expect(m.sumadas, 0);
    });
  });

  group('una familia con mesa adicional', () {
    // Mesas 12 y 13 (una extra), 2 sillas del contrato: el de siempre las pone
    // las dos en la principal.
    final a = _alumno(mesas: [12, 13], extras: 1, sillas: 2);

    test('la adicional tiene lugar aunque la principal esté llena', () {
      final f = SillasDeLaFamilia.de(a, null, const []);
      expect([for (final m in f.mesas) m.numero], [12, 13]);
      expect(f.mesas.first.puedeAgregar, isFalse);
      expect(f.mesas.last.texto,
          'Mesa adicional 13: 8 sillas · puede agregar hasta 2 · se cobran en la barra');
      expect(f.lugar, 2);
    });

    test('la próxima va a la adicional si la principal está llena', () {
      final f = SillasDeLaFamilia.de(a, null, const []);
      expect(f.mesaConLugar()?.numero, 13);
      expect(f.mesaConLugar(preferida: 12)?.numero, 13);
    });

    test('con el reparto que eligió la familia (1 y 1)', () {
      final guardado = SillasReparto(
        id: 'r',
        contratoAlumnoId: _c,
        sillasPrincipal: 1,
        sillasExtra: SalonMesas.sillasExtra(a),
        mesas: SalonMesas.mesas(a),
        createdAt: _hora,
        updatedAt: _hora,
      );
      final f = SillasDeLaFamilia.de(a, guardado, const []);
      expect([for (final m in f.mesas) m.extraDelContrato], [1, 1]);
      expect(f.mesaConLugar()?.numero, 12, reason: 'la principal antes');
      expect(f.mesaConLugar(preferida: 13)?.numero, 13);
    });

    test('con todo lleno no hay lugar', () {
      final f = SillasDeLaFamilia.de(a, null, [_silla(13, '1'), _silla(13, '2')]);
      expect(f.puedeAgregar, isFalse);
      expect(f.mesaConLugar(), isNull);
    });
  });

  test('sin mesa no hay líneas', () {
    final f = SillasDeLaFamilia.de(_alumno(mesas: const []), null, const []);
    expect(f.vacia, isTrue);
    expect(f.puedeAgregar, isFalse);
  });

  test('una silla en una mesa que ya no es de la familia se ve, para revisar', () {
    final f = SillasDeLaFamilia.de(_alumno(), null, [_silla(40, '0012')]);
    expect([for (final m in f.mesas) m.numero], [12, 40]);
    final fuera = f.mesas.last;
    expect(fuera.estado, EstadoMesaPuerta.revisar);
    expect(fuera.puedeAgregar, isFalse);
    expect(fuera.texto, contains('ya no es de la familia'));
    expect(f.mesa(40), isNull, reason: 'no es una de sus mesas');
  });

  group('el conteo de la noche', () {
    test('cuatro sumadas y una quitada', () {
      final c = ConteoDeLaNoche.de([
        _silla(12, '0015', minuto: 2),
        _silla(12, '0012', minuto: 1),
        _silla(13, '0021', minuto: 3),
        _silla(14, '0099', minuto: 4, quitada: true),
        _silla(14, '0030', minuto: 5),
      ]);
      expect(c.texto,
          'Esta noche: 4 sillas sumadas · vales 0012, 0015, 0021, 0030 · 1 quitada');
    });

    test('una sola', () {
      expect(ConteoDeLaNoche.de([_silla(12, '0012')]).texto,
          'Esta noche: 1 silla sumada · vale 0012');
    });

    test('sin nada no hay línea', () {
      expect(ConteoDeLaNoche.de(const []).texto, isNull);
    });

    test('solo una quitada', () {
      expect(ConteoDeLaNoche.de([_silla(12, '0012', quitada: true)]).texto,
          'Esta noche: ninguna silla sumada · 1 quitada');
    });
  });

  test('cada movimiento, en palabras', () {
    final s = _silla(12, '0012');
    expect(textoSillaSumada(s), startsWith('+1 silla · mesa 12 · vale 0012 · Pato '));
    expect(textoSillaQuitada(s), isNull);
    final q = _silla(12, '0012', quitada: true);
    expect(textoSillaQuitada(q), startsWith('quitada por Pato '));
    expect(textoSillaQuitada(q), endsWith(': devolvieron el vale'));
  });

  test('ida y vuelta por JSON', () {
    const m = SillasDeUnaMesa(
      numero: 13,
      esPrincipal: false,
      extraDelContrato: 1,
      sumadas: 1,
    );
    final vuelta = SillasDeUnaMesa.fromJson(m.toJson())!;
    expect(vuelta.texto, m.texto);
    expect(SillasDeUnaMesa.fromJson('cualquier cosa'), isNull);
  });
}
