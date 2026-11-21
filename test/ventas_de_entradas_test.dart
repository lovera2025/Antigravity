// VENTAS, el historial de la venta de entradas (etapa 5 del spec del 13-nov,
// sección 8), montada de verdad con la entrega y la venta en memoria: quién ve
// qué, "Pago verificado" y ANULAR solo del jefe, reimprimir y el historial.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/historial_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

class _Montada {
  final EntradasEnMemoria entradas;
  final List<DatosDelComprobante> comprobantes;
  final List<DatosDelHistorial> historiales;
  final CajaEntradas carla;
  final VentaEntradas v1, v2, v3;
  final ProviderContainer c;
  _Montada(this.entradas, this.comprobantes, this.historiales, this.carla,
      this.v1, this.v2, this.v3, this.c);
}

Future<VentaEntradas> _vender(
  EntradasEnMemoria entradas,
  CajaEntradas caja,
  String comprador, {
  int sueltas = 2,
  MedioBarra medio = MedioBarra.efectivo,
  String? numeros,
  String? familia,
}) =>
    entradas.vender(
      caja: caja,
      contratoAlumnoId: familia,
      compradorNombre: comprador,
      renglones: [
        RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: sueltas),
      ],
      medio: medio,
      efectivo: medio == MedioBarra.efectivo ? 10000.0 * sueltas : 0,
      transferencia: medio == MedioBarra.transferencia ? 10000.0 * sueltas : 0,
      numeros: numeros,
      quien: caja.operadorNombre!,
    );

/// Dos cajas: la de Carla (dos ventas) y la de Maxi (una). [jefe]: mira el
/// jefe en modo jefe; si no, Carla, con su caja.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool jefe = false,
  // El modo jefe, leído de acá cada vez: se cambia con
  // `c.invalidate(esRolJefeProvider)`, para cerrarlo con un cartel abierto.
  bool Function()? jefeAhora,
  bool conVentas = true,
  Size tamano = const Size(1200, 1300),
  String? numerosDeRuiz,
  void Function(EntregaEnMemoria)? preparar,
  // Lo que pasa en la caja de Carla después de sus ventas (una rendición).
  Future<void> Function(EntradasEnMemoria, CajaEntradas carla)? despues,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  preparar?.call(e);
  final entradas = EntradasEnMemoria()..conPrecio(idFiestaEntrega);
  final comprobantes = <DatosDelComprobante>[];
  final historiales = <DatosDelHistorial>[];
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: jefeAhora == null ? jefe : null),
    if (jefeAhora != null) esRolJefeProvider.overrideWith((ref) => jefeAhora()),
    ...entradas.reemplazos,
    abrirComprobanteDeEntradasProvider
        .overrideWithValue((datos, {context}) async => comprobantes.add(datos)),
    abrirHistorialDeEntradasProvider
        .overrideWithValue((datos, {context}) async => historiales.add(datos)),
  ]);
  addTearDown(c.dispose);
  final operadora = e.operador();
  await c.read(appRoleProvider.notifier).entrarComoEntradas(
        operadora,
        const PermisosEfectivos(entradas: true, vendeEntradas: true),
      );
  final carla = await entradas.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: operadora.id,
    operadorNombre: 'Carla',
  );
  final maxi = await entradas.abrirCaja(
    eventoId: idFiestaEntrega,
    operadorId: 'maxi',
    operadorNombre: 'Maxi',
  );
  late VentaEntradas v1, v2, v3;
  if (conVentas) {
    v1 = await _vender(entradas, carla, 'PEREZ MARTA',
        numeros: '2000-2001', familia: EntregaEnMemoria.idPerez);
    v2 = await _vender(entradas, carla, 'RUIZ MARTA',
        sueltas: 4, medio: MedioBarra.transferencia, numeros: numerosDeRuiz);
    v3 = await _vender(entradas, maxi, 'SOSA DIEGO', sueltas: 1, numeros: '2001');
  }
  await despues?.call(entradas, carla);
  entradas.escrituras = 0;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: VentasDeEntradasScreen(evento: fiestaDeLaEntrega, caja: carla),
    ),
  ));
  await tester.pumpAndSettle();
  return conVentas
      ? _Montada(entradas, comprobantes, historiales, carla, v1, v2, v3, c)
      : _Montada(entradas, comprobantes, historiales, carla,
          _nada, _nada, _nada, c);
}

/// Relleno para el caso sin ventas: no se usa.
final _nada = VentaEntradas.nueva(
  cajaEntradasId: 'x',
  eventoId: 'x',
  numero: 1,
  compradorNombre: 'NADIE NADIE',
  renglones: [
    RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 1, cantidad: 1),
  ],
  medio: MedioBarra.efectivo,
  efectivo: 1,
  ahora: DateTime.utc(2026),
);

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

Future<void> _tocar(WidgetTester tester, String clave) async {
  await tester.ensureVisible(find.byKey(Key(clave)));
  await tester.tap(find.byKey(Key(clave)));
  await tester.pumpAndSettle();
}

void main() {
  group('quién ve qué', () {
    testWidgets('quien vende ve solo las de su caja, con "Pago verificado" y ANULAR '
        'apagados y el motivo', (tester) async {
      final m = await _montar(tester);
      expect(_texto(tester, 'ventas_alcance'), 'PUERTO VIEJO · La caja de Carla');
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v3.id}')), findsNothing,
          reason: 'la de Maxi es de otra caja');
      // Sin sumas de plata: cuenta su caja a ciegas (revisión del 14-nov).
      expect(_texto(tester, 'ventas_totales'),
          '2 ventas · 6 entradas · pago verificado: 0 de 2');

      final tilde = tester.widget<Checkbox>(find.byKey(Key('verificar_${m.v1.id}')));
      expect(tilde.onChanged, isNull);
      final anular = tester.widget<TextButton>(find.byKey(Key('anular_${m.v1.id}')));
      expect(anular.onPressed, isNull);
      expect(_texto(tester, 'ventas_motivo'), contains(kSoloEnModoJefe));
      // Reimprimir sí puede.
      final reimprimir =
          tester.widget<TextButton>(find.byKey(Key('reimprimir_${m.v1.id}')));
      expect(reimprimir.onPressed, isNotNull);
      // Tocar lo apagado no escribe nada.
      await tester.tap(find.byKey(Key('verificar_${m.v1.id}')), warnIfMissed: false);
      await tester.tap(find.byKey(Key('anular_${m.v1.id}')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(m.entradas.escrituras, 0);
    });

    testWidgets('el jefe ve todas las de la fiesta, de la más nueva a la más vieja',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      expect(_texto(tester, 'ventas_alcance'), 'PUERTO VIEJO · Todas las cajas');
      for (final v in [m.v1, m.v2, m.v3]) {
        expect(find.byKey(Key('venta_${v.id}')), findsOneWidget);
      }
      expect(_texto(tester, 'ventas_totales'),
          r'3 ventas · 7 entradas · $ 70.000 · pago verificado: 0 de 3');
      expect(find.byKey(const Key('ventas_motivo')), findsNothing);
      final arriba = tester.getTopLeft(find.byKey(Key('venta_${m.v3.id}'))).dy;
      final abajo = tester.getTopLeft(find.byKey(Key('venta_${m.v1.id}'))).dy;
      expect(arriba, lessThan(abajo));
    });

    testWidgets('el número que quedó en dos ventas se avisa arriba, también a quien '
        'mira solo su caja', (tester) async {
      await _montar(tester);
      expect(
        find.text('El 2001 está en dos ventas (PEREZ MARTA y SOSA DIEGO): revisar.'),
        findsOneWidget,
      );
    });

    // Son dos talonarios (20-nov): lo vendido es el de las anticipadas y lo
    // entregado sin cargo, el de las generales. Hasta la 6.9.2 la venta de
    // RUIZ (1003 al 1006) salía repetida con la entrega de GÓMEZ (1001 al
    // 1007), y dos entregas con el mismo número no se avisaban nunca.
    testWidgets('el número que quedó en dos entregas se avisa aparte; el de una venta '
        'y una entrega, no', (tester) async {
      await _montar(
        tester,
        numerosDeRuiz: '1003-1006',
        preparar: (e) {
          final lopez =
              e.contratos.alumnos.firstWhere((a) => a.id == EntregaEnMemoria.idLopez);
          e.entregas.filas[lopez.id] = RetiroEntradas.nuevaEntrega(
            alumno: lopez,
            entradas: RetiroEntradas.entradasDe(lopez),
            tramos: const [TramoTalonario(1005, 1011)],
            menores10: 0,
            parentesco: ParentescoRetiro.madre,
            nombre: 'Sofía López',
            quien: 'Jefe',
            ahora: DateTime.utc(2026, 11, 7, 19),
          );
        },
      );
      String aviso(int i) => tester
          .widget<Text>(find.descendant(
            of: find.byKey(Key('ventas_repetido_$i')),
            matching: find.byType(Text),
          ))
          .data!;
      expect(aviso(0), 'El 2001 está en dos ventas (PEREZ MARTA y SOSA DIEGO): revisar.');
      expect(aviso(1), startsWith('El 1005 está en dos entregas ('));
      expect(aviso(1), allOf(contains('GÓMEZ, ANA'), contains('LÓPEZ, SOFÍA')));
      expect(find.byKey(const Key('ventas_repetido_2')), findsNothing,
          reason: 'la venta de RUIZ no choca con ninguna entrega');
      expect(find.textContaining('RUIZ MARTA y'), findsNothing);
      expect(find.textContaining('en una entrega'), findsNothing);
    });

    // 20-nov-2026: las generales se entregan por partes (un renglón de
    // `entradas_entregas`), y sus números también cuentan para el aviso.
    testWidgets('el número de unas generales entregadas por partes también se avisa',
        (tester) async {
      await _montar(
        tester,
        preparar: (e) {
          e.partes.renglones.add(EntregaEntradas.entrega(
            contratoAlumnoId: EntregaEnMemoria.idLopez,
            eventoId: idFiestaEntrega,
            parte: ParteEntrega.generales,
            cantidad: 7,
            tramos: const [TramoTalonario(1005, 1011)],
            parentesco: ParentescoRetiro.madre,
            nombre: 'Sofía López',
            escribioEnPlanilla: true,
            hechoPor: 'Carla',
            deviceId: 'tablet',
            ahora: DateTime.utc(2026, 11, 20, 19),
          ));
        },
      );
      final avisos = [
        for (final w in tester.widgetList<Text>(find.descendant(
          of: find.byWidgetPredicate(
            (w) => w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('ventas_repetido_'),
          ),
          matching: find.byType(Text),
        )))
          w.data ?? '',
      ];
      expect(
        avisos.where((a) =>
            a.startsWith('El 1005 está en dos entregas (') &&
            a.contains('GÓMEZ, ANA') &&
            a.contains('LÓPEZ, SOFÍA')),
        hasLength(1),
        reason: '$avisos',
      );
    });

    testWidgets('sin ventas lo dice', (tester) async {
      await _montar(tester, conVentas: false);
      expect(_texto(tester, 'ventas_vacio'), 'Todavía no hay ventas.');
    });
  });

  group('Pago verificado, solo el jefe', () {
    testWidgets('lo tilda y queda quién; destildar actualiza la misma fila',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'verificar_${m.v1.id}');
      final fila = m.entradas.listaVerificaciones.single;
      expect(fila.ventaId, m.v1.id);
      expect(fila.verificado, isTrue);
      expect(fila.hechoPor, isNotEmpty);
      expect(tester.widget<Checkbox>(find.byKey(Key('verificar_${m.v1.id}'))).value,
          isTrue);
      expect(_texto(tester, 'ventas_totales'), contains('pago verificado: 1 de 3'));

      await _tocar(tester, 'verificar_${m.v1.id}');
      expect(m.entradas.listaVerificaciones.single.verificado, isFalse);
      expect(_texto(tester, 'ventas_totales'), contains('pago verificado: 0 de 3'));
      // La venta no se tocó.
      expect(m.entradas.listaVentas.first.toMap(), m.v1.toMap());
    });

    testWidgets('el filtro: verificadas y sin verificar', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'verificar_${m.v1.id}');
      await tester.tap(find.text('Verificadas'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsNothing);
      await tester.tap(find.text('Sin verificar'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('venta_${m.v1.id}')), findsNothing);
      expect(find.byKey(Key('venta_${m.v2.id}')), findsOneWidget);
      expect(find.byKey(Key('venta_${m.v3.id}')), findsOneWidget);
    });
  });

  group('ANULAR, solo el jefe', () {
    testWidgets('pide el motivo y si devolvieron las entradas; la venta queda en la '
        'lista, tachada, con todo', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v1.id}');
      expect(find.text('Anular la venta N° 0001'), findsOneWidget);
      expect(find.textContaining('(2000 al 2001)'), findsOneWidget,
          reason: 'los números, a la vista');

      await _tocar(tester, 'anular_confirmar');
      expect(_texto(tester, 'anular_problema'), 'Escribí por qué se anula.');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se equivocó');
      await tester.pump();
      // Solo las entradas: la pulsera no se vende (pedido del usuario,
      // 21-nov-2026), así que no se pregunta por pulseras.
      expect(_texto(tester, 'anular_pregunta'), '¿Devolvieron las entradas? (2000 al 2001)');
      expect(find.textContaining('ulsera'), findsNothing);
      await _tocar(tester, 'anular_confirmar');
      expect(_texto(tester, 'anular_problema'), 'Decí si devolvieron las entradas.');
      expect(m.entradas.listaAnulaciones, isEmpty);

      await _tocar(tester, 'anular_devolvieron_no');
      await _tocar(tester, 'anular_confirmar');

      final a = m.entradas.listaAnulaciones.single;
      expect(a.ventaId, m.v1.id);
      expect(a.motivo, 'se equivocó');
      expect(a.devueltas, isFalse);
      expect(a.hechoPor, isNotEmpty);
      // La venta sigue, sin tocar, y en la lista.
      expect(m.entradas.listaVentas.first.toMap(), m.v1.toMap());
      expect(find.byKey(Key('venta_${m.v1.id}')), findsOneWidget);
      expect(_texto(tester, 'anulada_${m.v1.id}'), contains('se equivocó'));
      expect(_texto(tester, 'anulada_${m.v1.id}'),
          contains('NO devolvieron las entradas: esos números quedan anulados'));
      // Ya no se verifica ni se vuelve a anular.
      expect(find.byKey(Key('verificar_${m.v1.id}')), findsNothing);
      expect(find.byKey(Key('anular_${m.v1.id}')), findsNothing);
      expect(_texto(tester, 'ventas_totales'),
          r'2 ventas · 5 entradas · $ 50.000 · 1 anulada · pago verificado: 0 de 2');
    });

    testWidgets('con las entradas devueltas lo dice así', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v2.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'pagó dos veces');
      await tester.pump();
      await _tocar(tester, 'anular_devolvieron_si');
      await _tocar(tester, 'anular_confirmar');
      expect(m.entradas.listaAnulaciones.single.devueltas, isTrue);
      expect(_texto(tester, 'anulada_${m.v2.id}'), endsWith('devolvieron las entradas'));
      expect(find.textContaining('ulsera'), findsNothing);
    });

    testWidgets('volver del cartel no anula nada', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'anular_${m.v1.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'me arrepentí');
      await _tocar(tester, 'anular_volver');
      expect(m.entradas.listaAnulaciones, isEmpty);
      expect(m.entradas.escrituras, 0);
      expect(find.byKey(Key('anular_${m.v1.id}')), findsOneWidget);
    });
  });

  // 21-nov-2026: la plata de una rendición de entradas para rendir es una venta
  // más de la caja que cobró, marcada RENDICIÓN. Se anula acá, y solo acá: las
  // entradas vuelven a quedar a cargo de quien las llevó, así que no se
  // pregunta si las devolvieron (regla 48, `devueltas: false`).
  group('una rendición de entradas para rendir', () {
    /// El jefe le dio 20 a PÉREZ, JUAN (1201 al 1220) a $ 8.000, y Carla le
    /// cobró 15 en su caja (y él devolvió del 1216 al 1220).
    ///
    /// [sinSuVendio]: con la venta ya en este equipo y su renglón `vendio`
    /// todavía no (la venta sube antes): se lo saca de la lista y se lo deja
    /// ahí, para que "llegue" después.
    Future<_Montada> conUnaRendicion(
      WidgetTester tester, {
      bool jefe = true,
      List<MovimientoParaRendir>? sinSuVendio,
    }) =>
        _montar(
          tester,
          jefe: jefe,
          despues: (entradas, carla) async {
            final dio = await entradas.darParaRendir(
              eventoId: idFiestaEntrega,
              personaNombre: 'PÉREZ, JUAN',
              cantidad: 20,
              numeros: const [TramoTalonario(1201, 1220)],
              precio: 8000,
              nombrePrecio: 'Entrada anticipada',
              quien: 'Jefe',
            );
            await entradas.rendir(
              caja: carla,
              bloque: dio,
              vendidas: 15,
              devueltas: 5,
              numerosDevueltos: const [TramoTalonario(1216, 1220)],
              efectivo: 120000,
              quien: 'Carla',
            );
            if (sinSuVendio != null) {
              sinSuVendio.addAll(entradas.listaParaRendir.where((x) => x.esVendio));
              entradas.listaParaRendir.removeWhere((x) => x.esVendio);
            }
          },
        );

    String chip(WidgetTester tester, VentaEntradas v) => tester
        .widget<Text>(find.descendant(
          of: find.byKey(Key('rendicion_${v.id}')),
          matching: find.byType(Text),
        ))
        .data!;

    testWidgets('va marcada RENDICIÓN; su anular no pregunta si devolvieron y manda '
        '"no devueltas": las 15 vuelven a quien las llevó', (tester) async {
      final m = await conUnaRendicion(tester);
      final rendicion = m.entradas.listaVentas.last;
      expect(chip(tester, rendicion), 'RENDICIÓN · de PÉREZ, JUAN');
      expect(find.byKey(Key('rendicion_${m.v1.id}')), findsNothing,
          reason: 'una venta común no es una rendición');

      await _tocar(tester, 'anular_${rendicion.id}');
      expect(_texto(tester, 'anular_rendicion'),
          'Es una rendición: las 15 vuelven a quedar a cargo de PÉREZ, JUAN para rendir.');
      expect(find.byKey(const Key('anular_pregunta')), findsNothing);
      expect(find.byKey(const Key('anular_devolvieron_si')), findsNothing);
      expect(find.byKey(const Key('anular_devolvieron_no')), findsNothing);
      expect(find.textContaining('ulsera'), findsNothing);
      // El motivo sigue siendo obligatorio.
      await _tocar(tester, 'anular_confirmar');
      expect(_texto(tester, 'anular_problema'), 'Escribí por qué se anula.');
      expect(m.entradas.listaAnulaciones, isEmpty);

      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se cobró dos veces');
      await tester.pump();
      await _tocar(tester, 'anular_confirmar');
      final a = m.entradas.listaAnulaciones.single;
      expect(a.ventaId, rendicion.id);
      expect(a.devueltas, isFalse);
      expect(a.motivo, 'se cobró dos veces');
      final fila = _texto(tester, 'anulada_${rendicion.id}');
      // La fila dice lo que pasó, que es cierto siempre: cuántas le quedaron
      // depende de lo que había rendido (21-nov-2026).
      expect(fila, contains('las 15 dejaron de contar como vendidas'));
      expect(fila, isNot(contains('volvieron a quedar')));
      expect(fila, isNot(contains('devolvieron')));
      // Y vuelven a estar sin rendir: le quedan las 15 que había vendido.
      final cuenta = ParaRendir.de(
        movimientos: m.entradas.listaParaRendir,
        ventas: m.entradas.listaVentas,
        anulaciones: m.entradas.listaAnulaciones,
      );
      expect(cuenta.bloques.single.sinRendir, 15);
      expect(cuenta.bloques.single.vendidas, 0);
    });

    testWidgets('quien vende también la ve marcada; REIMPRIMIR queda apagado hasta '
        'que salga su comprobante (el de una venta habla de pulseras)', (tester) async {
      final m = await conUnaRendicion(tester, jefe: false);
      final rendicion = m.entradas.listaVentas.last;
      expect(chip(tester, rendicion), 'RENDICIÓN · de PÉREZ, JUAN');
      final reimprimir =
          tester.widget<TextButton>(find.byKey(Key('reimprimir_${rendicion.id}')));
      expect(reimprimir.onPressed, isNull);
      expect(
        tester.widget<TextButton>(find.byKey(Key('reimprimir_${m.v1.id}'))).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(Key('reimprimir_${rendicion.id}')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(m.comprobantes, isEmpty);
    });

    // 21-nov-2026: la venta sube antes que su renglón `vendio` (prioridad 4
    // contra 5), así que en la PC del jefe la venta puede bajar sola. Igual es
    // una rendición: se reconoce por la venta misma.
    testWidgets('con la venta acá y su "vendió" todavía no: igual va marcada, su anular '
        'no pregunta si devolvieron y no promete a cargo de quién quedan', (tester) async {
      final enCamino = <MovimientoParaRendir>[];
      final m = await conUnaRendicion(tester, sinSuVendio: enCamino);
      expect(enCamino, hasLength(1));
      final rendicion = m.entradas.listaVentas.last;
      expect(
        ParaRendir.de(
          movimientos: m.entradas.listaParaRendir,
          ventas: m.entradas.listaVentas,
          anulaciones: m.entradas.listaAnulaciones,
        ).bloqueDeLaVenta(rendicion.id),
        isNull,
        reason: 'sin su "vendió", la cuenta no sabe de qué bloque es',
      );
      expect(chip(tester, rendicion), 'RENDICIÓN · de PÉREZ, JUAN');
      expect(find.byKey(Key('rendicion_${m.v1.id}')), findsNothing);
      expect(
        tester.widget<TextButton>(find.byKey(Key('reimprimir_${rendicion.id}'))).onPressed,
        isNull,
        reason: 'el comprobante de una venta común habla de pulseras',
      );

      await _tocar(tester, 'anular_${rendicion.id}');
      // Sin el bloque no se sabe cuántas le quedan: no se promete (21-nov-2026).
      expect(_texto(tester, 'anular_rendicion'),
          'Es una rendición de PÉREZ, JUAN: las 15 dejan de contar como vendidas.');
      expect(find.byKey(const Key('anular_pregunta')), findsNothing);
      expect(find.byKey(const Key('anular_devolvieron_no')), findsNothing);
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se cobró dos veces');
      await tester.pump();
      await _tocar(tester, 'anular_confirmar');
      final a = m.entradas.listaAnulaciones.single;
      expect(a.ventaId, rendicion.id);
      expect(a.devueltas, isFalse);
      final fila = _texto(tester, 'anulada_${rendicion.id}');
      expect(fila, contains('las 15 dejaron de contar como vendidas'));
      expect(fila, isNot(contains('a cargo de')));
      expect(fila, isNot(contains('devolvieron')));

      // Llega el "vendió": las 15 vuelven a estar sin rendir, como si la
      // anulación se hubiera hecho con todo a la vista.
      m.entradas.listaParaRendir.addAll(enCamino);
      final cuenta = ParaRendir.de(
        movimientos: m.entradas.listaParaRendir,
        ventas: m.entradas.listaVentas,
        anulaciones: m.entradas.listaAnulaciones,
      );
      expect([cuenta.bloques.single.vendidas, cuenta.bloques.single.sinRendir], [0, 15]);
    });

    // 21-nov-2026: si rindió de más (otro equipo, sin internet, le cobró 3 de
    // las mismas), anular la de Carla no le devuelve 15 para rendir sino 12:
    // el cartel dice la cuenta del bloque, no "las 15 vuelven a quedar".
    testWidgets('si rindió de más, el cartel dice cuántas le quedan de verdad', (tester) async {
      final m = await _montar(
        tester,
        jefe: true,
        despues: (entradas, carla) async {
          final dio = await entradas.darParaRendir(
            eventoId: idFiestaEntrega,
            personaNombre: 'PÉREZ, JUAN',
            cantidad: 20,
            numeros: const [TramoTalonario(1201, 1220)],
            precio: 8000,
            nombrePrecio: 'Entrada anticipada',
            quien: 'Jefe',
          );
          await entradas.rendir(
            caja: carla,
            bloque: dio,
            vendidas: 15,
            devueltas: 5,
            numerosDevueltos: const [TramoTalonario(1216, 1220)],
            efectivo: 120000,
            quien: 'Carla',
          );
          // El "vendió" de otra tablet, con su venta todavía en camino.
          entradas.listaParaRendir.add(MovimientoParaRendir.vendio(
            dio,
            cantidad: 3,
            ventaId: 'venta-de-otra-tablet',
            cajaEntradasId: carla.id,
            ahora: entradas.reloj(),
          ));
        },
      );
      final rendicion = m.entradas.listaVentas.last;
      ParaRendir cuenta() => ParaRendir.de(
            movimientos: m.entradas.listaParaRendir,
            ventas: m.entradas.listaVentas,
            anulaciones: m.entradas.listaAnulaciones,
          );
      expect(cuenta().bloques.single.rindioDeMas, 3);

      await _tocar(tester, 'anular_${rendicion.id}');
      expect(
        _texto(tester, 'anular_rendicion'),
        'Es una rendición: las 15 dejan de contar como vendidas. PÉREZ, JUAN rindió 3 de '
        'más, así que le quedan 12 sin rendir.',
      );
      expect(find.textContaining('vuelven a quedar'), findsNothing);
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se cobró dos veces');
      await tester.pump();
      await _tocar(tester, 'anular_confirmar');
      expect(m.entradas.listaAnulaciones.single.devueltas, isFalse);
      // Lo que dijo el cartel es lo que quedó.
      expect(cuenta().bloques.single.sinRendir, 12);
      expect(cuenta().bloques.single.rindioDeMas, 0);
    });
  });

  // 21-nov-2026: ANULAR pregunta por el modo jefe antes de abrir su cartel y
  // otra vez antes de escribir, como PARA RENDIR: el jefe pudo salir del modo
  // jefe (o vencerse) con el cartel abierto.
  testWidgets('ANULAR con el modo jefe cerrado mientras el cartel estaba abierto no anula '
      'nada', (tester) async {
    var jefe = true;
    final m = await _montar(tester, jefeAhora: () => jefe);
    await _tocar(tester, 'anular_${m.v2.id}');
    await tester.enterText(find.byKey(const Key('anular_motivo')), 'se equivocó');
    await tester.pump();
    await _tocar(tester, 'anular_devolvieron_si');
    jefe = false;
    m.c.invalidate(esRolJefeProvider);
    await tester.pump();
    await _tocar(tester, 'anular_confirmar');
    expect(m.entradas.listaAnulaciones, isEmpty);
    expect(m.entradas.escrituras, 0);
    expect(find.text('$kSoloEnModoJefe: anular y verificar un pago es del jefe.'),
        findsOneWidget);
  });

  group('los papeles', () {
    testWidgets('REIMPRIMIR abre el comprobante como COPIA, con la familia; anulada, '
        'lo lleva cruzado', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'reimprimir_${m.v1.id}');
      final c = m.comprobantes.single;
      expect(c.venta.id, m.v1.id);
      expect(c.copia, isTrue);
      expect(c.alumno, 'PÉREZ, JUAN');
      expect(c.mesa, '12-13');
      expect(c.anulacion, isNull);

      await _tocar(tester, 'anular_${m.v1.id}');
      await tester.enterText(find.byKey(const Key('anular_motivo')), 'se equivocó');
      await tester.pump();
      await _tocar(tester, 'anular_devolvieron_si');
      await _tocar(tester, 'anular_confirmar');
      await _tocar(tester, 'reimprimir_${m.v1.id}');
      expect(m.comprobantes.last.anulacion?.motivo, 'se equivocó');
    });

    testWidgets('IMPRIMIR HISTORIAL arma el papel con lo que se está mirando',
        (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'ventas_imprimir');
      final h = m.historiales.single;
      expect(h.alcance, 'La caja de Carla');
      expect(h.conPlata, isFalse, reason: 'quien vende cuenta a ciegas');
      expect(h.fiesta, 'PUERTO VIEJO');
      expect(h.historial.ventas, hasLength(2));
      expect(h.historial.repetidos, hasLength(1));
    });

    testWidgets('el del jefe trae todas las cajas', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _tocar(tester, 'ventas_imprimir');
      expect(m.historiales.single.alcance, 'Todas las cajas');
      expect(m.historiales.single.conPlata, isTrue);
      expect(m.historiales.single.historial.ventas, hasLength(3));
    });

    // En un celular, con el texto IMPRIMIR HISTORIAL el título se cortaba
    // ("Ventas de e…"): va el ícono, que deja lugar, y hace lo mismo. Que el
    // título entra entero se mira en la muestra, con la letra de la app (la de
    // las pruebas es mucho más ancha).
    testWidgets('en un celular es un ícono chico, nada se desborda, y abre el papel',
        (tester) async {
      final m = await _montar(tester, jefe: true, tamano: const Size(390, 1250));
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('ventas_imprimir')),
          matching: find.byIcon(Icons.print_outlined),
        ),
        findsOneWidget,
      );
      expect(find.text('IMPRIMIR HISTORIAL'), findsNothing);
      expect(tester.getSize(find.byKey(const Key('ventas_imprimir'))).width,
          lessThanOrEqualTo(48));
      await _tocar(tester, 'ventas_imprimir');
      expect(m.historiales.single.alcance, 'Todas las cajas');
    });
  });
}
