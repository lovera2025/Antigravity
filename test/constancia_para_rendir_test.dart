// La constancia "ENTRADAS PARA RENDIR" (21-nov-2026,
// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 6, y la maqueta que
// aprobó el usuario): una A4 con dos copias de media hoja, PARA QUIEN LAS LLEVA
// arriba y PARA LA OFICINA abajo, cada una con firma y aclaración. Dice quién se
// las lleva, cuántas y qué números, **sin pulseras**, el precio fijo y lo que
// rinde si las vende todas. Reimpresa, también cómo está ahora.
//
// **Lo que no entra en una hoja no se dibuja, sin error**: por eso se mira que la
// última línea de cada copia (la aclaración) esté, y en su media hoja, también
// con un nombre largo, el contacto, una nota larga y dos tramos.
//
// Se arma con la letra de fábrica del paquete: con las de la app el texto va en
// códigos de glifo y no se puede leer. En un PDF el texto sale palabra por
// palabra: se busca cada palabra, no la frase.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/para_rendir_pdf.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import 'helpers/entradas_en_memoria.dart';
import 'helpers/leer_pdf.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

ParaRendir _cuenta(EntradasEnMemoria e) => ParaRendir.de(
      movimientos: e.listaParaRendir,
      ventas: e.listaVentas,
      anulaciones: e.listaAnulaciones,
    );

/// El jefe le da [numeros] a [persona], a $ 8.000 la anticipada (o a
/// $ 10.000 la general, con [nombrePrecio] "Entrada").
Future<(EntradasEnMemoria, MovimientoParaRendir)> _dar({
  String persona = 'PEREZ, JUAN',
  String? contacto,
  String? alumno,
  String? nota,
  List<TramoTalonario> numeros = const [TramoTalonario(1201, 1220)],
  String nombrePrecio = 'Entrada anticipada',
  double precio = 8000,
}) async {
  final e = EntradasEnMemoria();
  final dio = await e.darParaRendir(
    eventoId: _fiesta,
    personaNombre: persona,
    personaContacto: contacto,
    contratoAlumnoId: alumno,
    cantidad: numeros.fold(0, (s, t) => s + t.cantidad),
    numeros: numeros,
    precio: precio,
    nombrePrecio: nombrePrecio,
    nota: nota,
    quien: 'Jefe',
  );
  return (e, dio);
}

/// El día en que se reimprime, ya en el reloj de Argentina (como lo da
/// `hoyEnArgentinaProvider`): dos días después de que se las dieron.
final _el22 = DateTime.utc(2026, 11, 22, 12);

Future<Uint8List> _pdf(
  BloqueParaRendir b, {
  bool reimpresa = false,
  String? division,
}) =>
    ConstanciaParaRendirPdf.armar(DatosDeLaConstancia(
      bloque: b,
      fiesta: 'INSTITUTO SAN LORENZO',
      fechaFiesta: DateTime(2026, 12, 4),
      division: division,
      reimpresa: reimpresa,
      alDia: reimpresa ? _el22 : null,
    ));

List<String> _palabras(Uint8List bytes) => [for (final p in palabrasDelPdf(bytes)) p.texto];

String _texto(Uint8List bytes) => _palabras(bytes).join(' ');

/// Cuántas veces aparece [palabra].
int _veces(Uint8List bytes, String palabra) =>
    _palabras(bytes).where((p) => p == palabra).length;

/// Que cada palabra quede adentro de los márgenes de su media hoja (la de
/// arriba o la de abajo), y que las dos copias terminen con la aclaración.
void _cadaCopiaEnSuMediaHoja(Uint8List bytes) {
  final hoja = ConstanciaParaRendirPdf.hoja;
  final media = hoja.height / 2;
  const lados = ConstanciaParaRendirPdf.margenLados;
  const arriba = ConstanciaParaRendirPdf.margenArriba;
  const abajo = ConstanciaParaRendirPdf.margenAbajo;
  expect(paginasDelPdf(bytes), 1, reason: 'una sola hoja, con las dos copias');
  final palabras = palabrasDelPdf(bytes);
  expect(palabras, isNotEmpty);
  for (final p in palabras) {
    expect(p.x, greaterThanOrEqualTo(lados - 0.5),
        reason: '"${p.texto}" empieza antes del margen');
    expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - lados + 0.5),
        reason: '"${p.texto}" termina fuera de la hoja');
    // El PDF mide desde abajo: la copia de arriba va de la mitad para arriba.
    final deArriba = p.y > media;
    final piso = (deArriba ? media : 0) + abajo;
    final techo = (deArriba ? hoja.height : media) - arriba;
    expect(p.y, greaterThanOrEqualTo(piso - 0.5),
        reason: '"${p.texto}" queda debajo del margen de su media hoja');
    // Lo que sube la letra sobre su renglón (Helvetica: un 0,72 del cuerpo).
    expect(p.y + p.cuerpo * 0.7, lessThanOrEqualTo(techo + 0.5),
        reason: '"${p.texto}" queda arriba del margen de su media hoja');
  }
  // La última línea de cada copia, una en cada media hoja.
  final aclaraciones = palabras.where((p) => p.texto == 'Aclaración').toList();
  expect(aclaraciones, hasLength(2), reason: 'la aclaración de las dos copias');
  expect(aclaraciones.where((p) => p.y > media), hasLength(1));
  expect(aclaraciones.where((p) => p.y < media), hasLength(1));
  // Y lo de cada copia, en su media hoja: PARA QUIEN LAS LLEVA arriba.
  final lleva = palabras.firstWhere((p) => p.texto == 'LLEVA');
  final oficina = palabras.firstWhere((p) => p.texto == 'OFICINA');
  expect(lleva.y, greaterThan(media));
  expect(oficina.y, lessThan(media));
}

void main() {
  test('la hoja es una A4 entera, con las dos copias de media hoja', () {
    final hoja = ConstanciaParaRendirPdf.hoja;
    expect(hoja.width, closeTo(595.28, 0.01));
    expect(hoja.height, closeTo(841.89, 0.01));
    expect(ConstanciaParaRendirPdf.copias, ['PARA QUIEN LAS LLEVA', 'PARA LA OFICINA']);
  });

  test('dice quién se las lleva, cuántas, los números, sin pulseras, el precio fijo y lo '
      'que rinde si las vende todas, con firma y aclaración en las dos copias', () async {
    final (e, dio) = await _dar(contacto: '351 555-0101');
    final b = _cuenta(e).bloque(dio.id)!;
    expect(ConstanciaParaRendirPdf.seLleva(b), 'PEREZ, JUAN (de afuera)');
    expect(ConstanciaParaRendirPdf.entradas(b),
        '20 anticipadas · del 1201 al 1220 · sin pulseras');
    expect(ConstanciaParaRendirPdf.precio(b),
        r'$ 8.000 cada una (precio del 20/11, queda fijo)');
    expect(ConstanciaParaRendirPdf.siLasVendeTodas(b), 160000,
        reason: 'el renglón de la rendición de las 20, como lo cobraría RENDIR');
    expect(ConstanciaParaRendirPdf.quienSeLasDio(b), 'Se las dio: Jefe · el 20/11/2026 12:00 hs');

    final bytes = await _pdf(b);
    _cadaCopiaEnSuMediaHoja(bytes);
    final texto = _texto(bytes);
    // Lo mismo en las dos copias.
    for (final dos in [
      'RENDIR', 'INSTITUTO', '04/12/2026',
      'Se', 'lleva:', 'Contacto:', '555-0101',
      'Entradas:', 'anticipadas', 'pulseras',
      'Precio:', '8.000', 'fijo)',
      'vende', '160.000', 'devuelve.', 'plata.',
      'Jefe', '20/11/2026',
      'Firma', 'Aclaración',
    ]) {
      expect(_veces(bytes, dos), greaterThanOrEqualTo(2), reason: '"$dos" en las dos copias');
    }
    expect(_veces(bytes, 'QUIEN'), 1);
    expect(_veces(bytes, 'OFICINA'), 1);
    expect(texto, contains('PEREZ, JUAN (de afuera)'));
    expect(texto, contains('20 anticipadas · del 1201 al 1220 · sin pulseras'));
    expect(texto, contains(r'$ 8.000 cada una (precio del 20/11, queda fijo)'));
    expect(texto, contains('Si las vende todas, rinde'));
    expect(texto, contains('Las que no venda, las devuelve. Rinde toda la plata.'));
    expect(texto, contains('Se las dio: Jefe · el 20/11/2026 12:00 hs'));
    expect(texto, contains('Firma de quien se las lleva'));
    // Recién dadas: ni REIMPRESA ni "Hoy".
    expect(_palabras(bytes), isNot(contains('REIMPRESA')));
    expect(_palabras(bytes), isNot(contains('Hoy:')));
    expect(_palabras(bytes), isNot(contains('Hoy,')));
  });

  test('con un nombre largo, el contacto, una nota larga y dos tramos no se pierde nada, '
      'y cada copia queda en su media hoja', () async {
    final notaLarga = List.filled(30, 'se las lleva para venderlas en el club').join(' ');
    final (e, dio) = await _dar(
      persona: 'FERNANDEZ DE LA FUENTE ALVARENGA, MARIA DE LOS ANGELES GUADALUPE',
      contacto: 'Tel 351 555-0101 · DNI 30.111.222 · la mama atiende a la tarde',
      nota: notaLarga,
      numeros: const [TramoTalonario(1201, 1210), TramoTalonario(1301, 1310)],
    );
    final b = _cuenta(e).bloque(dio.id)!;
    expect(ConstanciaParaRendirPdf.nota(b)!.length,
        lessThanOrEqualTo(ConstanciaParaRendirPdf.kLargoDeLaNota + 3));
    expect(ConstanciaParaRendirPdf.nota(b), endsWith('...'), reason: 'se ve que se cortó');
    final bytes = await _pdf(b, reimpresa: true);
    _cadaCopiaEnSuMediaHoja(bytes);
    for (final dos in ['GUADALUPE', 'tarde', 'Nota:', '1210', '1301', '1310', 'pulseras']) {
      expect(_veces(bytes, dos), greaterThanOrEqualTo(2), reason: '"$dos" en las dos copias');
    }
    expect(_texto(bytes), contains('del 1201 al 1210 y 1301 al 1310 · sin pulseras'));
  });

  // 22-nov-2026 (revisión de la etapa 6): "Hoy:" iba sin fecha, y la única de la
  // hoja es la de cuando se las dieron: reimpresa días después, se leía como de
  // ese día. Ahora va "Hoy, 22/11:", con el día de la copia.
  test('reimpresa dice REIMPRESA y cómo está ahora, con el día de la copia: vendió, '
      'devolvió, no volvieron y le quedan', () async {
    final (e, dio) = await _dar();
    final caja = await e.abrirCaja(eventoId: _fiesta, operadorNombre: 'Carla');
    await e.rendir(
      caja: caja,
      bloque: dio,
      vendidas: 15,
      devueltas: 3,
      numerosDevueltos: const [TramoTalonario(1216, 1218)],
      efectivo: 120000,
      quien: 'Carla',
    );
    await e.noVolvieron(
      dio,
      cantidad: 1,
      numeros: const [TramoTalonario(1219, 1219)],
      motivo: 'la perdio',
      quien: 'Jefe',
    );
    final b = _cuenta(e).bloque(dio.id)!;
    expect(ConstanciaParaRendirPdf.comoEstaHoy(b),
        'vendió 15 · devolvió 3 · no volvieron 1 · le quedan 1');
    expect(ConstanciaParaRendirPdf.rotuloDeHoy(_el22), 'Hoy, 22/11');
    final bytes = await _pdf(b, reimpresa: true);
    _cadaCopiaEnSuMediaHoja(bytes);
    expect(_veces(bytes, 'REIMPRESA'), 2);
    expect(_veces(bytes, 'Hoy,'), 2);
    expect(_veces(bytes, '22/11:'), 2, reason: 'el día de la copia, en las dos');
    expect(_palabras(bytes), isNot(contains('Hoy:')), reason: 'ningún "Hoy" sin fecha');
    expect(_texto(bytes),
        contains('Hoy, 22/11: vendió 15 · devolvió 3 · no volvieron 1 · le quedan 1'));
    // Una reimpresa sin el día no se arma: volvería el "Hoy" sin fecha.
    expect(
      () => DatosDeLaConstancia(bloque: b, fiesta: 'X', reimpresa: true),
      throwsA(isA<AssertionError>()),
    );

    // Recién dadas no hay nada que contar.
    final (otra, dio2) = await _dar();
    expect(ConstanciaParaRendirPdf.comoEstaHoy(_cuenta(otra).bloque(dio2.id)!), isNull);
  });

  test('un alumno de la fiesta lleva su división; la general dice "generales"; una sola, '
      'en singular', () async {
    final (e, dio) = await _dar(
      persona: 'GOMEZ, ANA',
      alumno: 'c0000000-0000-4000-8000-000000000001',
      nombrePrecio: 'Entrada',
      precio: 10000,
    );
    final b = _cuenta(e).bloque(dio.id)!;
    expect(ConstanciaParaRendirPdf.seLleva(b, division: '5° A'),
        'GOMEZ, ANA (alumno de la fiesta, 5° A)');
    expect(ConstanciaParaRendirPdf.seLleva(b), 'GOMEZ, ANA (alumno de la fiesta)');
    expect(ConstanciaParaRendirPdf.entradas(b), startsWith('20 generales · del 1201'));
    final bytes = await _pdf(b, division: '5° A');
    expect(_texto(bytes), contains('GOMEZ, ANA (alumno de la fiesta, 5° A)'));
    expect(_texto(bytes), contains('20 generales'));

    final (una, dioUna) = await _dar(numeros: const [TramoTalonario(1500, 1500)]);
    final bUna = _cuenta(una).bloque(dioUna.id)!;
    expect(ConstanciaParaRendirPdf.entradas(bUna), '1 anticipada · del 1500 · sin pulseras');
    final bytesUna = await _pdf(bUna);
    _cadaCopiaEnSuMediaHoja(bytesUna);
    expect(_texto(bytesUna), contains('Si la vende, rinde'));
    expect(_texto(bytesUna), contains('Si no la vende, la devuelve. Rinde toda la plata.'));
  });

  test('el archivo se llama por quién se las lleva y su primer número', () async {
    final (e, dio) = await _dar();
    expect(
      ConstanciaParaRendirPdf.nombreDelArchivo(DatosDeLaConstancia(
        bloque: _cuenta(e).bloque(dio.id)!,
        fiesta: 'X',
      )),
      'Constancia_para_rendir_PEREZ_JUAN_1201.pdf',
    );
  });
}
