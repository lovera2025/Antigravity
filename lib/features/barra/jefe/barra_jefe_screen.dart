import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_providers.dart';
import '../services/fiestas_del_jefe.dart';
import '../widgets/elegir_impresora_screen.dart';
import 'barra_jefe_providers.dart';
import 'cajas_de_la_fiesta.dart';
import 'catalogo_del_jefe.dart';
import 'precios_de_la_fiesta.dart';

/// Las tres partes de BARRA.
enum PestanaBarraJefe { catalogo, precios, cajas }

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

  /// [donde] es el contexto de adentro del tema de la barra: con el de la pantalla, la
  /// ventana salía con los colores claros de la app.
  Future<void> _cambiarFiesta(FiestasDelJefe fiestas, Evento actual, BuildContext donde) async {
    final id = await showDialog<String>(
      context: donde,
      builder: (_) => _ElegirFiesta(
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
    final enLaWeb = ref.watch(enLaWebProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'BARRA',
              key: Key('jefe_titulo'),
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
            Text('Modo jefe', style: TextStyle(fontSize: 12, color: Color(0xFFA7A29A))),
          ],
        ),
        // La impresora de esta PC, para la lista de precios, las copias y el cierre: la
        // misma pantalla que la cajera abre desde VENDER. En la web no hay Bluetooth.
        actions: [
          if (!enLaWeb)
            IconButton(
              key: const Key('jefe_impresora'),
              tooltip: 'La impresora de esta PC',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ElegirImpresoraScreen(impresora: ref.read(impresoraDeLaBarraProvider)),
              )),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: fiestas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No se pudieron leer las fiestas.')),
        data: (datos) {
          final fiesta = datos.elegida(ref.watch(fiestaElegidaDelJefeProvider));
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
                        esLaQueAbre: fiesta.id == datos.laQueAbre?.id,
                      ),
                      onCambiar: datos.todas.length > 1 ? () => _cambiarFiesta(datos, fiesta, context) : null,
                    ),
                    const SizedBox(height: 12),
                    _Pestanas(
                      elegida: _pestana,
                      onElegir: (p) => setState(() => _pestana = p),
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
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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

  const _Pestanas({required this.elegida, required this.onElegir});

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

/// CAMBIAR DE FIESTA: las que vienen, la próxima primero, y las últimas.
class _ElegirFiesta extends StatelessWidget {
  final FiestasDelJefe fiestas;
  final String actual;
  final DateTime hoy;

  const _ElegirFiesta({required this.fiestas, required this.actual, required this.hoy});

  @override
  Widget build(BuildContext context) {
    Widget fila(Evento e, {required bool proxima}) {
      final fecha = fechaConCuando(e.fechaEvento, hoy, esLaQueAbre: proxima);
      final elegida = e.id == actual;
      return ListTile(
        key: Key('jefe_fiesta_${e.id}'),
        selected: elegida,
        title: Text(
          EventoPresentacion.tituloPrincipal(e),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(fecha),
        trailing: elegida ? const Icon(Icons.check, color: TemaBarra.dorado) : null,
        onTap: () => Navigator.pop(context, e.id),
      );
    }

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            t,
            style: const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700),
          ),
        );

    return AlertDialog(
      title: const Text('¿En qué fiesta?'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (fiestas.lasQueVienen.isNotEmpty) titulo('LAS QUE VIENEN'),
            for (final (i, e) in fiestas.lasQueVienen.indexed) fila(e, proxima: i == 0),
            if (fiestas.lasUltimas.isNotEmpty) titulo('LAS ÚLTIMAS'),
            for (final e in fiestas.lasUltimas) fila(e, proxima: false),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER')),
      ],
    );
  }
}
