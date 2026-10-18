import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/baja_temporal.dart';
import 'package:arguello_events/features/eventos/services/cobro_mora_resolver.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/widgets/modal_alumno_premium.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// La baja temporal no toca la mora (6.1.0).
///
/// Un alumno que vuelve de una baja tiene que verse exactamente igual que uno
/// que nunca estuvo de baja: cada cuota vencida con su mora desde su
/// vencimiento. Los números son los de la especificación del usuario
/// (`SPEC — Mora por cuota y bajas temporales`, 16-oct): TOÑANEZ, AGUSTINA, de
/// la Normal, 0 de 9 cuotas de $30.000, inscripta el 30-mar, al 16-oct.
void main() {
  final alDieciseis = DateTime(2026, 10, 16);

  /// La gemela: nunca estuvo de baja.
  ContratoAlumno gemela({
    String nombre = 'TOÑANEZ, AGUSTINA',
    DateTime? moraFechaReferencia,
    double moraPendienteTracked = 0,
  }) =>
      ContratoAlumno(
        id: 'tonanez',
        eventoId: 'normal',
        nombreAlumno: nombre,
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 270000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        diaVencimientoMensual: 10,
        createdAt: DateTime.utc(2026, 3, 30, 3),
        moraFechaReferencia: moraFechaReferencia,
        moraPendienteTracked: moraPendienteTracked,
      );

  /// Reincorporada: el nombre sin `[BAJA]`, pero con el 31-may que la 6.0.0
  /// le guardó al darla de baja (así llega a una PC que lo conservó).
  ContratoAlumno reincorporada() =>
      gemela(moraFechaReferencia: DateTime(2026, 5, 31));

  /// Todavía de baja.
  ContratoAlumno deBaja() => gemela(
        nombre: '[BAJA] TOÑANEZ, AGUSTINA',
        moraFechaReferencia: DateTime(2026, 5, 31),
      );

  /// Cuota por cuota: número, vencimiento, días y mora.
  List<String> renglones(ContratoAlumno c, DateTime dia) => [
        for (final d in MoraCuotaCalculator.calcularDesglose(c, dia))
          'cuota ${d.numeroCuota} · vto ${d.vencimiento.day}/'
              '${d.vencimiento.month} · ${d.diasMora} d · '
              '\$${d.interesBruto.toStringAsFixed(0)}',
      ];

  group('la mora de cada cuota, como en la especificación', () {
    test('0 pagos y nunca de baja: 6 moras, \$166.200 en total', () {
      expect(renglones(gemela(), alDieciseis), [
        'cuota 1 · vto 30/4 · 169 d · \$50700',
        'cuota 2 · vto 31/5 · 138 d · \$41400',
        'cuota 3 · vto 30/6 · 108 d · \$32400',
        'cuota 4 · vto 31/7 · 77 d · \$23100',
        'cuota 5 · vto 31/8 · 46 d · \$13800',
        'cuota 6 · vto 30/9 · 16 d · \$4800',
      ]);
      expect(
        MoraCuotaCalculator.moraPendienteOperativa(
          contrato: gemela(),
          moraCobradaHistorial: 0,
          ahoraAr: alDieciseis,
        ),
        closeTo(166200, 0.01),
      );
    });

    test('reincorporada con el 31-may guardado: idéntica a la gemela', () {
      expect(
        renglones(reincorporada(), alDieciseis),
        renglones(gemela(), alDieciseis),
      );
      expect(
        MoraCuotaCalculator.moraPendienteOperativa(
          contrato: reincorporada(),
          moraCobradaHistorial: 0,
          ahoraAr: alDieciseis,
        ),
        closeTo(166200, 0.01),
      );
    });

    test('la mora sigue corriendo día a día después de reincorporar', () {
      // Al 18-oct son dos días más en cada una de las 6 cuotas: $3.600.
      expect(
        MoraCuotaCalculator.moraPendienteOperativa(
          contrato: reincorporada(),
          moraCobradaHistorial: 0,
          ahoraAr: DateTime(2026, 10, 18),
        ),
        closeTo(169800, 0.01),
      );
    });

    test('mientras está de baja, la mora corre igual', () {
      // Sale de los cobros y de los totales, pero si vuelve debe esto.
      expect(
        renglones(deBaja(), alDieciseis),
        renglones(gemela(), alDieciseis),
      );
    });
  });

  group('la ventana de cobro, igual que la de la gemela', () {
    ResolucionMoraCobro cobrarCuota1SinMora(ContratoAlumno pre) {
      final post = pre.copyWith(saldoDeudor: 240000, cuotasPagadas: 1);
      return resolverMoraDeCobro(
        contratoPre: pre,
        contratoPost: post,
        moraCobradaHistorial: 0,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        saldoDeudorPost: 240000,
        fechaCobroAr: alDieciseis,
        formatoMonto: (v) => '\$${v.toStringAsFixed(0)}',
      );
    }

    test('cobra la cuota 1 sin su mora: queda debiendo lo mismo', () {
      final r = cobrarCuota1SinMora(reincorporada());
      final g = cobrarCuota1SinMora(gemela());
      expect(r.moraPendientePost, closeTo(g.moraPendientePost, 0.01));
      expect(r.trackedPost, closeTo(g.trackedPost, 0.01));
      expect(
        r.contratoPatch.moraPendienteTracked,
        closeTo(g.contratoPatch.moraPendienteTracked, 0.01),
      );
      expect(
        r.contratoPatch.moraCobradaOffset,
        closeTo(g.contratoPatch.moraCobradaOffset, 0.01),
      );
      expect(r.moraPendienteOrigen, g.moraPendienteOrigen);
      // La mora de la cuota 1 no se pierde por haberla cobrado sin ella.
      expect(r.moraPendientePost, closeTo(166200, 0.01));
    });

    test('cobra la cuota 1 sin su mora y vuelve el 20-oct: igual a la gemela',
        () {
      final r = cobrarCuota1SinMora(reincorporada()).contratoPatch;
      final g = cobrarCuota1SinMora(gemela()).contratoPatch;
      final dia = DateTime(2026, 10, 20);
      expect(
        MoraCuotaCalculator.moraPendienteOperativa(
          contrato: r,
          moraCobradaHistorial: 0,
          ahoraAr: dia,
        ),
        closeTo(
          MoraCuotaCalculator.moraPendienteOperativa(
            contrato: g,
            moraCobradaHistorial: 0,
            ahoraAr: dia,
          ),
          0.01,
        ),
      );
      expect(renglones(r, dia), renglones(g, dia));
    });
  });

  group('lo que se guarda al dar de baja y al reincorporar', () {
    test('dar de baja no escribe nada de la mora', () {
      final datos = BajaTemporal.alDarDeBaja(
        gemela(),
        ahoraUtcIso: '2026-10-18T12:00:00.000Z',
      );
      expect(datos, {
        'nombre_alumno': '[BAJA] TOÑANEZ, AGUSTINA',
        'baja_temporal_desde': '2026-10-18T12:00:00.000Z',
      });
      expect(datos.keys.where((k) => k.startsWith('mora')), isEmpty);
    });

    test('reincorporar solo devuelve el nombre', () {
      expect(BajaTemporal.alReincorporar(deBaja()), {
        'nombre_alumno': 'TOÑANEZ, AGUSTINA',
      });
    });

    test('la pantalla da de baja y reincorpora con estos datos', () {
      // Leer la pantalla: si alguien vuelve a armar los datos a mano adentro
      // (y con ellos la fecha que congelaba la mora), este test lo dice.
      final s = File('lib/features/eventos/detalle_evento_masivo_screen.dart')
          .readAsStringSync();
      expect(s, contains('BajaTemporal.alReincorporar(alumno)'));
      expect(s, contains('BajaTemporal.alDarDeBaja('));
      // Al reincorporar, su ficha se rehace en el momento.
      final toggle = s.substring(s.indexOf('Future<void> _toggleBajaTemporal('));
      final alGuardar = toggle.substring(
        toggle.indexOf('await repo.actualizarContrato(alumno.id, updates);'),
        toggle.indexOf('puertaAlDiaProvider'),
      );
      expect(alGuardar, contains('if (esBaja)'));
      expect(alGuardar, contains('revisarMora(soloContratos: {alumno.id})'));
      // La única escritura de la fecha que queda es la del cobro, que la borra.
      expect(
        RegExp(r"'mora_fecha_referencia':\s*(?!\s|null)").hasMatch(s),
        isFalse,
      );
    });

    test('la grilla le pasa a los filtros de mora las fichas sin explicar', () {
      final s = File('lib/features/eventos/detalle_evento_masivo_screen.dart')
          .readAsStringSync();
      // Las tres: la grilla, el chip y la planilla.
      expect('sinExplicar: sinExplicar'.allMatches(s).length, 3);
      expect(
        'cumpleFiltroMora('.allMatches(s).length,
        3,
        reason: 'un filtro nuevo de mora también necesita la lista',
      );
    });

    test('el [BAJA] no se duplica ni deja espacios', () {
      expect(
        BajaTemporal.alDarDeBaja(deBaja(), ahoraUtcIso: 'x')['nombre_alumno'],
        '[BAJA] TOÑANEZ, AGUSTINA',
      );
      expect(BajaTemporal.nombreLimpio('[BAJA]  PEREZ, ANA '), 'PEREZ, ANA');
    });
  });

  group('Editar alumno manda la mora solo si alguien la cambió', () {
    // La PC del jefe tenía $166.200 cargados a mano que en la nube ya estaban
    // en 0: editarle el teléfono los habría vuelto a subir.
    final enLaPc = gemela(moraFechaReferencia: DateTime(2026, 5, 31))
        .copyWith(moraTrackedAjuste: 166200, moraPendienteTracked: 166200);

    test('cambiar el teléfono no manda ningún campo de la mora', () {
      final datos = datosEdicionAlumno(
        antes: enLaPc,
        editado: enLaPc.copyWith(telefono: '3794000000'),
        numeroMesaEscrito: '',
      );
      expect(datos['telefono'], '3794000000');
      for (final campo in camposMoraDelAlumno) {
        expect(datos.containsKey(campo), isFalse, reason: campo);
      }
    });

    test('si la edición cambia la mora, esa sí viaja', () {
      final datos = datosEdicionAlumno(
        antes: enLaPc,
        editado: enLaPc.copyWith(moraTrackedAjuste: 0),
        numeroMesaEscrito: '',
      );
      expect(datos['mora_tracked_ajuste'], 0.0);
      expect(datos.containsKey('mora_pendiente_tracked'), isFalse);
    });

    test('borrar una fecha a propósito la manda vacía', () {
      final datos = datosEdicionAlumno(
        antes: enLaPc,
        editado: enLaPc.copyWith(moraFechaReferencia: null),
        numeroMesaEscrito: '',
      );
      expect(datos.containsKey('mora_fecha_referencia'), isTrue);
      expect(datos['mora_fecha_referencia'], isNull);
    });
  });
}
