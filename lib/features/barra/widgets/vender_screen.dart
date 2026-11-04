import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/cobro_barra.dart';
import '../cuentas/cuenta_barra.dart';
import '../cuentas/pesos.dart';
import '../cuentas/stock_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/impresora_bluetooth.dart';
import '../providers/barra_providers.dart';
import '../services/productos_para_vender.dart';
import 'cobrar_hoja.dart';
import 'elegir_impresora_screen.dart';
import 'elegir_vales.dart';
import 'pesos_enteros_formatter.dart';

/// VENDER: se tocan los productos y se arma la cuenta; debajo del total, **EFECTIVO,
/// TRANSFERENCIA y MIXTO** abren su cobro (pedido del 3-nov: sin un COBRAR que después
/// pregunte el medio). Al confirmar se guarda la venta (antes de imprimir: sin
/// impresora, igual queda), sube si hay internet y siguen los vales.
///
/// **Se adapta al ancho** (`CortesPantalla`): en el celular los productos arriba y la
/// cuenta abajo, con el total y los tres botones siempre a la vista; en la tablet y la
/// PC, lado a lado.
class VenderScreen extends ConsumerStatefulWidget {
  final Evento fiesta;
  final CajaBarra caja;

  const VenderScreen({super.key, required this.fiesta, required this.caja});

  @override
  ConsumerState<VenderScreen> createState() => _VenderScreenState();
}

class _VenderScreenState extends ConsumerState<VenderScreen> with WidgetsBindingObserver {
  List<ProductoEnVenta> _productos = const [];
  Map<String, StockDeProducto> _stock = const {};
  bool _cargando = true;
  CuentaBarra _cuenta = CuentaBarra.vacia;
  late CajaBarra _caja = widget.caja;
  final _buscador = TextEditingController();
  String _busqueda = '';
  String? _categoria;
  EstadoImpresora? _impresora;
  bool _cobrando = false;

  /// En el celular, si la cuenta está desplegada.
  bool _cuentaAbierta = false;

  /// Los productos sin stock que la cajera dijo que se venden igual, en esta cuenta.
  final _sinStockIgual = <String>{};

  String get _fiesta => EventoPresentacion.tituloPrincipal(widget.fiesta);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_cargar());
    unawaited(_prepararImpresora());
    // Cuando bajan ventas de las otras cajas, "Quedan" se pone al día solo.
    ref.listenManual(operationalSyncRevisionProvider, (_, _) => unawaited(_cargar()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _buscador.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_prepararImpresora());
  }

  Future<void> _cargar() async {
    final barra = ref.read(barraDeLaCajaProvider);
    final productos = await barra.productos();
    final precios = await barra.precios(widget.fiesta.id);
    // El stock es general: lo descuentan todas las cajas de la fiesta, no solo esta.
    final ventas = await barra.ventas(widget.fiesta.id);
    final anulaciones = await barra.anulaciones(widget.fiesta.id);
    if (!mounted) return;
    setState(() {
      _productos = productosParaVender(productos, precios, eventoId: widget.fiesta.id);
      _stock = StockDeLaBarra.de(
        eventoId: widget.fiesta.id,
        precios: precios,
        ventas: ventas,
        anulaciones: anulaciones,
      );
      _cargando = false;
    });
  }

  Future<void> _prepararImpresora() async {
    final estado = await ref.read(papelDeLaBarraProvider).preparar();
    if (mounted) setState(() => _impresora = estado);
  }

  /// Lo que queda de un producto: lo cargado por el jefe, menos lo vendido por todas
  /// las cajas y lo que ya está en esta cuenta. Null: no se controla.
  int? _quedan(String productoId) {
    final s = _stock[productoId];
    if (s == null || !s.controla) return null;
    return s.queda! - _cuenta.cantidadDe(productoId);
  }

  /// Suma uno. Sin stock, pregunta antes (una vez por producto y por cuenta): el
  /// stock avisa, pero lo cargado puede estar corto o sin internet otra caja ya vendió.
  Future<void> _sumar(ProductoEnVenta p) async {
    final q = _quedan(p.id);
    if (q != null && q <= 0 && !_sinStockIgual.contains(p.id)) {
      final igual = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('sin_stock'),
          title: Text('No queda ${p.nombre.toLowerCase()}'),
          content: const Text(
            'Según lo que cargó el jefe ya se vendieron todos. Si hay, se puede vender igual.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO')),
            FilledButton(
              key: const Key('sin_stock_vender_igual'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('VENDER IGUAL'),
            ),
          ],
        ),
      );
      if (igual != true || !mounted) return;
      _sinStockIgual.add(p.id);
    }
    setState(() {
      _cuenta = _cuenta.sumar(productoId: p.id, nombre: p.nombre, precio: p.precio.precio);
    });
  }

  void _vaciar() => setState(() {
        _cuenta = CuentaBarra.vacia;
        _cuentaAbierta = false;
        _sinStockIgual.clear();
      });

  Future<void> _cobrar(MedioBarra medio) async {
    if (_cuenta.estaVacia || _cobrando) return;
    setState(() => _cobrando = true);
    try {
      final recordado = await ref.read(recargoRecordadoProvider).leer();
      if (!mounted) return;
      final cobro = await pedirCobro(
        context,
        total: _cuenta.total,
        medio: medio,
        recargoPrendido: recordado.prendido,
        recargoPct: recordado.pct,
      );
      if (cobro == null || !mounted) return;
      if (medio != MedioBarra.efectivo) {
        await ref
            .read(recargoRecordadoProvider)
            .guardar(prendido: cobro.recargoPrendido, pct: cobro.recargoPct);
      }
      await _guardar(cobro);
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _guardar(CobroBarra cobro) async {
    final VentaBarra venta;
    try {
      venta = await ref.read(barraDeLaCajaProvider).vender(
            caja: _caja,
            renglones: _cuenta.renglones,
            medio: cobro.medio,
            efectivo: cobro.efectivo,
            transferencia: cobro.transfiere,
            recibe: cobro.recibeQueCuenta,
            recargo: cobro.recargo,
            recargoPct: cobro.recargoPctQueQueda,
            quien: ref.read(appRoleProvider).operador?.nombre ?? _caja.operadorNombre ?? 'Barra',
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se guardó la venta. Probá de nuevo.')),
        );
      }
      return;
    }
    unawaited(ref.read(subirVentaProvider)(venta));
    if (!mounted) return;
    _vaciar();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ValesDeLaVenta(venta: venta, caja: _caja, fiesta: _fiesta),
    ));
    if (mounted) unawaited(_cargar());
  }

  Future<void> _ponerCambio() async {
    final monto = await showDialog<int>(
      context: context,
      builder: (_) => _CambioDialog(cambio: _caja.cambioInicial),
    );
    if (monto == null || !mounted) return;
    try {
      final caja = await ref.read(barraDeLaCajaProvider).ponerCambio(
            _caja,
            monto.toDouble(),
            quien: ref.read(appRoleProvider).operador?.nombre ?? 'Barra',
          );
      if (mounted) setState(() => _caja = caja);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se guardó el cambio. Probá de nuevo.')),
        );
      }
    }
  }

  Future<void> _elegirImpresora() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ElegirImpresoraScreen(impresora: ref.read(impresoraDeLaBarraProvider)),
    ));
    if (mounted) unawaited(_prepararImpresora());
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final celular = CortesPantalla.esCelular(ancho);
    final pc = CortesPantalla.esPc(ancho);
    final nombre = _caja.operadorNombre;
    final impresoraLista = _impresora == EstadoImpresora.lista;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caja ${_caja.numeroCaja}${nombre == null ? '' : ' · $nombre'}',
              key: const Key('vender_titulo'),
              overflow: TextOverflow.ellipsis,
            ),
            Text(_fiesta, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('vender_cambio'),
            tooltip: _caja.cambioInicial > 0
                ? 'Cambio inicial: ${pesos(_caja.cambioInicial)}'
                : 'Poner el cambio inicial',
            onPressed: _ponerCambio,
            icon: Badge(
              isLabelVisible: _caja.cambioInicial > 0,
              smallSize: 8,
              child: const Icon(Icons.savings_outlined),
            ),
          ),
          IconButton(
            key: const Key('vender_impresora'),
            tooltip: impresoraLista ? 'Impresora conectada' : 'Elegir o conectar la impresora',
            onPressed: _elegirImpresora,
            icon: Icon(
              impresoraLista ? Icons.print : Icons.print_disabled_outlined,
              color: impresoraLista ? Colors.green.shade600 : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : celular
              ? Column(
                  children: [
                    _filtros(),
                    Expanded(child: _grilla(2)),
                    _cuentaCelular(),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        children: [_filtros(), Expanded(child: _grilla(pc ? 4 : 3))],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(width: pc ? 420 : ancho * 0.4, child: _cuentaCompleta()),
                  ],
                ),
    );
  }

  Widget _filtros() {
    final categorias = categoriasDe(_productos);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          TextField(
            key: const Key('vender_buscar'),
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar un producto',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar la búsqueda',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _buscador.clear();
                        _busqueda = '';
                      }),
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (t) => setState(() => _busqueda = t),
          ),
          if (categorias.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in [null, ...categorias])
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: ChoiceChip(
                        key: Key('vender_categoria_${c ?? 'todo'}'),
                        label: Text(c ?? 'Todo'),
                        selected: _categoria == c,
                        onSelected: (_) => setState(() => _categoria = c),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _grilla(int columnas) {
    final lista = filtrarProductos(_productos, busqueda: _busqueda, categoria: _categoria);
    if (_productos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Esta fiesta no tiene productos con precio.', textAlign: TextAlign.center),
        ),
      );
    }
    if (lista.isEmpty) {
      return Center(
        key: const Key('vender_sin_resultados'),
        child: Text(_busqueda.trim().isEmpty
            ? 'No hay productos en esta categoría.'
            : 'Ningún producto con "${_busqueda.trim()}".'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      // Alto fijo: con la tablet o el celular acostados, una proporción dejaba la
      // tarjeta más baja que su nombre y su precio.
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnas,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 150,
      ),
      itemCount: lista.length,
      itemBuilder: (_, i) => _tarjeta(lista[i]),
    );
  }

  Widget _tarjeta(ProductoEnVenta p) {
    final tema = Theme.of(context);
    final cantidad = _cuenta.cantidadDe(p.id);
    final aviso = _stock[p.id]?.aviso;
    final quedan = _quedan(p.id);
    final sinStock = quedan != null && quedan <= 0;
    final enAviso = quedan != null && (sinStock || (aviso != null && quedan <= aviso));
    return Opacity(
      opacity: sinStock && cantidad == 0 ? 0.55 : 1,
      child: Card(
        key: Key('producto_${p.id}'),
        clipBehavior: Clip.antiAlias,
        color: cantidad > 0 ? tema.colorScheme.primaryContainer : null,
        child: InkWell(
          onTap: () => _sumar(p),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El nombre usa lo que queda: el precio, el stock y el + / − siempre se ven.
                Expanded(
                  child: Text(
                    p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(pesos(p.precio.precio), style: const TextStyle(fontSize: 16)),
                if (quedan != null)
                  Text(
                    sinStock
                        ? (cantidad > 0 ? 'Sin stock' : 'Agotado')
                        : 'Quedan $quedan',
                    key: Key('stock_${p.id}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: enAviso ? tema.colorScheme.error : tema.hintColor,
                      fontWeight: enAviso ? FontWeight.bold : null,
                    ),
                  ),
                if (cantidad > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _BotonDeTarjeta(
                          key: Key('tarjeta_restar_${p.id}'),
                          icono: Icons.remove,
                          alTocar: () => setState(() => _cuenta = _cuenta.restar(p.id)),
                        ),
                        Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        _BotonDeTarjeta(
                          key: Key('tarjeta_sumar_${p.id}'),
                          icono: Icons.add,
                          alTocar: () => _sumar(p),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renglon(RenglonVenta r) => ListTile(
        key: Key('renglon_${r.productoId}'),
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        title: Text('${r.cantidad} x ${r.nombre}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(pesos(r.subtotal)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('restar_${r.productoId}'),
              tooltip: 'Uno menos',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(() => _cuenta = _cuenta.restar(r.productoId)),
            ),
            IconButton(
              key: Key('sumar_${r.productoId}'),
              tooltip: 'Uno más',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                // Por el mismo camino que la tarjeta: sin stock, pregunta.
                final p = _productos.where((x) => x.id == r.productoId).firstOrNull;
                if (p != null) {
                  unawaited(_sumar(p));
                } else {
                  setState(() {
                    _cuenta = _cuenta.sumar(productoId: r.productoId, nombre: r.nombre, precio: r.precio);
                  });
                }
              },
            ),
            IconButton(
              key: Key('quitar_${r.productoId}'),
              tooltip: 'Sacarlo de la cuenta',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _cuenta = _cuenta.quitar(r.productoId)),
            ),
          ],
        ),
      );

  Widget _total() => Row(
        children: [
          const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  pesos(_cuenta.total),
                  key: const Key('vender_total'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _botonesPago() {
    final puede = !_cuenta.estaVacia && !_cobrando;
    Widget boton(MedioBarra medio, String texto, IconData icono, {bool principal = false}) {
      final hijo = FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 18),
            const SizedBox(width: 6),
            Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
      final estilo = ButtonStyle(
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 14)),
      );
      return Expanded(
        child: principal
            ? FilledButton(
                key: Key('pagar_${medio.name}'),
                style: estilo,
                onPressed: puede ? () => _cobrar(medio) : null,
                child: hijo,
              )
            : FilledButton.tonal(
                key: Key('pagar_${medio.name}'),
                style: estilo,
                onPressed: puede ? () => _cobrar(medio) : null,
                child: hijo,
              ),
      );
    }

    return Row(
      children: [
        boton(MedioBarra.efectivo, 'EFECTIVO', Icons.payments_outlined, principal: true),
        const SizedBox(width: 6),
        boton(MedioBarra.transferencia, 'TRANSFERENCIA', Icons.qr_code_2),
        const SizedBox(width: 6),
        boton(MedioBarra.mixto, 'MIXTO', Icons.call_split),
      ],
    );
  }

  /// Tablet y PC: la cuenta entera, al costado.
  Widget _cuentaCompleta() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('La cuenta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  key: const Key('vender_vaciar'),
                  onPressed: _cuenta.estaVacia ? null : _vaciar,
                  child: const Text('VACIAR'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _cuenta.estaVacia
                ? const Center(child: Text('Tocá un producto para sumarlo.'))
                : ListView(children: [for (final r in _cuenta.renglones) _renglon(r)]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [_total(), const SizedBox(height: 10), _botonesPago()]),
          ),
        ],
      );

  /// Celular: el total y los tres botones siempre a la vista; los renglones se
  /// despliegan tocando el total.
  Widget _cuentaCelular() {
    final alto = MediaQuery.sizeOf(context).height;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_cuentaAbierta && !_cuenta.estaVacia) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: alto * 0.35),
                  child: ListView(
                    shrinkWrap: true,
                    children: [for (final r in _cuenta.renglones) _renglon(r)],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('vender_vaciar'),
                    onPressed: _vaciar,
                    child: const Text('VACIAR'),
                  ),
                ),
              ],
              InkWell(
                key: const Key('vender_ver_cuenta'),
                onTap: _cuenta.estaVacia ? null : () => setState(() => _cuentaAbierta = !_cuentaAbierta),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(_cuentaAbierta ? Icons.expand_more : Icons.expand_less),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _cuenta.estaVacia
                              ? 'La cuenta está vacía'
                              : '${_cuenta.unidades} ${_cuenta.unidades == 1 ? 'producto' : 'productos'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            pesos(_cuenta.total),
                            key: const Key('vender_total'),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _botonesPago(),
            ],
          ),
        ),
      ),
    );
  }
}

/// El + y el − de la tarjeta de un producto.
class _BotonDeTarjeta extends StatelessWidget {
  final IconData icono;
  final VoidCallback alTocar;

  const _BotonDeTarjeta({super.key, required this.icono, required this.alTocar});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: alTocar,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icono, size: 18, color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
      );
}

/// El cambio con que arrancó la caja. El diálogo es dueño de su casilla: si la
/// cerrara quien lo abre, se cerraría antes de que el diálogo termine de irse.
class _CambioDialog extends StatefulWidget {
  final double cambio;

  const _CambioDialog({required this.cambio});

  @override
  State<_CambioDialog> createState() => _CambioDialogState();
}

class _CambioDialogState extends State<_CambioDialog> {
  late final _ctrl = TextEditingController(
    text: widget.cambio > 0 ? PesosEnterosFormatter.escribir(widget.cambio) : '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cambio inicial'),
        content: TextField(
          key: const Key('cambio_monto'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [PesosEnterosFormatter()],
          decoration: const InputDecoration(
            prefixText: r'$ ',
            helperText: 'Con cuánto arrancó la caja, si arrancó con algo',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          FilledButton(
            key: const Key('cambio_guardar'),
            onPressed: () => Navigator.pop(context, PesosEnterosFormatter.leer(_ctrl.text) ?? 0),
            child: const Text('GUARDAR'),
          ),
        ],
      );
}

/// Después de cobrar: la venta guardada, el vuelto, y los vales (`ElegirVales`).
class _ValesDeLaVenta extends ConsumerStatefulWidget {
  final VentaBarra venta;
  final CajaBarra caja;
  final String fiesta;

  const _ValesDeLaVenta({required this.venta, required this.caja, required this.fiesta});

  @override
  ConsumerState<_ValesDeLaVenta> createState() => _ValesDeLaVentaState();
}

class _ValesDeLaVentaState extends ConsumerState<_ValesDeLaVenta> {
  bool _todoImpreso = false;

  Future<void> _listo() async {
    if (!_todoImpreso) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('Quedan bebidas sin vale. ¿Volver a vender igual?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO, IMPRIMIR')),
            FilledButton(
              key: const Key('vales_salir_igual'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SÍ, VOLVER'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final papel = ref.read(papelDeLaBarraProvider);
    final numero = v.numero.toString().padLeft(4, '0');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) unawaited(_listo());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Vales · N° $numero'),
          actions: [
            TextButton(
              key: const Key('vales_listo'),
              onPressed: _listo,
              child: const Text('LISTO, OTRA VENTA'),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Card(
                  key: const Key('vales_venta_guardada'),
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Venta guardada: ${pesos(v.cobrado)}')),
                        if (v.vuelto > 0)
                          Text(
                            'Vuelto ${pesos(v.vuelto)}',
                            key: const Key('vales_vuelto'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ElegirVales(
                    venta: v,
                    caja: widget.caja,
                    fiesta: widget.fiesta,
                    imprimir: papel.imprimir,
                    alImprimir: (todo) => setState(() => _todoImpreso = todo),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
