import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recepcion/services/lista_sin_internet.dart' show EstadoSinInternet;
import '../providers/barra_providers.dart';
import '../services/barra_sin_internet.dart';
import 'buscar_central.dart';
import 'central_barra_provider.dart';
import 'cliente_de_la_central.dart';

/// Cómo se ve una parte de la línea: bien, para mirar, o apagada.
enum TonoDeLaLinea { bien, atencion, quieto }

/// Lo que dice la línea de VENDER: **lo que espera subir a la nube** ("Todo subido", pedido
/// del 7-nov "para quedarnos tranquilos") y **la central de la barra**.
@immutable
class TextosDeLaCaja {
  final String subida;
  final TonoDeLaLinea tonoSubida;

  /// Null: este equipo no usa la central (o todavía no la buscó).
  final String? central;
  final TonoDeLaLinea tonoCentral;

  const TextosDeLaCaja({
    required this.subida,
    required this.tonoSubida,
    this.central,
    this.tonoCentral = TonoDeLaLinea.quieto,
  });

  static TextosDeLaCaja de(
    DatosSinInternetBarra d, {
    EstadoDeLaCentral? central,
    int cajas = 0,
    DateTime? desde,
    int porMandar = 0,
  }) {
    final p = d.porSubir;
    final (subida, tono) = switch ((d.hayInternet, p.vacio)) {
      (true, true) => (EstadoSinInternetBarra.todoSubido, TonoDeLaLinea.bien),
      (true, false) => ('${p.enPalabras} subiendo', TonoDeLaLinea.atencion),
      (false, true) => ('Sin internet · nada por subir', TonoDeLaLinea.quieto),
      (false, false) => ('Sin internet · ${p.enPalabras} por subir', TonoDeLaLinea.atencion),
    };
    final mandar = porMandar == 0 ? '' : ' · $porMandar por mandar';
    final (textoCentral, tonoCentral) = switch (central) {
      null || EstadoDeLaCentral.apagada => (null, TonoDeLaLinea.quieto),
      EstadoDeLaCentral.buscando => ('Buscando la central…$mandar', TonoDeLaLinea.quieto),
      EstadoDeLaCentral.conectada => (
          cajas <= 1 ? 'Central conectada' : 'Central · $cajas cajas',
          TonoDeLaLinea.bien,
        ),
      EstadoDeLaCentral.sinCentral => (
          '${desde == null ? 'Sin central' : 'Sin central desde las ${EstadoSinInternet.horaDe(desde)}'}$mandar',
          TonoDeLaLinea.atencion,
        ),
    };
    return TextosDeLaCaja(subida: subida, tonoSubida: tono, central: textoCentral, tonoCentral: tonoCentral);
  }
}

/// La línea de arriba de VENDER: lo que espera subir y la central. Tocar la parte de la
/// central abre cómo está, con la dirección para escribirla a mano.
class LineaDeLaCaja extends ConsumerWidget {
  const LineaDeLaCaja({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puesta = ref.watch(puestaAlDiaBarraProvider);
    final cliente = ref.watch(clienteDeLaBarraProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([puesta, ?cliente]),
      builder: (context, _) {
        final t = TextosDeLaCaja.de(
          puesta.datos,
          central: cliente?.estado,
          cajas: cliente?.cajas ?? 0,
          desde: cliente?.desde,
          porMandar: cliente?.porMandar ?? 0,
        );
        return LineaDeLaCajaVista(
          textos: t,
          alTocarLaCentral: cliente == null ? null : () => mostrarLaCentral(context, ref),
        );
      },
    );
  }
}

/// El dibujo de la línea, con los textos ya armados.
class LineaDeLaCajaVista extends StatelessWidget {
  final TextosDeLaCaja textos;
  final VoidCallback? alTocarLaCentral;

  const LineaDeLaCajaVista({super.key, required this.textos, this.alTocarLaCentral});

  @override
  Widget build(BuildContext context) {
    final t = textos;
        Color color(TonoDeLaLinea tono) => switch (tono) {
              TonoDeLaLinea.bien => const Color(0xFF59D38A),
              TonoDeLaLinea.atencion => const Color(0xFFF2B84B),
              TonoDeLaLinea.quieto => const Color(0xFFA7A29A),
            };
        // Las dos partes van en un Wrap: si no entran en un renglón (la tablet en vertical,
        // el celular), la central baja al segundo. Cortadas con "…" no se leía cuánto faltaba
        // mandar (recorrido del 7-nov).
        final subida = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              t.tonoSubida == TonoDeLaLinea.bien ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
              size: 16,
              color: color(t.tonoSubida),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                t.subida,
                key: const Key('caja_subida'),
                style: TextStyle(fontSize: 13, color: color(t.tonoSubida), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
        final central = t.central == null
            ? null
            : InkWell(
                key: const Key('caja_central'),
                onTap: alTocarLaCentral,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t.tonoCentral == TonoDeLaLinea.bien ? Icons.hub_outlined : Icons.wifi_find,
                      size: 16,
                      color: color(t.tonoCentral),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        t.central!,
                        key: const Key('caja_central_texto'),
                        style: TextStyle(fontSize: 13, color: color(t.tonoCentral), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 16,
              runSpacing: 2,
              children: [subida, ?central],
            ),
          ),
        );
  }
}

/// Cómo está la central, desde la caja: si se la encontró, desde cuándo no, y para
/// escribir a mano la dirección que muestra la notebook.
Future<void> mostrarLaCentral(BuildContext context, WidgetRef ref) async {
  final cliente = ref.read(clienteDeLaBarraProvider);
  if (cliente == null) return;
  final texto = TextEditingController(text: cliente.aMano?.texto ?? '');
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogo) => StatefulBuilder(
      builder: (dialogo, cambiar) => ListenableBuilder(
        listenable: cliente,
        builder: (dialogo, _) {
          final estado = switch (cliente.estado) {
            EstadoDeLaCentral.conectada =>
              'Conectada a la central (${cliente.donde?.texto ?? ''}). Lo que se vende en esta caja lo ven las demás, y al revés.',
            EstadoDeLaCentral.buscando =>
              'Buscando la central en el wifi del salón. Mientras tanto se vende igual: lo de esta caja se manda cuando la encuentre.',
            EstadoDeLaCentral.sinCentral =>
              'Sin central${cliente.desde == null ? '' : ' desde las ${EstadoSinInternet.horaDe(cliente.desde!)}'}. '
                  'Se vende igual; "Quedan" cuenta lo que esta caja sabe. Cuando vuelva, se manda lo de esta caja.',
            EstadoDeLaCentral.apagada => 'La central no se buscó todavía.',
          };
          return AlertDialog(
            title: const Text('La central de la barra'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(estado, key: const Key('central_estado')),
                  const SizedBox(height: 16),
                  const Text(
                    'Si no la encuentra sola, escribí la dirección que muestra la notebook de la barra:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('central_a_mano'),
                    controller: texto,
                    decoration: InputDecoration(
                      hintText: '192.168.0.10:8797',
                      errorText: error,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (cliente.aMano != null)
                TextButton(
                  key: const Key('central_buscar_sola'),
                  onPressed: () async {
                    await ref.read(clienteDeLaBarraProvider.notifier).ponerAMano(null);
                    texto.clear();
                    cambiar(() => error = null);
                  },
                  child: const Text('BUSCARLA SOLA'),
                ),
              TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('CERRAR')),
              FilledButton(
                key: const Key('central_conectar'),
                onPressed: () async {
                  final donde = DondeEstaLaCentral.deTexto(texto.text);
                  if (donde == null) {
                    cambiar(() => error = 'Así: 192.168.0.10:8797');
                    return;
                  }
                  await ref.read(clienteDeLaBarraProvider.notifier).ponerAMano(donde);
                  cambiar(() => error = null);
                },
                child: const Text('CONECTAR'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
