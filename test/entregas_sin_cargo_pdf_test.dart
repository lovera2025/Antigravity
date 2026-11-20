// El papel de la caja de entregas (IMPRIMIR en Cierre de caja → ENTRADAS,
// 20-nov-2026): lo entregado sin cargo, por quién, en A4. Armado con la letra
// de fábrica para poder leer cada palabra (`palabrasDelPdf`).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/entregas_sin_cargo_pdf.dart';
import 'package:arguello_events/features/eventos/services/caja_de_entregas.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import 'helpers/leer_pdf.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

ContratoAlumno _alumno(int i) => ContratoAlumno(
      id: 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      eventoId: _evento,
      nombreAlumno: 'APELLIDO$i, NOMBRE',
      cantidadAcompanantes: 2,
      nombresAcompanantes: const ['MAMÁ', 'PAPÁ'],
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([10 + i]),
      createdAt: DateTime(2026, 2, 1),
    );

DateTime _h(int minutos) => DateTime.utc(2026, 11, 20, 13).add(Duration(minutes: minutos));

EntregaEntradas _entrega(ContratoAlumno a, ParteEntrega parte, int minuto, String quien) =>
    EntregaEntradas.entrega(
      contratoAlumnoId: a.id,
      eventoId: _evento,
      parte: parte,
      cantidad: parte == ParteEntrega.pulseras ? 3 : 5,
      tramos: parte == ParteEntrega.generales
          ? [TramoTalonario(5000 + minuto * 10, 5004 + minuto * 10)]
          : const [],
      parentesco: ParentescoRetiro.madre,
      nombre: 'MADRE, UNA',
      escribioEnPlanilla: true,
      hechoPor: quien,
      deviceId: 'tablet-1',
      ahora: _h(minuto),
    );

CajaDeEntregas _caja(int familias) {
  final alumnos = [for (var i = 1; i <= familias; i++) _alumno(i)];
  final renglones = <EntregaEntradas>[];
  for (final (i, a) in alumnos.indexed) {
    renglones.add(_entrega(a, ParteEntrega.pulseras, i * 2, i.isEven ? 'Carla' : 'Maxi'));
    renglones.add(_entrega(a, ParteEntrega.generales, i * 2 + 1, i.isEven ? 'Carla' : 'Maxi'));
  }
  if (alumnos.isNotEmpty) renglones.add(EntregaEntradas.anulacion(
    contratoAlumnoId: alumnos.first.id,
    eventoId: _evento,
    parte: ParteEntrega.generales,
    cantidad: 0,
    motivo: 'se anotaron mal',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: _h(500),
  ));
  return CajaDeEntregas.de(
    alumnos: alumnos,
    todos: alumnos,
    retiros: const {},
    renglones: renglones,
  );
}

Future<List<PalabraDelPdf>> _palabras(CajaDeEntregas caja, {String? soloDe}) async =>
    palabrasDelPdf(await EntregasSinCargoPdf.construir(
      caja: caja,
      fiesta: 'PUERTO VIEJO',
      fechaFiesta: DateTime(2026, 12, 4),
      soloDe: soloDe,
      generada: DateTime.utc(2026, 11, 20, 18),
    ));

void main() {
  test('dice la fiesta, cuánto se dio de lo que tiene que llegar, quién entregó y '
      'cada entrega, con la anulada marcada', () async {
    final palabras = await _palabras(_caja(4));
    final textos = {for (final p in palabras) p.texto};
    for (final w in ['Entregas', 'sin', 'cargo', 'PUERTO', 'VIEJO', '04/12/2026',
        'Carla', 'Maxi', 'APELLIDO1,', 'ANULADA', 'Jefe:', 'mal', 'Pulseras', 'Generales']) {
      expect(textos, contains(w), reason: w);
    }
    // Pulseras 12 de 12; generales: la anulada no cuenta.
    expect(palabras.map((p) => p.texto).join(' '), contains('Pulseras VIP 12 de 12'));
    expect(palabras.map((p) => p.texto).join(' '), contains('Generales 15 de 20'));
    // Sin plata.
    expect(textos.any((t) => t.contains(r'$')), isFalse);
  });

  test('nada se sale de la hoja ni del margen', () async {
    final palabras = await _palabras(_caja(6));
    final derecha = PdfPageFormat.a4.width - 20 + 1;
    for (final p in palabras) {
      expect(p.x + p.ancho, lessThanOrEqualTo(derecha), reason: '"${p.texto}" se sale');
      expect(p.x, greaterThanOrEqualTo(19), reason: '"${p.texto}" se sale por la izquierda');
    }
  });

  test('solo lo de una persona: la otra no aparece', () async {
    final palabras = await _palabras(_caja(4), soloDe: 'Carla');
    final textos = {for (final p in palabras) p.texto};
    expect(textos, contains('Carla'));
    expect(textos, isNot(contains('Maxi')));
  });

  test('con muchas entregas se parte en varias hojas y no pierde ninguna', () async {
    final caja = _caja(120);
    final bytes = await EntregasSinCargoPdf.construir(
      caja: caja,
      fiesta: 'PUERTO VIEJO',
      generada: DateTime.utc(2026, 11, 20, 18),
    );
    expect(paginasDelPdf(bytes), greaterThan(2));
    final textos = [for (final p in palabrasDelPdf(bytes)) p.texto];
    for (final i in [1, 60, 120]) {
      expect(textos, contains('APELLIDO$i,'), reason: 'la familia $i');
    }
  });

  test('sin entregas lo dice', () async {
    final palabras = await _palabras(_caja(0));
    expect(palabras.map((p) => p.texto).join(' '),
        contains('Todavía no se entregó nada sin cargo'));
  });
}
