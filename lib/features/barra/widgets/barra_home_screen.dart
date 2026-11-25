import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/dia_de_la_fiesta.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../central/central_barra_provider.dart';
import '../cuentas/dia_de_operacion.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_providers.dart';
import '../services/barras_del_salon.dart';
import 'abrir_caja_barra_dialog.dart';
import 'barra_home_web.dart';
import 'elegir_impresora_screen.dart';
import 'las_cajas_screen.dart';
import 'linea_sin_internet_barra.dart';
import 'vender_screen.dart';

/// La pantalla de quien entró a la Barra con su PIN: elegir la fiesta y abrir (o
/// retomar) su caja de barra. No hay camino al panel ni a la caja de cuotas
/// (`test/modo_barra_cerrado_test.dart`).
///
/// **La Encargada de barra** (6.4.0) ve además LAS CAJAS en cada fiesta. Arriba, el
/// ícono de la impresora: se prueba antes de abrir la caja.
///
/// **En la web es [BarraHomeEnLaWeb]** (6.5.0): la encargada, desde un iPhone, ve LAS
/// CAJAS y anula; no vende ni imprime.
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
      final ahora = ref.read(relojDeLaBarraProvider)();
      // Una fiesta que ya pasó sigue solo para cerrar lo que quedó abierto: se retoma su
      // caja, sea de la noche que sea, y no se abren cajas nuevas. Si no, solo su caja de
      // esta noche (25-nov-2026): una de prueba de otro día que quedó abierta sigue
      // aparte, en su día, y esta noche se abre una nueva.
      final yaPaso = laFiestaYaPaso(fiesta, ahora);
      var caja = await barra.cajaAbierta(
        eventoId: fiesta.id,
        operadorId: op.id,
        desdeLaNoche: yaPaso ? null : DiaDeOperacion.de(ahora),
      );
      if (caja == null) {
        if (yaPaso) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              key: Key('barra_fiesta_pasada_sin_caja'),
              content: Text('Esta fiesta ya pasó: no se abren cajas nuevas. Siguen abiertas cajas de '
                  'esa noche: las cierra cada cajera desde su VENDER.'),
            ));
          }
          return;
        }
        final abiertas = abiertasDeEstaNoche(await barra.cajasAbiertas(fiesta.id), ahora);
        final recordada = await ref.read(barraDelEquipoProvider).leer();
        if (!mounted) return;
        final elegida = await pedirAbrirCajaBarra(
          context,
          fiesta: EventoPresentacion.tituloPrincipal(fiesta),
          abiertas: abiertas,
          barra: recordada,
        );
        if (elegida == null) return;
        unawaited(ref.read(barraDelEquipoProvider).guardar(elegida.sede));
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
        // Cerrada la caja de una fiesta que ya pasó, la fiesta se va de la lista
        // (revisión del 15-nov): se vuelve a mirar qué cajas siguen abiertas.
        if (mounted) {
          ref.invalidate(fiestasQueSiguenProvider);
          ref.invalidate(fiestasDeLaBarraProvider);
        }
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

  /// LAS CAJAS de la encargada. Antes de abrirla busca la central de la barra, por si
  /// entra directo acá sin haber pasado por VENDER (`arrancarSiNoHay`).
  void _abrirLasCajas(Evento fiesta) {
    final nombre = ref.read(appRoleProvider).operador?.nombre;
    unawaited(ref.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(
          eventoId: fiesta.id,
          nombre: nombre == null || nombre.isEmpty ? 'Encargada' : 'Encargada · $nombre',
        ));
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LasCajasScreen(fiesta: fiesta)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // En la web (el iPhone de la encargada, 6.5.0) no hay base del equipo, caja ni
    // impresora: va otra pantalla, antes de mirar nada de este equipo.
    if (ref.watch(enLaWebProvider)) return const BarraHomeEnLaWeb();

    const gold = Color(0xFFD4AF37);
    final app = ref.watch(appRoleProvider);
    final fiestas = ref.watch(fiestasDeLaBarraProvider);
    final siguen = ref.watch(fiestasQueSiguenProvider).value ?? const FiestasQueSiguen();
    final ahora = ref.watch(relojDeLaBarraProvider)();
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
          IconButton(
            key: const Key('barra_impresora'),
            tooltip: 'La impresora de este equipo: probarla o cambiarla',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ElegirImpresoraScreen(
                impresora: ref.read(impresoraDeLaBarraProvider),
                papel: ref.read(papelDeLaBarraProvider),
              ),
            )),
          ),
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
                                // Una fiesta que ya pasó sigue solo por la caja
                                // abierta de la cajera, o por cajas de su noche
                                // todavía abiertas (25-nov-2026): va al final y
                                // marcada (revisión del 15-nov), como en Entradas.
                                subtitle: laFiestaYaPaso(e, ahora)
                                    ? Text(
                                        siguen.conSuCaja.contains(e.id)
                                            ? '${_fecha(e.fechaEvento)} · Tu caja de barra sigue '
                                                'abierta: cerrala desde VENDER'
                                            : '${_fecha(e.fechaEvento)} · Siguen abiertas cajas de '
                                                'esa noche',
                                        key: Key('barra_caja_abierta_${e.id}'),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : Text(_fecha(e.fechaEvento)),
                                // Tocar la fiesta es VENDER (su caja); la encargada
                                // tiene además LAS CAJAS.
                                trailing: app.esEncargadaDeBarra
                                    ? OutlinedButton(
                                        key: Key('barra_las_cajas_${e.id}'),
                                        onPressed: () => _abrirLasCajas(e),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: gold,
                                          side: const BorderSide(color: gold),
                                        ),
                                        child: const Text(
                                          'LAS CAJAS',
                                          style: TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      )
                                    : const Icon(Icons.chevron_right),
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
