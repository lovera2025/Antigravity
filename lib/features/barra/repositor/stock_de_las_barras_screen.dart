import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/aviso_al_anotar.dart';
import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../central/central_barra_provider.dart';
import '../central/cliente_de_la_central.dart';
import '../central/linea_de_la_caja.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../cuentas/stock_por_barra.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import 'dialogos_del_stock.dart';
import 'stock_de_la_fiesta.dart';
import 'texto_del_stock.dart';

const _verde = Color(0xFF59D38A);
const _ambar = Color(0xFFF2B84B);
const _rojo = Color(0xFFFF8F82);
const _gris = Color(0xFFA7A29A);

/// **STOCK**: lo que hay de cada producto en cada barra y en el depósito, esta noche
/// (decidido por el usuario con la maqueta del 25-nov-2026).
///
/// - **El repositor** (y el jefe) anota desde acá: REPONER, FALTANTE, ANOTAR LO QUE HAY,
///   ENTRÓ MERCADERÍA y VOY EN CAMINO. Solo se agregan renglones.
/// - **La encargada** la ve para mirar: no toca nada.
///
/// **No muestra plata**: cantidades, nada más. La cuenta es [StockPorBarra]
/// (`stockDeLaFiestaProvider`); la llave de lo que guarda, `ReglasDeLaBarra.mueveElStock`,
/// antes de abrir cada ventana y otra vez antes de guardar.
class StockDeLasBarrasScreen extends ConsumerStatefulWidget {
  final Evento fiesta;

  const StockDeLasBarrasScreen({super.key, required this.fiesta});

  @override
  ConsumerState<StockDeLasBarrasScreen> createState() => _StockDeLasBarrasScreenState();
}

class _StockDeLasBarrasScreenState extends ConsumerState<StockDeLasBarrasScreen> {
  /// El lugar que se mira: una barra o el depósito. Null: la primera barra.
  String? _lugar;
  bool _ocupado = false;
  ({String texto, bool error})? _dicho;

  /// Lo que ya estaba en aviso: suena solo cuando aparece algo nuevo.
  Set<String>? _yaEnAviso;

  String get _id => widget.fiesta.id;

  @override
  void initState() {
    super.initState();
    // Por si entra directo acá sin haber pasado por VENDER: busca la central de la barra,
    // así lo que anota les llega a las cajas al toque y sin internet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(enLaWebProvider)) return;
      final nombre = ref.read(appRoleProvider).operador?.nombre;
      final rol = ref.read(rolEnLaBarraProvider);
      final que = rol == RolEnLaBarra.repositor ? 'Repositor' : (rol == RolEnLaBarra.jefe ? 'Jefe' : 'Encargada');
      unawaited(ref.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(
            eventoId: _id,
            nombre: nombre == null || nombre.isEmpty ? que : '$que · $nombre',
          ));
    });
  }

  String get _quien => ref.read(appRoleProvider).operador?.nombre ?? 'Jefe';

  void _decir(String texto, {bool error = false}) {
    if (mounted) setState(() => _dicho = (texto: texto, error: error));
  }

  /// La llave: el stock lo anotan el repositor y el jefe.
  bool _frenaSinPermiso() {
    if (ReglasDeLaBarra.mueveElStock(ref.read(rolEnLaBarraProvider))) return false;
    _decir('El stock lo anota el repositor.', error: true);
    return true;
  }

  /// Abre la ventana, y guarda lo que devuelve. La llave antes de abrirla **y otra vez
  /// antes de guardar**: el permiso pudo cambiar con la ventana abierta.
  Future<void> _anotar(
    Future<MovimientoDeStock?> Function(StockDeLaFiesta datos) pedir,
    String Function(MovimientoDeStock m, StockDeLaFiesta datos) hecho,
  ) async {
    if (_ocupado || _frenaSinPermiso()) return;
    final datos = ref.read(stockDeLaFiestaProvider(_id)).value;
    if (datos == null) return;
    final m = await pedir(datos);
    if (m == null || !mounted) return;
    if (_frenaSinPermiso()) return;
    setState(() => _ocupado = true);
    // Lo de `ref` antes de esperar: la respuesta puede llegar con la pantalla cerrada.
    final subir = ref.read(subirDeLaBarraProvider);
    try {
      final guardado = await ref.read(barraDelJefeProvider).anotarMovimientoDeStock(m, quien: _quien);
      unawaited(subir('barra_stock_movimientos', guardado.id));
      if (mounted) ref.invalidate(stockDeLaFiestaProvider(_id));
      _decir(hecho(guardado, datos));
    } catch (e) {
      _decir(textoDelError(e, 'No se pudo guardar. Probá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  DateTime Function() get _ahora => ref.read(relojDeLaBarraProvider);

  Future<void> _reponer({String? productoId, String? barra}) => _anotar(
        (d) => pedirReposicion(context, datos: d, ahora: _ahora, productoId: productoId, barra: barra),
        (m, d) => 'Anotado: ${m.cantidad} ${d.nombreDe(m.productoId)} a ${elLugar(m.hacia ?? '')}.',
      );

  Future<void> _faltante() => _anotar(
        (d) => pedirFaltante(context, datos: d, ahora: _ahora, lugar: _lugar),
        (m, d) => 'Anotado: ${m.cantidad == 1 ? 'falta 1' : 'faltan ${m.cantidad}'} '
            '${d.nombreDe(m.productoId)} en ${elLugar(m.desde ?? '')}.',
      );

  Future<void> _contar(String lugar) => _anotar(
        (d) => pedirConteo(context, datos: d, ahora: _ahora, lugar: lugar),
        (m, d) => 'Anotado: hay ${m.contadas} ${d.nombreDe(m.productoId)} en ${elLugar(lugar)}.',
      );

  Future<void> _entrada() => _anotar(
        (d) => pedirEntrada(context, datos: d, ahora: _ahora),
        (m, d) => 'Anotado: ${m.cantidad == 1 ? 'entró 1' : 'entraron ${m.cantidad}'} '
            '${d.nombreDe(m.productoId)} al depósito.',
      );

  /// VOY EN CAMINO a esa barra con ese producto: las cajeras de esa barra lo ven.
  Future<void> _voyEnCamino(StockDeUnLugar s, StockDeLaFiesta datos) async {
    if (_ocupado || _frenaSinPermiso()) return;
    setState(() => _ocupado = true);
    final subir = ref.read(subirDeLaBarraProvider);
    try {
      final aviso = await ref.read(barraDelJefeProvider).avisarQueVa(
            eventoId: _id,
            productoId: s.productoId,
            barra: s.lugar,
            quien: _quien,
          );
      unawaited(subir('barra_stock_movimientos', aviso.id));
      if (mounted) ref.invalidate(stockDeLaFiestaProvider(_id));
      _decir('Avisado a la ${s.lugar}: vas en camino con ${datos.nombreDe(s.productoId)}.');
    } catch (e) {
      _decir(textoDelError(e, 'No se pudo avisar. Probá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// YA NO VOY: saca el aviso (no hay en el depósito, o lo repuso otro).
  Future<void> _yaNoVoy(EnCamino e, StockDeLaFiesta datos) => _anotar(
        (d) async => MovimientoDeStock.yaNoVoy(aviso: e.aviso, ahora: _ahora()),
        (m, d) => 'Se sacó el aviso a la ${e.barra}.',
      );

  void _verMovimientos(StockDeLaFiesta datos) {
    showDialog<void>(
      context: context,
      builder: (_) => _Movimientos(datos: datos),
    );
  }

  /// Suena cuando aparece algo nuevo en "sin stock" o "está quedando poco".
  void _sonarSiHayAlgoNuevo(StockDeLaFiesta datos) {
    final ahora = {for (final s in datos.stock.enAviso()) '${s.lugar}|${s.productoId}'};
    final antes = _yaEnAviso;
    _yaEnAviso = ahora;
    if (antes != null && ahora.difference(antes).isNotEmpty) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = temaDeVender(DisenioBarra.nocheDorada, base: Theme.of(context));
    return Theme(data: tema, child: Builder(builder: _pantalla));
  }

  Widget _pantalla(BuildContext context) {
    final rol = ref.watch(rolEnLaBarraProvider);
    final anota = ReglasDeLaBarra.mueveElStock(rol);
    final stock = ref.watch(stockDeLaFiestaProvider(_id));
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
    final cliente = ref.watch(enLaWebProvider) ? null : ref.watch(clienteDeLaBarraProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'STOCK',
              key: Key('stock_titulo'),
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
            Text(
              EventoPresentacion.tituloPrincipal(widget.fiesta),
              style: const TextStyle(fontSize: 12, color: _gris),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cliente != null) const LineaDeLaCaja(),
              Expanded(
                child: stock.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(child: Text('No se pudo leer el stock. Volvé a entrar.')),
                  data: (datos) {
                    _sonarSiHayAlgoNuevo(datos);
                    return _cuerpo(datos, anota: anota, margen: margen, cliente: cliente);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo(
    StockDeLaFiesta datos, {
    required bool anota,
    required double margen,
    required ClienteDeLaCentral? cliente,
  }) {
    final hora = TimeOfDay.fromDateTime(datos.leidoEl.toLocal());
    final alDia = '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
    // Sin señal: este aparato buscó la central y no la tiene. Se sigue trabajando igual.
    final sinSenal = cliente != null && cliente.estado != EstadoDeLaCentral.conectada;
    if (!datos.stock.hayReparto) {
      return ListView(
        padding: EdgeInsets.all(margen),
        children: [
          const Text(
            'El jefe todavía no repartió el stock de esta fiesta entre las barras.',
            key: Key('stock_sin_reparto'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Lo hace en BARRA → PRECIOS → STOCK POR BARRA: carga el stock general y con cuánto '
            'arranca cada barra. Lo demás queda en el depósito.',
            style: TextStyle(color: _gris),
          ),
          if (datos.stock.faltaElStockGeneral.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Hay productos repartidos sin el stock general cargado: '
                '${datos.stock.faltaElStockGeneral.map(datos.nombreDe).join(', ')}.',
                style: const TextStyle(color: _ambar),
              ),
            ),
        ],
      );
    }
    final barras = datos.barras;
    final lugar = _lugar != null && ([...barras, kDeposito].contains(_lugar)) ? _lugar! : barras.first;
    final enAviso = datos.stock.enAviso();
    final sin = [for (final s in enAviso) if (s.sinStock) s];
    final poco = [for (final s in enAviso) if (!s.sinStock) s];
    final filas = datos.en(lugar);
    final dicho = _dicho;
    return ListView(
      key: const Key('stock_lista'),
      padding: EdgeInsets.fromLTRB(margen, 8, margen, 24),
      children: [
        Text(
          sinSenal
              ? 'Sin señal: seguí trabajando, se manda solo al acercarte a la barra. Lo que ves está al '
                  'día hasta las $alDia.'
              : 'Al día hasta las $alDia.',
          key: const Key('stock_al_dia'),
          style: TextStyle(fontSize: 12.5, color: sinSenal ? _ambar : _gris),
        ),
        if (!anota)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Solo para mirar: lo anota el repositor.',
              key: Key('stock_solo_mirar'),
              style: TextStyle(fontSize: 13, color: _gris),
            ),
          ),
        if (dicho != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              dicho.texto,
              key: const Key('stock_dicho'),
              style: TextStyle(color: dicho.error ? _rojo : _verde, fontWeight: FontWeight.w700),
            ),
          ),
        if (sin.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Sin stock: no se puede vender',
            key: Key('stock_sin_stock_titulo'),
            style: TextStyle(color: _rojo, fontWeight: FontWeight.w800),
          ),
          for (final s in sin) _alerta(s, datos, anota: anota),
        ],
        if (poco.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Está quedando poco',
            key: Key('stock_poco_titulo'),
            style: TextStyle(color: _ambar, fontWeight: FontWeight.w800),
          ),
          for (final s in poco) _alerta(s, datos, anota: anota),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in [...barras, kDeposito])
              ChoiceChip(
                key: Key('stock_lugar_${l == kDeposito ? 'deposito' : barras.indexOf(l) + 1}'),
                label: Text(nombreDelLugar(l).toUpperCase(), style: const TextStyle(letterSpacing: 1)),
                selected: l == lugar,
                onSelected: (_) => setState(() => _lugar = l),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (filas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Acá el jefe no repartió ningún producto.', style: TextStyle(color: _gris)),
          ),
        for (final s in filas) _fila(s, datos),
        const SizedBox(height: 14),
        if (anota)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('stock_reponer'),
                onPressed: _ocupado ? null : () => _reponer(barra: lugar == kDeposito ? null : lugar),
                icon: const Icon(Icons.add),
                label: const Text('REPONER'),
                style: FilledButton.styleFrom(backgroundColor: TemaBarra.dorado, foregroundColor: Colors.black),
              ),
              OutlinedButton.icon(
                key: const Key('stock_faltante'),
                onPressed: _ocupado ? null : _faltante,
                icon: const Icon(Icons.remove),
                label: const Text('FALTANTE'),
              ),
              OutlinedButton.icon(
                key: const Key('stock_contar'),
                onPressed: _ocupado ? null : () => _contar(lugar),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('ANOTAR LO QUE HAY'),
              ),
              if (lugar == kDeposito)
                OutlinedButton.icon(
                  key: const Key('stock_entrada'),
                  onPressed: _ocupado ? null : _entrada,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('ENTRÓ MERCADERÍA'),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('stock_movimientos'),
            onPressed: () => _verMovimientos(datos),
            icon: const Icon(Icons.history),
            label: const Text('VER LOS MOVIMIENTOS'),
          ),
        ),
      ],
    );
  }

  /// Un renglón de "sin stock" o "está quedando poco": qué, dónde, y lo que se puede hacer.
  Widget _alerta(StockDeUnLugar s, StockDeLaFiesta datos, {required bool anota}) {
    final enCamino = datos.stock.enCaminoDe(s.lugar, s.productoId);
    final clave = '${s.productoId}_${datos.barras.indexOf(s.lugar) + 1}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${datos.nombreDe(s.productoId)} · ${s.lugar}'
            '${s.queda > 0 ? ' · ${s.queda == 1 ? 'queda 1' : 'quedan ${s.queda}'}' : ''}'
            '${s.queda < 0 ? ' · se ${s.queda == -1 ? 'vendió 1' : 'vendieron ${-s.queda}'} de más' : ''}',
            key: Key('stock_alerta_$clave'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (enCamino != null)
            Text(
              'EN CAMINO${enCamino.quien == null ? '' : ' · ${enCamino.quien}'}',
              key: Key('stock_en_camino_$clave'),
              style: const TextStyle(color: _verde, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          if (anota && s.sinStock && enCamino == null)
            OutlinedButton(
              key: Key('stock_voy_$clave'),
              onPressed: _ocupado ? null : () => _voyEnCamino(s, datos),
              child: const Text('VOY EN CAMINO'),
            ),
          if (anota && enCamino != null)
            TextButton(
              key: Key('stock_ya_no_voy_$clave'),
              onPressed: _ocupado ? null : () => _yaNoVoy(enCamino, datos),
              child: const Text('YA NO VOY'),
            ),
          if (anota)
            FilledButton.tonal(
              key: Key('stock_reponer_$clave'),
              onPressed: _ocupado ? null : () => _reponer(productoId: s.productoId, barra: s.lugar),
              child: const Text('REPONER'),
            ),
        ],
      ),
    );
  }

  Widget _fila(StockDeUnLugar s, StockDeLaFiesta datos) {
    final color = s.sinStock ? _rojo : (s.enAviso ? _ambar : _verde);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        key: Key('stock_fila_${s.productoId}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En un celular angosto, "SIN STOCK · se vendieron 5 de más" no entra al lado del
          // nombre: baja al renglón siguiente en vez de salirse (28-nov-2026).
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  datos.nombreDe(s.productoId),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  cuantoQueda(s),
                  key: Key('stock_queda_${s.productoId}'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Text(
            detalleDelStock(s),
            key: Key('stock_detalle_${s.productoId}'),
            style: const TextStyle(fontSize: 12.5, color: _gris),
          ),
          const Divider(height: 14),
        ],
      ),
    );
  }
}

/// Los movimientos de la noche, del más nuevo al más viejo. Solo se agregan renglones:
/// para corregir, se anota otro.
class _Movimientos extends StatelessWidget {
  const _Movimientos({required this.datos});

  final StockDeLaFiesta datos;

  static String _hora(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lista = [for (final m in datos.movimientos) if (m.tipo != null) m];
    return AlertDialog(
      title: const Text('MOVIMIENTOS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
      content: SizedBox(
        width: 520,
        child: lista.isEmpty
            ? const Text('Todavía no se anotó ningún movimiento.', key: Key('movimientos_vacio'))
            : ListView.separated(
                key: const Key('movimientos_lista'),
                shrinkWrap: true,
                itemCount: lista.length,
                separatorBuilder: (_, _) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final m = lista[i];
                  final nota = notaDelMovimiento(m);
                  final cuanto = cuantoDelMovimiento(m);
                  return Column(
                    key: Key('movimiento_$i'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_hora(m.createdAt)} · ${queDelMovimiento(m, datos.nombreDe(m.productoId))}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (cuanto.isNotEmpty)
                            Text(
                              cuanto,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cuanto.startsWith('−') ? _rojo : _verde,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        [?nota, m.hechoPor ?? ''].where((x) => x.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: _gris),
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Text('Para corregir, se anota otro movimiento.', style: TextStyle(fontSize: 12, color: _gris)),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
      ],
    );
  }
}
