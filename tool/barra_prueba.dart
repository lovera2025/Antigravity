// Ventana de prueba de la barra: la entrada con el PIN, elegir la fiesta, abrir la caja,
// VENDER, cobrar y los vales, de verdad, **sin tocar la base de la PC ni la nube**. Lo
// que se vende se queda en esta ventana y al cerrarla se olvida todo. Los papeles salen
// por la TP-POS58 de verdad, si está prendida (se elige con el ícono de la impresora).
//
//   flutter run -d windows -t tool/barra_prueba.dart
//
// No corre `main.dart`: no abre la base ni inicia sesión. Los PIN inventados están en la
// barra de arriba, con el botón para cortar y volver el internet. Para verla como en un
// celular o una tablet, achicar la ventana.
//
// Sin gastar papel: `--dart-define=papel=pantalla`. Los papeles no salen por la
// impresora: PAPEL, arriba, muestra el último como texto (las líneas grandes, con >>).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/barra/impresion/impresora_recordada.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La impresora que ya eligió esta PC, para que se conecte sola; el resto, en memoria,
  // sin tocar las preferencias de la PC (el PIN maestro de siempre).
  final real = await const ImpresoraRecordada().leer();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  if (real != null) {
    await const ImpresoraRecordada().guardar(real);
  }

  final operadores = OperadoresEnPrueba();
  operadores.operadores.lista.addAll([
    operadorDePrueba('a0000000-0000-4000-8000-000000000001', 'Marta (solo Barra)', '1111'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000002', 'Tati (los tres)', '5555'),
  ]);
  operadores.permisos
    ..poner('a0000000-0000-4000-8000-000000000001', const PermisosEfectivos(barra: true))
    ..poner(
      'a0000000-0000-4000-8000-000000000002',
      const PermisosEfectivos(cobros: true, entradas: true, barra: true),
    );

  final prueba = BarraEnPrueba();
  final hoy = DateTime.now();
  final puertoViejo = fiestaDePrueba(BarraEnPrueba.id(1), 'PUERTO VIEJO', hoy);
  final tecnica = fiestaDePrueba(BarraEnPrueba.id(2), 'TÉCNICA', hoy.add(const Duration(days: 1)));
  prueba.eventos.addAll([
    puertoViejo,
    tecnica,
    fiestaDePrueba(BarraEnPrueba.id(3), 'BUENA VISTA (sin precios)', hoy.add(const Duration(days: 9))),
  ]);
  final b = prueba.barra;
  var orden = 0;
  for (final (nombre, categoria, precio, stock) in [
    ('Cerveza lata', 'Cervezas', 3500.0, 240),
    ('Cerveza porrón', 'Cervezas', 5000.0, null),
    ('Fernet con coca', 'Tragos', 6000.0, null),
    ('Gin tonic', 'Tragos', 7000.0, null),
    ('Speed con vodka', 'Tragos', 8000.0, 12),
    ('Agua sin gas', 'Sin alcohol', 1000.0, 3),
    ('Gaseosa', 'Sin alcohol', 2000.0, null),
    ('Champán Chandon Extra Brut', 'Vinos', 45000.0, null),
    // La silla de la noche (6.4.0): sale en su propio vale, que va a la recepcionista.
    ('Silla extra', 'Sillas', 8000.0, null),
  ]) {
    final p = b.producto(nombre, categoria: categoria);
    b.precio(puertoViejo.id, p, precio, orden: orden, stock: stock, aviso: stock == null ? null : 2);
    b.precio(tecnica.id, p, precio + 500, orden: orden);
    orden++;
  }

  // El internet de la prueba: el botón de arriba lo corta y lo vuelve.
  final conexion = operadores.conexion;
  runApp(ProviderScope(
    overrides: [
      ...operadores.reemplazos,
      barraDeLaCajaProvider.overrideWithValue(b),
      if (_papelEnPantalla) papelDeLaBarraProvider.overrideWithValue(prueba.papel),
      eventosDeLaBarraProvider.overrideWith((ref) async => prueba.eventos),
      subirVentaProvider.overrideWithValue((v) async {
        if (conexion.currentStatus == AppConnectivity.online) b.sinSubir.remove(v.id);
      }),
      // Las anulaciones y los vales que salieron: en la prueba no suben a ningún lado.
      subirDeLaBarraProvider.overrideWithValue((tabla, id) async {}),
      accesosBarraProvider.overrideWithValue(AccesosBarra(
        bajar: () async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return conexion.currentStatus == AppConnectivity.online;
        },
        contarFiestas: () async => (await b.fiestasConPrecio()).length,
        contarSinSubir: b.ventasSinSubir,
        leerAlDia: () async => prueba.alDia,
        anotarAlDia: (c) async => prueba.alDia = c,
      )),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Arriba(conexion: conexion, papel: _papelEnPantalla ? prueba.papel : null),
    ),
  ));
}

const _papelEnPantalla = String.fromEnvironment('papel') == 'pantalla';

class _Arriba extends ConsumerStatefulWidget {
  final ConexionFija conexion;

  /// Con `papel=pantalla`: los papeles que "salieron", para mirarlos.
  final PapelEnMemoria? papel;

  const _Arriba({required this.conexion, this.papel});

  @override
  ConsumerState<_Arriba> createState() => _ArribaState();
}

class _ArribaState extends ConsumerState<_Arriba> {
  /// El último papel, como texto: lo grande con >>, los renglones con su precio, y
  /// [LOGO] o [QR] si los lleva.
  void _verPapel(PapelEnMemoria papel) {
    final ultimo = papel.enCrudo.lastOrNull;
    final lineas = [
      for (final l in ultimo ?? const <LineaTicket>[])
        switch (l) {
          GrandeTicket() => '>> ${l.texto}',
          TituloTicket() => '## ${l.texto}',
          TextoTicket() => l.texto,
          RenglonTicket() => '${l.izquierda}  ·  ${l.derecha}',
          SeparadorTicket() => '--------------------------------',
          QrTicket() => '[QR]',
          LogoTicket() => '[LOGO]',
        },
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Papel ${papel.papeles.length}'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              ultimo == null ? 'Todavía no salió ningún papel.' : lineas.join('\n'),
              key: const Key('prueba_papel_texto'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR'))],
      ),
    );
  }

  Timer? _reloj;
  var _vistos = 0;

  @override
  void initState() {
    super.initState();
    // El contador de PAPEL se pone al día solo, cuando sale uno nuevo.
    if (widget.papel case final papel?) {
      _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && papel.papeles.length != _vistos) {
          setState(() => _vistos = papel.papeles.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appRoleProvider);
    final hay = widget.conexion.currentStatus == AppConnectivity.online;
    return Column(
      children: [
        Material(
          color: const Color(0xFFFFF3CD),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Prueba de la barra: nada se guarda de verdad.   PIN: Marta 1111 · Tati 5555',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.papel case final papel?)
                  TextButton(
                    key: const Key('prueba_papel'),
                    onPressed: () => _verPapel(papel),
                    child: Text('PAPEL (${papel.papeles.length})'),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() => widget.conexion.estado =
                        hay ? AppConnectivity.offline : AppConnectivity.online);
                    // La línea sin internet se vuelve a armar con la conexión nueva.
                    ref.invalidate(puestaAlDiaBarraProvider);
                  },
                  child: Text(hay ? 'CORTAR INTERNET' : 'VOLVER EL INTERNET'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: switch (destinoDeEntrada(app)) {
            DestinoDeEntrada.barra => const BarraHomeScreen(),
            DestinoDeEntrada.elegir => const RoleGateScreen(),
            _ => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: ref.read(appRoleProvider.notifier).logoutApp,
                    child: const Text('Esto no es la barra (la prueba es de la barra). SALIR'),
                  ),
                ),
              ),
          },
        ),
      ],
    );
  }
}
