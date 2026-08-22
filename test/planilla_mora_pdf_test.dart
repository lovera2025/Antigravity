import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';

/// La planilla de mora es la hoja con la que se llama a las familias.
///
/// Lo que no puede fallar es que salgan **todos**: un alumno que no aparece es
/// un alumno al que nadie llama, y no hay forma de notarlo mirando el papel.
void main() {
  MoraPdfFila fila(
    int i, {
    double vencida = 0,
    double noCobrada = 0,
    String curso = '2',
    String telefono = '3777123456',
  }) => MoraPdfFila(
    nombre: 'ALUMNO ${i.toString().padLeft(2, '0')}',
    curso: curso,
    telefono: telefono,
    cuotas: '4/9',
    moraVencida: vencida,
    detalleVencida: vencida > 0 ? 'C5 (May) 30d ${vencida.toString()}' : '',
    moraNoCobrada: noCobrada,
    detalleNoCobrada: noCobrada > 0 ? 'C1 (Abr) 20d' : '',
    saldoPlan: 200000,
  );

  group('planillaMoraFilasTabla', () {
    test('60 alumnos entran 60 filas y salen 60 filas', () {
      final filas = [
        for (var i = 0; i < 60; i++) fila(i, vencida: 1000.0 + i),
      ];
      final data = PdfService.planillaMoraFilasTabla(filas);

      expect(data.length, 60);
      // Y son 60 alumnos distintos, no uno repetido 60 veces.
      expect(data.map((f) => f[1]).toSet().length, 60);
      // Ninguna fila queda con menos columnas que el encabezado.
      for (final f in data) {
        expect(f.length, PdfService.planillaMoraHeaders.length);
      }
    });

    test('ordena de mayor a menor mora: se llama de arriba hacia abajo', () {
      final data = PdfService.planillaMoraFilasTabla([
        fila(1, vencida: 5000),
        fila(2, vencida: 40000),
        fila(3, noCobrada: 12000),
        fila(4, vencida: 10000, noCobrada: 15000),
      ]);
      // Totales: 40.000 · 25.000 · 12.000 · 5.000
      expect(
        data.map((f) => f[1]).toList(),
        ['ALUMNO 02\n2', 'ALUMNO 04\n2', 'ALUMNO 03\n2', 'ALUMNO 01\n2'],
      );
    });

    test('el orden no depende del orden de entrada', () {
      final base = [
        fila(1, vencida: 5000),
        fila(2, vencida: 40000),
        fila(3, vencida: 12000),
      ];
      final directo = PdfService.planillaMoraFilasTabla(base);
      final invertido =
          PdfService.planillaMoraFilasTabla(base.reversed.toList());
      expect(directo.map((f) => f[1]), invertido.map((f) => f[1]));
    });

    test('sin detalle, cada celda de mora conserva su total', () {
      final conDetalle = PdfService.planillaMoraFilasTabla([
        fila(1, vencida: 30400, noCobrada: 19400),
      ]);
      final sinDetalle = PdfService.planillaMoraFilasTabla(
        [fila(1, vencida: 30400, noCobrada: 19400)],
        conDetalle: false,
      );
      // Lo que la escalera de AjustePdf saca es el desglose, nunca el monto.
      expect(conDetalle.single[4], contains('\n'));
      expect(sinDetalle.single[4], isNot(contains('\n')));
      expect(sinDetalle.single[4], conDetalle.single[4].split('\n').first);
      expect(sinDetalle.single[6], conDetalle.single[6]);
    });

    test('la primera columna va vacía: es la casilla para tildar el llamado', () {
      final data = PdfService.planillaMoraFilasTabla([fila(1, vencida: 100)]);
      expect(data.single.first, '');
      expect(PdfService.planillaMoraHeaders.first, '');
    });

    test('sin teléfono no rompe: queda la raya y el alumno sigue en la lista', () {
      final data = PdfService.planillaMoraFilasTabla([
        fila(1, vencida: 100, telefono: '   '),
      ]);
      expect(data.length, 1);
      expect(data.single[2], '—');
    });

    test('mora en cero se muestra como raya, no como \$0,00', () {
      final data = PdfService.planillaMoraFilasTabla([
        fila(1, noCobrada: 19400),
      ]);
      expect(data.single[4], '—');
      expect(data.single[5], isNot('—'));
    });
  });

  group('bloques de tabla', () {
    test('partir en bloques de 28 no pierde ni duplica filas', () {
      // Espeja el chunking del generador: un solo pw.Table muy largo puede
      // disparar TooManyPagesException, así que se parte — y partir es
      // exactamente donde se pierden filas si el índice está mal.
      const porBloque = 28;
      final data = PdfService.planillaMoraFilasTabla([
        for (var i = 0; i < 60; i++) fila(i, vencida: 1000.0 + i),
      ]);

      final rearmado = <List<String>>[];
      for (var i = 0; i < data.length; i += porBloque) {
        final fin = (i + porBloque) < data.length ? i + porBloque : data.length;
        rearmado.addAll(data.sublist(i, fin));
      }

      expect(rearmado.length, data.length);
      expect(rearmado.map((f) => f[1]).toList(), data.map((f) => f[1]).toList());
    });
  });
}
