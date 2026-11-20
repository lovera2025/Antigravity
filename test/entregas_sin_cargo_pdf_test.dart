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

  // ── Los arreglos de la revisión independiente del 20-nov-2026 ──────────────

  test('7. la entrega que se volvió a dar no sale como válida: dice por qué no cuenta', () async {
    final a = _alumno(1);
    final caja = CajaDeEntregas.de(alumnos: [a], todos: [a], retiros: const {}, renglones: [
      _entrega(a, ParteEntrega.generales, 0, 'Carla'),
      _entrega(a, ParteEntrega.generales, 5, 'Sofi'),
    ]);
    final texto = (await _palabras(caja)).map((p) => p.texto).join(' ');
    expect(texto, contains('NO CUENTA: se volvió a entregar el 20/11/2026 10:05 hs por Sofi'));
    expect(texto, contains('Carla · 0 pulseras · 0 generales · 0 familias · 1 que no cuenta'));
  });

  test('2. las 8 juntas partidas: la persona suma lo suyo y el papel dice qué no cuenta',
      () async {
    final a = _alumno(1);
    final caja = CajaDeEntregas.de(
      alumnos: [a],
      todos: [a],
      retiros: {a.id: _fila(a, entregadoAt: _h(0))},
      renglones: [_entrega(a, ParteEntrega.pulseras, 10, 'Carla')],
    );
    final texto = (await _palabras(caja)).map((p) => p.texto).join(' ');
    expect(texto, contains('Marta · 0 pulseras · 5 generales · 1 familia'));
    expect(texto,
        contains('Pulseras VIP: NO CUENTA: se volvió a entregar el 20/11/2026 10:10 hs por Carla'));
  });

  test('3. la anulación de una entrega anterior va al final del papel, y no en el de una sola '
      'persona', () async {
    final a = _alumno(1);
    final caja = CajaDeEntregas.de(
      alumnos: [a],
      todos: [a],
      retiros: {a.id: _fila(a, entregadoAt: _h(20), anuladoAt: _h(10))},
      renglones: const [],
    );
    final todo = (await _palabras(caja)).map((p) => p.texto).join(' ');
    expect(todo, contains('Anuladas 1'));
    expect(todo, contains('Anulaciones de una entrega anterior'));
    expect(todo, contains('Anulación de una entrega anterior, por Jefe: se equivocó de familia'));
    final suyo = (await _palabras(caja, soloDe: 'Marta')).map((p) => p.texto).join(' ');
    expect(suyo, isNot(contains('Anulaciones de una entrega anterior')));
  });

  test('4. lo de una familia hoy de baja va marcado, con la línea arriba', () async {
    final a = _alumno(1);
    final baja = ContratoAlumno(
      id: _alumno(2).id,
      eventoId: _evento,
      nombreAlumno: '[BAJA] APELLIDO2, NOMBRE',
      cantidadAcompanantes: 2,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas([12]),
      createdAt: DateTime(2026, 2, 1),
    );
    final caja = CajaDeEntregas.de(alumnos: [a], todos: [a, baja], retiros: const {}, renglones: [
      _entrega(baja, ParteEntrega.pulseras, 0, 'Carla'),
    ]);
    final texto = (await _palabras(caja)).map((p) => p.texto).join(' ');
    expect(texto, contains('APELLIDO2, NOMBRE (hoy de baja)'));
    expect(texto,
        contains('Incluye 3 pulseras de 1 familia hoy de baja (APELLIDO2, NOMBRE): arriba no cuentan.'));
  });

  test('8. "Impreso el" sale con la hora de Argentina (antes salía 3 horas antes)', () async {
    String enArgentina(DateTime instante) {
      final a = instante.toUtc().subtract(const Duration(hours: 3));
      String d(int n) => n.toString().padLeft(2, '0');
      return '${d(a.day)}/${d(a.month)}/${a.year} ${d(a.hour)}:${d(a.minute)} hs';
    }

    final antes = enArgentina(DateTime.now());
    final bytes = await EntregasSinCargoPdf.construir(caja: _caja(1), fiesta: 'PUERTO VIEJO');
    final despues = enArgentina(DateTime.now());
    final texto = palabrasDelPdf(bytes).map((p) => p.texto).join(' ');
    expect(
      texto.contains('Impreso el $antes') || texto.contains('Impreso el $despues'),
      isTrue,
      reason: 'esperaba "Impreso el $antes" en: ${texto.substring(0, 120)}',
    );
  });
}

/// La fila de una entrega de las 8 juntas hecha con una 6.9.x, por Marta.
EntradasRetiro _fila(ContratoAlumno a, {required DateTime entregadoAt, DateTime? anuladoAt}) =>
    EntradasRetiro(
      id: 'f${a.id.substring(1)}',
      contratoAlumnoId: a.id,
      estado: EstadoRetiro.entregado,
      vip: 3,
      generales: 5,
      tramos: const [TramoTalonario(1001, 1005)],
      menores10: 0,
      parentesco: ParentescoRetiro.padre,
      retiroNombre: 'PADRE, UNO',
      escribioEnPlanilla: true,
      entregadoPor: 'Marta',
      entregadoAt: entregadoAt,
      anuladoPor: anuladoAt == null ? null : 'Jefe',
      anuladoAt: anuladoAt,
      anuladoMotivo: anuladoAt == null ? null : 'se equivocó de familia',
      createdAt: entregadoAt,
      updatedAt: entregadoAt,
    );
