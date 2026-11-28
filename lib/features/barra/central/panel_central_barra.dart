import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../services/barra_sin_internet.dart';
import '../services/barras_del_salon.dart';
import 'central_barra.dart';
import 'central_barra_provider.dart';

/// La central de la barra en la notebook, arriba de CAJAS: prenderla, a qué dirección se
/// conectan las tablets, qué cajas están conectadas y **lo que cada una tiene sin subir**
/// ("al día" o "2 ventas por subir"), y lo de esta notebook ("Todo subido").
///
/// **De qué barra es esta notebook** (25-nov-2026: una notebook y una central por barra):
/// se elige antes de prenderla (Barra 1 · Barra 2, la última queda elegida) y la central
/// lo dice. Si ve a la central de la otra barra, **se enganchan solas** y el panel lo
/// dice; si no, "esta barra trabaja sola".
class PanelCentralDeLaBarra extends ConsumerStatefulWidget {
  final String eventoId;

  /// La fecha de la fiesta: esa noche la central vuelve sola después de un reinicio.
  final DateTime? fechaDeLaFiesta;

  /// **Sin el botón APAGAR** (27-nov-2026): en la vista simple de la notebook, a la vista de
  /// todos, la central prendida no se apaga con un clic ("la central debe estar prendida,
  /// si no todos se desconectan"). PRENDER sí queda, por si está apagada.
  final bool sinApagar;

  const PanelCentralDeLaBarra({
    super.key,
    required this.eventoId,
    this.fechaDeLaFiesta,
    this.sinApagar = false,
  });

  @override
  ConsumerState<PanelCentralDeLaBarra> createState() => _PanelCentralDeLaBarraState();
}

class _PanelCentralDeLaBarraState extends ConsumerState<PanelCentralDeLaBarra> {
  bool _prendiendo = false;

  /// La barra elegida para prenderla. Null hasta leer la recordada.
  String? _barra;

  @override
  void initState() {
    super.initState();
    // Si estaba prendida (se reinició la notebook), se vuelve a prender sola, con su barra.
    Future.microtask(() => ref
        .read(centralDeLaBarraProvider.notifier)
        .reanudar(widget.eventoId, fechaDeLaFiesta: widget.fechaDeLaFiesta));
    Future.microtask(() async {
      final recordada = await ref.read(barraDelEquipoProvider).leer();
      if (mounted && _barra == null) setState(() => _barra = recordada ?? kBarrasDelSalon.first);
    });
  }

  Future<void> _prender() async {
    setState(() => _prendiendo = true);
    await ref
        .read(centralDeLaBarraProvider.notifier)
        .prender(widget.eventoId, barra: _barra ?? kBarrasDelSalon.first);
    if (mounted) setState(() => _prendiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(centralDeLaBarraProvider);
    final deEstaFiesta = estado.prendida && estado.eventoId == widget.eventoId;
    const borde = Color(0xFF2A2830);
    final elegida = _barra ?? kBarrasDelSalon.first;
    return DecoratedBox(
      key: const Key('central_barra_panel'),
      decoration: BoxDecoration(
        color: const Color(0xFF17161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: deEstaFiesta ? const Color(0xFF2F6B4A) : borde),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: deEstaFiesta ? const Color(0xFF59D38A) : const Color(0xFFA7A29A),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      deEstaFiesta
                          ? 'CENTRAL PRENDIDA${estado.barra == null ? '' : ' · ${estado.barra!.toUpperCase()}'}'
                          : 'CENTRAL DE LA BARRA',
                      key: const Key('central_barra_titulo'),
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ],
                ),
                if (deEstaFiesta && !widget.sinApagar)
                  TextButton(
                    key: const Key('central_barra_apagar'),
                    onPressed: () => ref.read(centralDeLaBarraProvider.notifier).apagar(),
                    child: const Text('APAGAR'),
                  )
                else if (!deEstaFiesta)
                  FilledButton.icon(
                    key: const Key('central_barra_prender'),
                    onPressed: _prendiendo ? null : _prender,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('PRENDER LA CENTRAL'),
                    style: FilledButton.styleFrom(
                      backgroundColor: TemaBarra.dorado,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 44),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (estado.error != null && estado.eventoId == widget.eventoId)
              Text(estado.error!, style: const TextStyle(color: Color(0xFFFF8F82)))
            else if (!deEstaFiesta) ...[
              const Text(
                'Prendela en la notebook de cada barra la noche de la fiesta: las tablets de esa barra '
                'la encuentran solas por el wifi y se ven entre ellas, también sin internet. Si las dos '
                'notebooks se ven, se pasan todo solas.',
                style: TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Esta notebook es de la', style: TextStyle(fontSize: 13)),
                  for (final b in kBarrasDelSalon)
                    ChoiceChip(
                      key: Key('central_barra_de_${kBarrasDelSalon.indexOf(b) + 1}'),
                      label: Text(b),
                      selected: elegida == b,
                      onSelected: _prendiendo ? null : (_) => setState(() => _barra = b),
                    ),
                ],
              ),
            ] else ...[
              Text(
                estado.direccion == null
                    ? 'Esta notebook no está conectada a ningún wifi: conectala al router del salón.'
                    : 'Las tablets la encuentran solas. Si alguna no, que escriba ${estado.direccion}.',
                key: const Key('central_barra_direccion'),
                style: const TextStyle(fontSize: 13, color: Color(0xFFC9C4BA)),
              ),
              if (!estado.contestaBusqueda)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Esta notebook no puede contestarles a las tablets que la buscan: van a tener que '
                    'escribir la dirección.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFF2B84B)),
                  ),
                ),
              const SizedBox(height: 6),
              _OtraBarra(estado),
              const SizedBox(height: 10),
              if (estado.soloCajas.isEmpty)
                const Text(
                  'Todavía no se conectó ninguna caja.',
                  key: Key('central_barra_sin_cajas'),
                  style: TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
                )
              else
                for (final c in estado.soloCajas) _Caja(c),
              if (estado.rechazos.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Rechazos(estado.rechazos),
              ],
              const SizedBox(height: 6),
              const _EstaNotebook(),
            ],
          ],
        ),
      ),
    );
  }
}

/// El enganche con la central de la otra barra: "Enganchada con la Barra 2: se pasan
/// todo", o "Esta barra trabaja sola" si no la ve (cada router por su lado).
class _OtraBarra extends StatelessWidget {
  final EstadoCentralBarra estado;

  const _OtraBarra(this.estado);

  @override
  Widget build(BuildContext context) {
    final conectadas = [for (final o in estado.otras) if (o.conectada) o];
    final String texto;
    final Color color;
    if (conectadas.isNotEmpty) {
      final nombres = {for (final o in conectadas) o.barra ?? 'la otra barra'}.join(' y ');
      texto = 'Enganchada con la central de $nombres: se pasan todo, y la encargada ve las dos barras '
          'desde cualquier punta.';
      color = const Color(0xFF59D38A);
    } else if (estado.otras.isNotEmpty) {
      texto = 'Se cortó el enganche con la otra barra: cada una sigue sola y se juntan cuando se '
          'vuelvan a ver (o con internet).';
      color = const Color(0xFFF2B84B);
    } else {
      texto = 'No ve la central de otra barra: esta barra trabaja sola. Si las dos notebooks quedan en '
          'la misma red, se enganchan solas.';
      color = const Color(0xFFA7A29A);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          conectadas.isNotEmpty ? Icons.link : Icons.link_off,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            key: const Key('central_barra_otra'),
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }
}

/// Lo que la central **no guardó** de lo que le mandaron por el wifi: cuántas cosas y las
/// últimas, con la hora, quién y por qué (28-nov-2026). Sin plata: va también en la vista
/// simple de la notebook.
class _Rechazos extends StatelessWidget {
  final List<RechazoDeLaCentral> rechazos;

  const _Rechazos(this.rechazos);

  static String _hora(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    final l = d.toLocal();
    return '${dos(l.hour)}:${dos(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    const ambar = Color(0xFFF2B84B);
    final n = rechazos.length;
    final ultimos = rechazos.reversed.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.report_gmailerrorred_outlined, size: 16, color: ambar),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                n == 1
                    ? 'La central no aceptó una cosa que le mandaron: no se guardó ni se repartió.'
                    : 'La central no aceptó $n cosas que le mandaron: no se guardaron ni se repartieron.',
                key: const Key('central_barra_rechazos'),
                style: const TextStyle(fontSize: 13, color: ambar, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        for (var i = 0; i < ultimos.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              '${_hora(ultimos[i].cuando)} · ${ultimos[i].nombre}: ${ultimos[i].motivo}',
              key: Key('central_barra_rechazo_$i'),
              style: const TextStyle(fontSize: 13, color: Color(0xFFC9C4BA)),
            ),
          ),
        if (n > ultimos.length)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              'y ${n - ultimos.length} más de antes.',
              style: const TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
            ),
          ),
      ],
    );
  }
}

/// Una caja conectada: si está, y lo que tiene sin subir a la nube.
class _Caja extends StatelessWidget {
  final CajaConectada caja;

  const _Caja(this.caja);

  @override
  Widget build(BuildContext context) {
    final p = caja.porSubir;
    final (texto, color) = !caja.conectada
        ? ('desconectada', const Color(0xFFA7A29A))
        : p.vacio
            ? ('al día', const Color(0xFF59D38A))
            : ('${p.enPalabras} por subir', const Color(0xFFF2B84B));
    return Padding(
      key: Key('central_barra_caja_${caja.equipo}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.circle, size: 9, color: caja.conectada ? const Color(0xFF59D38A) : const Color(0xFF6B675F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              caja.barra == null ? caja.nombre : '${caja.nombre} · ${caja.barra}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(texto, key: Key('central_barra_caja_estado_${caja.equipo}'), style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Mientras hay internet y algo de esta notebook está subiendo, cada cuánto se vuelve a
/// contar. **No es el ciclo de 10 s que la 6.3.3 sacó del sync**: aquel le pedía 16 tablas a
/// la nube; esto cuenta la cola de subida de esta PC, en su base, y solo mientras queda algo
/// por subir (igual que VENDER, `PuestaAlDiaBarra.cadaCuenta`).
const kRecuentoDeLaNotebook = Duration(seconds: 10);

/// Lo de esta notebook que espera subir (lo que anuló el jefe acá): "Todo subido" o cuánto.
/// Se cuenta al abrir, cuando esta notebook escribe algo, cuando cambia la conexión y cuando
/// baja o llega algo; y cada [kRecuentoDeLaNotebook] solo mientras está subiendo (lo que
/// sube no avisa: sin eso la línea se quedaba en "1 cambio subiendo").
class _EstaNotebook extends ConsumerStatefulWidget {
  const _EstaNotebook();

  @override
  ConsumerState<_EstaNotebook> createState() => _EstaNotebookState();
}

class _EstaNotebookState extends ConsumerState<_EstaNotebook> {
  PendientesDeLaBarra _pendientes = PendientesDeLaBarra.nada;
  bool _hay = true;
  Timer? _otra;
  StreamSubscription<AppConnectivity>? _red;
  late final ValueNotifier<int> _escrituras;

  @override
  void initState() {
    super.initState();
    final conexion = ref.read(connectivityServiceProvider);
    _hay = conexion.currentStatus != AppConnectivity.offline;
    _red = conexion.stream.listen((estado) {
      if (!mounted) return;
      setState(() => _hay = estado != AppConnectivity.offline);
      unawaited(_contar());
    });
    _escrituras = ref.read(avisoALaRedProvider).escrituras..addListener(_alEscribir);
    unawaited(_contar());
  }

  void _alEscribir() => unawaited(_contar());

  Future<void> _contar() async {
    try {
      final p = await ref.read(barraDeLaRedProvider).pendientesDeLaBarra();
      if (mounted && p != _pendientes) setState(() => _pendientes = p);
    } catch (e) {
      debugPrint('La notebook no pudo contar lo suyo sin subir: $e');
    }
    if (!mounted) return;
    // Solo mientras sube: sin internet o sin nada pendiente, el número no cambia solo.
    if (_hay && !_pendientes.vacio) {
      _otra ??= Timer(kRecuentoDeLaNotebook, () {
        _otra = null;
        unawaited(_contar());
      });
    } else {
      _otra?.cancel();
      _otra = null;
    }
  }

  @override
  void dispose() {
    _otra?.cancel();
    _escrituras.removeListener(_alEscribir);
    unawaited(_red?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(operationalSyncRevisionProvider, (_, _) => unawaited(_contar()));
    final p = _pendientes;
    final texto = switch ((_hay, p.vacio)) {
      (true, true) => 'Esta notebook: ${EstadoSinInternetBarra.todoSubido}',
      (true, false) => 'Esta notebook: ${p.enPalabras} subiendo',
      (false, true) => 'Esta notebook: sin internet · nada por subir',
      (false, false) => 'Esta notebook: sin internet · ${p.enPalabras} por subir',
    };
    return Text(
      texto,
      key: const Key('central_barra_esta_notebook'),
      style: TextStyle(
        fontSize: 13,
        color: _hay && p.vacio ? const Color(0xFF59D38A) : const Color(0xFFC9C4BA),
      ),
    );
  }
}
