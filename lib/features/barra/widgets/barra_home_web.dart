import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../jefe/barra_jefe_providers.dart';
import '../providers/barra_providers.dart';
import '../services/fiestas_del_jefe.dart';
import 'las_cajas_screen.dart';

/// Lo que se le dice en la web a quien entró a la barra sin ser la encargada. No se
/// llega por la pantalla de entrada (`OpcionesDeEntrada.de(enLaWeb:)` lo frena antes):
/// es la segunda llave.
const kBarraEnLaWebSoloEncargada =
    'Desde el navegador entra solo la Encargada de barra. Para vender, usá la app.';

/// El inicio de la barra **en la web** (el iPhone de la Encargada de barra, 6.5.0): elige
/// la fiesta y ve LAS CAJAS, donde anula con motivo, a su nombre.
///
/// **No vende ni imprime**, y no hay "Todo subido": en el navegador no hay base del
/// equipo, caja ni Bluetooth. Lo que ve es lo que las tablets ya subieron a la nube
/// (`barraDelJefeProvider` es `BarraNube` en la web), así que hace falta internet en el
/// salón. Sin catálogo, sin precios y sin camino al panel
/// (`test/modo_barra_cerrado_test.dart`).
class BarraHomeEnLaWeb extends ConsumerWidget {
  const BarraHomeEnLaWeb({super.key});

  static const _oro = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
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
      body: app.esEncargadaDeBarra
          ? const _FiestasDeLaEncargada()
          : const _Aviso(
              clave: Key('barra_web_solo_encargada'),
              texto: kBarraEnLaWebSoloEncargada,
            ),
    );
  }
}

class _FiestasDeLaEncargada extends ConsumerWidget {
  const _FiestasDeLaEncargada();

  Future<void> _releer(WidgetRef ref) async {
    ref.invalidate(eventosDeLaBarraProvider);
    try {
      await ref.read(fiestasDelJefeProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiestas = ref.watch(fiestasDelJefeProvider);
    final hoy = ref.watch(relojDelJefeProvider)();
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;

    return fiestas.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: BarraHomeEnLaWeb._oro),
      ),
      error: (_, _) => _Aviso(
        clave: const Key('barra_web_sin_fiestas_error'),
        texto: 'No se pudieron leer las fiestas. Revisá internet y probá de nuevo.',
        boton: 'PROBAR DE NUEVO',
        alTocar: () => _releer(ref),
      ),
      data: (f) {
        if (f.vacia) {
          return _Aviso(
            clave: const Key('barra_sin_fiestas'),
            texto: 'No hay ninguna fiesta cargada todavía.',
            boton: 'VOLVER A MIRAR',
            alTocar: () => _releer(ref),
          );
        }
        final abre = f.laQueAbre?.id;
        Widget tarjeta(Evento e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: Key('barra_fiesta_${e.id}'),
                  leading: const Icon(Icons.local_bar_outlined, color: BarraHomeEnLaWeb._oro),
                  title: Text(
                    EventoPresentacion.tituloPrincipal(e),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    fechaConCuando(e.fechaEvento, hoy, esLaQueAbre: e.id == abre),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => LasCajasScreen(fiesta: e),
                  )),
                ),
              ),
            );
        Widget titulo(String texto) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Color(0xFFA7A29A),
                ),
              ),
            );
        return RefreshIndicator(
          color: BarraHomeEnLaWeb._oro,
          onRefresh: () => _releer(ref),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(margen),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      'Tocá una fiesta para ver LAS CAJAS. Se ve lo que cada caja ya subió: '
                      'hace falta internet en el salón. Para vender, la app.',
                      key: Key('barra_web_ayuda'),
                      style: TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
                    ),
                  ),
                  if (f.lasQueVienen.isNotEmpty) titulo('LAS QUE VIENEN'),
                  for (final e in f.lasQueVienen) tarjeta(e),
                  if (f.lasUltimas.isNotEmpty) titulo('LAS ÚLTIMAS'),
                  for (final e in f.lasUltimas) tarjeta(e),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  final Key clave;
  final String texto;
  final String? boton;
  final VoidCallback? alTocar;

  const _Aviso({required this.clave, required this.texto, this.boton, this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, key: clave, textAlign: TextAlign.center),
            if (boton != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: alTocar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BarraHomeEnLaWeb._oro,
                  side: const BorderSide(color: BarraHomeEnLaWeb._oro),
                ),
                child: Text(boton!, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
