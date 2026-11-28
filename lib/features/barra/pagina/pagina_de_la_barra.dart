import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/models/operador_caja.dart';
import '../../caja_sesiones/models/permisos_operador.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../repositor/stock_de_las_barras_screen.dart';
import '../widgets/las_cajas_screen.dart';
import '../widgets/ok_del_cierre.dart';
import 'cliente_de_la_pagina.dart';
import 'sonido_de_la_pagina.dart';

/// **La página del iPhone de la encargada y del repositor** (28-nov-2026): la sirve la
/// notebook de la barra por el wifi, sin internet. Pide solo el PIN; la encargada (y el
/// jefe con el PIN maestro) ve **LAS CAJAS** de la noche, el repositor **STOCK**: las
/// mismas pantallas de la app, con la barra en memoria que le manda la notebook.
class PaginaDeLaBarraApp extends StatelessWidget {
  const PaginaDeLaBarraApp({super.key, required this.cliente});
  final ClienteDeLaPagina cliente;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Barra — Junior Eventos',
        debugShowCheckedModeBanner: false,
        theme: temaDeVender(
          DisenioBarra.nocheDorada,
          // Sin internet no hay letras de respaldo: la flecha de "VER SUS VENTAS →" salía
          // como un cuadradito (Roboto no la tiene). Outfit, que viene con la app, sí.
          base: ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamilyFallback: const ['PlanoLinea']),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'AR')],
        locale: const Locale('es', 'AR'),
        home: PaginaDeLaBarra(cliente: cliente),
      );
}

class PaginaDeLaBarra extends StatefulWidget {
  const PaginaDeLaBarra({super.key, required this.cliente});
  final ClienteDeLaPagina cliente;

  @override
  State<PaginaDeLaBarra> createState() => _PaginaDeLaBarraState();
}

class _PaginaDeLaBarraState extends State<PaginaDeLaBarra> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// El iPhone se desbloqueó o se volvió a Safari: si estaba cortada, se reconecta ya.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) widget.cliente.alVolverALaVista();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.cliente,
        builder: (context, _) {
          final c = widget.cliente;
          final quien = c.quien;
          final evento = c.evento;
          final adentro = (c.estado == EstadoDeLaPagina.conectada || c.estado == EstadoDeLaPagina.sinConexion) &&
              quien != null;
          if (!adentro) return PantallaDelPin(cliente: c);
          if (evento == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return AdentroDeLaPagina(
            key: ValueKey('${quien.rol.name}:${quien.operadorId ?? quien.nombre}'),
            cliente: c,
            quien: quien,
            fiesta: Evento.fromJson(evento),
          );
        },
      );
}

/// Lo primero: solo el PIN.
class PantallaDelPin extends StatefulWidget {
  const PantallaDelPin({super.key, required this.cliente});
  final ClienteDeLaPagina cliente;

  @override
  State<PantallaDelPin> createState() => _PantallaDelPinState();
}

class _PantallaDelPinState extends State<PantallaDelPin> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _entrar() {
    // El primer toque habilita el sonido del aviso (el iPhone lo pide).
    SonidoDeLaPagina.desbloquear();
    widget.cliente.entrar(_pin.text);
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final entrando = c.estado == EstadoDeLaPagina.entrando;
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'BARRA',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [c.fiesta, c.barraDelSalon].whereType<String>().join(' · '),
                    key: const Key('pagina_fiesta'),
                    textAlign: TextAlign.center,
                    style: tema.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('pagina_pin'),
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    enabled: !entrando,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 8),
                    decoration: const InputDecoration(labelText: 'Tu PIN'),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('pagina_entrar'),
                    onPressed: entrando ? null : _entrar,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: entrando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ENTRAR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ),
                  if (c.problema != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      c.problema!,
                      key: const Key('pagina_problema'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tema.colorScheme.error, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Para la encargada y el repositor de barra. Sin internet: el teléfono tiene que estar en '
                    'el wifi de la barra.',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Adentro: LAS CAJAS (la encargada y el jefe) o STOCK (el repositor), con la barra en
/// memoria de la página y quien entró.
class AdentroDeLaPagina extends StatefulWidget {
  const AdentroDeLaPagina({super.key, required this.cliente, required this.quien, required this.fiesta});
  final ClienteDeLaPagina cliente;
  final QuienEnLaPagina quien;
  final Evento fiesta;

  @override
  State<AdentroDeLaPagina> createState() => _AdentroDeLaPaginaState();
}

class _AdentroDeLaPaginaState extends State<AdentroDeLaPagina> {
  late final ProviderContainer _contenedor;
  StreamSubscription<void>? _cambios;

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    final esJefe = widget.quien.rol == RolEnLaBarra.jefe;
    _contenedor = ProviderContainer(overrides: [
      barraDelJefeProvider.overrideWithValue(c.barra),
      // Sin impresora ni cola: lo que se anota ya quedó en la notebook.
      enLaWebProvider.overrideWithValue(true),
      enLaPaginaDeLaBarraProvider.overrideWithValue(true),
      relojDeLaBarraProvider.overrideWithValue(c.ahora),
      ahoraEnLaBarraProvider.overrideWithValue(c.ahora),
      esRolJefeProvider.overrideWithValue(esJefe),
      // Lo que mira está en la memoria y llega al toque: cada 3 s, como en la tablet.
      cadaCuantoMirarPedidosDeCierreProvider.overrideWithValue(kMirarPedidosDeCierre),
      sonarPedidoDeCierreProvider.overrideWithValue(SonidoDeLaPagina.sonar),
    ]);
    if (!esJefe) {
      final ahora = DateTime.now();
      unawaited(_contenedor.read(appRoleProvider.notifier).entrarComoBarra(
            OperadorCaja(
              id: widget.quien.operadorId ?? '',
              nombre: widget.quien.nombre,
              pin: '',
              activo: true,
              createdAt: ahora,
              updatedAt: ahora,
            ),
            widget.quien.rol == RolEnLaBarra.repositor
                ? const PermisosEfectivos(repositorBarra: true)
                : const PermisosEfectivos(barra: true, encargadaBarra: true),
          ));
    }
    // Lo que llega de la notebook rehace las pantallas.
    _cambios = c.cambios.listen((_) => _contenedor.read(operationalSyncRevisionProvider.notifier).bump());
  }

  @override
  void dispose() {
    unawaited(_cambios?.cancel());
    _contenedor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esRepositor = widget.quien.rol == RolEnLaBarra.repositor;
    return UncontrolledProviderScope(
      container: _contenedor,
      child: Column(
        children: [
          FranjaDeLaPagina(cliente: widget.cliente),
          Expanded(
            child: esRepositor
                ? StockDeLasBarrasScreen(fiesta: widget.fiesta)
                : LasCajasScreen(fiesta: widget.fiesta),
          ),
        ],
      ),
    );
  }
}

/// Arriba de todo: quién está, si hay conexión con la notebook, y SALIR.
class FranjaDeLaPagina extends StatelessWidget {
  const FranjaDeLaPagina({super.key, required this.cliente});
  final ClienteDeLaPagina cliente;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: cliente,
        builder: (context, _) {
          final conectada = cliente.conectada;
          final colores = Theme.of(context).colorScheme;
          final quien = cliente.quien?.nombre ?? '';
          final franja = Material(
            color: conectada ? colores.surfaceContainerHighest : colores.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Icon(conectada ? Icons.wifi : Icons.wifi_off, size: 18),
                    const SizedBox(width: 8),
                    if (cliente.porConfirmar > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${cliente.porConfirmar} por confirmar',
                          key: const Key('pagina_por_confirmar'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF2B84B)),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        conectada
                            ? '$quien${cliente.barraDelSalon == null ? '' : ' · ${cliente.barraDelSalon}'} · conectada a la notebook'
                            : (cliente.problema ??
                                'Sin conexión con la notebook: no se anota nada. Reconectando… '
                                    'Si la notebook se reinició, escaneá otra vez su QR.'),
                        key: const Key('pagina_franja'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const Key('pagina_salir'),
                      onPressed: () => unawaited(_salir(context)),
                      child: const Text('SALIR'),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (cliente.noSeAnotaron.isEmpty) return franja;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              franja,
              Material(
                key: const Key('pagina_no_se_anotaron'),
                color: colores.error,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colores.onError),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cliente.noSeAnotaron.join('\n'),
                          style: TextStyle(color: colores.onError, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        key: const Key('pagina_entendido'),
                        onPressed: cliente.olvidarLoQueNoSeAnoto,
                        style: TextButton.styleFrom(foregroundColor: colores.onError),
                        child: const Text('ENTENDIDO'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );

  /// SALIR. Con algo por confirmar, avisa antes: saliendo ya no se puede saber si se anotó.
  Future<void> _salir(BuildContext context) async {
    if (cliente.porConfirmar > 0) {
      final salir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Falta confirmar'),
          content: Text('${cliente.porConfirmar == 1 ? 'Hay 1 cosa' : 'Hay ${cliente.porConfirmar} cosas'} sin '
              'confirmar. Si salís ahora, no se va a saber si se anotó. Esperá a que arriba diga "conectada".'),
          actions: [
            TextButton(
              key: const Key('pagina_salir_igual'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SALIR IGUAL'),
            ),
            FilledButton(
              key: const Key('pagina_esperar'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ESPERAR'),
            ),
          ],
        ),
      );
      if (salir != true) return;
    }
    await cliente.salir();
  }
}
