// El comprobante de una rendición de entradas para rendir (21-nov-2026,
// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 6, regla 59): el mismo
// recibo de media hoja de una venta (desde el 22-nov-2026, con la forma del
// "RECIBO DE PAGO" de las cuotas), de quien rinde, con "Rendición de entradas
// para rendir" en el concepto, quién recibió la plata, quién rinde y cómo quedó
// lo que se llevó. **No habla de pulseras**: la pulsera no se vende. Y una
// venta común tampoco.
//
// Se arma con la letra de fábrica del paquete: con las de la app el texto va en
// códigos de glifo y no se puede leer. **En un PDF el texto sale palabra por
// palabra: para comprobar que algo no está se busca cada palabra.**
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/recibo_de_entradas_pdf.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import 'helpers/entradas_en_memoria.dart';
import 'helpers/leer_pdf.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// El día en que se reimprime, ya en el reloj de Argentina (como lo da
/// `hoyEnArgentinaProvider`): dos días después de la rendición.
final _el22 = DateTime.utc(2026, 11, 22, 12);

/// El jefe le da 20 a PEREZ, JUAN (1201 al 1220) a $ 8.000, y Carla le cobra
/// 15 en su caja; él devuelve del 1216 al 1220.
class _Rendida {
  final EntradasEnMemoria entradas;
  final MovimientoParaRendir dio;
  final VentaEntradas venta;
  _Rendida(this.entradas, this.dio, this.venta);

  ParaRendir get cuenta => ParaRendir.de(
        movimientos: entradas.listaParaRendir,
        ventas: entradas.listaVentas,
        anulaciones: entradas.listaAnulaciones,
      );

  BloqueParaRendir get bloque => cuenta.bloque(dio.id)!;
}

Future<_Rendida> _rendida({String persona = 'PEREZ, JUAN'}) async {
  final e = EntradasEnMemoria();
  final caja = await e.abrirCaja(eventoId: _fiesta, operadorNombre: 'Carla');
  final dio = await e.darParaRendir(
    eventoId: _fiesta,
    personaNombre: persona,
    cantidad: 20,
    numeros: const [TramoTalonario(1201, 1220)],
    precio: 8000,
    nombrePrecio: 'Entrada anticipada',
    quien: 'Jefe',
  );
  final r = await e.rendir(
    caja: caja,
    bloque: dio,
    vendidas: 15,
    devueltas: 5,
    numerosDevueltos: const [TramoTalonario(1216, 1220)],
    efectivo: 120000,
    recibe: 130000,
    quien: 'Carla',
  );
  return _Rendida(e, dio, r.venta!);
}

Future<Uint8List> _pdf(
  VentaEntradas venta, {
  RendicionDelComprobante? rendicion,
  bool copia = false,
  AnulacionEntradas? anulacion,
}) =>
    ComprobanteEntradasPdf.armar(DatosDelComprobante(
      venta: venta,
      fiesta: 'INSTITUTO SAN LORENZO',
      fechaFiesta: DateTime(2026, 12, 4),
      copia: copia,
      anulacion: anulacion,
      rendicion: rendicion,
    ));

Set<String> _palabras(Uint8List bytes) =>
    {for (final p in palabrasDelPdf(bytes)) p.texto};

/// Todo lo que escribe, palabra por palabra y separado por un espacio.
String _texto(Uint8List bytes) => palabrasDelPdf(bytes).map((p) => p.texto).join(' ');

/// Ninguna palabra dice "pulsera" (ni "Pulseras", ni "pulseras,").
void _sinPulseras(Uint8List bytes) {
  for (final p in palabrasDelPdf(bytes)) {
    expect(p.texto.toLowerCase(), isNot(contains('pulsera')),
        reason: 'el papel dice "${p.texto}": la pulsera no se vende');
  }
}

void main() {
  // Para leer las letras de la app (Outfit) y el logo de los assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('es el recibo de quien rinde: dice Rendición, quién recibió, quién rinde y cómo '
      'quedó lo que se llevó, sin pulseras', () async {
    final r = await _rendida();
    final rendicion = RendicionDelComprobante.alRendir(
      persona: r.bloque.persona,
      bloque: r.bloque,
      devolvio: 5,
      numerosDevueltos: const [TramoTalonario(1216, 1220)],
    );
    expect(ComprobanteEntradasPdf.lineaDeLaRendicion(rendicion, r.venta.cantidad),
        'Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 · devolvió 5 (1216 al 1220) · '
        'le quedan 0');

    final bytes = await _pdf(r.venta, rendicion: rendicion);
    expect(paginasDelPdf(bytes), 1);
    expect(altoDeLaHoja(bytes), closeTo(ReciboDeEntradasPdf.mediaA4, 0.5));
    final palabras = _palabras(bytes);
    for (final esperada in [
      'RECIBO', 'PAGO', '0001', 'Rendición',
      'Recibió:', 'Carla', 'Rinde:', 'PEREZ,', 'JUAN',
      'TOTAL', '120.000', 'Efectivo', 'Vuelto', '10.000',
    ]) {
      expect(palabras, contains(esperada), reason: 'falta "$esperada"');
    }
    final texto = _texto(bytes);
    // Con la forma del recibo de las cuotas: de quién, la suma, el concepto.
    for (final frase in [
      'RECIBO DE PAGO',
      'Recibí de: PEREZ, JUAN',
      'La suma de pesos: CIENTO VEINTE MIL PESOS',
      'Concepto: Rendición de entradas para rendir · INSTITUTO SAN LORENZO · fiesta '
          '04/12/2026',
      r'TOTAL DE ESTE RECIBO $ 120.000',
      'Medio de pago: Efectivo',
      r'Entregó $ 130.000 · Vuelto $ 10.000',
      'Rinde: PEREZ, JUAN · Recibió: Carla',
    ]) {
      expect(texto, contains(frase), reason: 'falta "$frase"');
    }
    expect(texto,
        contains('Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 · devolvió 5 (1216 al '
            '1220) · le quedan 0'));
    expect(texto, contains('Entrada anticipada · para rendir'));
    expect(texto, contains('precio fijo'));
    // Ni "Vendió:" (es "Recibió"), ni "Compra" (es "Rinde"), ni COMPROBANTE.
    expect(palabras, isNot(contains('Vendió:')));
    expect(palabras, isNot(contains('Compra')));
    expect(palabras, isNot(contains('COMPROBANTE')));
    // Los números son los del bloque: la venta no los lleva.
    expect(palabras, isNot(contains('talonario')));
    expect(palabras, isNot(contains('Talonario:')));
    _sinPulseras(bytes);
  });

  // Lo que se imprime sale con Outfit, que mide distinto que la letra de
  // fábrica: una rendición tiene que entrar en media hoja con la letra de verdad.
  test('con las letras de la app y el logo, la rendición, recién rendida y anulada, '
      'entra justo en media hoja', () async {
    final fuentes = (await PdfService.fuentesOutfit())!;
    final logo = await isotipoDeLosPapeles();
    final r = await _rendida(persona: 'FERNANDEZ DE LA FUENTE, MARIA DE LOS ANGELES');
    final recien = DatosDelComprobante(
      venta: r.venta,
      fiesta: 'INSTITUTO SAN LORENZO',
      fechaFiesta: DateTime(2026, 12, 4),
      rendicion: RendicionDelComprobante.alRendir(
        persona: r.bloque.persona,
        bloque: r.bloque,
        devolvio: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
      ),
    );
    final anulacion = await r.entradas.anular(
      r.venta,
      motivo: 'se cobro dos veces',
      devueltas: false,
      quien: 'Jefe',
    );
    final anulada = DatosDelComprobante(
      venta: r.venta,
      fiesta: 'INSTITUTO SAN LORENZO',
      fechaFiesta: DateTime(2026, 12, 4),
      copia: true,
      anulacion: anulacion,
      rendicion: RendicionDelComprobante.reimpresa(
        persona: r.bloque.persona,
        bloque: r.bloque,
        alDia: _el22,
      ),
    );
    for (final d in [recien, anulada]) {
      final bytes = await ComprobanteEntradasPdf.armar(d, fuentes: fuentes, logo: logo);
      expect(paginasDelPdf(bytes), 1);
      expect(altoDeLaHoja(bytes), closeTo(ReciboDeEntradasPdf.mediaA4, 0.5));
    }
  });

  // 22-nov-2026 (revisión de la etapa 6): la copia decía "hoy le quedan 0" y la
  // única fecha de la hoja es la de la rendición: reimpresa días después, ese
  // "hoy" se leía como el día de la rendición. Ahora lleva el día de la copia.
  test('reimpresa dice solo lo seguro: lo vendido en esta rendición y lo que le queda '
      'el día de la copia, con la fecha, sin lo devuelto en ese acto', () async {
    final r = await _rendida();
    final rendicion = RendicionDelComprobante.reimpresa(
      persona: r.bloque.persona,
      bloque: r.bloque,
      alDia: _el22,
    );
    expect(rendicion.leQuedanDeHoy, isTrue);
    expect(ComprobanteEntradasPdf.lineaDeLaRendicion(rendicion, r.venta.cantidad),
        'Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 en esta rendición · al 22/11 le '
        'quedan 0');
    final bytes = await _pdf(r.venta, rendicion: rendicion, copia: true);
    final palabras = _palabras(bytes);
    expect(palabras, contains('COPIA'));
    expect(palabras, contains('Rendición'));
    expect(palabras, isNot(contains('devolvió')));
    expect(_texto(bytes), contains('al 22/11 le quedan 0'));
    // Ningún "hoy" suelto, sin fecha.
    expect(palabras, isNot(contains('hoy')));
    _sinPulseras(bytes);
  });

  test('si el bloque todavía no bajó a este equipo, sale con Recibió, Rinde y lo vendido, '
      'sin el renglón del bloque', () async {
    final r = await _rendida();
    final rendicion = RendicionDelComprobante.reimpresa(persona: 'PEREZ, JUAN', alDia: _el22);
    expect(ComprobanteEntradasPdf.lineaDeLaRendicion(rendicion, 15), isNull);
    final bytes = await _pdf(r.venta, rendicion: rendicion, copia: true);
    final palabras = _palabras(bytes);
    for (final esperada in ['Rendición', 'Recibió:', 'Carla', 'Rinde:', 'PEREZ,', 'TOTAL']) {
      expect(palabras, contains(esperada), reason: 'falta "$esperada"');
    }
    expect(palabras, isNot(contains('llevó')), reason: 'sin el bloque no se inventa');
    expect(_texto(bytes), contains('15 × Entrada anticipada · para rendir'));
    _sinPulseras(bytes);
  });

  // Regla 48: una rendición anulada no "devolvió las entradas" a la oficina:
  // dejaron de contar como vendidas y vuelven a quedar a cargo de quien las llevó.
  test('una rendición anulada va con ANULADA y dice que dejaron de contar como vendidas, '
      'nunca "devolvieron las entradas"', () async {
    final r = await _rendida();
    final anulacion = await r.entradas.anular(
      r.venta,
      motivo: 'se cobro dos veces',
      devueltas: false,
      quien: 'Jefe',
    );
    final bytes = await _pdf(
      r.venta,
      rendicion: RendicionDelComprobante.reimpresa(
        persona: 'PEREZ, JUAN',
        bloque: r.bloque,
        alDia: _el22,
      ),
      copia: true,
      anulacion: anulacion,
    );
    expect(paginasDelPdf(bytes), 1);
    final palabras = _palabras(bytes);
    expect(palabras, contains('ANULADA'));
    expect(palabras, contains('cobro'));
    expect(_texto(bytes), contains('las 15 dejaron de contar como vendidas'));
    expect(palabras, isNot(contains('devolvieron')));
    expect(palabras, isNot(contains('NO')));
    // Anulada, le vuelven a quedar 15 para rendir: es lo del día de la copia.
    expect(_texto(bytes), contains('al 22/11 le quedan 15'));
    _sinPulseras(bytes);
  });

  test('con un nombre largo nada se sale de la media hoja', () async {
    final r = await _rendida(
      persona: 'FERNANDEZ DE LA FUENTE ALVARENGA, MARIA DE LOS ANGELES GUADALUPE',
    );
    final ancho = PdfPageFormat.a4.width;
    const costado = ReciboDeEntradasPdf.costado;
    final bytes = await _pdf(
      r.venta,
      rendicion: RendicionDelComprobante.alRendir(
        persona: r.bloque.persona,
        bloque: r.bloque,
        devolvio: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
      ),
    );
    expect(paginasDelPdf(bytes), 1);
    final alto = altoDeLaHoja(bytes);
    expect(alto, closeTo(ReciboDeEntradasPdf.mediaA4, 0.5));
    final palabras = palabrasDelPdf(bytes);
    expect(palabras.map((p) => p.texto), contains('GUADALUPE'));
    expect(palabras.map((p) => p.texto), contains('quedan'),
        reason: 'el renglón del bloque, entero');
    for (final p in palabras) {
      expect(p.x, greaterThanOrEqualTo(costado - 0.5),
          reason: '"${p.texto}" empieza antes del margen');
      expect(p.x + p.ancho, lessThanOrEqualTo(ancho - costado + 0.5),
          reason: '"${p.texto}" termina fuera de la hoja');
      expect(p.y, greaterThanOrEqualTo(0), reason: '"${p.texto}" se sale por abajo');
      expect(p.y, lessThanOrEqualTo(alto), reason: '"${p.texto}" se sale por arriba');
    }
  });

  test('el archivo de una rendición se llama así', () async {
    final r = await _rendida();
    expect(
      ComprobanteEntradasPdf.nombreDelArchivo(DatosDelComprobante(
        venta: r.venta,
        fiesta: 'X',
        rendicion: RendicionDelComprobante.reimpresa(persona: 'PEREZ, JUAN', alDia: _el22),
      )),
      'Rendicion_0001_PEREZ_JUAN.pdf',
    );
  });

  // La pulsera no se vende (el usuario, 20-nov-2026): una venta común tampoco
  // habla de pulseras, ni al anularla.
  test('una venta común ya no dice "Pulseras": dice cuántas entradas', () async {
    final e = EntradasEnMemoria();
    final caja = await e.abrirCaja(eventoId: _fiesta, operadorNombre: 'Romi');
    final venta = await e.vender(
      caja: caja,
      compradorNombre: 'GOMEZ, CARLA',
      renglones: [RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 3)],
      medio: MedioBarra.efectivo,
      efectivo: 30000,
      numeros: '1043-1045',
      quien: 'Romi',
    );
    final bytes = await _pdf(venta);
    final palabras = _palabras(bytes);
    expect(palabras, contains('RECIBO'));
    expect(palabras, contains('Entradas'));
    expect(palabras, contains('Talonario:'));
    expect(_texto(bytes), contains('3 entradas · Talonario: 1043 al 1045'));
    expect(palabras, isNot(contains('Rendición')));
    expect(palabras, isNot(contains('Rinde:')));
    _sinPulseras(bytes);

    final anulacion = await e.anular(
      venta,
      motivo: 'se equivoco',
      devueltas: true,
      quien: 'Jefe',
    );
    final anulada = await _pdf(venta, copia: true, anulacion: anulacion);
    expect(_texto(anulada), contains('devolvieron las entradas'));
    _sinPulseras(anulada);
  });
}
