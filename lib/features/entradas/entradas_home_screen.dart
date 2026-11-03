import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/contrato_alumno.dart';
import '../../models/evento.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../common/utils/cortes_pantalla.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import '../eventos/repositories/eventos_repository.dart';
import '../eventos/retiro_entradas_screen.dart';
import '../eventos/utils/evento_presentacion.dart';
import 'services/fiestas_que_vienen.dart';

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
class EntradasHomeScreen extends ConsumerWidget {
  /// Para los tests y la ventana de prueba. Sin esto, abre el retiro de entradas.
  final void Function(BuildContext context, Evento evento)? onAbrirFiesta;

  const EntradasHomeScreen({super.key, this.onAbrirFiesta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const gold = Color(0xFFD4AF37);
    final app = ref.watch(appRoleProvider);
    final fiestas = ref.watch(fiestasQueVienenProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;

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
                      return Card(
                        child: ListTile(
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
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _abrir(context, ref, e),
                        ),
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

  void _abrir(BuildContext context, WidgetRef ref, Evento evento) {
    final abrir = onAbrirFiesta;
    if (abrir != null) {
      abrir(context, evento);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RetiroEntradasScreen(
          evento: evento,
          onCobrar: (a) => _decir(context, _queCobre(ref, a)),
          onEditarAlumno: (a) => _decir(
            context,
            'Los datos de ${a.nombreAlumno} los cambia el jefe: pedile que los '
            'revise.',
          ),
        ),
      ),
    );
  }

  String _queCobre(WidgetRef ref, ContratoAlumno a) =>
      ref.read(appRoleProvider).permisos.cobros
          ? 'Para cobrarle a ${a.nombreAlumno}, volvé atrás y tocá PASAR A CAJA.'
          : 'Que ${a.nombreAlumno} pase por caja a saldar todo. Cuando pague, la '
              'entrega se destraba sola.';

  Future<void> _decir(BuildContext context, String texto) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(texto),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
}
