// PARA RENDIR, la pantalla del jefe de las entradas para rendir (21-nov-2026,
// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 5), montada de verdad
// con la venta y la entrega en memoria: la lista por persona con sus totales y
// avisos, DAR (a alguien de afuera o a un alumno, con los números obligatorios
// y el precio de hoy fijo), NO VOLVIERON y ANULAR. Reglas 46, 50 y 52.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart'
    show esRolJefeProvider;
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/pdf/para_rendir_pdf.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/widgets/para_rendir_screen.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

class _Montada {
  final EntregaEnMemoria e;
  final EntradasEnMemoria entradas;
  final ProviderContainer c;

  /// Cada constancia que se abrió (al DAR y con CONSTANCIA).
  final List<DatosDeLaConstancia> constancias;
  _Montada(this.e, this.entradas, this.c, this.constancias);

  ParaRendir get cuenta => ParaRendir.de(
        movimientos: entradas.listaParaRendir,
        ventas: entradas.listaVentas,
        anulaciones: entradas.listaAnulaciones,
      );

  MovimientoParaRendir bloqueDe(String persona) => entradas.listaParaRendir
      .firstWhere((m) => m.esDio && m.personaNombre == persona);
}

/// El jefe le da a [persona] [cantidad] desde [desde], a $ 8.000 la anticipada.
Future<MovimientoParaRendir> _dar(
  EntradasEnMemoria e,
  String persona,
  int desde,
  int cantidad, {
  String? alumno,
  String? contacto,
}) =>
    e.darParaRendir(
      eventoId: idFiestaEntrega,
      personaNombre: persona,
      personaContacto: contacto,
      contratoAlumnoId: alumno,
      cantidad: cantidad,
      numeros: [TramoTalonario(desde, desde + cantidad - 1)],
      precio: 8000,
      nombrePrecio: 'Entrada anticipada',
      quien: 'Jefe',
    );

/// Cuatro personas, como la maqueta: PÉREZ (20, nada rendido), GÓMEZ, ANA
/// (alumna: 10, rindió todo en dos veces), SOSA (15: vendió 8, devolvió 5 y 2
/// no volvieron) y NIEVA (10, nada rendido). Carla cobró en su caja.
Future<void> _cuatroPersonas(EntradasEnMemoria e) async {
  final caja = await e.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: 'carla',
    operadorNombre: 'Carla',
  );
  await _dar(e, 'PÉREZ, JUAN', 1201, 20, contacto: '351 555-0101');
  final gomez = await _dar(e, 'GÓMEZ, ANA', 1221, 10, alumno: EntregaEnMemoria.idGomez);
  await e.rendir(caja: caja, bloque: gomez, vendidas: 6, efectivo: 48000, quien: 'Carla');
  await e.rendir(caja: caja, bloque: gomez, vendidas: 4, efectivo: 32000, quien: 'Carla');
  final sosa = await _dar(e, 'SOSA, DIEGO', 1231, 15, contacto: 'DNI 30.111.222');
  await e.rendir(
    caja: caja,
    bloque: sosa,
    vendidas: 8,
    devueltas: 5,
    numerosDevueltos: const [TramoTalonario(1239, 1243)],
    efectivo: 64000,
    quien: 'Carla',
  );
  await e.noVolvieron(
    sosa,
    cantidad: 2,
    numeros: const [TramoTalonario(1244, 1245)],
    motivo: 'Dice que las perdió',
    quien: 'Jefe',
  );
  await _dar(e, 'NIEVA, CARLOS', 1246, 10);
}

/// [jefeAhora]: el modo jefe se lee de ahí cada vez (y se cambia con
/// `c.invalidate(esRolJefeProvider)`), para cerrarlo con una ventana abierta.
/// [hoy]: el reloj de Argentina, para que pase la medianoche en el medio.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool jefe = true,
  bool Function()? jefeAhora,
  DateTime Function()? hoy,
  bool conPrecio = true,
  bool fallaLaConstancia = false,
  Future<void> Function(EntradasEnMemoria)? antes,
  Size tamano = const Size(1100, 1400),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  final entradas = EntradasEnMemoria();
  final constancias = <DatosDeLaConstancia>[];
  if (conPrecio) {
    entradas.conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-28');
  }
  await antes?.call(entradas);
  entradas.escrituras = 0;
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: jefeAhora == null ? jefe : null),
    if (jefeAhora != null) esRolJefeProvider.overrideWith((ref) => jefeAhora()),
    ...entradas.reemplazos,
    hoyEnArgentinaProvider.overrideWithValue(hoy ?? () => DateTime.utc(2026, 11, 20, 12)),
    // La constancia no se abre de verdad: se anota (o falla, como sin impresora).
    abrirConstanciaParaRendirProvider.overrideWithValue((datos, {context}) async {
      if (fallaLaConstancia) throw StateError('sin impresora (prueba)');
      constancias.add(datos);
    }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: ParaRendirScreen(evento: fiestaDeLaEntrega)),
  ));
  await tester.pumpAndSettle();
  return _Montada(e, entradas, c, constancias);
}

String _texto(WidgetTester tester, String clave) {
  final t = tester.widget<Text>(find.byKey(Key(clave)));
  return t.data ?? t.textSpan!.toPlainText();
}

/// El texto de un chip (`ChipDeVender`).
String _chip(WidgetTester tester, String clave) => tester
    .widget<Text>(find.descendant(of: find.byKey(Key(clave)), matching: find.byType(Text)))
    .data!;

bool _apagado(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;

Future<void> _tocar(WidgetTester tester, String clave, {int veces = 1}) async {
  for (var i = 0; i < veces; i++) {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.pump();
    await tester.tap(find.byKey(Key(clave)));
    await tester.pumpAndSettle();
  }
}

Future<void> _poner(WidgetTester tester, String clave, String texto) async {
  await tester.ensureVisible(find.byKey(Key(clave)));
  await tester.pump();
  await tester.enterText(find.byKey(Key(clave)), texto);
  await tester.pump();
}

/// La clave con la que la lista agrupa a alguien de afuera.
String _deAfuera(String nombre) => 'afuera|$nombre';

void main() {
  group('quién la ve', () {
    // Regla 50: el botón de ENTRADAS ya llega apagado sin modo jefe; si igual
    // se llegara, la pantalla no muestra ni deja nada.
    testWidgets('sin modo jefe solo dice que es del jefe: ni lista ni DAR', (tester) async {
      final m = await _montar(tester, jefe: false, antes: _cuatroPersonas);
      expect(_texto(tester, 'para_rendir_sin_modo_jefe'), contains('solo del jefe'));
      expect(find.byKey(const Key('para_rendir_dar')), findsNothing);
      expect(find.textContaining('PÉREZ'), findsNothing);
      expect(m.entradas.escrituras, 0);
    });

    testWidgets('vacía lo dice', (tester) async {
      await _montar(tester);
      expect(_texto(tester, 'para_rendir_vacio'), 'Nadie tiene entradas para rendir.');
      expect(_texto(tester, 'para_rendir_total_sin_rendir'), '0');
      expect(find.byKey(const Key('para_rendir_dar')), findsOneWidget);
    });
  });

  group('la lista', () {
    testWidgets('por persona, primero quien tiene más sin rendir, con los totales y '
        '"faltan hasta"', (tester) async {
      await _montar(tester, antes: _cuatroPersonas);
      expect(_texto(tester, 'para_rendir_total_sin_rendir'), '30');
      expect(_texto(tester, 'para_rendir_total_falta'), r'$ 240.000');
      expect(_texto(tester, 'para_rendir_total_no_volvieron'), '2');
      expect(find.text(r'$ 16.000'), findsOneWidget, reason: 'lo que valían');
      expect(find.text('entradas · 2 personas'), findsOneWidget);

      final perez = _deAfuera('perez juan');
      final nieva = _deAfuera('nieva carlos');
      final sosa = _deAfuera('sosa diego');
      final gomez = 'alumno|${EntregaEnMemoria.idGomez}';
      double arriba(String clave) =>
          tester.getTopLeft(find.byKey(Key('para_rendir_persona_$clave'))).dy;
      expect(arriba(perez), lessThan(arriba(nieva)));
      expect(arriba(nieva), lessThan(arriba(sosa)));

      expect(_chip(tester, 'para_rendir_estado_$perez'), 'sin rendir 20');
      expect(_texto(tester, 'para_rendir_falta_$perez'), r'faltan hasta $ 160.000');
      expect(_texto(tester, 'para_rendir_linea_$perez'),
          r'se llevó 20 el vie 20/11 · del 1201 al 1220 · $ 8.000 c/u (entrada anticipada, fijo)');
      expect(_chip(tester, 'para_rendir_estado_$gomez'), '✓ rindió todo');
      expect(find.byKey(Key('para_rendir_falta_$gomez')), findsNothing);
      expect(find.text('alumno · 5° A'), findsOneWidget, reason: 'GÓMEZ, ANA es alumna');
      expect(_texto(tester, 'para_rendir_cuenta_$sosa'),
          'vendió 8 · devolvió 5 · no volvieron 2');
      expect(_chip(tester, 'para_rendir_estado_$sosa'), '✓ rindió todo');
    });

    testWidgets('tocando a una persona se ven sus bloques: lo que se llevó, lo que '
        'rindió y sus botones', (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('sosa diego')}');
      final sosa = m.bloqueDe('SOSA, DIEGO');
      expect(_texto(tester, 'para_rendir_dio_${sosa.id}'),
          'Se llevó 15 · del 1231 al 1245 · sin pulseras · DNI 30.111.222');
      final movs = m.entradas.listaParaRendir.where((x) => x.bloqueId == sosa.id).toList();
      final vendio = movs.firstWhere((x) => x.esVendio);
      final devolvio = movs.firstWhere((x) => x.esDevolvio);
      final perdidas = movs.firstWhere((x) => x.esNoVolvieron);
      expect(_texto(tester, 'para_rendir_mov_${vendio.id}'), r'Vendió 8 · $ 64.000 · venta N° 0003');
      expect(_texto(tester, 'para_rendir_mov_${devolvio.id}'), 'Devolvió 5 · del 1239 al 1243');
      expect(_texto(tester, 'para_rendir_mov_${perdidas.id}'),
          'No volvieron 2 · del 1244 al 1245 · "Dice que las perdió"');
      // Lo vendido se anula en VENTAS; lo devuelto y lo perdido, acá.
      expect(find.byKey(Key('para_rendir_anular_${vendio.id}')), findsNothing);
      expect(find.byKey(Key('para_rendir_anular_${devolvio.id}')), findsOneWidget);
      expect(find.byKey(Key('para_rendir_anular_${perdidas.id}')), findsOneWidget);
      // El bloque con algo rendido no se anula entero, y lo dice.
      expect(_apagado(tester, 'para_rendir_anular_${sosa.id}'), isTrue);
      expect(_texto(tester, 'para_rendir_anular_motivo_${sosa.id}'),
          'Ya rindió algo: anulá cada movimiento (la plata, en VENTAS)');
      expect(_apagado(tester, 'para_rendir_no_volvieron_${sosa.id}'), isTrue,
          reason: 'no le queda nada');
      // CONSTANCIA: la del bloque, reimpresa, con cómo está ahora. No escribe.
      expect(find.text('CONSTANCIA'), findsOneWidget);
      expect(_apagado(tester, 'para_rendir_constancia_${sosa.id}'), isFalse);
      await _tocar(tester, 'para_rendir_constancia_${sosa.id}');
      final constancia = m.constancias.single;
      expect(constancia.reimpresa, isTrue);
      expect(constancia.bloque.id, sosa.id);
      expect(constancia.bloque.persona, 'SOSA, DIEGO');
      expect([constancia.bloque.vendidas, constancia.bloque.devueltas, constancia.bloque.noVolvieron],
          [8, 5, 2]);
      expect(constancia.fiesta, isNotEmpty);
      expect(constancia.fechaFiesta, fiestaDeLaEntrega.fechaEvento);
      // Con el día en que se saca (22-nov-2026): "Hoy, 20/11: vendió 8 · …".
      expect(constancia.alDia, DateTime.utc(2026, 11, 20, 12));
      expect(ConstanciaParaRendirPdf.rotuloDeHoy(constancia.alDia), 'Hoy, 20/11');
      expect(m.entradas.escrituras, 0, reason: 'la constancia no escribe nada');
    });

    testWidgets('la constancia de un alumno lleva su división', (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      final gomez = m.bloqueDe('GÓMEZ, ANA');
      await _tocar(tester, 'para_rendir_persona_alumno|${EntregaEnMemoria.idGomez}');
      await _tocar(tester, 'para_rendir_constancia_${gomez.id}');
      expect(m.constancias.single.division, '5° A');
      expect(m.constancias.single.bloque.esDeUnAlumno, isTrue);
    });

    testWidgets('si la constancia no se puede abrir, lo dice', (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas, fallaLaConstancia: true);
      final perez = m.bloqueDe('PÉREZ, JUAN');
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('perez juan')}');
      await _tocar(tester, 'para_rendir_constancia_${perez.id}');
      expect(find.text('No se pudo abrir la constancia. Probá de nuevo.'), findsOneWidget);
    });

    // Regla 49: dos equipos que rindieron lo mismo sin internet. Se avisa,
    // no se esconde.
    testWidgets('si alguien rindió de más, se avisa arriba y en su renglón', (tester) async {
      await _montar(tester, antes: (e) async {
        final caja = await e.abrirCaja(eventoId: idFiestaEntrega, operadorNombre: 'Carla');
        final dio = await _dar(e, 'RUIZ, MARTA', 1264, 2);
        // Dos rendiciones de las dos, desde dos equipos que no se vieron.
        for (var i = 0; i < 2; i++) {
          e.listaParaRendir.add(MovimientoParaRendir.vendio(
            dio,
            cantidad: 2,
            ventaId: 'venta-de-otro-equipo-$i',
            cajaEntradasId: caja.id,
            ahora: e.reloj(),
          ));
        }
      });
      final ruiz = _deAfuera('ruiz marta');
      expect(_chip(tester, 'para_rendir_estado_$ruiz'), 'rindió de más: revisar');
      expect(_texto(tester, 'para_rendir_aviso_0'), contains('rindió de más, revisar'));
    });
  });

  group('DAR ENTRADAS PARA RENDIR', () {
    // Regla 46: los números son obligatorios, no pisan una venta ni otro
    // bloque, y quien es de afuera lleva nombre y apellido.
    testWidgets('a alguien de afuera: el precio de hoy fijo, sin pulseras, los números '
        'obligatorios y sin pisar; confirma y aparece en la lista', (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      await _tocar(tester, 'para_rendir_dar');
      expect(_texto(tester, 'dar_precio_texto'),
          r'A $ 8.000 cada una · Entrada anticipada · el precio de hoy (PRECIOS), queda fijo');
      expect(_texto(tester, 'dar_sin_pulseras'),
          'Se lleva solo las entradas: sin pulseras. Rinde toda la plata.');
      expect(find.byType(Checkbox), findsNothing, reason: 'sin casilla de pulseras');
      expect(_texto(tester, 'dar_error'), 'Escribí nombre y apellido de quien se las lleva.');
      await _poner(tester, 'dar_nombre', 'lopez');
      expect(_texto(tester, 'dar_error'), 'Escribí nombre y apellido de quien se las lleva.');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      expect(_texto(tester, 'dar_error'),
          'Escribí el primer número del talonario: son obligatorios.');
      expect(_apagado(tester, 'dar_dar'), isTrue);
      await _poner(tester, 'dar_del', '1205');
      expect(_texto(tester, 'dar_error'),
          'El 1205 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1220).');
      // El 1239 lo devolvió SOSA: está libre. Pero del 1244 al 1245 no volvieron.
      await _poner(tester, 'dar_del', '1236');
      expect(_texto(tester, 'dar_error'), startsWith('El 1236 ya se le dio a SOSA, DIEGO'));
      await _poner(tester, 'dar_del', '1300');
      expect(find.byKey(const Key('dar_error')), findsNothing);
      expect(_texto(tester, 'dar_al_calculado'), 'al 1319');

      await _tocar(tester, 'dar_dar');
      expect(_texto(tester, 'dar_confirmar_texto'),
          r'A LOPEZ ANA, del 1300 al 1319, a $ 8.000 cada una (entrada anticipada, queda fijo).');
      expect(m.entradas.escrituras, 0, reason: 'la ventana no escribe');
      await _tocar(tester, 'dar_confirmar_si');

      final dio = m.entradas.listaParaRendir.last;
      expect(dio.esDio, isTrue);
      expect(dio.personaNombre, 'LOPEZ ANA');
      expect(dio.contratoAlumnoId, isNull);
      expect(dio.cantidad, 20);
      expect(dio.numeros, '1300-1319');
      expect(dio.precio, 8000);
      expect(dio.nombrePrecio, 'Entrada anticipada');
      expect(dio.conPulseras, isFalse);
      expect(dio.personaContacto, isNull, reason: 'vacío va en null, nunca en ""');
      // La lista se relee sola (avisarQueCambioLaVenta).
      expect(find.byKey(Key('para_rendir_persona_${_deAfuera('lopez ana')}')), findsOneWidget);
      expect(_texto(tester, 'para_rendir_total_sin_rendir'), '50');
      expect(_texto(tester, 'para_rendir_hecho'),
          'Se le dieron 20 entradas a LOPEZ ANA (del 1300 al 1319) para rendir.');
      // La constancia para firmar no sale sola (22-nov-2026): la saca IMPRIMIR
      // LA CONSTANCIA del aviso, de lo recién dado.
      expect(m.constancias, isEmpty, reason: 'ningún papel se abre solo');
      await _tocar(tester, 'para_rendir_hecho_constancia');
      final constancia = m.constancias.single;
      expect(constancia.reimpresa, isFalse);
      expect(constancia.alDia, isNull, reason: 'recién dadas no hay "Hoy"');
      expect(constancia.bloque.id, dio.id);
      expect(constancia.bloque.cantidad, 20);
      expect(TramoTalonario.legible(constancia.bloque.tramos), '1300 al 1319');
      expect(constancia.bloque.precioDeCadaUna, 8000);
      expect(constancia.bloque.sinRendir, 20);
    });

    testWidgets('si la constancia no se puede abrir, lo dado queda y se dice sin asustar',
        (tester) async {
      final m = await _montar(tester, fallaLaConstancia: true);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir.single.personaNombre, 'LOPEZ ANA');
      expect(_texto(tester, 'para_rendir_hecho'),
          'Se le dieron 20 entradas a LOPEZ ANA (del 1300 al 1319) para rendir.');
      await _tocar(tester, 'para_rendir_hecho_constancia');
      expect(find.text('No se pudo abrir la constancia. Probá de nuevo.'), findsOneWidget);
      expect(find.text('No se pudieron dar. Probá de nuevo.'), findsNothing);
      expect(find.byKey(const Key('para_rendir_hecho_constancia')), findsOneWidget,
          reason: 'se puede volver a probar');
    });

    // 22-nov-2026: como la primera constancia puede salir desde CONSTANCIA
    // (nada sale solo), la de un bloque sin nada rendido sale como la de recién
    // dado, sin REIMPRESA ni "Hoy".
    testWidgets('CONSTANCIA de un bloque sin nada rendido sale como la original',
        (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
      await _tocar(tester, 'dar_confirmar_si');
      final dio = m.entradas.listaParaRendir.single;
      expect(m.constancias, isEmpty);
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('lopez ana')}');
      await _tocar(tester, 'para_rendir_constancia_${dio.id}');
      final constancia = m.constancias.single;
      expect(constancia.reimpresa, isFalse);
      expect(constancia.alDia, isNull);
      expect(constancia.bloque.id, dio.id);
    });

    testWidgets('si no se dan (cambió el precio), no sale ninguna constancia', (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
      m.entradas.conPrecio(idFiestaEntrega, valor: 10000);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(m.constancias, isEmpty);
    });

    testWidgets('a un alumno de la fiesta: se elige de la lista y el nombre viene del '
        'alumno', (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'para_rendir_dar');
      await tester.tap(find.text('Un alumno de la fiesta'));
      await tester.pump();
      expect(_texto(tester, 'dar_error'), 'Elegí al alumno de la lista.');
      await _poner(tester, 'dar_buscar_alumno', 'lopez');
      await _tocar(tester, 'dar_alumno_${EntregaEnMemoria.idLopez}');
      await _tocar(tester, 'dar_cuantas_menos', veces: 10);
      await _poner(tester, 'dar_del', '500');
      await _tocar(tester, 'dar_dar');
      await _tocar(tester, 'dar_confirmar_si');
      final dio = m.entradas.listaParaRendir.single;
      expect(dio.personaNombre, 'LÓPEZ, SOFÍA');
      expect(dio.contratoAlumnoId, EntregaEnMemoria.idLopez);
      expect(dio.cantidad, 10);
      expect(dio.numeros, '500-509');
      expect(find.text('alumno · 5° A'), findsOneWidget);
      // La constancia dice que es alumno de la fiesta, con su división.
      await _tocar(tester, 'para_rendir_hecho_constancia');
      expect(m.constancias.single.bloque.esDeUnAlumno, isTrue);
      expect(m.constancias.single.division, '5° A');
    });

    testWidgets('sin precio en la fiesta no se da, y al jefe se le dice dónde cargarlo',
        (tester) async {
      final m = await _montar(tester, conPrecio: false);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      // DAR es del jefe: no le dice "el jefe todavía no puso el precio"
      // (21-nov-2026), sino que lo cargue en PRECIOS.
      expect(_texto(tester, 'dar_error'),
          'La fiesta todavía no tiene el precio de la entrada. Cargalo en PRECIOS.');
      expect(find.textContaining('El jefe todavía no puso'), findsNothing);
      expect(_apagado(tester, 'dar_dar'), isTrue);
      await tester.tap(find.byKey(const Key('dar_dar')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(m.entradas.listaParaRendir, isEmpty);
    });

    testWidgets('volver de la confirmación no da nada', (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
      await _tocar(tester, 'dar_confirmar_volver');
      await _tocar(tester, 'dar_cancelar');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(m.entradas.escrituras, 0);
    });

    // 21-nov-2026: el bloque queda fijo con el precio que se dio. Si cambió
    // con la ventana abierta, no se da: el jefe vuelve a abrir DAR y ve el de
    // ahora.
    const elPrecioCambio = r'No se dieron: el precio cambió mientras cargabas. Ahora es '
        r'$ 10.000 cada una (entrada general). Volvé a abrir DAR.';

    Future<void> hastaLaConfirmacion(WidgetTester tester) async {
      await _tocar(tester, 'para_rendir_dar');
      expect(_texto(tester, 'dar_precio_texto'),
          startsWith(r'A $ 8.000 cada una · Entrada anticipada'));
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
    }

    testWidgets('si con la ventana abierta otro equipo apretó GENERAL en PRECIOS, no se '
        'da y dice el precio de ahora', (tester) async {
      final m = await _montar(tester);
      await hastaLaConfirmacion(tester);
      // La anticipada ya no está: rige la general, a $ 10.000.
      m.entradas.conPrecio(idFiestaEntrega, valor: 10000);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(m.entradas.escrituras, 0);
      expect(find.text(elPrecioCambio), findsOneWidget);
    });

    testWidgets('si con la ventana abierta pasó la medianoche del último día de la '
        'anticipada, tampoco', (tester) async {
      var ahora = DateTime.utc(2026, 11, 20, 23, 58);
      final m = await _montar(
        tester,
        hoy: () => ahora,
        antes: (e) async =>
            e.conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-20'),
      );
      await hastaLaConfirmacion(tester);
      ahora = DateTime.utc(2026, 11, 21, 0, 1);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(m.entradas.escrituras, 0);
      expect(find.text(elPrecioCambio), findsOneWidget);
    });

    testWidgets('con la misma plata pero otro nombre (la anticipada valía lo mismo que la '
        'general), tampoco: el bloque se rendiría con otro nombre', (tester) async {
      var ahora = DateTime.utc(2026, 11, 20, 23, 58);
      final m = await _montar(
        tester,
        hoy: () => ahora,
        antes: (e) async => e.conPrecio(idFiestaEntrega,
            valor: 8000, anticipada: 8000, hasta: '2026-11-20'),
      );
      await hastaLaConfirmacion(tester);
      ahora = DateTime.utc(2026, 11, 21, 0, 1);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(
          find.text(r'No se dieron: el precio cambió mientras cargabas. Ahora es '
              r'$ 8.000 cada una (entrada general). Volvé a abrir DAR.'),
          findsOneWidget);
    });

    // 21-nov-2026: la razón de `errorAlDar` va después de los dos puntos, con
    // minúscula, como "el precio cambió".
    testWidgets('si con la ventana abierta otro equipo dio esos números, no se da y '
        'dice por qué, con minúscula después de los dos puntos', (tester) async {
      final m = await _montar(tester);
      await hastaLaConfirmacion(tester);
      await _dar(m.entradas, 'NIEVA, CARLOS', 1300, 5);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir.map((d) => d.personaNombre), ['NIEVA, CARLOS']);
      expect(
          find.text('No se dieron: el 1300 ya se le dio a NIEVA, CARLOS, para rendir '
              '(1300 al 1304).'),
          findsOneWidget);
    });

    testWidgets('con el mismo precio, aunque PRECIOS se haya vuelto a guardar, se da',
        (tester) async {
      final m = await _montar(tester);
      await hastaLaConfirmacion(tester);
      m.entradas.conPrecio(idFiestaEntrega, anticipada: 8000, hasta: '2026-11-30');
      await _tocar(tester, 'dar_confirmar_si');
      final dio = m.entradas.listaParaRendir.single;
      expect([dio.precio, dio.nombrePrecio], [8000, 'Entrada anticipada']);
      expect(find.text(elPrecioCambio), findsNothing);
    });
  });

  // 21-nov-2026: dar, NO VOLVIERON y ANULAR preguntan por el modo jefe antes de
  // abrir su ventana y **otra vez antes de escribir**: el jefe pudo salir del
  // modo jefe (o vencerse) con la ventana abierta.
  group('la segunda llave: el modo jefe se cerró con la ventana abierta', () {
    const frena = '$kSoloEnModoJefe: dar, marcar lo que no volvió y anular es del jefe.';

    Future<void> saleDelModoJefe(_Montada m, WidgetTester tester, void Function() cerrar) async {
      cerrar();
      m.c.invalidate(esRolJefeProvider);
      await tester.pump();
    }

    testWidgets('DAR: confirma y no se da nada', (tester) async {
      var jefe = true;
      final m = await _montar(tester, jefeAhora: () => jefe);
      await _tocar(tester, 'para_rendir_dar');
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      await _tocar(tester, 'dar_dar');
      await saleDelModoJefe(m, tester, () => jefe = false);
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir, isEmpty);
      expect(m.entradas.escrituras, 0);
      expect(find.text(frena), findsOneWidget);
    });

    testWidgets('NO VOLVIERON: confirma y no se marca nada', (tester) async {
      var jefe = true;
      final m = await _montar(tester, jefeAhora: () => jefe, antes: _cuatroPersonas);
      final perez = m.bloqueDe('PÉREZ, JUAN');
      final antes = m.entradas.listaParaRendir.length;
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('perez juan')}');
      await _tocar(tester, 'para_rendir_no_volvieron_${perez.id}');
      await _poner(tester, 'no_volvieron_motivo', 'dice que la perdió');
      await saleDelModoJefe(m, tester, () => jefe = false);
      await _tocar(tester, 'no_volvieron_confirmar');
      expect(m.entradas.listaParaRendir, hasLength(antes));
      expect(m.entradas.escrituras, 0);
      expect(find.text(frena), findsOneWidget);
    });

    testWidgets('ANULAR: confirma y no se anula nada', (tester) async {
      var jefe = true;
      final m = await _montar(tester, jefeAhora: () => jefe, antes: _cuatroPersonas);
      final nieva = m.bloqueDe('NIEVA, CARLOS');
      final antes = m.entradas.listaParaRendir.length;
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('nieva carlos')}');
      await _tocar(tester, 'para_rendir_anular_${nieva.id}');
      await tester.enterText(find.byKey(const Key('motivo_texto')), 'se cargó mal');
      await tester.pump();
      await saleDelModoJefe(m, tester, () => jefe = false);
      await _tocar(tester, 'para_rendir_anular_confirmar');
      expect(m.entradas.listaParaRendir, hasLength(antes));
      expect(m.entradas.escrituras, 0);
      expect(find.text(frena), findsOneWidget);
    });
  });

  group('NO VOLVIERON y ANULAR', () {
    // Revisión del 22-nov-2026: anular lo que devolvió SOSA le vuelve a poner
    // del 1239 al 1243 a su cargo. Si en el medio VENDER vendió alguno, rendirlo
    // después sería cobrar dos veces la misma entrada: no se anula.
    testWidgets('ANULAR lo devuelto cuyos números ya se vendieron: no se anula y lo dice',
        (tester) async {
      final m = await _montar(tester, antes: (e) async {
        await _cuatroPersonas(e);
        final caja = e.listaCajas.first;
        await e.vender(
          caja: caja,
          compradorNombre: 'RUIZ, MARTA',
          renglones: [
            RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 8000, cantidad: 2),
          ],
          medio: MedioBarra.efectivo,
          efectivo: 16000,
          numeros: '1240-1241',
          quien: 'Carla',
        );
      });
      final sosa = m.bloqueDe('SOSA, DIEGO');
      final devolvio = m.entradas.listaParaRendir
          .firstWhere((x) => x.esDevolvio && x.bloqueId == sosa.id);
      final antes = m.entradas.listaParaRendir.length;
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('sosa diego')}');
      await _tocar(tester, 'para_rendir_anular_${devolvio.id}');
      expect(find.byKey(const Key('motivo_texto')), findsNothing,
          reason: 'no llega a pedir el motivo');
      expect(
        find.textContaining('No se puede anular: El 1240 ya se le dio a RUIZ, MARTA'),
        findsOneWidget,
      );
      expect(m.entradas.listaParaRendir, hasLength(antes));
      expect(m.entradas.escrituras, 0);
    });

    testWidgets('NO VOLVIERON: cuántas, sus números y el motivo; no entra plata',
        (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      final perez = m.bloqueDe('PÉREZ, JUAN');
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('perez juan')}');
      await _tocar(tester, 'para_rendir_no_volvieron_${perez.id}');
      await _tocar(tester, 'no_volvieron_mas');
      expect(_texto(tester, 'no_volvieron_cantidad'), '2');
      expect(find.textContaining(r'valían $ 16.000'), findsOneWidget);
      // No "para siempre" (21-nov-2026): si aparecen, se anula este "no
      // volvieron" y se rinden.
      expect(
          find.text(r'No entra plata y quedan anuladas: la lista dice que valían $ 16.000. '
              'Si después aparecen, anulá este "no volvieron" y se rinden.'),
          findsOneWidget);
      expect(find.textContaining('para siempre'), findsNothing);
      expect(_apagado(tester, 'no_volvieron_confirmar'), isTrue, reason: 'falta el motivo');
      await _poner(tester, 'no_volvieron_del', '1239');
      expect(_texto(tester, 'no_volvieron_error'),
          'El 1239 no es de las que se llevó (1201 al 1220).');
      await _poner(tester, 'no_volvieron_del', '1219');
      expect(_texto(tester, 'no_volvieron_al'), 'al 1220');
      await _poner(tester, 'no_volvieron_motivo', 'dice que las perdió');
      final ventas = m.entradas.listaVentas.length;
      await _tocar(tester, 'no_volvieron_confirmar');

      final perdidas = m.entradas.listaParaRendir.last;
      expect(perdidas.esNoVolvieron, isTrue);
      expect(perdidas.bloqueId, perez.id);
      expect(perdidas.cantidad, 2);
      expect(perdidas.numeros, '1219-1220');
      expect(perdidas.motivo, 'dice que las perdió');
      expect(m.entradas.listaVentas, hasLength(ventas), reason: 'no entra plata');
      expect(_texto(tester, 'para_rendir_total_no_volvieron'), '4');
      expect(_chip(tester, 'para_rendir_estado_${_deAfuera('perez juan')}'), 'sin rendir 18');
    });

    testWidgets('ANULAR un bloque sin nada rendido: queda tachado y sus números libres',
        (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      final nieva = m.bloqueDe('NIEVA, CARLOS');
      expect(m.cuenta.ocupados.keys, contains('NIEVA, CARLOS, para rendir'));
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('nieva carlos')}');
      expect(_apagado(tester, 'para_rendir_anular_${nieva.id}'), isFalse);
      await _tocar(tester, 'para_rendir_anular_${nieva.id}');
      expect(find.text('Anular las entradas de NIEVA, CARLOS'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('motivo_texto')), 'se cargó mal');
      await tester.pump();
      await _tocar(tester, 'para_rendir_anular_confirmar');

      final anulo = m.entradas.listaParaRendir.last;
      expect(anulo.esAnulo, isTrue);
      expect(anulo.anulaId, nieva.id);
      expect(anulo.motivo, 'se cargó mal');
      expect(_texto(tester, 'para_rendir_anulado_${nieva.id}'), contains('se cargó mal'));
      expect(_texto(tester, 'para_rendir_total_sin_rendir'), '20');
      expect(m.cuenta.ocupados.keys, isNot(contains('NIEVA, CARLOS, para rendir')));
    });

    testWidgets('ANULAR lo que devolvió: vuelve a quedar a su cargo', (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas);
      final sosa = m.bloqueDe('SOSA, DIEGO');
      final devolvio = m.entradas.listaParaRendir
          .firstWhere((x) => x.bloqueId == sosa.id && x.esDevolvio);
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('sosa diego')}');
      await _tocar(tester, 'para_rendir_anular_${devolvio.id}');
      // Los números entre paréntesis, no con el " · " de la lista (21-nov-2026).
      expect(
          find.text('Las 5 que devolvió (del 1239 al 1243) vuelven a quedar a su cargo '
              'para rendir.'),
          findsOneWidget);
      await tester.enterText(find.byKey(const Key('motivo_texto')), 'no las trajo');
      await tester.pump();
      await _tocar(tester, 'para_rendir_anular_confirmar');
      expect(m.entradas.listaParaRendir.last.anulaId, devolvio.id);
      expect(_chip(tester, 'para_rendir_estado_${_deAfuera('sosa diego')}'), 'sin rendir 5');
      expect(_texto(tester, 'para_rendir_mov_${devolvio.id}'),
          'Devolvió 5 · del 1239 al 1243 (anulado: no las trajo)');
      expect(find.byKey(Key('para_rendir_anular_${devolvio.id}')), findsNothing);
    });
  });

  group('en un celular', () {
    testWidgets('la lista, un bloque abierto y DAR (una hoja desde abajo), sin cortes',
        (tester) async {
      final m = await _montar(tester, antes: _cuatroPersonas, tamano: const Size(390, 1500));
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'para_rendir_persona_${_deAfuera('sosa diego')}');
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'para_rendir_dar');
      expect(find.byType(BottomSheet), findsOneWidget);
      await _poner(tester, 'dar_nombre', 'lopez ana');
      await _poner(tester, 'dar_del', '1300');
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'dar_dar');
      await _tocar(tester, 'dar_confirmar_si');
      expect(m.entradas.listaParaRendir.last.personaNombre, 'LOPEZ ANA');
      expect(tester.takeException(), isNull);
    });
  });
}
