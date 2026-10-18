import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/contrato_al_bajar.dart';
import 'package:arguello_events/features/eventos/services/revision_mora_constancia.dart';

/// Qué manda la nube y qué conserva la PC al bajar un contrato (6.1.0).
void main() {
  Map<String, dynamic> nube({
    double ajuste = 0,
    String? exenta,
    String? fechaRef,
  }) =>
      {
        'id': 'tonanez',
        'nombre_alumno': 'TOÑANEZ, AGUSTINA',
        'mora_tracked_ajuste': ajuste,
        'mora_exenta_hasta': exenta,
        'mora_exencion_reinicia': 1,
        'mora_fecha_referencia': fechaRef,
      };

  group('el ajuste de la mora lo manda la nube', () {
    // TOÑANEZ, 16-oct: la PC del jefe tenía $166.200 cargados a mano; en la
    // nube se pusieron en 0. Antes la PC se quedaba con los suyos.
    const pcDelJefe = MoraLocalDelContrato(ajuste: 166200);

    test('la nube en 0 pone en 0 el de la PC', () {
      expect(contratoAlBajar(nube(), pcDelJefe)['mora_tracked_ajuste'], 0.0);
    });

    test('un perdón de la nube llega igual que antes', () {
      final fila = contratoAlBajar(nube(ajuste: -315877.5), pcDelJefe);
      expect(fila['mora_tracked_ajuste'], -315877.5);
    });

    test('una PC sin nada guardado toma el de la nube', () {
      expect(
        contratoAlBajar(nube(ajuste: -12000), null)['mora_tracked_ajuste'],
        -12000.0,
      );
      expect(contratoAlBajar(nube(), null)['mora_tracked_ajuste'], 0.0);
    });

    test('la nube sin el dato cuenta como 0', () {
      final fila = nube()..remove('mora_tracked_ajuste');
      expect(contratoAlBajar(fila, pcDelJefe)['mora_tracked_ajuste'], 0.0);
    });
  });

  group('lo que se pone en 0 queda escrito', () {
    test('avisa el ajuste que la PC tenía y la nube trae en 0', () {
      expect(
        ajusteQueSeVa(nube(), const MoraLocalDelContrato(ajuste: 166200)),
        166200,
      );
      expect(
        ajusteQueSeVa(nube(), const MoraLocalDelContrato(ajuste: -40000)),
        -40000,
      );
    });

    test('no avisa si no se pierde nada', () {
      expect(ajusteQueSeVa(nube(), const MoraLocalDelContrato()), isNull);
      expect(ajusteQueSeVa(nube(), null), isNull);
      expect(
        ajusteQueSeVa(
          nube(ajuste: -5000),
          const MoraLocalDelContrato(ajuste: -9000),
        ),
        isNull,
      );
    });

    test('el renglón y el encabezado de revision_mora.txt', () {
      final t = RevisionMoraConstancia.textoDe(
        [renglonAjusteQueSeVa('TOÑANEZ, AGUSTINA', 166200)],
        DateTime(2026, 10, 20, 8, 30),
        queHizo: queHizoAjustesQueSeFueron,
      );
      expect(
        t,
        startsWith('20/10/2026 08:30 · al bajar de la nube, la mora cargada a '
            'mano o perdonada quedó en 0 en 1 alumno(s):'),
      );
      expect(
        t,
        contains('  TOÑANEZ, AGUSTINA: ajuste de la mora en esta PC \$166200 '
            '-> \$0, como en la nube'),
      );
    });
  });

  group('lo que la PC sigue conservando', () {
    test('la eximición que la nube no trae, con su permanencia', () {
      final fila = contratoAlBajar(
        nube(),
        const MoraLocalDelContrato(exentaHasta: '2026-08-31', reinicia: 0),
      );
      expect(fila['mora_exenta_hasta'], '2026-08-31');
      expect(fila['mora_exencion_reinicia'], 0);
    });

    test('la eximición de la nube manda si viene', () {
      final fila = contratoAlBajar(
        nube(exenta: '2026-10-31'),
        const MoraLocalDelContrato(exentaHasta: '2026-08-31', reinicia: 0),
      );
      expect(fila['mora_exenta_hasta'], '2026-10-31');
      expect(fila['mora_exencion_reinicia'], 1);
    });

    test('la fecha de la baja, para una PC con la 6.0.0', () {
      final fila = contratoAlBajar(
        nube(),
        const MoraLocalDelContrato(fechaReferencia: '2026-05-31'),
      );
      expect(fila['mora_fecha_referencia'], '2026-05-31');
    });

    test('lee bien la fila de la PC', () {
      final local = MoraLocalDelContrato.deFila({
        'mora_exenta_hasta': ' 2026-08-31 ',
        'mora_exencion_reinicia': '0',
        'mora_fecha_referencia': '2026-05-31',
        'mora_tracked_ajuste': 166200,
      });
      expect(local.exentaHasta, '2026-08-31');
      expect(local.reinicia, 0);
      expect(local.fechaReferencia, '2026-05-31');
      expect(local.ajuste, 166200);
      expect(MoraLocalDelContrato.deFila({}).reinicia, 1);
    });
  });

  test('el pull usa estas reglas (no las reescribe al lado)', () {
    // Leer el motor: si alguien vuelve a escribir la combinación adentro, este
    // test lo dice.
    final s = _leer('lib/core/services/sync_engine.dart');
    expect(s, contains('contratoAlBajar(cleanRow, preserved)'));
    expect(s, contains('ajusteQueSeVa(cleanRow, preserved)'));
    expect(s, isNot(contains('cloudAjuste.abs() > 0.01 ? cloudAjuste')));
  });
}

String _leer(String ruta) => File(ruta).readAsStringSync();
