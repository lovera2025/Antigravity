// La lista de PRECIOS de una fiesta sorteada antes de la regla del descuento
// (17-nov-2026), montada de verdad con la revisión en memoria
// (`test/helpers/revision_en_memoria.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/solo_jefe.dart';
import 'package:arguello_events/features/eventos/widgets/lugares_al_sorteo_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/revision_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';

// 12/11/2026 21:40 en Argentina.
final _sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  int sillas = 0,
  String? mesa,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _fiesta,
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
      createdAt: DateTime.utc(2026, 3, 1),
    );

SorteoMesasRegistro _r(
  String id,
  Map<String, String> resultado, {
  int horas = 0,
  Map<String, String>? antes,
  Map<String, String>? lugares,
  bool auto = false,
}) =>
    SorteoMesasRegistro(
      id: id,
      eventoId: _fiesta,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: antes,
      lugares: lugares,
      automatico: auto,
      hechoPor: auto ? null : 'Jefe',
      createdAt: _sorteoEl.add(Duration(hours: horas)),
    );

/// PÉREZ agregó una mesa que el programa le dio sola (vino después); LÓPEZ
/// tiene 2 sillas sin huella (para revisar); GÓMEZ, solo su mesa.
RevisionEnMemoria _fiestaSinAnotar() => RevisionEnMemoria(
      alumnosDeLaFiesta: [
        _alumno('p', 'PÉREZ, JUAN', extras: 1, mesa: '12, 151'),
        _alumno('l', 'LÓPEZ, SOFÍA', sillas: 2, mesa: '14'),
        _alumno('g', 'GÓMEZ, ANA', mesa: '15'),
      ],
      registrosDeLaFiesta: [
        _r('sorteo', const {'p': '12', 'l': '14', 'g': '15'}, antes: const {}),
        _r(
          'auto',
          const {'p': '12, 151'},
          horas: 50,
          antes: const {'p': '12'},
          auto: true,
        ),
      ],
    );

void main() {
  bool? devuelto;

  setUp(() => devuelto = null);

  Future<void> abrir(
    WidgetTester tester,
    RevisionEnMemoria m, {
    bool jefe = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        m.reemplazo,
        esRolJefeProvider.overrideWith((ref) => jefe),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  devuelto = await mostrarRevisionDeLugares(
                    context,
                    eventoId: _fiesta,
                    fiesta: 'PUERTO VIEJO',
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  bool tildado(WidgetTester tester, String clave) => tester
      .widget<CheckboxListTile>(find.byKey(Key('revision_$clave')))
      .value!;

  String texto(WidgetTester tester, String clave) =>
      tester.widget<Text>(find.byKey(Key(clave))).data!;

  Future<void> aceptar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('revision_aceptar')));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el día del sorteo, lo que vino después tildado y lo de '
      'revisar sin tildar, cada uno con su porqué', (tester) async {
    await abrir(tester, _fiestaSinAnotar());
    expect(find.text('Lugares agregados después del sorteo'), findsOneWidget);
    expect(find.text('PUERTO VIEJO'), findsOneWidget);
    expect(texto(tester, 'revision_sorteo'),
        'El sorteo fue el 12/11/2026 21:40 hs.');

    expect(find.text('Se agregaron después del sorteo'), findsOneWidget);
    expect(find.text('PÉREZ, JUAN · 1 mesa adicional (8 entradas)'),
        findsOneWidget);
    expect(tildado(tester, 'p|m|d'), isTrue);
    expect(find.textContaining('Mesa 151: el programa se la dio el'),
        findsOneWidget);

    expect(find.text('Para revisar'), findsOneWidget);
    expect(find.text('LÓPEZ, SOFÍA · 2 sillas extra (2 entradas)'),
        findsOneWidget);
    expect(tildado(tester, 'l|s|r'), isFalse);
    expect(find.text('Sin pagos de sillas extra.'), findsOneWidget);

    // Quien tiene solo su mesa no figura.
    expect(find.textContaining('GÓMEZ'), findsNothing);
    expect(texto(tester, 'revision_resumen'),
        'Pagan entera: 8 entradas de 1 familia. Lo demás queda con descuento.');
  });

  testWidgets('la lista no dice mora, deuda ni "sin pagar"', (tester) async {
    await abrir(tester, _fiestaSinAnotar());
    for (final palabra in ['mora', 'deuda', 'debe', 'sin pagar']) {
      expect(find.textContaining(palabra, findRichText: true), findsNothing,
          reason: palabra);
    }
  });

  testWidgets('tildar y destildar cambia la cuenta de abajo', (tester) async {
    await abrir(tester, _fiestaSinAnotar());
    await tester.tap(find.byKey(const Key('revision_l|s|r')));
    await tester.pump();
    expect(texto(tester, 'revision_resumen'),
        'Pagan entera: 10 entradas de 2 familias. Lo demás queda con descuento.');
    await tester.tap(find.byKey(const Key('revision_p|m|d')));
    await tester.tap(find.byKey(const Key('revision_l|s|r')));
    await tester.pump();
    expect(texto(tester, 'revision_resumen'),
        'Nadie paga entera: todo lo cargado hoy queda con descuento.');
  });

  testWidgets('ACEPTAR como viene: guarda en el renglón del sorteo y cierra',
      (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m);
    await aceptar(tester);
    expect(devuelto, isTrue);
    expect(find.text('Lugares agregados después del sorteo'), findsNothing);
    expect(m.guardados.single.registroId, 'sorteo');
    // PÉREZ queda con solo su mesa (no figura); las sillas de LÓPEZ, con
    // descuento.
    expect(m.guardados.single.lugares, {'l': '1,2'});
  });

  testWidgets('destildando al que no corresponde, queda con descuento',
      (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m);
    await tester.tap(find.byKey(const Key('revision_p|m|d')));
    await tester.pump();
    await aceptar(tester);
    expect(m.guardados.single.lugares, {'p': '2,0', 'l': '1,2'});
  });

  testWidgets('CANCELAR no guarda nada', (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m);
    await tester.tap(find.byKey(const Key('revision_cancelar')));
    await tester.pumpAndSettle();
    expect(devuelto, isFalse);
    expect(m.guardados, isEmpty);
    expect(m.puestasAlDia, 0);
  });

  testWidgets('sin modo jefe se ve, con ACEPTAR apagado y el motivo',
      (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m, jefe: false);
    final boton =
        tester.widget<FilledButton>(find.byKey(const Key('revision_aceptar')));
    expect(boton.onPressed, isNull);
    expect(find.byTooltip(kSoloEnModoJefe), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('revision_p|m|d')))
          .onChanged,
      isNull,
    );
    expect(m.guardados, isEmpty);
  });

  testWidgets('sin internet lo dice, no guarda y sigue abierta', (tester) async {
    final m = _fiestaSinAnotar()..hayInternet = false;
    await abrir(tester, m);
    await aceptar(tester);
    expect(texto(tester, 'revision_problema'), contains('hace falta internet'));
    expect(texto(tester, 'revision_problema'), contains('No se guardó nada'));
    expect(m.guardados, isEmpty);
    expect(devuelto, isNull);

    // Vuelve internet: acepta.
    m.hayInternet = true;
    await aceptar(tester);
    expect(devuelto, isTrue);
    expect(m.guardados, hasLength(1));
  });

  testWidgets('si otra PC cargó algo mientras miraba, muestra la lista nueva, '
      'conserva lo que ya había decidido y no guarda hasta que acepte de nuevo',
      (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m);
    // Decide que las sillas de LÓPEZ pagan entera.
    await tester.tap(find.byKey(const Key('revision_l|s|r')));
    await tester.pump();
    m.alPonerAlDia = (m) => m.alumnosDeLaFiesta[2] =
        _alumno('g', 'GÓMEZ, ANA', sillas: 1, mesa: '15');
    await aceptar(tester);

    expect(m.guardados, isEmpty);
    expect(texto(tester, 'revision_problema'), contains('La lista cambió'));
    expect(find.text('GÓMEZ, ANA · 1 silla extra (1 entrada)'), findsOneWidget);
    expect(tildado(tester, 'g|s|r'), isFalse);
    expect(tildado(tester, 'l|s|r'), isTrue);
    expect(tildado(tester, 'p|m|d'), isTrue);

    m.alPonerAlDia = null;
    await aceptar(tester);
    expect(devuelto, isTrue);
    expect(m.guardados.single.lugares, {'g': '1,1'});
  });

  testWidgets('si otra PC ya la había aceptado, lo dice y no pisa nada',
      (tester) async {
    final m = _fiestaSinAnotar();
    await abrir(tester, m);
    m.alPonerAlDia = (m) => m.registrosDeLaFiesta[0] = _r(
          'sorteo',
          const {'p': '12', 'l': '14', 'g': '15'},
          antes: const {},
          lugares: const {'p': '2,0'},
        );
    await aceptar(tester);
    expect(m.guardados, isEmpty);
    expect(texto(tester, 'revision_nada'), contains('ya no tiene nada para revisar'));
    expect(find.byKey(const Key('revision_aceptar')), findsNothing);
    await tester.tap(find.text('CERRAR'));
    await tester.pumpAndSettle();
    // Quien la abrió tiene que releer: ahora rige lo anotado.
    expect(devuelto, isTrue);
  });

  testWidgets('si la base no guarda, lo dice y sigue abierta', (tester) async {
    final m = _fiestaSinAnotar()..guarda = false;
    await abrir(tester, m);
    await aceptar(tester);
    expect(texto(tester, 'revision_problema'), 'No se pudo guardar. Probá de nuevo.');
    expect(devuelto, isNull);
  });

  testWidgets('sin ninguna duda igual se acepta: desde ahí rige la regla',
      (tester) async {
    final m = RevisionEnMemoria(
      alumnosDeLaFiesta: [
        _alumno('p', 'PÉREZ, JUAN', extras: 1, mesa: '12, 13'),
        _alumno('g', 'GÓMEZ, ANA', mesa: '15'),
      ],
      registrosDeLaFiesta: [
        _r('sorteo', const {'p': '12, 13', 'g': '15'}, antes: const {}),
      ],
    );
    await abrir(tester, m);
    expect(find.byKey(const Key('revision_sin_dudas')), findsOneWidget);
    expect(find.text('Se agregaron después del sorteo'), findsNothing);
    expect(find.text('Para revisar'), findsNothing);
    await aceptar(tester);
    expect(devuelto, isTrue);
    expect(m.guardados.single.lugares, {'p': '2,0'});
  });

  testWidgets('una fiesta sin sorteo: nada para revisar, y solo se cierra',
      (tester) async {
    final m = RevisionEnMemoria(
      alumnosDeLaFiesta: [_alumno('p', 'PÉREZ, JUAN', extras: 1)],
      registrosDeLaFiesta: [],
    );
    await abrir(tester, m);
    expect(texto(tester, 'revision_nada'),
        'Esta fiesta no tiene nada para revisar.');
    expect(find.byKey(const Key('revision_aceptar')), findsNothing);
    await tester.tap(find.text('CERRAR'));
    await tester.pumpAndSettle();
    expect(devuelto, isFalse);
  });
}
