import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../central/central_barra_provider.dart';
import '../central/panel_central_barra.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../repositor/stock_de_las_barras_screen.dart';
import '../services/fiestas_del_jefe.dart';
import '../widgets/elegir_impresora_screen.dart';
import 'barra_jefe_providers.dart';
import 'cajas_de_la_fiesta.dart';
import 'catalogo_del_jefe.dart';
import 'elegir_fiesta.dart';
import 'ganancia_del_jefe.dart';
import 'precios_de_la_fiesta.dart';
import 'vista_simple_de_la_notebook.dart';

/// Las tres partes de BARRA.
/// GANANCIA va al final y solo la ve el jefe (`ReglasDeLaBarra.veElCostoYLaGanancia`).
enum PestanaBarraJefe { catalogo, precios, cajas, ganancia }

/// BARRA, la pantalla del jefe en la PC (etapa 7): **primero la fiesta** (abre en la
/// próxima; CAMBIAR DE FIESTA para otra), y debajo CATÁLOGO, PRECIOS y CAJAS.
///
/// Se llega desde el Centro de Comando, que solo se ve en modo jefe. Lo que guarda
/// pregunta otra vez por el modo jefe antes de guardar (`_frenaSinModoJefe` en cada
/// pestaña; `test/solo_modo_jefe_test.dart`). Sin modo jefe se ve todo y lo que guarda
/// queda apagado, con el motivo.
class BarraJefeScreen extends ConsumerStatefulWidget {
  /// Con qué pestaña abre. Para los tests y la ventana de prueba.
  final PestanaBarraJefe pestanaInicial;

  const BarraJefeScreen({super.key, this.pestanaInicial = PestanaBarraJefe.catalogo});

  @override
  ConsumerState<BarraJefeScreen> createState() => _BarraJefeScreenState();
}

class _BarraJefeScreenState extends ConsumerState<BarraJefeScreen> {
  late PestanaBarraJefe _pestana = widget.pestanaInicial;

  /// La fiesta para la que este aparato ya buscó la central de la barra.
  String? _buscoLaCentralDe;

  /// **La vista simple** (27-nov-2026, `vista_simple_de_la_notebook.dart`): en la notebook
  /// de la barra queda a la vista solo la central. Lo demás vuelve con el logo y la clave.
  bool _vistaSimple = false;
  Timer? _sinUso;

  @override
  void initState() {
    super.initState();
    // El uso se mira en toda la app, no solo en esta pantalla: si el jefe está leyendo una
    // caja (otra pantalla, encima de esta), no se le tiene que cerrar.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_alTocar);
    HardwareKeyboard.instance.addHandler(_alTeclear);
    _huboUso();
  }

  @override
  void dispose() {
    _sinUso?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_alTocar);
    HardwareKeyboard.instance.removeHandler(_alTeclear);
    super.dispose();
  }

  void _alTocar(PointerEvent e) => _huboUso();

  bool _alTeclear(KeyEvent e) {
    _huboUso();
    return false;
  }

  void _huboUso() {
    _sinUso?.cancel();
    if (!mounted) return;
    _sinUso = Timer(ref.read(esperaParaLaVistaSimpleProvider), _nadieLaToca);
  }

  /// Solo en la notebook (donde se prende la central) y con el modo jefe: en una tablet o
  /// en la web no hay vista simple.
  bool get _esLaNotebookDelJefe =>
      !ref.read(enLaWebProvider) && ref.read(centralSePrendeAcaProvider) && ref.read(esRolJefeProvider);

  /// Pasó el tiempo sin que nadie la toque: con la central prendida acá, queda la vista
  /// simple (si el jefe no lo apagó al desbloquear).
  void _nadieLaToca() {
    if (!mounted || _vistaSimple || !_esLaNotebookDelJefe) return;
    if (!ref.read(vuelveSolaALaVistaSimpleProvider)) return;
    if (!ref.read(centralDeLaBarraProvider).prendida) return;
    _dejarSoloLaCentral();
  }

  /// El candado, o el tiempo sin uso. Lo que haya quedado abierto encima (una caja, un
  /// cartel) se cierra: mostraría la plata.
  void _dejarSoloLaCentral() {
    final esta = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == esta || r.isFirst);
    setState(() => _vistaSimple = true);
  }

  /// El logo, apretado: la clave de esta notebook y, si está bien, vuelve todo.
  Future<void> _pedirLaClave(BuildContext donde) async {
    final entro = await showDialog<bool>(context: donde, builder: (_) => const ClaveDeLaNotebookDialog());
    if (entro != true || !mounted) return;
    setState(() => _vistaSimple = false);
    _huboUso();
  }

  /// **El jefe en MODO JEFE desde una tablet también se conecta a la central** (27-nov-2026,
  /// lo pidió el usuario): sin internet, lo que acepta, anula o saca no les llegaba a las
  /// cajas, porque solo VENDER y LAS CAJAS de la encargada la buscaban. Entra con el PIN
  /// maestro de este aparato (`credencialDeLaBarraProvider`), que tiene que ser el de la
  /// notebook. En la notebook que tiene la central prendida no hace nada (`arrancar`), y en
  /// la web no hay red del salón.
  void _buscarLaCentral(String eventoId) {
    if (_buscoLaCentralDe == eventoId) return;
    _buscoLaCentralDe = eventoId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(eventoId: eventoId, nombre: 'Jefe').ignore();
    });
  }

  /// [donde] es el contexto de adentro del tema de la barra: con el de la pantalla, la
  /// ventana salía con los colores claros de la app.
  Future<void> _cambiarFiesta(FiestasDelJefe fiestas, Evento actual, BuildContext donde) async {
    final id = await showDialog<String>(
      context: donde,
      builder: (_) => ElegirFiestaDelJefe(
        fiestas: fiestas,
        actual: actual.id,
        hoy: ref.read(relojDelJefeProvider)(),
      ),
    );
    if (id == null || !mounted) return;
    ref.read(fiestaElegidaDelJefeProvider.notifier).elegir(id);
  }

  @override
  Widget build(BuildContext context) {
    final tema = temaDeVender(DisenioBarra.nocheDorada, base: Theme.of(context));
    return Theme(
      data: tema,
      child: Builder(builder: _pantalla),
    );
  }

  Widget _pantalla(BuildContext context) {
    final fiestas = ref.watch(fiestasDelJefeProvider);
    final esJefe = ref.watch(esRolJefeProvider);
    // GANANCIA (lo que se le debe al proveedor y lo que se gana): solo el jefe.
    final veGanancia = ReglasDeLaBarra.veElCostoYLaGanancia(ref.watch(rolEnLaBarraProvider));
    final enLaWeb = ref.watch(enLaWebProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
    // La notebook de la barra (donde se prende la central), con el modo jefe.
    final esLaNotebook = !enLaWeb && ref.watch(centralSePrendeAcaProvider);
    final enLaNotebook = esLaNotebook && esJefe;
    // Una vez puesta, la vista simple no depende de que el modo jefe siga: si se vence
    // (el PIN del modo jefe dura unos minutos) con la notebook bloqueada, no vuelve sola la
    // pantalla de antes (28-nov-2026: lo encontró la prueba de la vista simple).
    final simple = _vistaSimple && esLaNotebook;
    // La fiesta que se está mirando, para abrir su STOCK desde arriba.
    final laFiesta = fiestas.value?.elegida(ref.watch(fiestaElegidaDelJefeProvider), enLaBarra: true);
    return PopScope(
      // En la vista simple no se sale para atrás: del otro lado está todo lo del jefe.
      canPop: !simple,
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !simple,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // El logo va siempre, como un adorno. En la vista simple, mantenerlo apretado
            // pide la clave de la notebook; nada en la pantalla lo dice.
            if (enLaNotebook || simple) ...[
              RawGestureDetector(
                key: const Key('jefe_logo'),
                gestures: {
                  LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                    () => LongPressGestureRecognizer(duration: kApretarElLogo),
                    (r) => r.onLongPress = simple ? () => _pedirLaClave(context) : null,
                  ),
                },
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/isotipo-ej.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.local_bar_outlined, size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'BARRA',
                  key: Key('jefe_titulo'),
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
                ),
                Text(
                  simple ? 'Central' : 'Modo jefe',
                  key: const Key('jefe_subtitulo'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA7A29A)),
                ),
              ],
            ),
          ],
        ),
        // La impresora de esta PC, para la lista de precios, las copias y el cierre: la
        // misma pantalla que la cajera abre desde VENDER. En la web no hay Bluetooth.
        actions: [
          // El stock de cada barra (28-nov-2026): el jefe también repone y anota.
          if (!simple && laFiesta != null)
            IconButton(
              key: const Key('jefe_stock_de_las_barras'),
              tooltip: 'El stock de cada barra',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StockDeLasBarrasScreen(fiesta: laFiesta),
              )),
            ),
          if (!enLaWeb && !simple)
            IconButton(
              key: const Key('jefe_impresora'),
              tooltip: 'La impresora de esta PC',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ElegirImpresoraScreen(
                  impresora: ref.read(impresoraDeLaBarraProvider),
                  papel: ref.read(papelDeLaBarraProvider),
                ),
              )),
            ),
          // El candado: dejar solo la central a la vista ya, y prender o apagar que se
          // bloquee sola (viene apagado: el jefe lo prende para la fiesta).
          if (enLaNotebook && !simple)
            PopupMenuButton<String>(
              key: const Key('jefe_bloquear'),
              tooltip: 'La notebook a la vista de todos',
              icon: Icon(ref.watch(vuelveSolaALaVistaSimpleProvider) ? Icons.lock_clock_outlined : Icons.lock_outline),
              onSelected: (que) {
                if (que == 'ahora') {
                  _dejarSoloLaCentral();
                } else {
                  final notifier = ref.read(vuelveSolaALaVistaSimpleProvider.notifier);
                  notifier.poner(!ref.read(vuelveSolaALaVistaSimpleProvider));
                  _huboUso();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  key: Key('jefe_bloquear_ahora'),
                  value: 'ahora',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline),
                    title: Text('Dejar solo la central ahora'),
                    subtitle: Text('Lo demás vuelve apretando el logo, con la clave'),
                  ),
                ),
                CheckedPopupMenuItem(
                  key: const Key('jefe_bloquear_sola'),
                  value: 'sola',
                  checked: ref.read(vuelveSolaALaVistaSimpleProvider),
                  child: Text('Que se bloquee sola a los ${kVistaSimpleSinUso.inMinutes} minutos\n(con la central prendida)'),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: fiestas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No se pudieron leer las fiestas.')),
        data: (datos) {
          // La de esta noche, si hay (25-nov-2026): la barra abre en la fiesta en curso.
          final fiesta = datos.elegida(ref.watch(fiestaElegidaDelJefeProvider), enLaBarra: true);
          if (fiesta != null && esJefe && !enLaWeb) _buscarLaCentral(fiesta.id);
          if (fiesta == null) {
            return const Center(
              key: Key('jefe_sin_fiestas'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Todavía no hay fiestas cargadas. Se crean en EVENTOS.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (simple) {
            // Solo la central: las cajas conectadas y si está todo subido. Prendida, **no se
            // apaga desde acá** (se desconectarían todas las cajas); apagada, se puede prender.
            // Ni las cajas con la plata, ni el catálogo, ni los precios, ni GANANCIA.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  key: const Key('jefe_vista_simple'),
                  padding: EdgeInsets.fromLTRB(margen, 8, margen, 24),
                  children: [
                    _BloqueFiesta(
                      fiesta: fiesta,
                      fecha: fechaConCuando(
                        fiesta.fechaEvento,
                        ref.read(relojDelJefeProvider)(),
                        esLaQueAbre: fiesta.id == datos.laQueAbreEnLaBarra?.id,
                      ),
                      onCambiar: null,
                    ),
                    const SizedBox(height: 12),
                    PanelCentralDeLaBarra(
                      eventoId: fiesta.id,
                      fechaDeLaFiesta: fiesta.fechaEvento,
                      sinApagar: true,
                    ),
                  ],
                ),
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: EdgeInsets.fromLTRB(margen, 8, margen, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!esJefe)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          '$kSoloEnModoJefe: se ve todo, pero para cambiar algo hace falta el modo jefe.',
                          key: Key('jefe_sin_modo_jefe'),
                          style: TextStyle(color: Color(0xFFF2B84B)),
                        ),
                      ),
                    _BloqueFiesta(
                      fiesta: fiesta,
                      fecha: fechaConCuando(
                        fiesta.fechaEvento,
                        ref.read(relojDelJefeProvider)(),
                        esLaQueAbre: fiesta.id == datos.laQueAbreEnLaBarra?.id,
                      ),
                      onCambiar: datos.todas.length > 1 ? () => _cambiarFiesta(datos, fiesta, context) : null,
                    ),
                    const SizedBox(height: 12),
                    _Pestanas(
                      elegida: _pestana,
                      onElegir: (p) => setState(() => _pestana = p),
                      conGanancia: veGanancia,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: switch (_pestana) {
                        PestanaBarraJefe.catalogo => const CatalogoDelJefe(),
                        PestanaBarraJefe.precios => PreciosDeLaFiestaVista(
                            key: ValueKey('precios_${fiesta.id}'),
                            fiesta: fiesta,
                            otras: [for (final e in datos.todas) if (e.id != fiesta.id) e],
                          ),
                        PestanaBarraJefe.cajas => CajasDeLaFiestaVista(
                            key: ValueKey('cajas_${fiesta.id}'),
                            fiesta: fiesta,
                          ),
                        // Sin modo jefe no se ve (y la pestaña ni aparece).
                        PestanaBarraJefe.ganancia when veGanancia => GananciaDelJefeVista(
                            key: ValueKey('ganancia_${fiesta.id}'),
                            fiesta: fiesta,
                            todas: datos.todas,
                            onIrAPrecios: () => setState(() => _pestana = PestanaBarraJefe.precios),
                          ),
                        PestanaBarraJefe.ganancia => const SizedBox.shrink(),
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Arriba de todo: la fiesta, en grande, con su fecha.
class _BloqueFiesta extends StatelessWidget {
  final Evento fiesta;
  final String fecha;
  final VoidCallback? onCambiar;

  const _BloqueFiesta({required this.fiesta, required this.fecha, this.onCambiar});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1D1910),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3F1C)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'FIESTA',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFA7A29A),
                  ),
                ),
                Text(
                  EventoPresentacion.tituloPrincipal(fiesta),
                  key: const Key('jefe_fiesta_nombre'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text(
                  fecha,
                  key: const Key('jefe_fiesta_fecha'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFC9C4BA)),
                ),
              ],
            ),
            OutlinedButton(
              key: const Key('jefe_cambiar_fiesta'),
              onPressed: onCambiar,
              style: OutlinedButton.styleFrom(
                foregroundColor: TemaBarra.dorado,
                side: const BorderSide(color: TemaBarra.dorado),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('CAMBIAR DE FIESTA', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pestanas extends StatelessWidget {
  final PestanaBarraJefe elegida;
  final ValueChanged<PestanaBarraJefe> onElegir;
  final bool conGanancia;

  const _Pestanas({required this.elegida, required this.onElegir, this.conGanancia = false});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (p, texto) in [
          (PestanaBarraJefe.catalogo, 'CATÁLOGO'),
          (PestanaBarraJefe.precios, 'PRECIOS'),
          (PestanaBarraJefe.cajas, 'CAJAS'),
          if (conGanancia) (PestanaBarraJefe.ganancia, 'GANANCIA'),
        ])
          ChoiceChip(
            key: Key('jefe_pestana_${p.name}'),
            label: Text(texto, style: const TextStyle(letterSpacing: 1)),
            selected: p == elegida,
            onSelected: (_) => onElegir(p),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
      ],
    );
  }
}

