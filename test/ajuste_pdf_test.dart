import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/common/services/ajuste_pdf.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';

/// La escalera de compactación: **abreviar antes que achicar**. La letra chica
/// es el último recurso, y tiene piso — la 4.6.2 se dedicó justamente a hacer
/// legibles estos papeles.
void main() {
  group('escalera', () {
    test('el nivel 0 no toca nada: el papel de siempre sale igual', () {
      const a = AjustePdf.intacto;
      expect(a.esIntacto, isTrue);
      expect(a.fs(9), 9);
      expect(a.fs(7.5, piso: 6.5), 7.5);
      expect(a.sp(12), 12);
      expect(a.subtextos, isTrue);
      expect(a.abreviar, isFalse);
    });

    test('arranca en intacto y va de menos a más invasiva', () {
      expect(AjustePdf.escalera.first.esIntacto, isTrue);
      for (var i = 1; i < AjustePdf.escalera.length; i++) {
        final ant = AjustePdf.escalera[i - 1];
        final act = AjustePdf.escalera[i];
        expect(act.nivel, ant.nivel + 1);
        expect(
          act.aire,
          lessThanOrEqualTo(ant.aire),
          reason: 'el aire nunca se afloja al subir de nivel',
        );
        expect(
          act.texto,
          lessThanOrEqualTo(ant.texto),
          reason: 'la letra nunca se agranda al subir de nivel',
        );
      }
    });

    test('se comprime el aire antes de tocar la letra', () {
      final primerAireComprimido = AjustePdf.escalera.firstWhere(
        (a) => a.aire < 1.0,
      );
      final primerTextoAchicado = AjustePdf.escalera.firstWhere(
        (a) => a.texto < 1.0,
      );
      expect(primerAireComprimido.nivel, lessThan(primerTextoAchicado.nivel));
    });

    test('se abrevian rótulos antes de achicar la letra', () {
      final primerAbreviado = AjustePdf.escalera.firstWhere((a) => a.abreviar);
      final primerTextoAchicado = AjustePdf.escalera.firstWhere(
        (a) => a.texto < 1.0,
      );
      expect(primerAbreviado.nivel, lessThanOrEqualTo(primerTextoAchicado.nivel));
    });

    test('se sacan los subtextos antes de achicar la letra', () {
      final primerSinSubtextos = AjustePdf.escalera.firstWhere(
        (a) => !a.subtextos,
      );
      final primerTextoAchicado = AjustePdf.escalera.firstWhere(
        (a) => a.texto < 1.0,
      );
      expect(
        primerSinSubtextos.nivel,
        lessThan(primerTextoAchicado.nivel),
      );
    });
  });

  group('piso de legibilidad', () {
    test('ninguna fuente baja del piso, por más apretado que esté', () {
      for (final a in AjustePdf.escalera) {
        expect(a.fs(10), greaterThanOrEqualTo(7));
        expect(a.fs(9), greaterThanOrEqualTo(7));
        expect(a.fs(8), greaterThanOrEqualTo(7));
        expect(a.fs(7, piso: 6.5), greaterThanOrEqualTo(6.5));
      }
    });

    test('el espaciado sí se comprime, pero no colapsa a cero', () {
      final ultima = AjustePdf.escalera.last;
      expect(ultima.sp(12), lessThan(12));
      expect(ultima.sp(12), greaterThanOrEqualTo(1));
      expect(ultima.sp(1), greaterThanOrEqualTo(1));
      expect(ultima.sp(0), 0, reason: 'cero sigue siendo cero');
    });
  });

  group('abreviarDisplayPdf', () {
    test('acorta la cuota y su vencimiento sin perder el dato', () {
      expect(
        abreviarDisplayPdf('Cuota 3 de 9 — venció 31/05/2026'),
        'Cuota 3/9 · vto 31/05',
      );
      expect(
        abreviarDisplayPdf('Cuota 4 de 9 — vence 30/06/2026'),
        'Cuota 4/9 · vto 30/06',
      );
    });

    test('acorta el rango ya compactado', () {
      expect(abreviarDisplayPdf('Cuotas 1 a 9 de 9'), 'Cuotas 1–9/9');
      expect(
        abreviarDisplayPdf('Cuotas 4-5-6-7 de 9'),
        'Cuotas 4-5-6-7/9',
      );
    });

    test('acorta mesas y sillas conservando el número', () {
      expect(
        abreviarDisplayPdf('Mesa extra 2 — cuota 3 de 9'),
        'Mesa 2 · cuota 3/9',
      );
      expect(
        abreviarDisplayPdf('Sillas extra — cuota 3 de 9'),
        'Sillas · cuota 3/9',
      );
    });

    test('acorta la mora anidada y la de arrastre', () {
      expect(abreviarDisplayPdf('Mora — 23 días fuera de término'), 'Mora · 23 d');
      expect(
        abreviarDisplayPdf('Mora de la cuota 2'),
        'Mora cuota 2',
      );
      expect(
        abreviarDisplayPdf('Mora no cobrada al pagar la cuota 2'),
        'Mora cuota 2',
      );
      expect(
        abreviarDisplayPdf(
          'Mora de la cuota 2 de May — 23 días fuera de término, '
          'no cobrada en su momento',
        ),
        'Mora cuota 2 (May)',
      );
    });

    test('un rótulo que no reconoce lo devuelve intacto', () {
      const raro = 'Concepto nuevo que todavía no existe';
      expect(abreviarDisplayPdf(raro), raro);
    });

    test('nunca devuelve vacío si entró algo', () {
      for (final s in [
        'Cuota 1 de 1',
        'Mora — 1 día fuera de término',
        'Sillas extra',
        'Mesa extra 4',
      ]) {
        expect(abreviarDisplayPdf(s), isNotEmpty, reason: s);
        expect(
          abreviarDisplayPdf(s).length,
          lessThanOrEqualTo(s.length),
          reason: 'abreviar no puede alargar: $s',
        );
      }
    });
  });
}
