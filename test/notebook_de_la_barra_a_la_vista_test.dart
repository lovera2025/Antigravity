// La notebook de la barra, a la vista de todos (27-nov-2026, pedido del usuario):
// queda toda la noche con la central prendida y la pantalla abierta, y cualquiera
// que pasaba podía hacer clic y mirar las cajas.
//
// - En modo jefe, con el candado de arriba queda **la vista simple**: solo la
//   central (las cajas conectadas, si está todo subido). Sin plata, sin cajas,
//   sin catálogo, precios ni GANANCIA, y **sin botón para apagar la central**
//   ("si no, todos se desconectan").
// - Lo demás vuelve **manteniendo apretado 2 segundos el logo de arriba** y
//   escribiendo **la clave de esa notebook** (la del modo jefe; no es una nueva).
// - **Viene apagado**: se bloquea sola a los 2 minutos solo si el jefe lo tilda,
//   y solo con la central prendida.
// - Solo en la notebook (donde se prende la central), con el modo jefe y fuera de
//   la web. La encargada no tiene vista simple (28-nov-2026: "la encargada tiene
//   las limitaciones que no puede ver ganancia y eso").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/central_barra.dart'
    show RechazoDeLaCentral, kPuertoCentralBarra;
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/jefe/vista_simple_de_la_notebook.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/models/evento.dart';

import 'helpers/barra_en_memoria.dart';
import 'helpers/operadores_en_memoria.dart';

/// La central de la notebook, ya prendida (sin abrir puertos). Cuenta si alguien
/// la apaga: bloquear y desbloquear no la tocan.
class _CentralPrendida extends CentralDeLaBarra {
  final String eventoId;
  var apagadas = 0;

  /// Lo que la central no guardó de lo que le mandaron.
  var rechazos = <RechazoDeLaCentral>[];

  _CentralPrendida(this.eventoId);

  @override
  EstadoCentralBarra build() => EstadoCentralBarra(
        eventoId: eventoId,
        puerto: kPuertoCentralBarra,
        direcciones: ['192.168.0.10'],
        contestaBusqueda: true,
        rechazos: rechazos,
      );

  @override
  Future<void> reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) async {}

  @override
  Future<void> apagar() async => apagadas++;
}

/// El modo jefe de la prueba, que se puede vencer en el medio (como el PIN de
/// verdad, que dura unos minutos).
class _ModoJefe extends Notifier<bool> {
  @override
  bool build() => true;

  void vencer() => state = false;
}

final _modoJefe = NotifierProvider<_ModoJefe, bool>(_ModoJefe.new);

const _clave = '4321';
const _espera = Duration(minutes: 2);
const _preferencia = 'barra_notebook_vuelve_sola_v1';

void main() {
  late OperadoresEnPrueba operadores;
  late BarraEnPrueba prueba;
  late Evento pinaroli, rotonda;
  late _CentralPrendida central;

  // La noche de la fiesta, con una venta: en CAJAS hay plata a la vista.
  final hoy = DateTime(2026, 12, 4, 23);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    operadores = OperadoresEnPrueba();
    prueba = BarraEnPrueba();
    pinaroli = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22));
    rotonda = fiestaDePrueba(BarraEnPrueba.id(2), 'ROTONDA', DateTime(2026, 12, 12, 22));
    prueba.eventos.addAll([pinaroli, rotonda]);
    central = _CentralPrendida(pinaroli.id);
    final b = prueba.barra;
    final fernet = b.producto('Fernet con Coca', categoria: 'Tragos');
    b.precio(pinaroli.id, fernet, 6000, stock: 10, aviso: 4);
    final caja = await b.abrirCaja(
      eventoId: pinaroli.id,
      operadorId: 'm',
      operadorNombre: 'Marta',
      numeroCaja: 1,
    );
    await b.vender(
      caja: caja,
      renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 2)],
      medio: MedioBarra.efectivo,
      efectivo: 12000,
      quien: 'Marta',
    );
  });

  /// Abre BARRA del jefe encima de un inicio (para probar que no se sale para atrás).
  Future<void> abrir(
    WidgetTester tester, {
    bool esJefe = true,
    bool enLaWeb = false,
    bool esLaNotebook = true,
    bool centralPrendida = true,
    PestanaBarraJefe pestana = PestanaBarraJefe.cajas,
  }) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...operadores.reemplazos,
        ...prueba.reemplazos,
        if (centralPrendida) centralDeLaBarraProvider.overrideWith(() => central),
        barraDelJefeProvider.overrideWithValue(prueba.barra),
        esRolJefeProvider.overrideWith((ref) => esJefe && ref.watch(_modoJefe)),
        enLaWebProvider.overrideWithValue(enLaWeb),
        centralSePrendeAcaProvider.overrideWithValue(esLaNotebook),
        relojDelJefeProvider.overrideWithValue(() => hoy),
        // La clave de esa notebook (la del modo jefe), sin leer la base.
        esLaClaveDeEstaNotebookProvider.overrideWithValue((escrita) async => escrita.trim() == _clave),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => BarraJefeScreen(pestanaInicial: pestana),
                )),
                child: const Text('ir a la barra'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ir a la barra'));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, String clave) async {
    await tester.tap(find.byKey(Key(clave)));
    await tester.pumpAndSettle();
  }

  /// El candado de arriba y una de sus dos opciones.
  Future<void> candado(WidgetTester tester, String opcion) async {
    await tocar(tester, 'jefe_bloquear');
    await tocar(tester, opcion);
  }

  /// Mantiene apretado el logo [cuanto] y lo suelta.
  Future<void> apretarElLogo(WidgetTester tester, Duration cuanto) async {
    final dedo = await tester.startGesture(tester.getCenter(find.byKey(const Key('jefe_logo'))));
    await tester.pump(cuanto);
    await dedo.up();
    await tester.pumpAndSettle();
  }

  /// Nadie toca la notebook durante [cuanto].
  Future<void> nadieLaToca(WidgetTester tester, Duration cuanto) async {
    await tester.pump(cuanto);
    await tester.pumpAndSettle();
  }

  bool enVistaSimple() => find.byKey(const Key('jefe_vista_simple')).evaluate().isNotEmpty;

  String subtitulo(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('jefe_subtitulo'))).data!;

  /// Todo lo escrito en la pantalla.
  List<String> loQueSeLee(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ];

  group('de fábrica viene apagada', () {
    testWidgets('en la notebook, con modo jefe, se ven el logo y el candado, y todo lo del jefe',
        (tester) async {
      await abrir(tester);
      expect(find.byKey(const Key('jefe_logo')), findsOneWidget);
      expect(find.byKey(const Key('jefe_bloquear')), findsOneWidget);
      expect(enVistaSimple(), isFalse);
      expect(subtitulo(tester), 'Modo jefe');
      expect(find.byKey(const Key('jefe_pestana_cajas')), findsOneWidget);
      expect(find.byKey(const Key('jefe_pestana_ganancia')), findsOneWidget);
      // En CAJAS hay plata a la vista: es lo que la vista simple tiene que sacar.
      expect(loQueSeLee(tester).any((t) => t.contains(r'$')), isTrue);
    });

    testWidgets('sin tildar nada no se bloquea sola, aunque nadie la toque y la central esté '
        'prendida', (tester) async {
      await abrir(tester);
      await nadieLaToca(tester, const Duration(minutes: 30));
      expect(enVistaSimple(), isFalse);
      expect(find.byKey(const Key('jefe_pestana_cajas')), findsOneWidget);
    });
  });

  group('el candado: dejar solo la central ahora', () {
    testWidgets('queda solo la central: sin plata, sin pestañas, sin impresora ni candado, y '
        'sin botón para apagarla', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      expect(enVistaSimple(), isTrue);
      expect(subtitulo(tester), 'Central');
      // La central, con sus cajas conectadas y lo que falta subir.
      expect(find.byKey(const Key('central_barra_panel')), findsOneWidget);
      expect(find.byKey(const Key('central_barra_esta_notebook')), findsOneWidget);
      // Nada del jefe.
      for (final clave in [
        'jefe_pestana_catalogo',
        'jefe_pestana_precios',
        'jefe_pestana_cajas',
        'jefe_pestana_ganancia',
        'jefe_impresora',
        'jefe_bloquear',
      ]) {
        expect(find.byKey(Key(clave)), findsNothing, reason: clave);
      }
      // Ni un peso en toda la pantalla.
      for (final t in loQueSeLee(tester)) {
        expect(t, isNot(contains(r'$')), reason: t);
      }
      // La central no se apaga desde acá: se desconectarían todas las cajas.
      expect(find.byKey(const Key('central_barra_apagar')), findsNothing);
      expect(find.text('APAGAR'), findsNothing);
      // No se cambia de fiesta desde la vista simple.
      expect(
        tester.widget<OutlinedButton>(find.byKey(const Key('jefe_cambiar_fiesta'))).onPressed,
        isNull,
      );
      // Nada en la pantalla dice cómo se vuelve: el logo parece un adorno.
      expect(loQueSeLee(tester).any((t) => t.toLowerCase().contains('clave')), isFalse);
    });

    testWidgets('bloquear no toca la central: sigue prendida', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      final c = ProviderScope.containerOf(tester.element(find.byType(BarraJefeScreen)));
      expect(c.read(centralDeLaBarraProvider).prendida, isTrue);
      expect(central.apagadas, 0);
    });

    testWidgets('con la central apagada, en la vista simple se puede prender (y no apagar)',
        (tester) async {
      await abrir(tester, centralPrendida: false);
      await candado(tester, 'jefe_bloquear_ahora');
      expect(enVistaSimple(), isTrue);
      expect(find.byKey(const Key('central_barra_prender')), findsOneWidget);
      expect(find.byKey(const Key('central_barra_apagar')), findsNothing);
    });

    testWidgets('si el modo jefe se vence con la vista simple puesta, no vuelve sola la '
        'pantalla de antes: sigue la vista simple, y se sale con el logo y la clave',
        (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      ProviderScope.containerOf(tester.element(find.byType(BarraJefeScreen)))
          .read(_modoJefe.notifier)
          .vencer();
      await tester.pumpAndSettle();
      expect(enVistaSimple(), isTrue);
      expect(find.byKey(const Key('jefe_pestana_catalogo')), findsNothing);
      expect(find.byKey(const Key('jefe_pestana_precios')), findsNothing);
      for (final t in loQueSeLee(tester)) {
        expect(t, isNot(contains(r'$')), reason: t);
      }
      // El logo sigue: con la clave se sale, a la pantalla sin modo jefe.
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), _clave);
      await tocar(tester, 'notebook_clave_listo');
      await tocar(tester, 'notebook_entrar');
      expect(enVistaSimple(), isFalse);
      expect(find.byKey(const Key('jefe_sin_modo_jefe')), findsOneWidget);
    });

    testWidgets('en la vista simple no se sale para atrás; fuera de ella, sí', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      expect(find.byType(BackButton), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BarraJefeScreen), findsOneWidget, reason: 'del otro lado está todo lo del jefe');
      expect(enVistaSimple(), isTrue);

      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), _clave);
      await tocar(tester, 'notebook_clave_listo');
      await tocar(tester, 'notebook_entrar');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BarraJefeScreen), findsNothing);
    });
  });

  // 28-nov-2026 (el hallazgo 2 de la revisión de los roles): lo que la central no guarda
  // no se veía en ninguna pantalla de la notebook.
  group('lo que la central no aceptó', () {
    RechazoDeLaCentral rechazo(int minuto, String nombre, String motivo) => RechazoDeLaCentral(
          cuando: DateTime(2026, 12, 4, 23, minuto),
          equipo: 'tablet',
          nombre: nombre,
          tabla: 'barra_anulaciones',
          id: 'r$minuto',
          motivo: motivo,
        );

    String texto(WidgetTester tester, String clave) => tester.widget<Text>(find.byKey(Key(clave))).data!;

    testWidgets('sin rechazos, el panel no dice nada', (tester) async {
      await abrir(tester);
      expect(find.byKey(const Key('central_barra_rechazos')), findsNothing);
    });

    testWidgets('uno solo: quién, a qué hora y por qué', (tester) async {
      central.rechazos = [rechazo(41, 'Caja 2 · Sofía', 'Anula solo la encargada')];
      await abrir(tester);
      expect(texto(tester, 'central_barra_rechazos'),
          'La central no aceptó una cosa que le mandaron: no se guardó ni se repartió.');
      expect(texto(tester, 'central_barra_rechazo_0'), '23:41 · Caja 2 · Sofía: Anula solo la encargada');
    });

    testWidgets('varios: cuántos, los últimos cinco (el más nuevo arriba), y se ven también en '
        'la vista simple', (tester) async {
      central.rechazos = [
        for (var i = 1; i <= 7; i++) rechazo(40 + i, 'Caja $i · Sofía', 'La venta es de una caja de otro aparato'),
      ];
      await abrir(tester);
      expect(texto(tester, 'central_barra_rechazos'),
          'La central no aceptó 7 cosas que le mandaron: no se guardaron ni se repartieron.');
      expect(texto(tester, 'central_barra_rechazo_0'),
          '23:47 · Caja 7 · Sofía: La venta es de una caja de otro aparato');
      expect(texto(tester, 'central_barra_rechazo_4'),
          '23:43 · Caja 3 · Sofía: La venta es de una caja de otro aparato');
      expect(find.byKey(const Key('central_barra_rechazo_5')), findsNothing);
      expect(find.text('y 2 más de antes.'), findsOneWidget);

      await candado(tester, 'jefe_bloquear_ahora');
      expect(enVistaSimple(), isTrue);
      expect(find.byKey(const Key('central_barra_rechazos')), findsOneWidget);
      for (final t in loQueSeLee(tester)) {
        expect(t, isNot(contains(r'$')), reason: t);
      }
    });
  });

  group('el logo de arriba', () {
    testWidgets('apretado menos de 2 segundos no pide nada', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, const Duration(milliseconds: 1500));
      expect(find.byKey(const Key('notebook_clave')), findsNothing);
      // Un toque corto tampoco.
      await tester.tap(find.byKey(const Key('jefe_logo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notebook_clave')), findsNothing);
      expect(enVistaSimple(), isTrue);
    });

    testWidgets('apretado 2 segundos pide la clave de la notebook', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      expect(find.text('La clave de esta notebook'), findsOneWidget);
      expect(find.byKey(const Key('notebook_clave')), findsOneWidget);
      // Lo que se escribe no se ve.
      expect(tester.widget<TextField>(find.byKey(const Key('notebook_clave'))).obscureText, isTrue);
      expect(enVistaSimple(), isTrue, reason: 'hasta poner la clave, nada vuelve');
    });

    testWidgets('con una clave que no es, no entra y lo dice; VOLVER deja la vista simple',
        (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), '1111');
      await tocar(tester, 'notebook_clave_listo');
      expect(find.text('Esa no es la clave de esta notebook.'), findsOneWidget);
      expect(find.byKey(const Key('notebook_entrar')), findsNothing);
      // Vacía tampoco.
      await tocar(tester, 'notebook_clave_listo');
      expect(find.byKey(const Key('notebook_entrar')), findsNothing);
      await tester.tap(find.text('VOLVER'));
      await tester.pumpAndSettle();
      expect(enVistaSimple(), isTrue);
      expect(find.byKey(const Key('jefe_pestana_cajas')), findsNothing);
    });

    testWidgets('con la clave de la notebook vuelve todo lo del jefe', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), _clave);
      await tocar(tester, 'notebook_clave_listo');
      // Con la clave bien: si se bloquea sola, y ENTRAR.
      expect(find.byKey(const Key('notebook_se_bloquea_sola')), findsOneWidget);
      expect(enVistaSimple(), isTrue, reason: 'todavía no tocó ENTRAR');
      await tocar(tester, 'notebook_entrar');
      expect(enVistaSimple(), isFalse);
      expect(subtitulo(tester), 'Modo jefe');
      expect(find.byKey(const Key('jefe_pestana_cajas')), findsOneWidget);
      expect(find.byKey(const Key('jefe_bloquear')), findsOneWidget);
      expect(central.apagadas, 0, reason: 'desbloquear tampoco toca la central');
    });

    testWidgets('la clave también entra con Enter', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), _clave);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notebook_entrar')), findsOneWidget);
    });

    testWidgets('fuera de la vista simple, apretar el logo no hace nada', (tester) async {
      await abrir(tester);
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      expect(find.byKey(const Key('notebook_clave')), findsNothing);
      expect(enVistaSimple(), isFalse);
    });
  });

  group('que se bloquee sola', () {
    testWidgets('con el tilde y la central prendida, a los 2 minutos sin tocarla queda solo la '
        'central', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_sola');
      expect(enVistaSimple(), isFalse, reason: 'tildar no bloquea en el momento');
      await nadieLaToca(tester, _espera - const Duration(seconds: 5));
      expect(enVistaSimple(), isFalse);
      await nadieLaToca(tester, const Duration(seconds: 10));
      expect(enVistaSimple(), isTrue);
      expect(central.apagadas, 0);
    });

    testWidgets('mientras se la usa no se bloquea: la cuenta empieza de nuevo con cada toque',
        (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_sola');
      for (var i = 0; i < 4; i++) {
        await nadieLaToca(tester, const Duration(seconds: 90));
        await tocar(tester, 'jefe_pestana_precios');
        await tocar(tester, 'jefe_pestana_cajas');
        expect(enVistaSimple(), isFalse, reason: 'vuelta $i');
      }
      await nadieLaToca(tester, _espera + const Duration(seconds: 5));
      expect(enVistaSimple(), isTrue);
    });

    testWidgets('con el tilde pero la central apagada, no se bloquea', (tester) async {
      await abrir(tester, centralPrendida: false);
      await candado(tester, 'jefe_bloquear_sola');
      await nadieLaToca(tester, const Duration(minutes: 30));
      expect(enVistaSimple(), isFalse);
    });

    testWidgets('al bloquearse cierra lo que quedó abierto encima (mostraría la plata)',
        (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_sola');
      await tocar(tester, 'jefe_cambiar_fiesta');
      expect(find.text('LAS QUE VIENEN'), findsOneWidget);
      await nadieLaToca(tester, _espera + const Duration(seconds: 5));
      expect(find.text('LAS QUE VIENEN'), findsNothing);
      expect(enVistaSimple(), isTrue);
    });

    testWidgets('el tilde se recuerda en el equipo, y destildar lo apaga', (tester) async {
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_sola');
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_preferencia), isTrue);
      await candado(tester, 'jefe_bloquear_sola');
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_preferencia), isFalse);
      await nadieLaToca(tester, const Duration(minutes: 30));
      expect(enVistaSimple(), isFalse);
    });

    testWidgets('con el tilde guardado de antes, se bloquea sola sin volver a tildarlo',
        (tester) async {
      SharedPreferences.setMockInitialValues({_preferencia: true});
      await abrir(tester);
      await nadieLaToca(tester, _espera + const Duration(seconds: 5));
      expect(enVistaSimple(), isTrue);
    });

    testWidgets('al desbloquear se puede apagar desde el cartel de la clave', (tester) async {
      SharedPreferences.setMockInitialValues({_preferencia: true});
      await abrir(tester);
      await candado(tester, 'jefe_bloquear_ahora');
      await apretarElLogo(tester, kApretarElLogo + const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('notebook_clave')), _clave);
      await tocar(tester, 'notebook_clave_listo');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('notebook_se_bloquea_sola'))).value, isTrue);
      await tocar(tester, 'notebook_se_bloquea_sola');
      await tocar(tester, 'notebook_entrar');
      await nadieLaToca(tester, const Duration(minutes: 30));
      expect(enVistaSimple(), isFalse);
      expect((await SharedPreferences.getInstance()).getBool(_preferencia), isFalse);
    });
  });

  group('solo en la notebook del jefe', () {
    for (final (donde, web, notebook, jefe) in [
      ('en la web', true, true, true),
      ('en una tablet', false, false, true),
      ('sin modo jefe', false, true, false),
    ]) {
      testWidgets('$donde no hay logo ni candado, y nunca queda la vista simple', (tester) async {
        SharedPreferences.setMockInitialValues({_preferencia: true});
        await abrir(tester, enLaWeb: web, esLaNotebook: notebook, esJefe: jefe);
        expect(find.byKey(const Key('jefe_logo')), findsNothing);
        expect(find.byKey(const Key('jefe_bloquear')), findsNothing);
        await nadieLaToca(tester, const Duration(minutes: 30));
        expect(enVistaSimple(), isFalse);
      });
    }
  });
}
