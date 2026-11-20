import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/evento.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../common/utils/cortes_pantalla.dart';
import '../common/utils/dia_de_la_fiesta.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import '../eventos/repositories/eventos_repository.dart';
import '../eventos/retiro_entradas_screen.dart';
import '../eventos/utils/evento_presentacion.dart';
import 'providers/entradas_providers.dart';
import 'services/fiestas_que_vienen.dart';
import 'widgets/vender_entradas_screen.dart';

/// Los eventos masivos que vienen. Se vuelve a leer cuando baja algo de la otra
/// PC: en una PC recién entrada, la primera bajada llega después de abrir esto.
///
/// Más las que ya pasaron donde quien entró tiene su caja de entradas abierta en
/// este equipo (revisión final de la 6.9.0): así la puede cerrar.
final fiestasQueVienenProvider = FutureProvider<List<Evento>>((ref) async {
  ref.watch(operationalSyncRevisionProvider);
  final operador = ref.watch(appRoleProvider).operador;
  final eventos =
      await ref.read(eventosRepositoryProvider).getAll(modalidad: 'masivo');
  final ahora = DateTime.now();
  final conCaja = <String>{};
  if (operador != null && ref.read(entradasEnEsteEquipoProvider)) {
    final porDelante = {for (final e in fiestasQueVienen(eventos, ahora)) e.id};
    final caja = ref.read(entradasDeLaCajaProvider);
    for (final e in eventos) {
      if (porDelante.contains(e.id)) continue;
      try {
        final abierta = await caja.cajaAbierta(eventoId: e.id, operadorId: operador.id);
        if (abierta != null) conCaja.add(e.id);
      } catch (_) {
        // Si no se puede leer, la lista sale como siempre.
      }
    }
  }
  return fiestasQueVienen(eventos, ahora, conCajaAbierta: conCaja);
});

/// Si [e] ya pasó (solo sigue en la lista por una caja abierta).
bool _yaPaso(Evento e) => laFiestaYaPaso(e, DateTime.now());

/// La pantalla de quien entró a Entradas: elegir la fiesta y entregar. No hay
/// camino a cobrar ni a editar un alumno (`test/modo_entradas_cerrado_test.dart`).
///
/// Si además tiene Cobros, PASAR A CAJA lo lleva sin volver a poner el PIN.
///
/// **Quien tiene "Vende entradas" ve un solo botón en cada fiesta, VENDER**
/// (decisión del usuario, 20-nov-2026), y tocar la tarjeta entera también abre
/// VENDER: ahí está todo, lo sin cargo que se entrega (en dos partes) y lo que
/// se paga (`widgets/vender_entradas_screen.dart`). Solo en un equipo con la
/// base (`entradasEnEsteEquipoProvider`): en la web no se vende.
///
/// **Quien solo entrega la ve como siempre**: sin VENDER, y la tarjeta abre la
/// entrega del mostrador (`RetiroEntradasScreen.mostrador`).
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
    // Con "Vende entradas" y la base del equipo, VENDER es la única puerta.
    final vende = ref.watch(puedeVenderEntradasProvider) &&
        ref.watch(entradasEnEsteEquipoProvider);

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
                      // Con "Vende entradas": un solo botón, VENDER. Adentro se
                      // entrega lo sin cargo y se vende lo que se paga.
                      final botones = !vende
                          ? null
                          : FilledButton(
                              key: Key('vender_${e.id}'),
                              onPressed: () => _vender(context, ref, e),
                              child: const Text('VENDER'),
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
                        subtitle: _yaPaso(e)
                            ? Text(
                                '${_fecha(e.fechaEvento)} · Tu caja de entradas sigue '
                                'abierta: cerrala desde VENDER',
                                key: Key('caja_abierta_${e.id}'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : Text(_fecha(e.fechaEvento)),
                        trailing: botones == null
                            ? const Icon(Icons.chevron_right)
                            : (enCelular ? null : botones),
                        // La tarjeta entera abre lo mismo que su botón: VENDER
                        // a quien vende; a quien solo entrega, la entrega.
                        onTap: vende
                            ? () => _vender(context, ref, e)
                            : () => _abrir(context, ref, e),
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

  /// VENDER: la caja de entradas de esa fiesta. **Al volver se relee la lista**
  /// (revisión del 15-nov): cerrada la caja de una fiesta que ya pasó, la fiesta se
  /// va; si no, seguía con "Tu caja sigue abierta" y VENDER ofrecía abrir otra.
  Future<void> _vender(BuildContext context, WidgetRef ref, Evento evento) async {
    final vender = onVenderFiesta;
    if (vender != null) {
      vender(context, evento);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenderEntradasScreen(evento: evento),
      ),
    );
    if (context.mounted) ref.invalidate(fiestasQueVienenProvider);
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
