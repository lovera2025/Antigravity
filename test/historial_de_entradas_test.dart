// El historial de ventas de entradas (VENTAS, sección 8 del spec del 13-nov):
// cada venta con su anulación y su "Pago verificado", el filtro, los totales y
// los números repetidos. Sin pantalla; y el PDF, medido y leído.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/entradas/cuentas/historial_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/models/entradas_retiro.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/leer_pdf.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// Dos cajas (Carla y Maxi) con cuatro ventas: una verificada, una anulada.
class _Noche {
  final entradas = EntradasEnMemoria();
  late CajaEntradas carla, maxi;
  late VentaEntradas v1, v2, v3, v4;

  Future<VentaEntradas> _vender(
    CajaEntradas caja,
    String comprador, {
    int sueltas = 2,
    MedioBarra medio = MedioBarra.efectivo,
    String? numeros,
  }) =>
      entradas.vender(
        caja: caja,
        compradorNombre: comprador,
        renglones: [
          RenglonEntradas.suelta(
              nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
        ],
        medio: medio,
        efectivo: medio == MedioBarra.efectivo ? 10000.0 * sueltas : 0,
        transferencia: medio == MedioBarra.transferencia ? 10000.0 * sueltas : 0,
        numeros: numeros,
        quien: caja.operadorNombre!,
      );

  Future<void> armar() async {
    carla = await entradas.abrirCaja(
        eventoId: _fiesta, operadorId: 'carla', operadorNombre: 'Carla');
    maxi = await entradas.abrirCaja(
        eventoId: _fiesta, operadorId: 'maxi', operadorNombre: 'Maxi');
    v1 = await _vender(carla, 'PEREZ, ANA', numeros: '100-101');
    v2 = await _vender(carla, 'RUIZ, MARTA',
        sueltas: 4, medio: MedioBarra.transferencia, numeros: '200-203');
    v3 = await _vender(maxi, 'SOSA, DIEGO', sueltas: 1);
    v4 = await _vender(maxi, 'LEDESMA, JUAN', numeros: '203-204');
    await entradas.verificar(v1, verificado: true, quien: 'Jefe');
    await entradas.anular(v3,
        motivo: 'se equivoco de persona', devueltas: true, quien: 'Jefe');
  }

  Future<HistorialDeEntradas> historial({String? caja}) async =>
      HistorialDeEntradas.de(
        cajas: await entradas.cajas(_fiesta),
        ventas: await entradas.ventas(_fiesta),
        anulaciones: await entradas.anulaciones(_fiesta),
        verificaciones: await entradas.verificaciones(_fiesta),
        soloDeLaCaja: caja,
      );
}

void main() {
  // Para leer las letras de la app (Outfit) de los assets.
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Noche n;

  setUp(() async {
    n = _Noche();
    await n.armar();
  });

  group('el historial', () {
    test('el jefe ve todas las de la fiesta, de la más nueva a la más vieja', () async {
      final h = await n.historial();
      expect([for (final v in h.ventas) v.venta.compradorNombre],
          ['LEDESMA, JUAN', 'SOSA, DIEGO', 'RUIZ, MARTA', 'PEREZ, ANA']);
      expect(h.ventas.last.caja?.operadorNombre, 'Carla');
      expect(h.ventas.first.vendio, 'Maxi');
    });

    test('quien vende ve solo las de su caja, con sus cuentas', () async {
      final h = await n.historial(caja: n.carla.id);
      expect([for (final v in h.ventas) v.venta.compradorNombre],
          ['RUIZ, MARTA', 'PEREZ, ANA']);
      expect(h.totales.ventas, 2);
      expect(h.totales.efectivo, 20000);
      expect(h.totales.transferencia, 40000);
      expect(h.totales.anuladas, 0, reason: 'la anulada es de la otra caja');
    });

    test('cada venta sabe si está anulada y si tiene el pago verificado', () async {
      final h = await n.historial();
      final por = {for (final v in h.ventas) v.venta.compradorNombre: v};
      expect(por['PEREZ, ANA']!.verificada, isTrue);
      expect(por['RUIZ, MARTA']!.verificada, isFalse);
      expect(por['SOSA, DIEGO']!.anulada, isTrue);
      expect(por['SOSA, DIEGO']!.anulacion!.motivo, 'se equivoco de persona');
      expect(h.verificadas, 1);
      expect(h.sinVerificar, 2, reason: 'la anulada no espera verificación');
    });

    test('destildar deja la venta sin verificar; una anulada no cuenta como verificada',
        () async {
      await n.entradas.verificar(n.v1, verificado: false, quien: 'Jefe');
      await n.entradas.verificar(n.v3, verificado: true, quien: 'Jefe');
      final h = await n.historial();
      expect(h.verificadas, 0);
      expect(h.sinVerificar, 3);
      expect(n.entradas.listaVerificaciones, hasLength(2),
          reason: 'tildar y destildar actualiza la misma fila: no se borra');
    });

    test('el filtro: todas, verificadas y sin verificar', () async {
      final h = await n.historial();
      List<String> con(FiltroDeVentas f) =>
          [for (final v in h.con(f)) v.venta.compradorNombre];
      expect(con(FiltroDeVentas.todas), hasLength(4));
      expect(con(FiltroDeVentas.verificadas), ['PEREZ, ANA']);
      expect(con(FiltroDeVentas.sinVerificar), ['LEDESMA, JUAN', 'RUIZ, MARTA']);
    });

    test('los totales de la fiesta no cuentan la anulada', () async {
      final t = (await n.historial()).totales;
      expect(t.ventas, 3);
      expect(t.anuladas, 1);
      expect(t.entradas, 8);
      expect(t.efectivo, 40000);
      expect(t.transferencia, 40000);
      expect(t.total, 80000);
    });

    test('los números repetidos se buscan en toda la fiesta, aunque se mire una caja',
        () async {
      // El 203 está en la venta de Carla y en la de Maxi.
      final deCarla = await n.historial(caja: n.carla.id);
      expect([for (final r in deCarla.repetidos) r.texto],
          ['El 203 está en dos ventas (RUIZ, MARTA y LEDESMA, JUAN): revisar.']);
      final deTodos = await n.historial();
      expect(deTodos.repetidos, hasLength(1));
    });

    // Hasta la 6.9.2 esto avisaba "El 100 está en una venta (PEREZ, ANA) y en
    // una entrega (ALUMNO, UNO)". Cambió a propósito el 20-nov: lo vendido es
    // el talonario de las anticipadas y lo entregado, el de las generales.
    test('el número que está en una venta y en una entrega no es un repetido', () async {
      final h = HistorialDeEntradas.de(
        cajas: await n.entradas.cajas(_fiesta),
        ventas: [n.v1],
        anulaciones: const [],
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(95, 100)],
        },
      );
      expect(h.repetidos, isEmpty);
    });

    test('el número que está en dos entregas se avisa aparte, después de los de las ventas',
        () async {
      final h = HistorialDeEntradas.de(
        cajas: await n.entradas.cajas(_fiesta),
        ventas: await n.entradas.ventas(_fiesta),
        anulaciones: await n.entradas.anulaciones(_fiesta),
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(95, 100)],
          'ALUMNO, DOS': [TramoTalonario(100, 106)],
        },
      );
      expect([for (final r in h.repetidosDeLaVenta) r.texto],
          ['El 203 está en dos ventas (RUIZ, MARTA y LEDESMA, JUAN): revisar.']);
      expect([for (final r in h.repetidosDeLaEntrega) r.texto],
          ['El 100 está en dos entregas (ALUMNO, UNO y ALUMNO, DOS): revisar.']);
      expect([for (final r in h.repetidos) r.numero], [203, 100],
          reason: 'lo que se muestra: primero las ventas, después las entregas');
    });

    test('sin ventas da todo en cero', () {
      final h = HistorialDeEntradas.de(
        cajas: const [],
        ventas: const [],
        anulaciones: const [],
      );
      expect(h.ventas, isEmpty);
      expect(h.totales.ventas, 0);
      expect(h.repetidos, isEmpty);
    });
  });

  group('el historial impreso', () {
    Future<Uint8List> pdf(HistorialDeEntradas h) => HistorialEntradasPdf.armar(
          DatosDelHistorial(
            historial: h,
            fiesta: 'INSTITUTO SAN LORENZO',
            fechaFiesta: DateTime(2026, 12, 4),
            alcance: 'Todas las cajas',
            emitido: DateTime.utc(2026, 11, 21, 13),
          ),
        );

    test('es A4, y nada se sale de la hoja', () async {
      final bytes = await pdf(await n.historial());
      expect(paginasDelPdf(bytes), 1);
      final hoja = HistorialEntradasPdf.hoja;
      expect(hoja.width, closeTo(PdfPageFormat.a4.width, 0.01));
      for (final p in palabrasDelPdf(bytes)) {
        expect(p.x, greaterThanOrEqualTo(hoja.marginLeft - 0.5),
            reason: '"${p.texto}" empieza antes del margen');
        expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - hoja.marginRight + 0.5),
            reason: '"${p.texto}" termina fuera de la hoja');
        expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
            reason: '"${p.texto}" cae debajo del margen de abajo');
      }
    });

    test('trae todas las ventas, las anuladas con su motivo, y los totales', () async {
      final palabras = {
        for (final p in palabrasDelPdf(await pdf(await n.historial()))) p.texto,
      };
      for (final esperada in [
        'INSTITUTO', 'HISTORIAL', 'ENTRADAS', '04/12/2026',
        'PEREZ,', 'RUIZ,', 'SOSA,', 'LEDESMA,',
        'Carla', 'Maxi', 'Efectivo', 'Transf.',
        'Anul.', 'ANULADA', 'equivoco', 'devolvieron',
        '80.000', 'verificado', 'revisar.',
      ]) {
        expect(palabras, contains(esperada), reason: 'falta "$esperada"');
      }
    });

    test('los números repetidos en dos entregas también salen en el papel', () async {
      final h = HistorialDeEntradas.de(
        cajas: await n.entradas.cajas(_fiesta),
        ventas: await n.entradas.ventas(_fiesta),
        anulaciones: await n.entradas.anulaciones(_fiesta),
        entregados: const {
          'ALUMNO, UNO': [TramoTalonario(95, 100)],
          'ALUMNO, DOS': [TramoTalonario(100, 106)],
        },
      );
      final palabras = [for (final p in palabrasDelPdf(await pdf(h))) p.texto];
      expect(palabras.where((p) => p == 'revisar.').length, 2,
          reason: 'el de las ventas y el de las entregas');
      expect(palabras, contains('entregas'));
      expect(palabras, contains('DOS):'));
    });

    // Con un recargo, lo vendido y lo cobrado no dan lo mismo: así se ve que
    // cada monto va en el renglón de su rótulo y no el de al lado.
    test('cada total va en su renglón: lo vendido sin recargos, lo cobrado con ellos',
        () async {
      await n.entradas.vender(
        caja: n.carla,
        compradorNombre: 'DIAZ, LUCIA',
        renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 1),
        ],
        medio: MedioBarra.transferencia,
        transferencia: 11000,
        recargo: 1000,
        recargoPct: 10,
        quien: 'Carla',
      );
      final t = (await n.historial()).totales;
      expect(t.vendido, 90000);
      expect(t.total, 91000);
      final palabras = palabrasDelPdf(await pdf(await n.historial()));
      Set<String> renglonDe(String rotulo) {
        final y = palabras.lastWhere((p) => p.texto == rotulo).y;
        return {
          for (final p in palabras)
            if ((p.y - y).abs() < 2) p.texto,
        };
      }

      expect(renglonDe('cobrado'), contains('91.000'));
      expect(renglonDe('cobrado'), isNot(contains('90.000')));
      expect(renglonDe('vendidas:'), contains('90.000'));
      expect(renglonDe('recargos)'), contains('51.000'));
      expect(renglonDe('Recargos'), contains('1.000'));
    });

    test('en la tabla, cuándo va en un renglón: día, mes y hora de Argentina', () {
      expect(HistorialEntradasPdf.cuandoEnLaTabla('2026-11-21T13:05:00Z'), '21/11 10:05');
      expect(HistorialEntradasPdf.cuandoEnLaTabla('2026-12-05T01:30:00Z'), '04/12 22:30');
      expect(HistorialEntradasPdf.cuandoEnLaTabla(''), '');
    });

    // Quien vende cuenta su caja a ciegas: su papel no trae las sumas de plata
    // (revisión del 14-nov). El monto de cada venta sí.
    test('el de quien vende va sin las sumas de plata', () async {
      final bytes = await HistorialEntradasPdf.armar(
        DatosDelHistorial(
          historial: await n.historial(caja: n.carla.id),
          fiesta: 'INSTITUTO SAN LORENZO',
          alcance: 'La caja de Carla',
          emitido: DateTime.utc(2026, 11, 21, 13),
          conPlata: false,
        ),
      );
      final palabras = {for (final p in palabrasDelPdf(bytes)) p.texto};
      expect(palabras, containsAll(['vendidas:', 'verificado', 'PEREZ,', '20.000']));
      for (final no in ['cobrado', 'recargos)', '60.000']) {
        expect(palabras, isNot(contains(no)), reason: 'no tiene que estar "$no"');
      }
    });

    test('con muchas ventas se parte en hojas, sin perder ninguna', () async {
      for (var i = 0; i < 90; i++) {
        await n._vender(n.carla, 'COMPRADOR NUMERO$i', sueltas: 1);
      }
      final bytes = await pdf(await n.historial());
      expect(paginasDelPdf(bytes), greaterThan(1));
      final palabras = {for (final p in palabrasDelPdf(bytes)) p.texto};
      expect(palabras, contains('NUMERO0'));
      expect(palabras, contains('NUMERO89'));
      expect(palabras, contains('Hoja'));
    });

    test('sin ventas lo dice', () async {
      final vacio = HistorialDeEntradas.de(
        cajas: const [],
        ventas: const [],
        anulaciones: const [],
      );
      final palabras = {for (final p in palabrasDelPdf(await pdf(vacio))) p.texto};
      expect(palabras, contains('ventas.'));
    });
  });

  // La forma C que eligió el usuario el 15-nov: un renglón por venta, y otro
  // solo si hay algo que explicar; por hojas cuando son muchas.
  group('la forma C', () {
    DatosDelHistorial datos(HistorialDeEntradas h, {Map<String, String> familias = const {}}) =>
        DatosDelHistorial(
          historial: h,
          fiesta: 'INSTITUTO SAN LORENZO',
          fechaFiesta: DateTime(2026, 12, 4),
          alcance: 'Todas las cajas',
          emitido: DateTime.utc(2026, 11, 21, 13),
          familias: familias,
        );

    RenglonEntradas anticipadas(int n) =>
        RenglonEntradas.suelta(nombre: 'Entrada anticipada', precioLista: 8000, cantidad: n);
    RenglonEntradas lugar(int n) => RenglonEntradas.lugar(
        nombre: 'Entrada de lugar adicional (50 %)', precioLista: 10000, descuentoPct: 50, cantidad: n);

    Future<VentaEntradas> vender(
      String comprador,
      List<RenglonEntradas> renglones, {
      MedioBarra medio = MedioBarra.efectivo,
      double? efectivo,
      double transferencia = 0,
      String? familia,
      String? numeros,
    }) {
      final total = renglones.fold<double>(0, (s, r) => s + r.subtotal);
      return n.entradas.vender(
        caja: n.carla,
        contratoAlumnoId: familia,
        compradorNombre: comprador,
        renglones: renglones,
        medio: medio,
        efectivo: efectivo ?? (medio == MedioBarra.efectivo ? total : 0),
        transferencia: transferencia,
        numeros: numeros,
        quien: 'Carla',
      );
    }

    test('qué entradas, corto: el lugar dice lo que paga del valor', () async {
      Future<String> corto(List<RenglonEntradas> r) async {
        final v = await vender('X', r, familia: 'f');
        return HistorialEntradasPdf.entradasCorto(v);
      }

      expect(await corto([anticipadas(2)]), '2 anticip.');
      expect(await corto([lugar(3)]), '3 lugar 50 %');
      expect(await corto([anticipadas(1), lugar(2)]), '1 anticip. + 2 lugar');
      expect(
        await corto([RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 1)]),
        '1 entrada',
      );
    });

    test('el segundo renglón, solo cuando hay algo que explicar', () async {
      await vender('MIXTO, MARIA', [anticipadas(2)],
          medio: MedioBarra.mixto, efectivo: 10000, transferencia: 6000);
      await vender('CORTO, ANA', [lugar(2)], familia: 'f1');
      await vender('CON UN NOMBRE BASTANTE LARGO, MARIA JOSEFINA', [lugar(2)], familia: 'f2');
      final filas = HistorialEntradasPdf.filas(datos(
        await n.historial(),
        familias: {
          'f1': 'CORTO, JUAN m.12',
          'f2': 'OTRO NOMBRE TAMBIEN LARGO, JUAN CARLOS m.40-41',
        },
      ));
      FilaDelHistorial de(String comprador) =>
          filas.firstWhere((f) => f.venta.venta.compradorNombre == comprador);

      expect(de('PEREZ, ANA').abajo, isNull, reason: 'una venta común: un renglón');
      expect(de('PEREZ, ANA').renglonesAbajo, 0);
      expect(de('MIXTO, MARIA').abajo, r'efectivo $ 10.000 + transf. $ 6.000');
      expect(de('CORTO, ANA').familia, 'CORTO, JUAN m.12');
      expect(de('CORTO, ANA').abajo, isNull);
      final larga = de('CON UN NOMBRE BASTANTE LARGO, MARIA JOSEFINA');
      expect(larga.familia, isNull, reason: 'no entra arriba');
      expect(
        larga.abajo,
        startsWith('CON UN NOMBRE BASTANTE LARGO, MARIA JOSEFINA · fam. OTRO NOMBRE'),
        reason: 'el nombre que no entra arriba va entero abajo, y la familia después',
      );
      expect(de('SOSA, DIEGO').abajo, contains('ANULADA por Jefe'));
      expect(de('SOSA, DIEGO').abajo, contains('se equivoco de persona'));
      // Sin pulseras (22-nov-2026): la pulsera no se vende.
      expect(de('SOSA, DIEGO').abajo, contains('devolvieron las entradas'));
      expect(de('SOSA, DIEGO').abajo, isNot(contains('pulsera')));
    });

    // Un talonario partido no entra en su columna: la columna dice "abajo" y
    // los números van enteros en el segundo renglón.
    test('el talonario largo va abajo, entero', () async {
      await vender('DIAZ, LUCIA', [anticipadas(4)], numeros: '3001-3002, 9001-9002');
      final d = datos(await n.historial());
      final fila = HistorialEntradasPdf.filas(d)
          .firstWhere((f) => f.venta.venta.compradorNombre == 'DIAZ, LUCIA');
      expect(fila.abajo, contains('talonario 3001-3002, 9001-9002'));
      final textos = {for (final p in palabrasDelPdf(await HistorialEntradasPdf.armar(d))) p.texto};
      expect(textos, containsAll(['abajo', '9001-9002']));
    });

    // Lo que no entra en un segundo renglón ocupa dos, y no se pierde nada.
    test('un segundo renglón largo ocupa dos, sin perder palabras', () async {
      final v = await vender(
        'CON UN NOMBRE BASTANTE LARGO, MARIA JOSEFINA',
        [anticipadas(1), lugar(2)],
        familia: 'f3',
        numeros: '4001, 9101-9102',
      );
      await n.entradas.anular(
        v,
        motivo: 'la familia pidio la devolucion porque pago dos veces, se hizo el reintegro',
        devueltas: false,
        quien: 'Jefe',
      );
      final d = datos(
        await n.historial(),
        familias: {'f3': 'OTRO NOMBRE TAMBIEN LARGO, JUAN CARLOS m.40-41'},
      );
      final fila = HistorialEntradasPdf.filas(d).firstWhere((f) => f.venta.venta.id == v.id);
      expect(fila.abajo!.length, greaterThan(140), reason: 'no entra en un renglón');
      expect(fila.renglonesAbajo, greaterThanOrEqualTo(2));
      final textos = {for (final p in palabrasDelPdf(await HistorialEntradasPdf.armar(d))) p.texto};
      for (final palabra in ['JOSEFINA', 'm.40-41', '9101-9102', 'ANULADA', 'reintegro', 'NO']) {
        expect(textos, contains(palabra), reason: 'falta "$palabra"');
      }
    });

    test('lo que no entra en ENTRADAS ni en VEND. va entero abajo', () async {
      final v = await n.entradas.vender(
        caja: await n.entradas.abrirCaja(
          eventoId: _fiesta,
          operadorId: 'flor',
          operadorNombre: 'Florencia Belén',
        ),
        contratoAlumnoId: 'f9',
        compradorNombre: 'PRUEBA, ANA',
        renglones: [
          RenglonEntradas.suelta(nombre: 'Entrada anticipada', precioLista: 8000, cantidad: 2),
          lugar(8),
          RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 3),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 86000,
        quien: 'Florencia Belén',
      );
      final fila = HistorialEntradasPdf.filas(datos(await n.historial()))
          .firstWhere((f) => f.venta.venta.id == v.id);
      expect(fila.entradas, '13 en total');
      expect(fila.abajo, contains('2 anticip. + 8 lugar + 3 entradas'));
      expect(fila.abajo, contains('vendió Florencia Belén'));
    });

    test('un nombre que no entra arriba va entero abajo', () async {
      const largo = 'GONZALEZ FERNANDEZ DE LA FUENTE, MARIA DE LOS ANGELES';
      await vender(largo, [anticipadas(1)]);
      final d = datos(await n.historial());
      final fila = HistorialEntradasPdf.filas(d)
          .firstWhere((f) => f.venta.venta.compradorNombre == largo);
      expect(fila.abajo, largo);
      expect(fila.renglonesAbajo, 1);
    });

    // Las medidas del papel son fijas (así se sabe qué va en cada hoja), y se
    // miden acá con las letras de la app: Outfit tiene los números de distinto
    // ancho, y con la columna angosta el "0004" salía "000" (la muestra del
    // 15-nov). El PDF con Outfit no se puede leer palabra por palabra, así que
    // se mide con la letra misma.
    test('con las letras de la app, lo de cada columna entra entero', () async {
      final f = (await PdfService.fuentesOutfit())!;
      final contexto = pw.Context(document: PdfDocument());
      final regular = f.$1.getFont(contexto);
      final negrita = f.$2.getFont(contexto);
      double ancho(PdfFont letra, String texto, double tam) =>
          letra.stringMetrics(texto).advanceWidth * tam;
      const relleno = 5.0; // 2,5 a cada lado de la celda
      const v = HistorialEntradasPdf.letraVenta;
      const a = HistorialEntradasPdf.anchos;

      for (final c in '0123456789'.split('')) {
        expect(ancho(regular, c * 4, v), lessThanOrEqualTo(a.numero - relleno),
            reason: 'el N° ${c * 4}');
      }
      for (final (titulo, columna) in [
        ('N°', a.numero),
        ('CUÁNDO', a.cuando),
        ('ENTRADAS', a.entradas),
        ('TALONARIO', a.talonario),
        ('TOTAL', a.total),
        ('PAGÓ', a.pago),
        ('VEND.', a.vendio),
        ('VERIF', a.verif),
      ]) {
        expect(ancho(negrita, titulo, 7.2), lessThanOrEqualTo(columna - relleno),
            reason: 'el título $titulo');
      }
      // CUÁNDO: el día, el mes, la hora y los minutos más anchos que existen
      // (los ceros y los ochos son las cifras más anchas; revisión del 15-nov).
      // Sin kerning, el ancho es la suma de las partes.
      double elMasAncho(Iterable<int> numeros) => numeros
          .map((x) => ancho(regular, x.toString().padLeft(2, '0'), v))
          .reduce((a, b) => a > b ? a : b);
      final cuando = elMasAncho([for (var i = 1; i <= 31; i++) i]) +
          ancho(regular, '/', v) +
          elMasAncho([for (var i = 1; i <= 12; i++) i]) +
          ancho(regular, ' ', v) +
          elMasAncho([for (var i = 0; i <= 23; i++) i]) +
          ancho(regular, ':', v) +
          elMasAncho([for (var i = 0; i <= 59; i++) i]);
      expect(cuando, lessThanOrEqualTo(a.cuando - relleno), reason: 'el CUÁNDO más ancho');
      // ENTRADAS: todo lo que va en la columna (hasta letrasEntradas letras), de
      // 1 a 16 lugares y de 0 a 16 sueltas, entradas o anticipadas.
      for (var l = 1; l <= 16; l++) {
        for (var s = 0; s <= 16; s++) {
          for (final suelta in ['entradas', 'anticip.']) {
            final texto = s == 0
                ? '$l lugar 50 %'
                : '$l lugar + $s ${s == 1 && suelta == 'entradas' ? 'entrada' : suelta}';
            if (texto.length > HistorialEntradasPdf.letrasEntradas) continue;
            expect(ancho(regular, texto, v), lessThanOrEqualTo(a.entradas - relleno),
                reason: texto);
          }
        }
      }
      expect(ancho(regular, '128 en total', v), lessThanOrEqualTo(a.entradas - relleno));
      final talonario = '8888-8888, 88'.substring(0, HistorialEntradasPdf.letrasTalonario);
      expect(ancho(regular, talonario, v), lessThanOrEqualTo(a.talonario - relleno),
          reason: 'el talonario más largo que va en su columna');
      expect(ancho(negrita, r'$ 1.000.000', v), lessThanOrEqualTo(a.total - relleno));
      expect(ancho(regular, 'Efectivo', v), lessThanOrEqualTo(a.pago - relleno));
      // VEND.: el nombre más largo que va en la columna (más, va entero abajo).
      for (final quien in ['Maximiliano', 'Juan Carlos', 'Valentina']) {
        expect(quien.length, lessThanOrEqualTo(HistorialEntradasPdf.letrasVendio));
        expect(ancho(regular, quien, v), lessThanOrEqualTo(a.vendio - relleno), reason: quien);
      }

      // El comprador más largo que va entero arriba, en negrita: un nombre con
      // muchas M, las letras más anchas.
      final nombre = 'ACEBO DOMINGUEZ, MARIA MERCEDES'
          .substring(0, HistorialEntradasPdf.letrasComprador);
      expect(ancho(negrita, nombre, v),
          lessThanOrEqualTo(HistorialEntradasPdf.anchoComprador - relleno), reason: nombre);
      // Y el comprador con su familia, lo más largo que va arriba.
      const comprador = 'MENDOZA, MARIA';
      final familia = 'ACEBO, EMMA m.12-13'
          .substring(0, HistorialEntradasPdf.letrasArriba - 8 - comprador.length);
      expect(
        ancho(negrita, comprador, v) + ancho(regular, ' · fam. $familia', v),
        lessThanOrEqualTo(HistorialEntradasPdf.anchoComprador - relleno),
        reason: '$comprador · fam. $familia',
      );

      // Lo más largo que va en un solo renglón de abajo (letra de 7), con
      // mayúsculas, que son las más anchas.
      const abajo = 'ACEBO DOMINGUEZ DE LA FUENTE, MARIA MERCEDES · fam. MAMANI '
          'ACEBO, MAXIMO MARTIN m.12-13 · talonario 3001-3004, 9001-9004 · efectivo';
      expect(
        ancho(regular, abajo.substring(0, HistorialEntradasPdf.letrasAbajo), 7.0),
        lessThanOrEqualTo(HistorialEntradasPdf.anchoAbajo),
      );

      // Los signos que usa el papel están en la letra (si no, no se dibujan).
      for (final signo in '—·°ÁÉÍÓÚÑ\$%'.runes) {
        expect(regular.isRuneSupported(signo), isTrue, reason: String.fromCharCode(signo));
      }
    });

    // Los totales van después de la última venta si entran; si no, en una hoja
    // más. Nunca se salen por abajo, haya las ventas que haya.
    test('los totales nunca se salen de la hoja', () async {
      final hoja = HistorialEntradasPdf.hoja;
      for (var i = 0; i < 70; i++) {
        await vender('COMPRADOR NUMERO$i', [anticipadas(1)]);
        if (i < 40) continue;
        final d = datos(await n.historial());
        final bytes = await HistorialEntradasPdf.armar(d);
        expect(paginasDelPdf(bytes), HistorialEntradasPdf.hojas(d));
        final palabras = palabrasDelPdf(bytes);
        for (final p in palabras) {
          expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
              reason: 'con ${i + 5} ventas, "${p.texto}" se sale por abajo');
        }
        // Una hoja que no entra no se dibuja entera: lo que sobra no aparece.
        for (final rotulo in ['cobrado', 'verificado']) {
          expect(palabras.where((p) => p.texto == rotulo).length, 1,
              reason: 'con ${i + 5} ventas, "$rotulo" tiene que estar una vez');
        }
      }
    });

    // Revisión del 15-nov: con muchos números repetidos los totales no entraban
    // ni en una hoja sola, y lo que sobra de una hoja no se dibuja.
    test('con muchos números repetidos, los totales siguen en otra hoja y no se pierde ninguno',
        () async {
      for (var i = 0; i < 60; i++) {
        await vender('PRIMERO$i', [anticipadas(1)], numeros: '${7000 + i}');
        await vender('SEGUNDO$i', [anticipadas(1)], numeros: '${7000 + i}');
      }
      final d = datos(await n.historial());
      final repetidos = d.historial.repetidos.length;
      expect(repetidos, greaterThanOrEqualTo(60));
      final paginas = HistorialEntradasPdf.paginar(d);
      expect(paginas.where((p) => p.conTotales).length, greaterThan(1),
          reason: 'los totales siguen en otra hoja');
      final bytes = await HistorialEntradasPdf.armar(d);
      expect(paginasDelPdf(bytes), paginas.length);
      final palabras = palabrasDelPdf(bytes);
      final hoja = HistorialEntradasPdf.hoja;
      for (final p in palabras) {
        expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
            reason: '"${p.texto}" se sale por abajo');
      }
      expect(palabras.where((p) => p.texto == 'revisar.').length, repetidos,
          reason: 'cada número repetido, una vez');
      expect(palabras.where((p) => p.texto == 'cobrado').length, 1);
      expect(
        palabras.where((p) => p.texto == 'Hoja').length,
        paginas.length,
        reason: 'el pie de cada hoja',
      );
    });

    test('1.000 entradas: unas 8 hojas, ninguna venta afuera ni repetida, nada se sale de la hoja',
        () async {
      var entradas = 0;
      for (var i = 0; entradas < 1000; i++) {
        final r = switch (i % 4) {
          0 => [lugar(4)],
          1 => [anticipadas(2)],
          2 => [anticipadas(1), lugar(2)],
          _ => [anticipadas(3)],
        };
        entradas += r.fold(0, (s, x) => s + x.cantidad);
        final total = r.fold<double>(0, (s, x) => s + x.subtotal);
        await vender(
          'COMPRADOR NUMERO$i',
          r,
          medio: i % 9 == 0 ? MedioBarra.mixto : MedioBarra.efectivo,
          efectivo: i % 9 == 0 ? 5000 : null,
          transferencia: i % 9 == 0 ? total - 5000 : 0,
          familia: i.isEven ? 'f$i' : null,
          numeros: '${3000 + i * 4}-${3000 + i * 4 + 3}',
        );
      }
      final d = datos(
        await n.historial(),
        familias: {for (var i = 0; i < 400; i += 2) 'f$i': 'FAMILIA NUMERO$i m.${10 + i % 50}'},
      );
      final hojas = HistorialEntradasPdf.hojas(d);
      expect(hojas, inInclusiveRange(7, 10), reason: 'unas 40 ventas por hoja');
      final bytes = await HistorialEntradasPdf.armar(d);
      expect(paginasDelPdf(bytes), hojas);
      final palabras = palabrasDelPdf(bytes);
      final hoja = HistorialEntradasPdf.hoja;
      for (final p in palabras) {
        expect(p.y, greaterThanOrEqualTo(hoja.marginBottom - 0.5),
            reason: '"${p.texto}" se sale por abajo');
        expect(p.x + p.ancho, lessThanOrEqualTo(hoja.width - hoja.marginRight + 0.5),
            reason: '"${p.texto}" se sale por la derecha');
      }
      final textos = [for (final p in palabras) p.texto];
      for (var i = 0; i < d.historial.ventas.length - 4; i++) {
        expect(textos.where((t) => t == 'NUMERO$i').length, greaterThanOrEqualTo(1),
            reason: 'NUMERO$i');
      }
      expect(textos.where((t) => t == 'cobrado').length, 1, reason: 'los totales, una vez');
    });

    test('por hojas: solo las del tramo, con la numeración del papel entero', () async {
      for (var i = 0; i < 150; i++) {
        await vender('COMPRADOR NUMERO$i', [anticipadas(1)]);
      }
      final d = datos(await n.historial());
      final total = HistorialEntradasPdf.hojas(d);
      expect(total, greaterThanOrEqualTo(4));
      final bytes = await HistorialEntradasPdf.armar(d.soloLasHojas(2, 3));
      expect(paginasDelPdf(bytes), 2);
      final textos = [for (final p in palabrasDelPdf(bytes)) p.texto];
      final numeros = {
        for (var i = 0; i < textos.length - 1; i++)
          if (textos[i] == 'Hoja') textos[i + 1],
      };
      expect(numeros, {'2', '3'});
      expect(textos, contains('$total'), reason: '"Hoja 2 de $total"');
      expect(textos, isNot(contains('cobrado')), reason: 'los totales van en la última');
      expect(textos, isNot(contains('NUMERO0')), reason: 'la primera hoja no sale');
      expect(
        HistorialEntradasPdf.nombreDelArchivo(d.soloLasHojas(2, 3)),
        'Ventas_de_entradas_INSTITUTO_SAN_LORENZO_hojas_2_a_3.pdf',
      );
    });
  });

}
