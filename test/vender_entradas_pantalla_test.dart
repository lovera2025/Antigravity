// VENDER, la pantalla de la caja de entradas, montada de verdad: la entrega y la
// venta en memoria, y la hoja del cobro de verdad (la misma de la barra).
//
// **Desde el 20-nov-2026 VENDER es la única puerta de quien vende** (decisión del
// usuario): la lista de alumnos a la vista con su filtro, y en la tarjeta de cada
// uno GRATIS · SE ENTREGA (las 8 de la mesa del contrato, en dos partes: pulseras
// VIP y generales, solo con el contrato entero pago) y A PAGAR (cada mesa
// adicional y las sillas, solo lo que está pago entero). Hasta la 6.9.2 VENDER era
// solo la venta, con un buscador que mostraba 6 nombres al escribir: los tests de
// la venta siguen acá, adaptados a la pantalla nueva (cada cambio lleva su
// comentario).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/entradas/cuentas/para_rendir.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';
import 'package:arguello_events/features/entradas/pdf/comprobante_entradas_pdf.dart';
import 'package:arguello_events/features/entradas/pdf/papeles_de_entradas.dart';
import 'package:arguello_events/features/entradas/providers/entradas_providers.dart';
import 'package:arguello_events/features/entradas/services/en_caja.dart';
import 'package:arguello_events/features/entradas/widgets/abrir_caja_entradas_dialog.dart';
import 'package:arguello_events/features/entradas/widgets/vender_entradas_screen.dart';
import 'package:arguello_events/features/entradas/widgets/ventas_de_entradas_screen.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import 'helpers/entradas_en_memoria.dart';
import 'helpers/entrega_en_memoria.dart';

const _perez = EntregaEnMemoria.idPerez;
const _lopez = EntregaEnMemoria.idLopez;
const _gomez = EntregaEnMemoria.idGomez;

// Los alumnos que suma cada prueba a los tres de siempre.
const _mora = 'a0000000-0000-4000-8000-000000000111';
const _cuota = 'a0000000-0000-4000-8000-000000000112';
const _ficha = 'a0000000-0000-4000-8000-000000000113';
const _tres = 'a0000000-0000-4000-8000-000000000114';
const _cuatro = 'a0000000-0000-4000-8000-000000000115';
const _diez = 'a0000000-0000-4000-8000-000000000116';
const _noEntran = 'a0000000-0000-4000-8000-000000000117';
const _sillas = 'a0000000-0000-4000-8000-000000000118';
const _nueveConSilla = 'a0000000-0000-4000-8000-000000000119';

/// Un alumno más en la fiesta, con la base de $300.000 y lo que se le pase.
/// [pagado]: lo que pagó de la base (viene entera). [extras] mesas adicionales
/// de $70.000 ([mesaPaga]: pagadas) y [sillas] sillas de $8.000 ([sillasPagas]
/// de ellas pagadas). La ficha dice lo que dan los pagos, salvo [saldoFicha].
ContratoAlumno _sumar(
  EntregaEnMemoria e, {
  required String id,
  required String nombre,
  required List<int> mesas,
  int extras = 0,
  bool mesaPaga = true,
  int sillas = 0,
  int sillasPagas = 0,
  int acompanantes = 0,
  List<String> nombres = const [],
  double pagado = 300000,
  double? saldoFicha,
  double mora = 0,
}) {
  final total = 300000 + 70000.0 * extras + 8000.0 * sillas;
  final pagos = pagado + (mesaPaga ? 70000.0 * extras : 0) + 8000.0 * sillasPagas;
  final a = ContratoAlumno(
    id: id,
    eventoId: idFiestaEntrega,
    nombreAlumno: nombre,
    cantidadAcompanantes: acompanantes,
    nombresAcompanantes: nombres,
    montoTotalPactado: total,
    saldoDeudor: saldoFicha ?? (total - pagos),
    totalCuotas: 9,
    cuotasPagadas: 9,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    mesaExtraCuotas: 1,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: 8000.0 * sillas,
    sillasExtraCuotas: 1,
    moraPendienteTracked: mora,
    numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
    cursoDivision: '5° B',
    createdAt: DateTime(2026, 2, 1),
  );
  e.contratos.alumnos.add(a);
  if (pagado > 0) e.contratos.pagos.add(pagoDeLaEntrega(id, pagado, 'Cuota Base (9/9)'));
  if (mesaPaga && extras > 0) {
    e.contratos.pagos.add(pagoDeLaEntrega(id, 70000.0 * extras, 'Mesa Extra 1'));
  }
  if (sillasPagas > 0) {
    e.contratos.pagos.add(pagoDeLaEntrega(id, 8000.0 * sillasPagas, 'Sillas extra (1/1)'));
  }
  return a;
}

/// PÉREZ pagó entera su mesa adicional, pero debe $30.000 de la base: no retira
/// lo sin cargo, y lo de la mesa adicional sí se le vende (regla del 20-nov).
void _perezDebeOtraCosa(EntregaEnMemoria e) {
  final i = e.contratos.alumnos.indexWhere((a) => a.id == _perez);
  e.contratos.alumnos[i] = e.contratos.alumnos[i].copyWith(
    saldoDeudor: 30000,
    mesaExtraCuotasPagadas: 1,
  );
  e.contratos.pagos
    ..removeWhere((p) => p['contrato_alumno_id'] == _perez)
    ..add(pagoDeLaEntrega(_perez, 270000, 'Cuota Base (8/9)'))
    ..add(pagoDeLaEntrega(_perez, 70000, 'Mesa Extra 1'));
}

class _Montada {
  final EntregaEnMemoria e;
  final EntradasEnMemoria entradas;
  final List<DatosDelComprobante> comprobantes;
  final ProviderContainer c;
  _Montada(this.e, this.entradas, this.comprobantes, this.c);

  EnCaja get enCaja => c.read(enCajaProvider(idFiestaEntrega));
}

/// Entra Carla (con "Vende entradas" salvo [vende] false) y toca VENDER.
///
/// [pagaLaMesa]: PÉREZ ya pagó su mesa adicional (si no, la debe: no retira lo
/// sin cargo y lo de su mesa no se le vende). [foto]: lo que cada familia tenía
/// al sorteo. [preparar]: alumnos o pagos de más.
Future<_Montada> _montar(
  WidgetTester tester, {
  bool vende = true,
  bool jefe = false,
  bool cobros = false,
  bool conPrecio = true,
  bool conCaja = true,
  bool aMano = false,
  double recargo = 0,
  bool anticipada = false,
  bool fallaElComprobante = false,
  bool pagaLaMesa = false,
  FotoDeLosLugares? foto,
  void Function(EntregaEnMemoria)? preparar,
  Future<void> Function(EntradasEnMemoria)? ventasDeAntes,
  String? familiaId,
  Size tamano = const Size(1100, 1500),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntregaEnMemoria();
  if (pagaLaMesa) e.cobrar(_perez, 70000);
  preparar?.call(e);
  final entradas = EntradasEnMemoria();
  final comprobantes = <DatosDelComprobante>[];
  if (conPrecio) {
    entradas.conPrecio(
      idFiestaEntrega,
      aMano: aMano,
      recargo: recargo,
      anticipada: anticipada ? 8000 : null,
      hasta: anticipada ? '2026-11-28' : null,
    );
  }
  final c = ProviderContainer(overrides: [
    ...e.reemplazos(jefe: jefe),
    ...entradas.reemplazos,
    hoyEnArgentinaProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 12)),
    if (foto != null) fotoDeLosLugaresProvider.overrideWithValue((_) async => foto),
    abrirComprobanteDeEntradasProvider.overrideWithValue((datos, {context}) async {
      if (fallaElComprobante) throw StateError('sin impresora (prueba)');
      comprobantes.add(datos);
    }),
  ]);
  addTearDown(c.dispose);
  final carla = e.operador(cobros: cobros, vende: vende);
  await c.read(appRoleProvider.notifier).entrarComoEntradas(
        carla,
        PermisosEfectivos(entradas: true, vendeEntradas: vende, cobros: cobros),
      );
  if (conCaja) {
    await entradas.abrirCaja(
      eventoId: idFiestaEntrega,
      operadorId: jefe ? null : carla.id,
      operadorNombre: jefe ? 'Jefe' : 'Carla',
      cambioInicial: 5000,
    );
    entradas.escrituras = 0;
  }
  await ventasDeAntes?.call(entradas);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VenderEntradasScreen(
                    evento: fiestaDeLaEntrega,
                    familiaId: familiaId,
                  ),
                ),
              ),
              child: const Text('ir a vender'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ir a vender'));
  await tester.pumpAndSettle();
  return _Montada(e, entradas, comprobantes, c);
}

String _texto(WidgetTester tester, String clave) {
  final t = tester.widget<Text>(find.byKey(Key(clave)));
  return t.data ?? t.textSpan!.toPlainText();
}

/// El texto de un chip (`ChipDeVender`).
String _chip(WidgetTester tester, String clave) => tester
    .widget<Text>(find.descendant(of: find.byKey(Key(clave)), matching: find.byType(Text)))
    .data!;

String? _falta(WidgetTester tester) {
  final f = find.byKey(const Key('vender_falta'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

bool _apagado(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed == null;

Future<void> _tocar(WidgetTester tester, String clave, {int veces = 1}) async {
  for (var i = 0; i < veces; i++) {
    await tester.ensureVisible(find.byKey(Key(clave)));
    await tester.pump();
    await tester.tap(find.byKey(Key(clave)));
    await tester.pump();
  }
}

Future<void> _poner(WidgetTester tester, String clave, String texto) async {
  await tester.ensureVisible(find.byKey(Key(clave)));
  await tester.pump();
  await tester.enterText(find.byKey(Key(clave)), texto);
  await tester.pump();
}

Future<void> _aAlguienDeAfuera(WidgetTester tester, {int sueltas = 2}) async {
  await tester.tap(find.text('Alguien de afuera'));
  await tester.pump();
  await _tocar(tester, 'vender_sueltas_mas', veces: sueltas);
}

/// Elige al alumno [id] de la lista, con el filtro [filtro] (sin él, el que
/// está).
Future<void> _elegir(WidgetTester tester, String id, {String? filtro}) async {
  if (filtro != null) await _tocar(tester, filtro);
  await tester.ensureVisible(find.byKey(Key('vender_familia_$id')));
  await tester.pump();
  await tester.tap(find.byKey(Key('vender_familia_$id')));
  await tester.pumpAndSettle();
}

/// PÉREZ: con la mesa paga está en "puede retirar"; si debe, en "debe".
Future<void> _elegirAPerez(WidgetTester tester, {bool debe = false}) => _elegir(
      tester,
      _perez,
      filtro: debe ? 'vender_filtro_debe' : null,
    );

Future<void> _confirmarElCobro(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('cobro_confirmar')));
  await tester.pumpAndSettle();
}

/// En la tarjeta: ENTREGAR de [parte], quién retira y CONFIRMAR, por el
/// formulario de la entrega (el mismo de ENTRADAS de la fiesta). [numero]: el
/// primero de las generales, si vienen numeradas.
Future<void> _entregarParte(
  WidgetTester tester,
  ParteEntrega parte, {
  String quien = 'Padre',
  String nombre = 'Hugo López',
  String? numero,
}) async {
  await _tocar(tester, 'vender_entregar_${parte.clave}');
  await tester.pumpAndSettle();
  final formulario = find.byKey(Key('vender_formulario_${parte.clave}'));
  Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
  if (numero != null) {
    await tester.ensureVisible(adentro(find.text('Vienen con número')));
    await tester.tap(adentro(find.text('Vienen con número')));
    await tester.pump();
    await tester.enterText(adentro(find.widgetWithText(TextField, 'Del')), numero);
  }
  await tester.ensureVisible(adentro(find.text(quien)));
  await tester.tap(adentro(find.text(quien)));
  await tester.enterText(
    adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
    nombre,
  );
  final planilla = adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
  await tester.ensureVisible(planilla);
  await tester.tap(planilla);
  await tester.pump();
  await _tocar(tester, 'entrega_confirmar_${parte.clave}');
  await tester.pumpAndSettle();
}

void main() {
  group('quién puede vender', () {
    testWidgets('sin el permiso no se vende: lo dice, y no abre ninguna caja',
        (tester) async {
      final m = await _montar(tester, vende: false, conCaja: false);
      expect(_texto(tester, 'vender_sin_permiso'), kSinPermisoParaVender);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(find.byKey(const Key('vender_gratis')), findsNothing);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(m.entradas.listaCajas, isEmpty);
    });

    // Hasta la 6.9.2, sin precio VENDER mostraba solo el aviso. Desde el 20-nov
    // también entrega lo sin cargo, que no necesita precio ni caja.
    testWidgets('sin precio: lo dice, no pide la caja y lo sin cargo se entrega igual',
        (tester) async {
      final m = await _montar(tester, conPrecio: false, conCaja: false);
      expect(_texto(tester, 'vender_sin_precio'), kLaFiestaNoTienePrecio);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(m.entradas.listaCajas, isEmpty);
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(m.e.estadoDe(_lopez).pulseras.entregada, isTrue);
    });
  });

  group('la caja', () {
    testWidgets('sin caja abierta la pide al entrar, con su cambio inicial', (tester) async {
      final m = await _montar(tester, conCaja: false);
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
      expect(find.textContaining('PUERTO VIEJO · vende Carla'), findsOneWidget);
      await _poner(tester, 'abrir_caja_cambio', '5000');
      await tester.tap(find.byKey(const Key('abrir_caja_abrir')));
      await tester.pumpAndSettle();

      final caja = m.entradas.listaCajas.single;
      expect(caja.cambioInicial, 5000);
      expect(caja.operadorNombre, 'Carla');
      expect(caja.eventoId, idFiestaEntrega);
      expect(caja.abierta, isTrue);
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
    });

    // Hasta la 6.9.2, volver sin abrirla sacaba de VENDER. Desde el 20-nov VENDER
    // se queda: lo sin cargo se entrega sin caja. Y no vuelve a preguntar.
    testWidgets('volver sin abrirla no cierra VENDER, no vuelve a preguntar, y lo sin '
        'cargo se entrega igual', (tester) async {
      final m = await _montar(tester, conCaja: false);
      await tester.tap(find.byKey(const Key('abrir_caja_volver')));
      await tester.pumpAndSettle();
      expect(find.byType(VenderEntradasScreen), findsOneWidget);
      expect(m.entradas.listaCajas, isEmpty);
      expect(_texto(tester, 'vender_linea_texto'), startsWith('Sin caja abierta · Carla'));

      // Baja algo de otro equipo: relee, y no vuelve a pedir la caja.
      m.e.motor.bajo.add({'entradas_ventas'});
      await tester.pumpAndSettle();
      expect(find.text('Abrir la caja de entradas'), findsNothing);

      // Lo sin cargo, sin caja.
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(m.e.estadoDe(_lopez).pulseras.entregada, isTrue);

      // Para cobrar: ABRIR LA CAJA en vez de los medios.
      await tester.tap(find.text('Alguien de afuera'));
      await tester.pump();
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      await _tocar(tester, 'vender_abrir_caja');
      await tester.pumpAndSettle();
      expect(find.text('Abrir la caja de entradas'), findsOneWidget);
      await _poner(tester, 'abrir_caja_cambio', '0');
      await tester.tap(find.byKey(const Key('abrir_caja_abrir')));
      await tester.pumpAndSettle();
      expect(m.entradas.listaCajas, hasLength(1));
      expect(find.byKey(const Key('vender_efectivo')), findsOneWidget);
    });

    testWidgets('con una ya abierta la retoma: tocar dos veces no abre dos',
        (tester) async {
      final m = await _montar(tester);
      expect(find.text('Abrir la caja de entradas'), findsNothing);
      expect(m.entradas.listaCajas, hasLength(1));
      expect(m.entradas.escrituras, 0);
    });
  });

  group('arriba: el total de la fiesta y la planilla', () {
    testWidgets('cuántas pulseras y generales tienen que llegar, y cuántas se entregaron',
        (tester) async {
      await _montar(tester);
      // PÉREZ, LÓPEZ y GÓMEZ: 1 con cena y 7 generales cada uno; GÓMEZ ya retiró
      // las 8 juntas (6.9.x), que cuentan como las dos partes.
      expect(
        _texto(tester, 'vender_total_fiesta'),
        'Total de la fiesta · Pulseras VIP: 3 (entregadas 1) · Generales: 21 '
        '(entregadas 7)',
      );
    });

    testWidgets('la planilla de entrega, una por material', (tester) async {
      await _montar(tester);
      await tester.tap(find.byKey(const Key('vender_planilla')));
      await tester.pumpAndSettle();
      for (final k in [
        'vender_planilla_pulseras_bn',
        'vender_planilla_pulseras_color',
        'vender_planilla_generales_bn',
        'vender_planilla_generales_color',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });
  });

  group('la lista y el filtro', () {
    /// Cada caso de deuda: LÓPEZ pagó todo; PÉREZ debe su mesa adicional; MORA
    /// debe solo mora; CUOTA debe una cuota de la base; FICHA tiene la ficha en
    /// cero y ningún pago (la ficha y los pagos no coinciden); GÓMEZ ya retiró.
    void deudas(EntregaEnMemoria e) {
      _sumar(e, id: _mora, nombre: 'MORA, SOLO', mesas: const [20], mora: 15000);
      _sumar(e, id: _cuota, nombre: 'CUOTA, UNA', mesas: const [21], pagado: 266667);
      _sumar(
        e,
        id: _ficha,
        nombre: 'FICHA, DISTINTA',
        mesas: const [22],
        pagado: 0,
        saldoFicha: 0,
      );
    }

    testWidgets('se ve sin buscar, abre en "puede retirar" y cada uno cae en su grupo',
        (tester) async {
      await _montar(tester, preparar: deudas);
      expect(_chip(tester, 'vender_filtro_puede'), 'Pagó todo: puede retirar (1)');
      expect(_chip(tester, 'vender_filtro_debe'), 'Debe: a caja (3)');
      expect(_chip(tester, 'vender_filtro_revisar'), 'Revisar (1)');
      expect(_chip(tester, 'vender_filtro_ya'), 'Ya retiró (1)');
      expect(_chip(tester, 'vender_filtro_todos'), 'Todos (6)');

      // Sin escribir nada, la lista a la vista: solo los que pueden retirar.
      expect(find.byKey(const Key('vender_familia_$_lopez')), findsOneWidget);
      for (final id in [_perez, _mora, _cuota, _ficha, _gomez]) {
        expect(find.byKey(Key('vender_familia_$id')), findsNothing, reason: id);
      }
      expect(_chip(tester, 'vender_estado_$_lopez'), 'Pagó todo');
      expect(_texto(tester, 'vender_resumen_$_lopez'),
          '1 VIP con cena + 7 generales · nada a pagar');

      await _tocar(tester, 'vender_filtro_debe');
      expect(find.byKey(const Key('vender_familia_$_lopez')), findsNothing);
      expect(_chip(tester, 'vender_estado_$_perez'), r'Debe $ 70.000');
      expect(_chip(tester, 'vender_estado_$_mora'), r'Debe $ 15.000');
      expect(_chip(tester, 'vender_estado_$_cuota'), r'Debe $ 33.333');
      expect(_texto(tester, 'vender_resumen_$_perez'),
          '1 VIP con cena + 7 generales · A pagar: 8 a confirmar');

      await _tocar(tester, 'vender_filtro_revisar');
      expect(_chip(tester, 'vender_estado_$_ficha'), 'Revisar la cuenta');

      await _tocar(tester, 'vender_filtro_ya');
      expect(_chip(tester, 'vender_estado_$_gomez'), '✓ Retiró');

      await _tocar(tester, 'vender_filtro_todos');
      for (final id in [_perez, _lopez, _gomez, _mora, _cuota, _ficha]) {
        expect(find.byKey(Key('vender_familia_$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('lo escrito filtra la lista, y los números del filtro cuentan lo que '
        'coincide', (tester) async {
      await _montar(tester, preparar: deudas);
      await _poner(tester, 'vender_buscar', 'perez');
      expect(_chip(tester, 'vender_filtro_puede'), 'Pagó todo: puede retirar (0)');
      expect(_chip(tester, 'vender_filtro_debe'), 'Debe: a caja (1)');
      expect(find.byKey(const Key('vender_lista_vacia')), findsOneWidget,
          reason: 'PÉREZ debe: no está en "puede retirar"');
      await _tocar(tester, 'vender_filtro_debe');
      expect(find.byKey(const Key('vender_familia_$_perez')), findsOneWidget);
      expect(find.byKey(const Key('vender_familia_$_mora')), findsNothing);
    });

    testWidgets('ninguno que debe tiene ENTREGAR: va a la caja', (tester) async {
      await _montar(tester, preparar: deudas);
      for (final (id, texto) in [
        (
          _perez,
          r'Debe $ 70.000 de su contrato: cuotas y extras $ 70.000. Primero pasa por '
              'caja a saldar todo. Cuando pague, se destraba solo.'
        ),
        (
          _mora,
          r'Debe $ 15.000 de su contrato: mora $ 15.000. Primero pasa por caja a '
              'saldar todo. Cuando pague, se destraba solo.'
        ),
        (
          _cuota,
          r'Debe $ 33.333 de su contrato: cuotas y extras $ 33.333. Primero pasa por '
              'caja a saldar todo. Cuando pague, se destraba solo.'
        ),
      ]) {
        await _elegir(tester, id, filtro: 'vender_filtro_debe');
        expect(_texto(tester, 'vender_gratis_titulo'), 'GRATIS · TODAVÍA NO SE ENTREGA');
        expect(_texto(tester, 'vender_gratis_debe'), texto, reason: id);
        expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
        expect(find.byKey(const Key('vender_entregar_generales')), findsNothing);
        expect(find.byKey(const Key('vender_mandar_a_caja')), findsOneWidget);
        expect(find.byKey(const Key('vender_pasar_a_caja')), findsNothing,
            reason: 'Carla no tiene Cobros');
        await _tocar(tester, 'vender_cambiar_familia');
        await tester.pumpAndSettle();
      }
      // La ficha y los pagos no coinciden: lo revisa el jefe, sin botón.
      await _elegir(tester, _ficha, filtro: 'vender_filtro_revisar');
      expect(_texto(tester, 'vender_gratis_revisar'), contains('Pedile al jefe'));
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
      expect(find.byKey(const Key('vender_mandar_a_caja')), findsNothing);
    });
  });

  group('cuántas VIP y cuántas generales', () {
    void familias(EntregaEnMemoria e) {
      _sumar(
        e,
        id: _tres,
        nombre: 'TRES, CON DOS',
        mesas: const [30],
        acompanantes: 2,
        nombres: const ['MAMÁ TRES', 'PAPÁ TRES'],
      );
      _sumar(
        e,
        id: _cuatro,
        nombre: 'CUATRO, CON TRES',
        mesas: const [31],
        acompanantes: 3,
        nombres: const ['MAMÁ CUATRO', 'PAPÁ CUATRO'],
      );
      _sumar(
        e,
        id: _diez,
        nombre: 'DIEZ, CON NUEVE',
        mesas: const [32, 33],
        extras: 1,
        acompanantes: 9,
      );
      _sumar(e, id: _noEntran, nombre: 'NOENTRAN, DIEZ', mesas: const [34], acompanantes: 9);
    }

    testWidgets('solo el egresado: 1 pulsera y 7 generales', (tester) async {
      await _montar(tester);
      await _elegir(tester, _lopez);
      expect(_texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 1');
      expect(_texto(tester, 'vender_parte_detalle_pulseras'), 'Solo el egresado');
      expect(_texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 7');
      expect(_texto(tester, 'vender_nada_a_pagar'),
          'Nada: no tiene mesa adicional ni sillas extra.');
    });

    testWidgets('con dos acompañantes: 3 con cena, con sus nombres, y 5 generales',
        (tester) async {
      await _montar(tester, preparar: familias);
      expect(_texto(tester, 'vender_resumen_$_tres'),
          '3 VIP con cena + 5 generales · nada a pagar');
      await _elegir(tester, _tres);
      expect(_texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 3');
      expect(_texto(tester, 'vender_parte_detalle_pulseras'),
          'El egresado · MAMÁ TRES · PAPÁ TRES');
      expect(_texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 5');
      expect(find.byKey(const Key('vender_mas_de_dos')), findsNothing);
    });

    testWidgets('con tres acompañantes y uno sin nombre: 4 con cena, "1 sin nombre" y '
        'el aviso del máximo', (tester) async {
      await _montar(tester, preparar: familias);
      await _elegir(tester, _cuatro);
      expect(_texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 4');
      expect(_texto(tester, 'vender_parte_detalle_pulseras'),
          'El egresado · MAMÁ CUATRO · PAPÁ CUATRO · 1 sin nombre');
      expect(_texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 4');
      expect(_texto(tester, 'vender_mas_de_dos'),
          'Tiene 3 acompañantes con cena (el máximo es 2): confirmalo con el jefe.');
    });

    testWidgets('más de 8 con cena y una mesa adicional: sin generales, y en A PAGAR la '
        'mesa adicional sin los lugares de sus VIP', (tester) async {
      await _montar(tester, preparar: familias);
      expect(_texto(tester, 'vender_resumen_$_diez'), '10 VIP con cena · A pagar 6 con 50 %');
      await _elegir(tester, _diez);
      expect(_texto(tester, 'vender_parte_titulo_pulseras'), 'Pulseras VIP con cena · 10');
      expect(_texto(tester, 'vender_parte_titulo_generales'), 'Entradas generales · 0');
      expect(_texto(tester, 'vender_parte_detalle_generales'),
          'No lleva: las 8 de la mesa son con cena.');
      expect(find.byKey(const Key('vender_entregar_generales')), findsNothing);
      expect(_texto(tester, 'vender_linea_mesa_1_titulo'), 'Mesa adicional 33 · 6 entradas');
      // Revisión del 20-nov: decía "2 lugares los ocupan un VIP con cena".
      expect(find.text('2 lugares son de VIP con cena: esas entradas no se pagan.'),
          findsOneWidget);
      // Arriba, GRATIS dice que los 2 de más van en sus lugares adicionales:
      // decía siempre "8 de su mesa" y la parte decía 10.
      expect(_texto(tester, 'vender_gratis_por_contrato'),
          'Por contrato: las 8 de su mesa, y 2 VIP más en sus lugares adicionales, '
          'sin cargo. Cada parte se entrega cuando llega.');
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '6');
      // Con las pulseras se entrega todo: las generales no le tocan.
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(find.byKey(const Key('vender_todo_entregado')), findsOneWidget);
    });

    testWidgets('si no entran, lo revisa el jefe', (tester) async {
      await _montar(tester, preparar: familias);
      await _elegir(tester, _noEntran, filtro: 'vender_filtro_revisar');
      expect(_chip(tester, 'vender_familia_estado'), 'No entran');
      expect(_texto(tester, 'vender_gratis_revisar'),
          'No entran: tiene 10 con cena y 8 lugares. Pedile al jefe que lo revise.');
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
    });
  });

  group('GRATIS: entregar en dos partes', () {
    testWidgets('las pulseras un día y las generales otro, con números', (tester) async {
      final m = await _montar(tester);
      await _elegir(tester, _lopez);
      expect(_texto(tester, 'vender_gratis_titulo'), 'GRATIS · SE ENTREGA');

      await _entregarParte(tester, ParteEntrega.pulseras, quien: 'Madre', nombre: 'Ana López');
      expect(m.e.estadoDe(_lopez).pulseras.entregada, isTrue);
      expect(m.e.estadoDe(_lopez).generales.entregada, isFalse);
      expect(find.byKey(const Key('vender_entregada_pulseras')), findsOneWidget);
      expect(_texto(tester, 'vender_quien_pulseras'), startsWith('Madre ANA LÓPEZ, el '));
      expect(find.byKey(const Key('vender_entregar_generales')), findsOneWidget);
      expect(find.byKey(const Key('vender_todo_entregado')), findsNothing);
      expect(_chip(tester, 'vender_familia_estado'), 'Pagó todo · ✓ pulseras');
      expect(m.e.filasEscritas, 0, reason: 'a medias, la fila de siempre no se toca');
      // Una sola, en singular (revisión del 20-nov: decía "1 pulseras").
      expect(find.textContaining('✓ Entregada 1 pulsera VIP con cena a ANA LÓPEZ'),
          findsOneWidget);
      expect(
        _texto(tester, 'vender_total_fiesta'),
        'Total de la fiesta · Pulseras VIP: 3 (entregadas 2) · Generales: 21 '
        '(entregadas 7)',
      );

      await _entregarParte(tester, ParteEntrega.generales, numero: '5001');
      final e = m.e.estadoDe(_lopez);
      expect(e.todoEntregado, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(5001, 5007)]);
      expect(find.byKey(const Key('vender_todo_entregado')), findsOneWidget);
      expect(_chip(tester, 'vender_familia_estado'), '✓ Retiró');
      expect(m.e.filasEscritas, 1, reason: 'con las dos partes, la fila completa');
      expect(find.textContaining('✓ Todo entregado: LÓPEZ, SOFÍA'), findsOneWidget);
      // VENDER no anula entregas: eso es del jefe, en ENTRADAS de la fiesta.
      expect(find.text('ANULAR ENTREGA'), findsNothing);
    });

    testWidgets('las generales sin número', (tester) async {
      final m = await _montar(tester);
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.generales);
      final e = m.e.estadoDe(_lopez);
      expect(e.generales.entregada, isTrue);
      expect(e.generales.tramos, isEmpty);
      expect(_chip(tester, 'vender_familia_estado'), 'Pagó todo · ✓ generales');
    });

    testWidgets('un número de las generales ya dado a otra familia no se repite',
        (tester) async {
      final m = await _montar(tester);
      await _elegir(tester, _lopez);
      // GÓMEZ, ANA se llevó del 1001 al 1007.
      await _entregarParte(tester, ParteEntrega.generales, numero: '1005');
      expect(find.textContaining('ya se le dio a GÓMEZ, ANA'), findsOneWidget);
      expect(m.e.estadoDe(_lopez).generales.entregada, isFalse);
    });

    // Roturas a propósito del 20-nov-2026: si GRATIS miraba también lo vendido,
    // ningún test de VENDER fallaba (sí el de la entrega de ENTRADAS de la
    // fiesta). Las generales de los alumnos y las anticipadas son dos talonarios.
    testWidgets('las generales pueden llevar un número ya vendido: es otro talonario',
        (tester) async {
      final m = await _montar(
        tester,
        ventasDeAntes: (entradas) async {
          await entradas.vender(
            caja: entradas.listaCajas.single,
            compradorNombre: 'RUIZ, ANA',
            renglones: [
              RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2),
            ],
            medio: MedioBarra.efectivo,
            efectivo: 20000,
            numeros: '5001-5002',
            quien: 'Carla',
          );
        },
      );
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.generales, numero: '5001');
      expect(find.textContaining('ya se'), findsNothing);
      final e = m.e.estadoDe(_lopez);
      expect(e.generales.entregada, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(5001, 5007)]);
    });

    testWidgets('sin internet pregunta antes; con CANCELAR no guarda nada', (tester) async {
      final m = await _montar(tester);
      m.e.conexion.cambiar(AppConnectivity.offline);
      await tester.pumpAndSettle();
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('CANCELAR')),
      );
      await tester.pumpAndSettle();
      expect(m.e.estadoDe(_lopez).pulseras.entregada, isFalse);
      expect(find.byKey(const Key('vender_formulario_pulseras')), findsOneWidget,
          reason: 'el formulario queda con lo escrito');
    });

    testWidgets('si otro equipo ya las entregó: "Ya retiró", y no se guarda dos veces',
        (tester) async {
      final m = await _montar(tester);
      await _elegir(tester, _lopez);
      await _tocar(tester, 'vender_entregar_pulseras');
      await tester.pumpAndSettle();
      // Mientras tanto, otro equipo las entrega.
      m.e.partes.renglones.add(EntregaEntradas.entrega(
        contratoAlumnoId: _lopez,
        eventoId: idFiestaEntrega,
        parte: ParteEntrega.pulseras,
        cantidad: 1,
        parentesco: ParentescoRetiro.madre,
        nombre: 'Otra Madre',
        escribioEnPlanilla: true,
        hechoPor: 'Jefe',
        deviceId: 'otra-pc',
        ahora: DateTime.utc(2026, 11, 20, 12),
      ));
      final formulario = find.byKey(const Key('vender_formulario_pulseras'));
      Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
      await tester.tap(adentro(find.text('Padre')));
      await tester.enterText(
        adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
        'Hugo López',
      );
      final planilla =
          adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
      await tester.ensureVisible(planilla);
      await tester.tap(planilla);
      await tester.pump();
      await _tocar(tester, 'entrega_confirmar_pulseras');
      await tester.pumpAndSettle();
      expect(find.text('Ya retiró'), findsOneWidget);
      expect(m.e.renglonesDe(_lopez), hasLength(1));
    });

    testWidgets('quien debe no retira lo sin cargo, pero compra lo que ya pagó entero',
        (tester) async {
      final m = await _montar(tester, preparar: _perezDebeOtraCosa);
      await _elegirAPerez(tester, debe: true);
      expect(_texto(tester, 'vender_gratis_debe'),
          startsWith(r'Debe $ 30.000 de su contrato: cuotas y extras $ 30.000.'));
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing);
      // La mesa adicional está paga entera: esas sí.
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
      await _poner(tester, 'vender_comprador', 'PEREZ MARTA');
      expect(_falta(tester), isNull);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(m.e.estadoDe(_perez).algoEntregado, isFalse);
    });

    testWidgets('MANDAR A CAJA: queda "En caja", y cuando baja el pago salta "pagó todo: '
        'ya podés entregar"', (tester) async {
      final m = await _montar(tester);
      await _elegirAPerez(tester, debe: true);
      await _tocar(tester, 'vender_mandar_a_caja');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_familia_elegida')), findsNothing,
          reason: 'vuelve a la lista');
      expect(m.enCaja.contiene(_perez), isTrue);
      expect(find.byKey(const Key('vender_en_caja_$_perez')), findsOneWidget);

      // La otra PC cobra: baja el pago y la ficha.
      m.e.cobrar(_perez, 70000);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_pago_texto_$_perez'),
          'PÉREZ, JUAN pagó todo: ya podés entregar');
      await _tocar(tester, 'vender_pago_abrir_$_perez');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsOneWidget);
      await _entregarParte(tester, ParteEntrega.pulseras);
      expect(m.enCaja.contiene(_perez), isFalse, reason: 'entregado, sale de "En caja"');
    });

    // Revisión independiente del 20-nov-2026: lo que bajaba con el cartel de
    // una entrega abierto se tiraba (VENDER estaba "ocupado") y no se releía
    // hasta la próxima bajada.
    testWidgets('el pago que baja con el cartel de una entrega abierto no se pierde: '
        'al cerrarlo salta "pagó todo"', (tester) async {
      final m = await _montar(tester);
      await _elegirAPerez(tester, debe: true);
      await _tocar(tester, 'vender_mandar_a_caja');
      await tester.pumpAndSettle();
      expect(m.enCaja.contiene(_perez), isTrue);

      // Se entrega a LÓPEZ, y otro equipo ya se las había dado: sale "Ya retiró".
      await _elegir(tester, _lopez, filtro: 'vender_filtro_puede');
      await _tocar(tester, 'vender_entregar_pulseras');
      await tester.pumpAndSettle();
      m.e.partes.renglones.add(EntregaEntradas.entrega(
        contratoAlumnoId: _lopez,
        eventoId: idFiestaEntrega,
        parte: ParteEntrega.pulseras,
        cantidad: 1,
        parentesco: ParentescoRetiro.madre,
        nombre: 'Otra Madre',
        escribioEnPlanilla: true,
        hechoPor: 'Jefe',
        deviceId: 'otra-pc',
        ahora: DateTime.utc(2026, 11, 20, 12),
      ));
      final formulario = find.byKey(const Key('vender_formulario_pulseras'));
      Finder adentro(Finder f) => find.descendant(of: formulario, matching: f);
      await tester.tap(adentro(find.text('Padre')));
      await tester.enterText(
        adentro(find.widgetWithText(TextField, 'Nombre y apellido de quien retira')),
        'Hugo López',
      );
      final planilla =
          adentro(find.text('Escribió su nombre y apellido en la planilla de papel'));
      await tester.ensureVisible(planilla);
      await tester.tap(planilla);
      await tester.pump();
      await _tocar(tester, 'entrega_confirmar_pulseras');
      await tester.pumpAndSettle();
      expect(find.text('Ya retiró'), findsOneWidget);

      // Con el cartel abierto, la otra PC le cobra a PÉREZ y baja el pago.
      m.e.cobrar(_perez, 70000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ENTENDIDO'));
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_pago_texto_$_perez'),
          'PÉREZ, JUAN pagó todo: ya podés entregar');
    });

    // Revisión del 20-nov-2026: VENDER queda abierto toda la noche. Si al
    // completar la fila la nube no contestaba, no se volvía a intentar.
    testWidgets('si la nube no contesta al completar la fila, se vuelve a intentar en '
        'la próxima lectura', (tester) async {
      final m = await _montar(
        tester,
        preparar: (e) {
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18));
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.generales, DateTime.utc(2026, 11, 19));
          e.nubeQueNoContesta = 1;
        },
      );
      expect(m.e.entregas.filas[_lopez], isNull, reason: 'la nube no contestó');
      m.e.motor.bajo.add({'entradas_entregas'});
      await tester.pumpAndSettle();
      expect(m.e.entregas.filas[_lopez]?.entregado, isTrue);
    });

    testWidgets('la fila que dice "entregado" con las pulseras anuladas se pone al día',
        (tester) async {
      final m = await _montar(
        tester,
        preparar: (e) {
          final g = e.entregadaEnOtroEquipo(
              _lopez, ParteEntrega.generales, DateTime.utc(2026, 11, 19));
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18));
          final lopez = e.contratos.alumnos.firstWhere((a) => a.id == _lopez);
          e.entregas.filas[_lopez] = RetiroEntradas.nuevaEntrega(
            alumno: lopez,
            entradas: RetiroEntradas.entradasDe(lopez),
            tramos: const [],
            menores10: 0,
            parentesco: ParentescoRetiro.madre,
            nombre: 'MADRE, UNA',
            quien: 'Sofi',
            ahora: g.createdAt,
          );
          e.anuladaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 20));
        },
      );
      expect(m.e.entregas.filas[_lopez]!.entregado, isFalse);
      expect(m.e.entregas.filas[_lopez]!.anuladoMotivo,
          'Solo las pulseras VIP con cena: eran de otro');
    });

    testWidgets('sin el permiso de vender, VENDER no pone al día ninguna fila',
        (tester) async {
      final m = await _montar(
        tester,
        vende: false,
        preparar: (e) {
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.pulseras, DateTime.utc(2026, 11, 18));
          e.entregadaEnOtroEquipo(_lopez, ParteEntrega.generales, DateTime.utc(2026, 11, 19));
        },
      );
      expect(m.e.entregas.filas[_lopez], isNull);
      expect(m.e.filasEscritas, 0);
    });

    testWidgets('PASAR A CAJA, solo con el permiso de Cobros: va a la caja sin el PIN',
        (tester) async {
      final m = await _montar(tester, cobros: true);
      await _elegirAPerez(tester, debe: true);
      await _tocar(tester, 'vender_pasar_a_caja');
      await tester.pumpAndSettle();
      expect(m.c.read(appRoleProvider).esCaja, isTrue);
      expect(m.enCaja.contiene(_perez), isTrue);
    });
  });

  group('A PAGAR: solo lo pago entero', () {
    // 20-nov-2026: A PAGAR va por cosa pagada. La mesa adicional que no está paga
    // entera no se vende (hasta la 6.9.1, "se le vende igual").
    testWidgets('la mesa adicional que debe: "a confirmar", apagada y sin botones',
        (tester) async {
      await _montar(tester);
      await _elegirAPerez(tester, debe: true);
      expect(_texto(tester, 'vender_linea_mesa_1_titulo'), 'Mesa adicional 13 · 8 entradas');
      expect(_texto(tester, 'vender_linea_mesa_1_a_confirmar'),
          'A confirmar: falta pagarla en caja.');
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);
      expect(find.byKey(const Key('vender_a_pagar_motivo')), findsNothing,
          reason: 'la línea ya lo dice: no se repite');
      expect(find.byKey(const Key('vender_comprador')), findsNothing,
          reason: 'sin nada para comprar no se cobra');
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
    });

    testWidgets('con la mesa adicional paga: el precio con el descuento, el entero '
        'tachado, y nunca más de las que le quedan', (tester) async {
      await _montar(tester, pagaLaMesa: true);
      await _elegirAPerez(tester);
      expect(_chip(tester, 'vender_linea_mesa_1_chip'), 'Con descuento 50 %');
      expect(_texto(tester, 'vender_linea_mesa_1_precio'), r'$ 5.000 c/u  $ 10.000');
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '8',
          reason: 'viene con todas las que le quedan');
      expect(
        tester.widget<IconButton>(find.byKey(const Key('vender_linea_mesa_1_mas'))).onPressed,
        isNull,
        reason: 'el tope',
      );
      await _tocar(tester, 'vender_linea_mesa_1_menos', veces: 3);
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '5');
      expect(_texto(tester, 'vender_linea_mesa_1_subtotal'), r'$ 25.000');
      expect(_texto(tester, 'vender_total'), r'$ 25.000');
      expect(_texto(tester, 'vender_cantidad'), 'Total a pagar · 5 entradas');
      expect(_texto(tester, 'vender_talonario_titulo'),
          'Talonario de las anticipadas · las 5 que paga');
      await _poner(tester, 'vender_comprador', 'PEREZ MARTA');
      expect(_falta(tester), isNull);
    });

    testWidgets('lo agregado después del sorteo, pago: sin descuento, al precio del día',
        (tester) async {
      // Al sorteo PÉREZ tenía solo la mesa del contrato: la adicional la agregó
      // después.
      await _montar(
        tester,
        pagaLaMesa: true,
        foto: FotoDeLosLugares.anotada({_perez: LugaresCargados.soloElContrato}),
      );
      await _elegirAPerez(tester);
      expect(_texto(tester, 'vender_linea_mesa_1_titulo'),
          'Mesa adicional 13, agregada después del sorteo · 8 entradas');
      expect(_chip(tester, 'vender_linea_mesa_1_chip'), 'Sin descuento');
      expect(_texto(tester, 'vender_linea_mesa_1_precio'), r'$ 10.000 c/u · precio del día');
      expect(_texto(tester, 'vender_total'), r'$ 80.000');
      await _tocar(tester, 'vender_linea_mesa_1_menos', veces: 3);
      expect(_texto(tester, 'vender_total'), r'$ 50.000');
    });

    testWidgets('con la anticipada, lo agregado después va a la anticipada y las de '
        'lugar no bajan', (tester) async {
      await _montar(
        tester,
        anticipada: true,
        pagaLaMesa: true,
        foto: FotoDeLosLugares.anotada({_perez: LugaresCargados.soloElContrato}),
      );
      await _elegirAPerez(tester);
      expect(_texto(tester, 'vender_linea_mesa_1_precio'),
          r'$ 8.000 c/u · precio del día (anticipada)');
      expect(_texto(tester, 'vender_total'), r'$ 64.000');
    });

    testWidgets('las sillas: las del sorteo con descuento y la de después aparte; la que '
        'no está paga, a confirmar', (tester) async {
      await _montar(
        tester,
        preparar: (e) => _sumar(
          e,
          id: _sillas,
          nombre: 'SILLAS, CON TRES',
          mesas: const [40],
          sillas: 3,
          sillasPagas: 2,
        ),
        // Al sorteo tenía la mesa y 2 sillas: la tercera la agregó después.
        foto: FotoDeLosLugares.anotada({_sillas: const LugaresCargados(1, 2)}),
      );
      await _elegir(tester, _sillas, filtro: 'vender_filtro_debe');
      expect(_texto(tester, 'vender_linea_sillas_titulo'), 'Sillas extra · 2 entradas');
      expect(_chip(tester, 'vender_linea_sillas_chip'), 'Con descuento 50 %');
      expect(_texto(tester, 'vender_linea_sillas_cantidad'), '2');
      expect(_texto(tester, 'vender_linea_sillas_despues_titulo'),
          'Silla extra, agregada después del sorteo · 1 entrada');
      expect(_texto(tester, 'vender_linea_sillas_despues_a_confirmar'),
          'A confirmar: falta pagarla en caja.');
      expect(find.byKey(const Key('vender_linea_sillas_despues_mas')), findsNothing);
      expect(_texto(tester, 'vender_total'), r'$ 10.000');
    });

    // Revisión del 20-nov-2026: A PAGAR sigue la misma regla que el diálogo de
    // la entrega, y con la ficha distinta de los pagos no se vende ("la cuenta
    // puede estar mal"). Hasta esa revisión, con el pago bajado y la ficha no,
    // la mesa ya se habilitaba; ahora espera a que bajen los dos (casi siempre
    // bajan juntos: el cobro escribe los dos).
    testWidgets('con VENDER abierto, bajan el pago de la mesa adicional y la ficha: se '
        'habilita sola, y lo sin cargo se destraba', (tester) async {
      final m = await _montar(tester);
      await _elegirAPerez(tester, debe: true);
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);

      // Llega solo el pago (la ficha todavía no bajó): la ficha y los pagos no
      // coinciden, y hasta aclararlo no se le vende.
      m.e.contratos.pagos.add(pagoDeLaEntrega(_perez, 70000, 'Mesa Extra 1'));
      m.e.motor.bajo.add({'pagos_contrato_alumno'});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);
      expect(_texto(tester, 'vender_a_pagar_motivo'),
          'Hasta que el jefe revise su cuenta no se le vende: pedile que la revise.');
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsNothing,
          reason: 'la ficha todavía dice que debe');

      // Baja la ficha: la mesa adicional se habilita y lo sin cargo se destraba.
      final i = m.e.contratos.alumnos.indexWhere((a) => a.id == _perez);
      m.e.contratos.alumnos[i] =
          m.e.contratos.alumnos[i].copyWith(saldoDeudor: 0, mesaExtraCuotasPagadas: 1);
      m.e.motor.bajo.add({'contratos_alumnos'});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsOneWidget,
          reason: 'la mesa adicional ya está paga');
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
      expect(_texto(tester, 'vender_gratis_titulo'), 'GRATIS · SE ENTREGA');
      expect(find.byKey(const Key('vender_entregar_pulseras')), findsOneWidget);
      expect(find.byKey(const Key('vender_entregar_generales')), findsOneWidget);
    });

    testWidgets('lo que ya compró no se vuelve a vender', (tester) async {
      final m = await _montar(tester, pagaLaMesa: true);
      await _elegirAPerez(tester);
      await _poner(tester, 'vender_comprador', 'perez marta');
      await _poner(tester, 'vender_dni', '30111222');
      await _poner(tester, 'vender_del', '2000');
      expect(_texto(tester, 'vender_total'), r'$ 40.000');
      expect(_texto(tester, 'vender_al_calculado'), 'al 2007');

      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      expect(find.text('Pagar en efectivo'), findsOneWidget);
      expect(_texto(tester, 'cobro_a_cobrar'), r'$ 40.000');
      await _confirmarElCobro(tester);

      final v = m.entradas.listaVentas.single;
      expect(v.numero, 1);
      expect(v.total, 40000);
      expect(v.efectivo, 40000);
      expect(v.medio, MedioBarra.efectivo);
      expect(v.cantidad, 8);
      expect(v.cuantas(TipoRenglonEntradas.lugar), 8);
      expect(v.contratoAlumnoId, _perez);
      expect(v.compradorNombre, 'perez marta');
      expect(v.compradorDni, '30111222');
      expect(v.numeros, '2000-2007');
      expect(v.hechoPor, 'Carla');
      expect(v.cajaEntradasId, m.entradas.listaCajas.single.id);

      // El comprobante no sale solo (22-nov-2026): lo saca IMPRIMIR EL
      // COMPROBANTE del aviso, de esa venta, con el alumno y su mesa.
      expect(m.comprobantes, isEmpty);
      await _tocar(tester, 'vender_ver_comprobante');
      await tester.pumpAndSettle();
      final c = m.comprobantes.single;
      expect(c.venta.id, v.id);
      expect(c.fiesta, 'PUERTO VIEJO');
      expect(c.alumno, 'PÉREZ, JUAN');
      expect(c.mesa, '12-13');
      expect(c.copia, isFalse);

      // Hasta la 6.9.2 la pantalla volvía al buscador; desde el 20-nov la familia
      // queda elegida (le puede faltar retirar lo sin cargo), sin lo escrito.
      expect(find.textContaining(r'Venta N° 0001 guardada · 8 entradas · $ 40.000'),
          findsOneWidget);
      expect(find.byKey(const Key('vender_familia_elegida')), findsOneWidget);
      expect(find.byKey(const Key('vender_comprador')), findsNothing,
          reason: 'ya no le queda nada para comprar');
      expect(_texto(tester, 'vender_linea_mesa_1_ya_compro'), 'Ya compró las de esta línea.');
      // Revisión del 20-nov: abajo se repetía "Ya compró todas las entradas de sus
      // lugares adicionales." justo debajo de la línea que ya lo decía.
      expect(find.byKey(const Key('vender_a_pagar_motivo')), findsNothing);
    });
  });

  // Lo que encontró la revisión del 20-nov-2026 en A PAGAR.
  group('A PAGAR: la misma regla que el diálogo de la entrega', () {
    // VENDER le vendía a una familia que el diálogo de ENTRADAS frenaba: PÉREZ
    // tiene la mesa adicional paga pero una sola mesa en el salón ("le falta 1
    // mesa"), y se le cobraban las 8 de una mesa sin número.
    testWidgets('con las mesas mal cargadas no se le vende, aunque la mesa adicional '
        'esté paga: lo revisa el jefe', (tester) async {
      await _montar(
        tester,
        pagaLaMesa: true,
        preparar: (e) {
          final i = e.contratos.alumnos.indexWhere((a) => a.id == _perez);
          e.contratos.alumnos[i] = e.contratos.alumnos[i].copyWith(
            numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [12]),
          );
        },
      );
      await _tocar(tester, 'vender_filtro_revisar');
      await tester.pumpAndSettle();
      // En la lista tampoco dice "nada a pagar": tiene cosas pagas, frenadas.
      expect(_texto(tester, 'vender_resumen_$_perez'),
          '1 VIP con cena + 7 generales · A pagar: lo revisa el jefe');
      await _elegir(tester, _perez);
      expect(_texto(tester, 'vender_gratis_revisar'), contains('pedile al jefe'));
      expect(_texto(tester, 'vender_a_pagar_motivo'),
          'Hasta que el jefe revise sus mesas no se le vende: pedile que lo revise.');
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);
      expect(find.byKey(const Key('vender_comprador')), findsNothing);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(find.byKey(const Key('vender_total')), findsNothing);
    });

    // Revisión independiente del 20-nov-2026: si además debía algo, la deuda
    // tapaba el freno de las mesas (`RetiroEntradas.bloqueo` mira la deuda
    // primero) y se le cobraban las 8 de una mesa sin número en el salón. A
    // PAGAR va con `RetiroEntradas.bloqueoDeLaVenta`.
    testWidgets('con las mesas mal cargadas y algo debido tampoco se le vende: la '
        'deuda no tapa el freno', (tester) async {
      await _montar(
        tester,
        preparar: (e) {
          _perezDebeOtraCosa(e);
          final i = e.contratos.alumnos.indexWhere((a) => a.id == _perez);
          e.contratos.alumnos[i] = e.contratos.alumnos[i].copyWith(
            numeroMesa: MesasExtraUtils.formatearAsignacionMesas(const [12]),
          );
        },
      );
      // Debe: cae en "a caja", no en "revisar" (para lo sin cargo frena la deuda).
      await _tocar(tester, 'vender_filtro_debe');
      await tester.pumpAndSettle();
      await _elegir(tester, _perez);
      expect(_texto(tester, 'vender_a_pagar_motivo'),
          'Hasta que el jefe revise sus mesas no se le vende: pedile que lo revise.');
      expect(find.byKey(const Key('vender_linea_mesa_1_mas')), findsNothing);
      expect(find.byKey(const Key('vender_comprador')), findsNothing);
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      expect(find.byKey(const Key('vender_total')), findsNothing);
    });

    // La 6.9.0 vendía las de la mesa adicional antes de que estuviera paga. Ya
    // las compró: la línea no puede decir "A confirmar" mientras la cuenta dice
    // que pagarla no le da nada más.
    testWidgets('compró las de su mesa adicional antes de pagarla: la línea no dice "a '
        'confirmar"', (tester) async {
      await _montar(
        tester,
        ventasDeAntes: (en) async {
          await en.vender(
            caja: en.listaCajas.first,
            contratoAlumnoId: _perez,
            compradorNombre: 'PÉREZ, MARTA',
            renglones: [
              RenglonEntradas.lugar(
                nombre: 'Entrada de lugar adicional (50 %)',
                precioLista: 10000,
                descuentoPct: 50,
                cantidad: 8,
              ),
            ],
            medio: MedioBarra.efectivo,
            efectivo: 40000,
            quien: 'Carla',
          );
        },
      );
      await _elegirAPerez(tester, debe: true);
      expect(find.byKey(const Key('vender_linea_mesa_1_a_confirmar')), findsNothing);
      expect(_texto(tester, 'vender_linea_mesa_1_ya_compro'), 'Ya compró las de esta línea.');
      expect(find.byKey(const Key('vender_a_pagar_motivo')), findsNothing,
          reason: 'la línea ya lo dice');
      expect(find.byKey(const Key('vender_comprador')), findsNothing);
    });

    // Lo que explica por qué no se vende no va apagado: el naranja al 60 % casi
    // no se leía.
    testWidgets('"A confirmar" va con su color entero; lo apagado es el título',
        (tester) async {
      await _montar(tester);
      await _elegirAPerez(tester, debe: true);
      final opacidades = tester
          .widgetList<Opacity>(find.ancestor(
            of: find.byKey(const Key('vender_linea_mesa_1_a_confirmar')),
            matching: find.byType(Opacity),
          ))
          .map((o) => o.opacity);
      expect(opacidades.every((o) => o == 1), isTrue);
      final delTitulo = tester
          .widgetList<Opacity>(find.ancestor(
            of: find.byKey(const Key('vender_linea_mesa_1_titulo')),
            matching: find.byType(Opacity),
          ))
          .map((o) => o.opacity);
      expect(delTitulo, contains(0.6));
    });

    // Con 9 con cena y una silla extra, la silla la ocupa un VIP: no tiene
    // entradas para comprar, pero el lugar se paga con el contrato. Decía "no se
    // paga" con la familia debiéndolo.
    testWidgets('la silla que ocupa un VIP y no está paga: no dice que no se paga',
        (tester) async {
      await _montar(
        tester,
        preparar: (e) => _sumar(
          e,
          id: _nueveConSilla,
          nombre: 'NUEVE, CON SILLA',
          mesas: const [41],
          acompanantes: 8,
          sillas: 1,
        ),
      );
      await _elegir(tester, _nueveConSilla, filtro: 'vender_filtro_debe');
      expect(
        _texto(tester, 'vender_linea_sillas_sin_entradas'),
        'La ocupan sus VIP con cena: no hay entradas para comprar. (el lugar se '
        'paga en caja con el contrato)',
      );
    });
  });

  group('alguien de afuera, como siempre', () {
    testWidgets('nombre y apellido son obligatorios: sin eso los medios están apagados '
        'y dice por qué', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester);
      expect(_falta(tester), 'Escribí nombre y apellido de quien compra');
      for (final b in ['vender_efectivo', 'vender_transferencia', 'vender_mixto']) {
        expect(_apagado(tester, b), isTrue, reason: b);
      }
      await _poner(tester, 'vender_comprador', 'Carla');
      expect(_falta(tester), 'Escribí nombre y apellido de quien compra',
          reason: 'una sola palabra no alcanza');
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), isNull);
      expect(_apagado(tester, 'vender_efectivo'), isFalse);
      expect(_texto(tester, 'vender_total'), r'$ 20.000');
      expect(_texto(tester, 'vender_cantidad'), 'Total a pagar · 2 entradas');
    });

    testWidgets('sin entradas elegidas tampoco se puede', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 0);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), 'Elegí cuántas entradas lleva');
      expect(_apagado(tester, 'vender_efectivo'), isTrue);
    });

    testWidgets('el descuento a mano, solo con permiso: apagado y con el motivo',
        (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester);
      final campo = tester.widget<TextField>(find.byKey(const Key('vender_descuento')));
      expect(campo.enabled, isFalse);
      expect(_texto(tester, 'vender_descuento_motivo'), contains(kSoloEnModoJefe));
      expect(_texto(tester, 'vender_total'), r'$ 20.000');
    });

    testWidgets('si el jefe lo permitió en PRECIOS, quien vende descuenta', (tester) async {
      await _montar(tester, aMano: true);
      await _aAlguienDeAfuera(tester);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vender_descuento'))).enabled,
        isTrue,
      );
      expect(find.byKey(const Key('vender_descuento_motivo')), findsNothing);
      await _poner(tester, 'vender_descuento', '20');
      expect(_texto(tester, 'vender_total'), r'$ 16.000');
      expect(_texto(tester, 'vender_sueltas_subtotal'), r'$ 16.000');
    });

    testWidgets('con la anticipada dice "anticipada" y cobra ese precio', (tester) async {
      await _montar(tester, anticipada: true);
      await _aAlguienDeAfuera(tester);
      expect(find.text('Entradas (anticipada)'), findsOneWidget);
      expect(_texto(tester, 'vender_sueltas_subtotal'), r'$ 16.000');
    });

    testWidgets('por transferencia, con el recargo de la fiesta', (tester) async {
      final m = await _montar(tester, recargo: 5);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_transferencia');
      await tester.pumpAndSettle();
      expect(_texto(tester, 'cobro_transfiere'), r'$ 21.000');
      await _confirmarElCobro(tester);
      final v = m.entradas.listaVentas.single;
      expect(v.medio, MedioBarra.transferencia);
      expect(v.total, 20000);
      expect(v.recargo, 1000);
      expect(v.transferencia, 21000);
      expect(v.efectivo, 0);
    });

    testWidgets('en modo jefe, con el 100 % de descuento se guarda sin cobrar',
        (tester) async {
      final m = await _montar(tester, jefe: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'INVITADA DEL JEFE');
      await _poner(tester, 'vender_descuento', '100');
      expect(_texto(tester, 'vender_total'), r'$ 0');
      expect(find.byKey(const Key('vender_efectivo')), findsNothing);
      await _tocar(tester, 'vender_sin_cargo');
      await tester.pumpAndSettle();
      expect(find.text('Venta sin cargo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vender_sin_cargo_confirmar')));
      await tester.pumpAndSettle();
      final v = m.entradas.listaVentas.single;
      expect(v.total, 0);
      expect(v.descuento, 20000, reason: 'el descuento queda escrito en la venta');
      expect(v.cantidad, 2);
    });
  });

  group('el talonario de las anticipadas', () {
    testWidgets('los números son opcionales, y el "al" se calcula solo', (tester) async {
      await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 4);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), isNull);
      expect(_texto(tester, 'vender_al_calculado'), 'al …',
          reason: 'la caja todavía no vendió nada: no hay número propuesto');
      expect(_texto(tester, 'vender_talonario_titulo'),
          'Talonario de las anticipadas · las 4 que paga');
      await _poner(tester, 'vender_del', '3000');
      expect(_texto(tester, 'vender_al_calculado'), 'al 3003');
      expect(_falta(tester), isNull);
    });

    testWidgets('propone el que sigue al último que vendió esta caja; se puede cambiar o '
        'borrar', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      // La primera venta de la caja: no hay número que proponer, y el texto no
      // dice que viene uno (revisión del 20-nov-2026).
      expect(_texto(tester, 'vender_talonario_ayuda'),
          'Opcional: escribí el primer número de las anticipadas que entregás.');
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '3000');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '3000-3001');

      String del() =>
          tester.widget<TextField>(find.byKey(const Key('vender_del'))).controller!.text;
      expect(del(), '3002', reason: 'el que sigue');
      expect(_texto(tester, 'vender_talonario_ayuda'),
          'Opcional. Viene el número que sigue al último que vendió esta caja: se '
          'puede cambiar o borrar.');
      await _tocar(tester, 'vender_sueltas_mas', veces: 2);
      expect(_texto(tester, 'vender_al_calculado'), 'al 3003');

      // Lo borra: se vende sin números, y no se lo vuelve a proponer.
      await _poner(tester, 'vender_comprador', 'RUIZ MARTA');
      await _poner(tester, 'vender_del', '');
      m.e.motor.bajo.add({'entradas_config'});
      await tester.pumpAndSettle();
      expect(del(), '', reason: 'lo que escribió quien vende no se pisa');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.last.numeros, isNull);
      expect(del(), '3002', reason: 'después de la venta vuelve a proponer');
    });

    // Hasta la 6.9.2 este número no se vendía ("El 1006 ya se le dio a GÓMEZ,
    // ANA"). Cambió a propósito el 20-nov: lo que se vende sale del talonario de
    // las anticipadas, y lo entregado sin cargo es otro.
    testWidgets('pueden repetir uno ya entregado sin cargo: es otro talonario',
        (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '1006');
      expect(_falta(tester), isNull, reason: 'GÓMEZ, ANA tiene del 1001 al 1007 entregados');
      expect(_apagado(tester, 'vender_efectivo'), isFalse);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '1006-1007');
    });

    testWidgets('no pueden repetir uno ya vendido', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '3000');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '3000-3001');

      await _tocar(tester, 'vender_sueltas_mas', veces: 2);
      await _poner(tester, 'vender_comprador', 'RUIZ MARTA');
      await _poner(tester, 'vender_del', '3001');
      expect(_falta(tester), 'El 3001 ya se le dio a GOMEZ CARLA (3000 al 3001).');
      expect(_apagado(tester, 'vender_efectivo'), isTrue);
      await _poner(tester, 'vender_del', '3002');
      expect(_falta(tester), isNull);
    });

    testWidgets('dos tramos, cuando el talonario salta', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester, sueltas: 8);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_dos_tramos');
      await _poner(tester, 'vender_del', '100');
      await _poner(tester, 'vender_al', '104');
      await _poner(tester, 'vender_del_2', '200');
      expect(_texto(tester, 'vender_al_calculado'), 'al 202');
      expect(_falta(tester), isNull);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '100-104,200-202');
    });
  });

  group('cobrar y guardar', () {
    testWidgets(
        'el comprobante no sale solo: IMPRIMIR EL COMPROBANTE saca el original y '
        'después VER DE NUEVO, la COPIA (22-nov-2026)', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas, hasLength(1));
      expect(m.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      expect(
        find.descendant(
          of: find.byKey(const Key('vender_ver_comprobante')),
          matching: find.text('IMPRIMIR EL COMPROBANTE'),
        ),
        findsOneWidget,
      );
      await _tocar(tester, 'vender_ver_comprobante');
      await tester.pumpAndSettle();
      expect(m.comprobantes, hasLength(1));
      expect(m.comprobantes.single.copia, isFalse, reason: 'la primera vez, el original');
      expect(m.comprobantes.single.alumno, isNull, reason: 'compró alguien de afuera');
      expect(
        find.descendant(
          of: find.byKey(const Key('vender_ver_comprobante')),
          matching: find.text('VER DE NUEVO'),
        ),
        findsOneWidget,
      );
      await _tocar(tester, 'vender_ver_comprobante');
      await tester.pumpAndSettle();
      expect(m.comprobantes, hasLength(2));
      expect(m.comprobantes.last.copia, isTrue, reason: 'después, la COPIA');
    });

    testWidgets('volver del cobro no guarda nada', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_mixto');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cobro_volver')));
      await tester.pumpAndSettle();
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.comprobantes, isEmpty);
      expect(_texto(tester, 'vender_total'), r'$ 20.000', reason: 'sigue lo escrito');
    });

    testWidgets('si la base no anda, lo dice y no pierde lo escrito', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      m.entradas.falla = true;
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(find.text('No se guardó la venta. Probá de nuevo.'), findsOneWidget);
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.comprobantes, isEmpty);
      expect(
        tester.widget<TextField>(find.byKey(const Key('vender_comprador'))).controller!.text,
        'GOMEZ CARLA',
      );
      expect(find.byKey(const Key('vender_guardada')), findsNothing);
    });

    testWidgets('sin impresora la venta igual queda; el comprobante se puede volver '
        'a pedir', (tester) async {
      final m = await _montar(tester, fallaElComprobante: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas, hasLength(1));
      expect(find.byKey(const Key('vender_guardada')), findsOneWidget);
      await _tocar(tester, 'vender_ver_comprobante');
      await tester.pumpAndSettle();
      expect(find.textContaining('La venta está guardada'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('vender_ver_comprobante')),
          matching: find.text('IMPRIMIR EL COMPROBANTE'),
        ),
        findsOneWidget,
        reason: 'no salió: el próximo sigue siendo el original',
      );
    });
  });

  group('la línea de arriba', () {
    testWidgets('dice cuántas ventas esperan subir, también sin internet',
        (tester) async {
      final m = await _montar(tester);
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · 1 venta subiendo');
      m.e.conexion.cambiar(AppConnectivity.offline);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · Sin internet · 1 venta por subir');
    });

    // Etapa 7: el aviso del motor sale al bajar, no al subir. Sin escuchar lo
    // pendiente, la línea quedaba en "1 venta subiendo" aunque la venta ya hubiera
    // subido, hasta la próxima venta o la próxima bajada.
    testWidgets('cuando la venta termina de subir, dice "Todo subido" sola', (tester) async {
      final m = await _montar(tester);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · 1 venta subiendo');
      // El motor terminó de subir: la cola quedó vacía y avisa lo pendiente.
      m.entradas.sinSubir = 0;
      m.e.motor.pendiente.add(0);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
    });

    // Pedido del usuario (20-nov-2026, "si sube, que suba de verdad"): con una
    // entrega hecha sin internet todavía en la cola, decía "Todo subido".
    testWidgets('una entrega sin subir también cuenta: "Todo subido" solo sin nada en '
        'la cola', (tester) async {
      final m = await _montar(tester);
      m.e.conexion.cambiar(AppConnectivity.offline);
      await _elegir(tester, _lopez);
      await _entregarParte(tester, ParteEntrega.pulseras);
      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();
      // Quedó en la cola (lo que contaría la base).
      m.e.partes.sinSubir = 1;
      m.e.motor.pendiente.add(1);
      await tester.pumpAndSettle();
      if (find.text('ENTENDIDO').evaluate().isNotEmpty) {
        await tester.tap(find.text('ENTENDIDO'));
        await tester.pumpAndSettle();
      }
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · Sin internet · 1 entrega por subir');
      // Vuelve internet y sube: la línea lo dice sola.
      m.e.conexion.cambiar(AppConnectivity.online);
      m.e.partes.sinSubir = 0;
      m.e.motor.pendiente.add(0);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'), 'Caja abierta · Carla · Todo subido');
    });

    testWidgets('la caja cerrada o una anulación sin subir también: "1 cambio"',
        (tester) async {
      final m = await _montar(tester);
      m.entradas.sinSubir = 2;
      m.entradas.cambiosPendientes = 1;
      m.e.partes.sinSubir = 1;
      m.e.motor.pendiente.add(4);
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_linea_texto'),
          'Caja abierta · Carla · 2 ventas, 1 entrega y 1 cambio subiendo');
    });
  });

  group('VENTAS, desde la barra de VENDER', () {
    testWidgets('abre las ventas de la caja de quien vende, y al volver sigue en VENDER',
        (tester) async {
      final m = await _montar(tester);
      await _tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      final ventas =
          tester.widget<VentasDeEntradasScreen>(find.byType(VentasDeEntradasScreen));
      expect(ventas.caja?.id, m.entradas.listaCajas.single.id);
      expect(_texto(tester, 'ventas_alcance'), contains('La caja de Carla'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(VentasDeEntradasScreen), findsNothing);
      expect(find.byType(VenderEntradasScreen), findsOneWidget);
    });

    // Revisión del 14-nov: al volver con la última venta anulada, el aviso verde
    // de "guardada" seguía arriba y su comprobante salía sin ANULADA.
    testWidgets('si se anula la última venta, se va el aviso de guardada', (tester) async {
      final m = await _montar(tester, jefe: true);
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(find.byKey(const Key('vender_guardada')), findsOneWidget);
      final venta = m.entradas.listaVentas.single;
      expect(m.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      await m.entradas.anular(venta, motivo: 'error de carga', devueltas: true, quien: 'Jefe');
      await _tocar(tester, 'vender_ventas');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_guardada')), findsNothing);
    });

    testWidgets('sin caja abierta no está', (tester) async {
      await _montar(tester, conCaja: false);
      await tester.tap(find.byKey(const Key('abrir_caja_volver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vender_ventas')), findsNothing);
    });
  });

  group('desde la entrega, con la familia ya elegida', () {
    testWidgets('abre su tarjeta directo', (tester) async {
      await _montar(tester, preparar: _perezDebeOtraCosa, familiaId: _perez);
      expect(find.byKey(const Key('vender_familia_elegida')), findsOneWidget);
      expect(_texto(tester, 'vender_linea_mesa_1_cantidad'), '8');
    });
  });

  // ── Las entradas para rendir (21-nov-2026) ─────────────────────────────────
  //
  // `docs/SPEC_entradas_para_rendir_2026-11-20.md`: el jefe le da a alguien
  // entradas para que las venda por su cuenta; en VENDER sale el aviso y quien
  // cobra le rinde lo vendido (una venta de esta caja) y lo que no vendió.
  group('las entradas para rendir', () {
    /// El jefe le da a [persona] [cantidad] desde [desde], a $ 8.000 la
    /// anticipada.
    Future<MovimientoParaRendir> dar(
      EntradasEnMemoria entradas, {
      String persona = 'PÉREZ, JUAN',
      int desde = 1201,
      int cantidad = 20,
    }) =>
        entradas.darParaRendir(
          eventoId: idFiestaEntrega,
          personaNombre: persona,
          cantidad: cantidad,
          numeros: [TramoTalonario(desde, desde + cantidad - 1)],
          precio: 8000,
          nombrePrecio: 'Entrada anticipada',
          quien: 'Jefe',
        );

    /// Todo lo que dice el aviso de VENDER, junto.
    String aviso(WidgetTester tester) => [
          for (final t in tester.widgetList<Text>(find.descendant(
            of: find.byKey(const Key('vender_para_rendir')),
            matching: find.byType(Text),
          )))
            t.data ?? t.textSpan!.toPlainText(),
        ].join(' ');

    // Regla 53: quien cobra cuenta su caja a ciegas. Si el aviso dijera
    // "faltan $ 240.000", sabría cuánta plata tendría que entrar.
    testWidgets('el aviso dice cuántas personas, sin ninguna plata, y solo si alguien '
        'tiene algo sin rendir', (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) async {
        await dar(entradas);
        await dar(entradas, persona: 'SOSA, DIEGO', desde: 1231, cantidad: 10);
      });
      expect(_texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 2 personas');
      expect(aviso(tester), isNot(contains(r'$')), reason: 'sin plata: ${aviso(tester)}');
      expect(aviso(tester), isNot(matches(RegExp(r'\d{4}'))),
          reason: 'ni montos ni números del talonario');
      expect(find.byKey(const Key('vender_rendir')), findsOneWidget);

      // SOSA devuelve todo: queda una persona.
      final sosa = m.entradas.listaParaRendir.last;
      await m.entradas.rendir(
        bloque: sosa,
        vendidas: 0,
        devueltas: 10,
        numerosDevueltos: const [TramoTalonario(1231, 1240)],
        quien: 'Jefe',
      );
      m.e.motor.bajo.add({'entradas_para_rendir'});
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');
    });

    testWidgets('sin nadie con entradas para rendir, el aviso no está', (tester) async {
      await _montar(tester);
      expect(find.byKey(const Key('vender_para_rendir')), findsNothing);
    });

    // Regla 43: los números que alguien tiene para rendir son del mismo
    // talonario de las anticipadas: una venta común no los vende.
    testWidgets('una venta común no vende un número que alguien tiene para rendir; uno '
        'que devolvió, sí', (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      await _aAlguienDeAfuera(tester);
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      await _poner(tester, 'vender_del', '1205');
      expect(_falta(tester), 'El 1205 ya se le dio a PÉREZ, JUAN, para rendir (1201 al 1220).');
      expect(_apagado(tester, 'vender_efectivo'), isTrue);
      // El 1200 y el 1201: el segundo ya es del bloque.
      await _poner(tester, 'vender_del', '1200');
      expect(_falta(tester), startsWith('El 1201 ya se le dio a PÉREZ, JUAN, para rendir'));
      await _poner(tester, 'vender_del', '1221');
      expect(_falta(tester), isNull);

      // Devuelve del 1216 al 1220: esos quedan libres.
      await m.entradas.rendir(
        bloque: m.entradas.listaParaRendir.single,
        vendidas: 0,
        devueltas: 5,
        numerosDevueltos: const [TramoTalonario(1216, 1220)],
        quien: 'Jefe',
      );
      m.e.motor.bajo.add({'entradas_para_rendir'});
      await tester.pumpAndSettle();
      await _poner(tester, 'vender_del', '1216');
      expect(_falta(tester), isNull);
      await _tocar(tester, 'vender_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.numeros, '1216-1217');
    });

    testWidgets('el número propuesto salta los que alguien tiene para rendir',
        (tester) async {
      await _montar(tester, ventasDeAntes: (entradas) async {
        final caja = entradas.listaCajas.single;
        await entradas.vender(
          caja: caja,
          compradorNombre: 'RUIZ MARTA',
          renglones: [RenglonEntradas.suelta(nombre: 'Entrada', precioLista: 10000, cantidad: 2)],
          medio: MedioBarra.efectivo,
          efectivo: 20000,
          numeros: '1199-1200',
          quien: 'Carla',
        );
        await dar(entradas);
      });
      await _aAlguienDeAfuera(tester);
      String del() =>
          tester.widget<TextField>(find.byKey(const Key('vender_del'))).controller!.text;
      expect(del(), '1221', reason: 'el que sigue (1201) lo tiene PÉREZ, JUAN para rendir');
      expect(_texto(tester, 'vender_talonario_ayuda'), contains('para rendir'));
      await _poner(tester, 'vender_comprador', 'GOMEZ CARLA');
      expect(_falta(tester), isNull);
    });

    // De punta a punta: Carla le cobra a PÉREZ, JUAN las 15 que vendió y él le
    // devuelve las 5 que no (las últimas, propuestas). Queda una venta de su
    // caja, sin familia, al precio del día en que se las llevó.
    testWidgets('RENDIR: vendió 15 y devuelve 5; queda la venta en esta caja y no le '
        'queda ninguna', (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      final caja = m.entradas.listaCajas.single;
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      // Uno solo con algo para rendir: ya viene elegido.
      expect(_texto(tester, 'rendir_tarjeta_texto'),
          'se llevó 20 el vie 20/11 · del 1201 al 1220 · Entrada anticipada · le quedan 20');
      expect(find.byKey(const Key('rendir_guardar_devolucion')), findsOneWidget);
      expect(_apagado(tester, 'rendir_guardar_devolucion'), isTrue);

      await _tocar(tester, 'rendir_vendio_mas', veces: 15);
      await _tocar(tester, 'rendir_devuelve_mas', veces: 5);
      expect(_texto(tester, 'rendir_le_quedan'), '0');
      expect(tester.widget<TextField>(find.byKey(const Key('rendir_del'))).controller!.text,
          '1216', reason: 'los últimos que tiene, propuestos');
      expect(_texto(tester, 'rendir_al_calculado'), 'al 1220');
      expect(_texto(tester, 'rendir_a_cobrar'), r'A cobrar: 15 × $ 8.000');
      expect(_texto(tester, 'rendir_total'), r'$ 120.000');
      expect(find.byKey(const Key('rendir_error')), findsNothing);
      // No se puede rendir más de lo que se llevó.
      expect(
        tester.widget<IconButton>(find.byKey(const Key('rendir_vendio_mas'))).onPressed,
        isNull,
      );

      await _tocar(tester, 'rendir_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);

      final venta = m.entradas.listaVentas.single;
      expect(venta.cajaEntradasId, caja.id);
      expect(venta.compradorNombre, 'PÉREZ, JUAN');
      expect(venta.contratoAlumnoId, isNull, reason: 'no es de ninguna familia');
      expect(venta.cantidad, 15);
      expect(venta.total, 120000);
      expect(venta.renglones.single.nombre, 'Entrada anticipada · para rendir');
      expect(venta.renglones.single.descuentoPct, 0);
      expect(venta.numeros, isNull, reason: 'los números los lleva el bloque');
      final movimientos = m.entradas.listaParaRendir;
      expect(movimientos.where((x) => x.esVendio).single.ventaId, venta.id);
      expect(movimientos.where((x) => x.esDevolvio).single.numeros, '1216-1220');
      final cuenta = ParaRendir.de(
        movimientos: movimientos,
        ventas: m.entradas.listaVentas,
        anulaciones: m.entradas.listaAnulaciones,
      );
      expect(cuenta.bloques.single.sinRendir, 0);
      expect(cuenta.bloques.single.rindioTodo, isTrue);

      // VENDER: ya nadie tiene para rendir, y el aviso de lo guardado.
      expect(find.byKey(const Key('vender_para_rendir')), findsNothing);
      expect(_texto(tester, 'vender_rendicion_guardada_texto'),
          r'Rendición guardada · PÉREZ, JUAN · vendió 15 · devolvió 5 · le quedan 0 · $ 120.000');
      // El comprobante de la rendición (no el de una venta) no sale solo
      // (22-nov-2026): lo saca IMPRIMIR EL COMPROBANTE del aviso, con quién
      // rinde, lo que devolvió en este acto y lo que le quedó.
      expect(m.comprobantes, isEmpty, reason: 'ningún papel se abre solo');
      await _tocar(tester, 'vender_ver_comprobante_rendicion');
      await tester.pumpAndSettle();
      final c = m.comprobantes.single;
      expect(c.venta.id, venta.id);
      expect(c.copia, isFalse);
      expect(c.alumno, isNull);
      final rendicion = c.rendicion!;
      expect(rendicion.persona, 'PÉREZ, JUAN');
      expect(rendicion.devolvio, 5);
      expect(rendicion.numerosDevueltos, const [TramoTalonario(1216, 1220)]);
      expect(rendicion.leQuedanDeHoy, isFalse);
      expect(ComprobanteEntradasPdf.lineaDeLaRendicion(rendicion, c.venta.cantidad),
          'Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 · devolvió 5 (1216 al 1220) · '
          'le quedan 0');
      expect(find.byKey(const Key('vender_ver_comprobante')), findsNothing,
          reason: 'el aviso de una venta común no está');
      // VER DE NUEVO: el mismo, como COPIA.
      await _tocar(tester, 'vender_ver_comprobante_rendicion');
      expect(m.comprobantes, hasLength(2));
      expect(m.comprobantes.last.copia, isTrue);
      expect(m.comprobantes.last.rendicion?.devolvio, 5);
    });

    /// RENDIR con [vendio] vendidas y [devuelve] devueltas, en efectivo; con
    /// [imprimir], después saca el comprobante del aviso (no sale solo).
    Future<void> rendirEnEfectivo(
      WidgetTester tester, {
      int vendio = 15,
      int devuelve = 5,
      bool imprimir = true,
    }) async {
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: vendio);
      if (devuelve > 0) await _tocar(tester, 'rendir_devuelve_mas', veces: devuelve);
      await _tocar(tester, 'rendir_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      if (imprimir) {
        await _tocar(tester, 'vender_ver_comprobante_rendicion');
        await tester.pumpAndSettle();
      }
    }

    // 22-nov-2026 (revisión de la etapa 6): la COPIA del aviso salía con lo
    // devuelto en ese acto y "le quedan" de ahora: si después el jefe anulaba
    // ese "devolvió", decía "vendió 15 · devolvió 5 · le quedan 5" (25 de 20).
    // Ahora dice cómo quedó en ese acto, igual que el papel que salió.
    testWidgets('la COPIA de VER DE NUEVO dice cómo quedó en ese acto, aunque '
        'después el jefe anule lo devuelto', (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      await rendirEnEfectivo(tester);
      const enEseActo = 'Se llevó 20 (1201 al 1220) el 20/11 · vendió 15 · devolvió 5 '
          '(1216 al 1220) · le quedan 0';
      expect(
        ComprobanteEntradasPdf.lineaDeLaRendicion(
            m.comprobantes.single.rendicion!, m.comprobantes.single.venta.cantidad),
        enEseActo,
      );

      // El jefe, desde la PC, anula ese "devolvió", y baja a la tablet: ahora le
      // quedan 5, y el aviso de arriba vuelve.
      final devolvio = m.entradas.listaParaRendir.where((x) => x.esDevolvio).single;
      await m.entradas.anularDeParaRendir(devolvio, motivo: 'no las trajo', quien: 'Jefe');
      m.e.motor.bajo.add({'entradas_para_rendir'});
      await tester.pumpAndSettle();
      expect(_texto(tester, 'vender_para_rendir_texto'), 'Entradas para rendir: 1 persona');

      // Lo de esa rendición no cambia: ni el aviso verde ni la COPIA.
      expect(_texto(tester, 'vender_rendicion_guardada_texto'),
          r'Rendición guardada · PÉREZ, JUAN · vendió 15 · devolvió 5 · le quedan 0 · $ 120.000');
      await _tocar(tester, 'vender_ver_comprobante_rendicion');
      final copia = m.comprobantes.last;
      expect(copia.copia, isTrue);
      expect(ComprobanteEntradasPdf.lineaDeLaRendicion(copia.rendicion!, copia.venta.cantidad),
          enEseActo);
    });

    // Si la relectura de después de rendir no anda (VENDER no avisa: es en
    // silencio), lo de la pantalla es de antes de rendir. El papel no puede decir
    // "vendió 15 · devolvió 5 · le quedan 20": sale sin el renglón del bloque.
    testWidgets('si después de rendir no se puede leer cómo quedó, el papel y el aviso '
        'van sin "le quedan", nunca con el número de antes', (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      m.entradas.fallaLeerDespuesDeRendir = true;
      await rendirEnEfectivo(tester);
      expect(m.entradas.listaVentas.single.cantidad, 15, reason: 'la rendición quedó guardada');
      final c = m.comprobantes.single;
      expect(c.rendicion!.persona, 'PÉREZ, JUAN');
      expect(c.rendicion!.bloque, isNull);
      expect(ComprobanteEntradasPdf.lineaDeLaRendicion(c.rendicion!, c.venta.cantidad), isNull);
      expect(_texto(tester, 'vender_rendicion_guardada_texto'),
          r'Rendición guardada · PÉREZ, JUAN · vendió 15 · devolvió 5 · $ 120.000');
      expect(find.textContaining('No se guardó'), findsNothing);
    });

    testWidgets('si el comprobante de la rendición no se puede abrir, la rendición queda '
        'y se dice sin asustar', (tester) async {
      final m = await _montar(
        tester,
        fallaElComprobante: true,
        ventasDeAntes: (entradas) => dar(entradas),
      );
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: 2);
      await _tocar(tester, 'rendir_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.cantidad, 2);
      await _tocar(tester, 'vender_ver_comprobante_rendicion');
      await tester.pumpAndSettle();
      expect(
          find.text('La rendición está guardada. No se pudo abrir el comprobante: probá '
              'de nuevo.'),
          findsOneWidget);
      expect(find.textContaining('No se guardó'), findsNothing);
      expect(find.byKey(const Key('vender_ver_comprobante_rendicion')), findsOneWidget);
    });

    // 21-nov-2026, sección 2 de la SPEC: el cobro de RENDIR es la hoja de
    // siempre **con el recargo apagado** (rinde toda la plata, al precio del
    // día en que se las llevó); se puede prender si paga por transferencia.
    // Una venta común por transferencia, con el mismo recargo de la fiesta, lo
    // trae prendido ("por transferencia, con el recargo de la fiesta").
    testWidgets('el cobro de RENDIR abre con el recargo apagado aunque la fiesta tenga '
        'recargo, y se puede prender', (tester) async {
      final m = await _montar(tester, recargo: 5, ventasDeAntes: (entradas) => dar(entradas));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: 3);
      await _tocar(tester, 'rendir_transferencia');
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('cobro_recargo'))).value,
          isFalse);
      expect(_texto(tester, 'cobro_transfiere'), r'$ 24.000', reason: r'3 × $ 8.000, sin recargo');
      await _confirmarElCobro(tester);
      final v = m.entradas.listaVentas.single;
      expect([v.medio, v.total, v.recargo, v.transferencia],
          [MedioBarra.transferencia, 24000, 0, 24000]);
    });

    testWidgets('el recargo de RENDIR se puede prender a mano', (tester) async {
      final m = await _montar(tester, recargo: 5, ventasDeAntes: (entradas) => dar(entradas));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: 3);
      await _tocar(tester, 'rendir_transferencia');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cobro_recargo')));
      await tester.pumpAndSettle();
      expect(_texto(tester, 'cobro_transfiere'), r'$ 25.200');
      await _confirmarElCobro(tester);
      final v = m.entradas.listaVentas.single;
      expect([v.total, v.recargo, v.transferencia], [24000, 1200, 25200]);
    });

    // El precio del bloque queda fijo: si hoy la entrada vale otra cosa, RENDIR
    // lo dice, para que quien cobra no se sorprenda; si vale lo mismo, nada.
    String? otroPrecio(WidgetTester tester) {
      final f = find.descendant(
        of: find.byKey(const Key('rendir_otro_precio')),
        matching: find.byType(Text),
      );
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets('si hoy la entrada vale otra cosa, RENDIR avisa que rinde al precio del '
        'día en que se las llevó', (tester) async {
      // Se las llevó con la anticipada a $ 8.000; hoy rige la general a $ 10.000.
      await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      expect(otroPrecio(tester),
          r'Se las llevó a $ 8.000 (entrada anticipada): rinde a ese precio, aunque hoy '
          r'la entrada valga $ 10.000.');
      await _tocar(tester, 'rendir_vendio_mas', veces: 2);
      expect(_texto(tester, 'rendir_a_cobrar'), r'A cobrar: 2 × $ 8.000');
    });

    testWidgets('si hoy vale lo mismo, RENDIR no avisa nada del precio', (tester) async {
      // Hoy rige la anticipada a $ 8.000, la misma con que se las llevó.
      await _montar(tester, anticipada: true, ventasDeAntes: (entradas) => dar(entradas));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rendir_tarjeta_texto')), findsOneWidget);
      expect(otroPrecio(tester), isNull);
      expect(find.byKey(const Key('rendir_otro_precio')), findsNothing);
    });

    testWidgets('volver del cobro no guarda nada y vuelve a RENDIR con lo cargado',
        (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: 3);
      await _tocar(tester, 'rendir_efectivo');
      await tester.pumpAndSettle();
      // La hoja del cobro: se vuelve sin confirmar.
      await tester.tap(find.byKey(const Key('cobro_volver')));
      await tester.pumpAndSettle();
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.entradas.listaParaRendir, hasLength(1));
      expect(_texto(tester, 'rendir_vendio_cantidad'), '3');
    });

    testWidgets('solo devuelve: no pide caja ni plata', (tester) async {
      final m = await _montar(
        tester,
        conCaja: false,
        ventasDeAntes: (entradas) => dar(entradas, cantidad: 4),
      );
      // VENDER pide la caja al entrar: se vuelve sin abrirla.
      await tester.tap(find.byKey(const Key('abrir_caja_volver')));
      await tester.pumpAndSettle();
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_devuelve_mas', veces: 4);
      expect(find.byKey(const Key('rendir_efectivo')), findsNothing);
      await _tocar(tester, 'rendir_guardar_devolucion');
      await tester.pumpAndSettle();
      expect(m.entradas.listaCajas, isEmpty);
      expect(m.entradas.listaVentas, isEmpty);
      expect(m.entradas.listaParaRendir.where((x) => x.esDevolvio).single.numeros, '1201-1204');
      expect(_texto(tester, 'vender_rendicion_guardada_texto'),
          'Devolución guardada · PÉREZ, JUAN · devolvió 4 · le quedan 0');
      // Solo devolvió: no hay plata ni comprobante.
      expect(m.comprobantes, isEmpty);
      expect(find.byKey(const Key('vender_ver_comprobante_rendicion')), findsNothing);
    });

    testWidgets('lo vendido sin caja pide ABRIR LA CAJA, y abierta se cobra',
        (tester) async {
      final m = await _montar(
        tester,
        conCaja: false,
        ventasDeAntes: (entradas) => dar(entradas),
      );
      await tester.tap(find.byKey(const Key('abrir_caja_volver')));
      await tester.pumpAndSettle();
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_vendio_mas', veces: 2);
      expect(find.byKey(const Key('rendir_sin_caja')), findsOneWidget);
      expect(find.byKey(const Key('rendir_efectivo')), findsNothing);
      await _tocar(tester, 'rendir_abrir_caja');
      await tester.pumpAndSettle();
      await _poner(tester, 'abrir_caja_cambio', '0');
      await tester.tap(find.byKey(const Key('abrir_caja_abrir')));
      await tester.pumpAndSettle();
      expect(m.entradas.listaCajas, hasLength(1));
      expect(find.byKey(const Key('rendir_sin_caja')), findsNothing);
      await _tocar(tester, 'rendir_efectivo');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(m.entradas.listaVentas.single.cajaEntradasId, m.entradas.listaCajas.single.id);
      expect(m.entradas.listaVentas.single.total, 16000);
    });

    testWidgets('si otro equipo rindió en el medio, no guarda nada y lo dice',
        (tester) async {
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas, cantidad: 4));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_devuelve_mas', veces: 4);
      // Mientras tanto, otro equipo le recibió 2.
      await m.entradas.rendir(
        bloque: m.entradas.listaParaRendir.single,
        vendidas: 0,
        devueltas: 2,
        numerosDevueltos: const [TramoTalonario(1201, 1202)],
        quien: 'Romi',
      );
      await _tocar(tester, 'rendir_guardar_devolucion');
      await tester.pumpAndSettle();
      expect(find.textContaining('cambió algo mientras cargabas la rendición'), findsOneWidget);
      expect(m.entradas.listaParaRendir.where((x) => x.esDevolvio), hasLength(1));
    });

    testWidgets('sin el permiso de vender no se rinde (la segunda llave)', (tester) async {
      // Con el permiso se monta; se lo sacan con RENDIR abierto.
      final m = await _montar(tester, ventasDeAntes: (entradas) => dar(entradas, cantidad: 2));
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      await _tocar(tester, 'rendir_devuelve_mas', veces: 2);
      m.e.operadores.permisos.poner(
        m.e.operador().id,
        const PermisosEfectivos(entradas: true),
      );
      await m.c.read(appRoleProvider.notifier).entrarComoEntradas(
            m.e.operador(),
            const PermisosEfectivos(entradas: true),
          );
      await _tocar(tester, 'rendir_guardar_devolucion');
      await tester.pumpAndSettle();
      expect(m.entradas.listaParaRendir, hasLength(1), reason: 'no se guardó nada');
    });

    testWidgets('en un celular RENDIR es una hoja desde abajo, sin cortes', (tester) async {
      final m = await _montar(
        tester,
        tamano: const Size(390, 1300),
        ventasDeAntes: (entradas) => dar(entradas),
      );
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'vender_rendir');
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await _tocar(tester, 'rendir_vendio_mas', veces: 15);
      await _tocar(tester, 'rendir_devuelve_mas', veces: 5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'rendir_transferencia');
      await tester.pumpAndSettle();
      await _confirmarElCobro(tester);
      expect(tester.takeException(), isNull);
      expect(m.entradas.listaVentas.single.medio, MedioBarra.transferencia);
    });
  });

  group('en un celular', () {
    testWidgets('la lista, la tarjeta y alguien de afuera, uno debajo del otro y sin '
        'cortes', (tester) async {
      await _montar(
        tester,
        pagaLaMesa: true,
        tamano: const Size(390, 1600),
        preparar: (e) => _sumar(
          e,
          id: _cuatro,
          nombre: 'FERNÁNDEZ DE LA TORRE, MARÍA DE LOS ÁNGELES',
          mesas: const [31],
          acompanantes: 3,
          nombres: const ['MAMÁ CUATRO', 'PAPÁ CUATRO'],
        ),
      );
      expect(tester.takeException(), isNull);
      await _elegirAPerez(tester);
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'vender_entregar_pulseras');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'vender_cambiar_familia');
      await tester.pumpAndSettle();
      await _elegir(tester, _cuatro);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Alguien de afuera'));
      await _aAlguienDeAfuera(tester);
      expect(tester.takeException(), isNull);
    });

    // Revisión independiente del 20-nov-2026: en 360 px el renglón de
    // "Alguien de afuera" (el descuento, la cantidad y el subtotal en una
    // fila) se salía 30 px del ancho.
    testWidgets('alguien de afuera en un celular de 360 px: el descuento en su '
        'renglón, sin salirse', (tester) async {
      await _montar(tester, tamano: const Size(360, 1600));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Alguien de afuera'));
      await _aAlguienDeAfuera(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('vender_descuento')), findsOneWidget);
      await _tocar(tester, 'vender_sueltas_mas');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
