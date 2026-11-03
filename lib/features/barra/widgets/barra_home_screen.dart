import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_providers.dart';
import 'abrir_caja_barra_dialog.dart';
import 'linea_sin_internet_barra.dart';
import 'vender_screen.dart';

/// La pantalla de quien entró a la Barra con su PIN: elegir la fiesta y abrir (o
/// retomar) su caja de barra. No hay camino al panel ni a la caja de cuotas
/// (`test/modo_barra_cerrado_test.dart`).
class BarraHomeScreen extends ConsumerStatefulWidget {
  /// Para los tests y la ventana de prueba. Sin esto, abre VENDER.
  final void Function(BuildContext context, Evento fiesta, CajaBarra caja)? onCajaLista;

  const BarraHomeScreen({super.key, this.onCajaLista});

  @override
  ConsumerState<BarraHomeScreen> createState() => _BarraHomeScreenState();
}

class _BarraHomeScreenState extends ConsumerState<BarraHomeScreen> {
  bool _abriendo = false;

  Future<void> _abrir(Evento fiesta) async {
    final op = ref.read(appRoleProvider).operador;
    if (op == null || _abriendo) return;
    setState(() => _abriendo = true);
    try {
      final barra = ref.read(barraDeLaCajaProvider);
      var caja = await barra.cajaAbierta(eventoId: fiesta.id, operadorId: op.id);
      if (caja == null) {
        final abiertas = await barra.cajasAbiertas(fiesta.id);
        if (!mounted) return;
        final elegida = await pedirAbrirCajaBarra(
          context,
          fiesta: EventoPresentacion.tituloPrincipal(fiesta),
          abiertas: abiertas,
        );
        if (elegida == null) return;
        caja = await barra.abrirCaja(
          eventoId: fiesta.id,
          operadorId: op.id,
          operadorNombre: op.nombre,
          numeroCaja: elegida.numero,
          sede: elegida.sede,
        );
      }
      if (!mounted) return;
      final lista = widget.onCajaLista;
      if (lista != null) {
        lista(context, fiesta, caja);
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => VenderScreen(fiesta: fiesta, caja: caja!),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la caja. Probá de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final app = ref.watch(appRoleProvider);
    final fiestas = ref.watch(fiestasDeLaBarraProvider);
    final puesta = ref.watch(puestaAlDiaBarraProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'BARRA · ${(app.operador?.nombre ?? '').toUpperCase()}',
          key: const Key('barra_titulo'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            key: const Key('barra_salir'),
            onPressed: () => ref.read(appRoleProvider.notifier).logoutApp(),
            child: const Text('SALIR'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          LineaSinInternetBarra(puesta: puesta),
          Expanded(
            child: fiestas.when(
              loading: () => const Center(child: CircularProgressIndicator(color: gold)),
              error: (_, _) => const Center(child: Text('No se pudieron leer las fiestas.')),
              data: (lista) => lista.isEmpty
                  ? const Center(
                      key: Key('barra_sin_fiestas'),
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ninguna fiesta tiene precios de barra todavía: los carga el jefe.',
                          textAlign: TextAlign.center,
                        ),
                      ),
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
                                key: Key('barra_fiesta_${e.id}'),
                                enabled: !_abriendo,
                                leading: const Icon(Icons.local_bar_outlined, color: gold),
                                title: Text(
                                  EventoPresentacion.tituloPrincipal(e),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(_fecha(e.fechaEvento)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _abrir(e),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}';
  }
}
