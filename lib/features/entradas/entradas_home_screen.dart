import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/evento.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../common/utils/cortes_pantalla.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import '../eventos/repositories/eventos_repository.dart';
import '../eventos/retiro_entradas_screen.dart';
import '../eventos/utils/evento_presentacion.dart';
import 'services/fiestas_que_vienen.dart';
import 'widgets/vender_entradas_screen.dart';

/// Los eventos masivos que vienen. Se vuelve a leer cuando baja algo de la otra
/// PC: en una PC recién entrada, la primera bajada llega después de abrir esto.
final fiestasQueVienenProvider = FutureProvider<List<Evento>>((ref) async {
  ref.watch(operationalSyncRevisionProvider);
  final eventos =
      await ref.read(eventosRepositoryProvider).getAll(modalidad: 'masivo');
  return fiestasQueVienen(eventos, DateTime.now());
});

/// La pantalla de quien entró a Entradas: elegir la fiesta y entregar. No hay
/// camino a cobrar ni a editar un alumno (`test/modo_entradas_cerrado_test.dart`).
///
/// Si además tiene Cobros, PASAR A CAJA lo lleva sin volver a poner el PIN.
///
/// **Quien tiene "Vende entradas" (6.9.0) ve dos botones en cada fiesta,
/// ENTREGAR y VENDER**; quien solo entrega la ve como siempre, sin VENDER
/// (`puedeVenderEntradasProvider`). La venta va en su propia pantalla
/// (`widgets/vender_entradas_screen.dart`): acá solo está el botón.
class EntradasHomeScreen extends ConsumerWidget {
  /// Para los tests y la ventana de prueba. Sin esto, abre el retiro de entradas.
  final void Function(BuildContext context, Evento evento)? onAbrirFiesta;

  /// Para los tests y la ventana de prueba. Sin esto, abre VENDER.
  final void Function(BuildContext context, Evento evento)? onVenderFiesta;

  const EntradasHomeScreen({
    super.key,
    this.onAbrirFiesta,
    this.onVenderFiesta,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const gold = Color(0xFFD4AF37);
    final app = ref.watch(appRoleProvider);
    final fiestas = ref.watch(fiestasQueVienenProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final enCelular = CortesPantalla.esCelular(ancho);
    final margen = enCelular ? 12.0 : 24.0;
    final vende = ref.watch(puedeVenderEntradasProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'ENTRADAS · ${(app.operador?.nombre ?? '').toUpperCase()}',
          key: const Key('entradas_titulo'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (app.permisos.cobros)
            TextButton(
              key: const Key('pasar_a_caja'),
              onPressed: () => ref.read(appRoleProvider.notifier).pasarACaja(),
              child: const Text('PASAR A CAJA'),
            ),
          TextButton(
            key: const Key('entradas_salir'),
            onPressed: () => ref.read(appRoleProvider.notifier).logoutApp(),
            child: const Text('SALIR'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: fiestas.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: gold)),
        error: (_, _) =>
            const Center(child: Text('No se pudieron leer los eventos.')),
        data: (lista) => lista.isEmpty
            ? const Center(
                key: Key('entradas_sin_fiestas'),
                child: Text('No hay eventos masivos por delante.'),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView.separated(
                    padding: EdgeInsets.all(margen),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = lista[i];
                      // Con la caja de entradas: ENTREGAR y VENDER, a la vista.
                      final botones = !vende
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  key: Key('entregar_${e.id}'),
                                  onPressed: () => _abrir(context, ref, e),
                                  child: const Text('ENTREGAR'),
                                ),
                                const SizedBox(width: 6),
                                FilledButton(
                                  key: Key('vender_${e.id}'),
                                  onPressed: () => _vender(context, e),
                                  child: const Text('VENDER'),
                                ),
                              ],
                            );
                      final tile = ListTile(
                        key: Key('fiesta_${e.id}'),
                        leading: const Icon(
                          Icons.confirmation_number_outlined,
                          color: gold,
                        ),
                        title: Text(
                          EventoPresentacion.tituloPrincipal(e),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(_fecha(e.fechaEvento)),
                        trailing: botones == null
                            ? const Icon(Icons.chevron_right)
                            : (enCelular ? null : botones),
                        // Quien solo entrega toca la tarjeta entera, como siempre.
                        onTap: vende ? null : () => _abrir(context, ref, e),
                      );
                      return Card(
                        child: botones != null && enCelular
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  tile,
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                    child: botones,
                                  ),
                                ],
                              )
                            : tile,
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }

  static String _fecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}';
  }

  /// VENDER: la caja de entradas de esa fiesta.
  void _vender(BuildContext context, Evento evento) {
    final vender = onVenderFiesta;
    if (vender != null) {
      vender(context, evento);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenderEntradasScreen(evento: evento),
      ),
    );
  }

  /// La entrega en modo mostrador: sin cobrar ni editar al alumno; la familia que
  /// debe va a la caja, y cuando paga salta "pagó: ya podés entregar".
  void _abrir(BuildContext context, WidgetRef ref, Evento evento) {
    final abrir = onAbrirFiesta;
    if (abrir != null) {
      abrir(context, evento);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RetiroEntradasScreen.mostrador(evento: evento),
      ),
    );
  }
}
