import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../central/central_barra_provider.dart';
import '../central/linea_de_la_caja.dart';
import '../cuentas/cobro_barra.dart';
import '../cuentas/cuenta_barra.dart';
import '../cuentas/pesos.dart';
import '../cuentas/stock_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../impresion/impresora_bluetooth.dart';
import '../providers/barra_providers.dart';
import '../services/imagen_de_producto.dart';
import '../services/productos_para_vender.dart';
import 'cerrar_caja_barra_screen.dart';
import 'cobrar_hoja.dart';
import 'elegir_disenio.dart';
import 'elegir_impresora_screen.dart';
import 'pesos_enteros_formatter.dart';
import 'tarjeta_producto.dart';
import 'vales_de_la_venta_screen.dart';
import 'ventas_de_la_caja_screen.dart';

/// VENDER: se tocan los productos y se arma la cuenta; debajo del total, **EFECTIVO,
/// TRANSFERENCIA y MIXTO** abren su cobro (pedido del 3-nov: sin un COBRAR que después
/// pregunte el medio). Al confirmar se guarda la venta (antes de imprimir: sin
/// impresora, igual queda), sube si hay internet y siguen los vales.
///
/// **Se adapta al ancho** (`CortesPantalla`): en el celular los productos arriba y la
/// cuenta abajo, con el total y los tres botones siempre a la vista; en la tablet y la
/// PC, lado a lado.
///
/// **Con el diseño de este equipo** (Noche dorada o Mostrador, `disenio_barra.dart`):
/// el tema va acá arriba, así la pantalla de adentro abre la hoja de cobro y los
/// avisos con sus colores.
class VenderScreen extends ConsumerWidget {
  final Evento fiesta;
  final CajaBarra caja;

  const VenderScreen({super.key, required this.fiesta, required this.caja});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disenio = ref.watch(disenioDeLaBarraProvider);
    return Theme(
      data: temaDeVender(disenio, base: Theme.of(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: TemaBarra.de(disenio).fondo),
        child: _Vender(fiesta: fiesta, caja: caja),
      ),
    );
  }
}

class _Vender extends ConsumerStatefulWidget {
  final Evento fiesta;
  final CajaBarra caja;

  const _Vender({required this.fiesta, required this.caja});

  @override
  ConsumerState<_Vender> createState() => _VenderState();
}

class _VenderState extends ConsumerState<_Vender> with WidgetsBindingObserver {
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
    // Cuando bajan ventas de las otras cajas (de la nube o de la central de la barra),
    // "Quedan" se pone al día solo.
    ref.listenManual(operationalSyncRevisionProvider, (_, _) => unawaited(_cargar()));
    // La central de la barra: esta caja la busca por el wifi del salón.
    final caja = widget.caja;
    unawaited(ref.read(clienteDeLaBarraProvider.notifier).arrancar(
          eventoId: widget.fiesta.id,
          nombreCaja: 'Caja ${caja.numeroCaja}${caja.operadorNombre == null ? '' : ' · ${caja.operadorNombre}'}',
        ));
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
      final deLaFiesta = await ref.read(barraDeLaCajaProvider).recargo(_caja.eventoId);
      if (!mounted) return;
      final arranque = recargoDeArranque(deLaFiesta, recordado);
      final cobro = await pedirCobro(
        context,
        total: _cuenta.total,
        medio: medio,
        recargoPrendido: arranque.prendido,
        recargoPct: arranque.pct,
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
    // La pantalla de los vales es otra ruta: lleva el tema de VENDER a mano.
    final tema = Theme.of(context);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: tema,
        child: ValesDeLaVentaScreen(venta: venta, caja: _caja, fiesta: _fiesta),
      ),
    ));
    if (mounted) unawaited(_cargar());
  }

  /// Cerrar la caja: contar a ciegas y ver el cierre. Si quedó cerrada, VENDER se va y
  /// vuelve al inicio de la barra: con la caja cerrada no se vende.
  Future<void> _cerrarCaja() async {
    final tema = Theme.of(context);
    final cerrada = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => Theme(
        data: tema,
        child: CerrarCajaBarraScreen(caja: _caja, fiesta: _fiesta),
      ),
    ));
    if (cerrada == true && mounted) Navigator.of(context).pop();
  }

  /// VENTAS: las ventas de esta caja, para reimprimir, imprimir lo que faltó, sacar el
  /// ticket o anular. Al volver, "Quedan" se pone al día (una anulada devuelve stock).
  Future<void> _verVentas() async {
    final tema = Theme.of(context);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: tema,
        child: VentasDeLaCajaScreen(caja: _caja, fiesta: _fiesta),
      ),
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
      // El degradé del diseño lo pinta VenderScreen, detrás.
      backgroundColor: Colors.transparent,
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
            key: const Key('vender_ventas'),
            tooltip: 'Ventas de esta caja: reimprimir, ticket, anular',
            onPressed: _verVentas,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            key: const Key('vender_disenio'),
            tooltip: 'Cómo se ve',
            onPressed: () => elegirDisenio(context, ref, muestra: _productos.firstOrNull),
            icon: const Icon(Icons.palette_outlined),
          ),
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
          IconButton(
            key: const Key('vender_cerrar'),
            tooltip: 'Cerrar la caja',
            onPressed: _cerrarCaja,
            icon: const Icon(Icons.lock_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : celular
              ? Column(
                  children: [
                    const LineaDeLaCaja(),
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
                        children: [
                          // Lo que espera subir ("Todo subido") y la central de la barra.
                          const LineaDeLaCaja(),
                          _filtros(),
                          Expanded(child: _grilla(pc ? 4 : 3)),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: pc ? 420 : ancho * 0.4,
                      child: ColoredBox(color: TemaBarra.of(context).panel, child: _cuentaCompleta()),
                    ),
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
    final disenio = TemaBarra.of(context).disenio;
    const espacio = 10.0;
    const margen = 12.0;
    return LayoutBuilder(
      builder: (context, lugar) {
        // El alto sale del ancho de cada tarjeta: la foto va en 4:3 y debajo el
        // precio (y en Mostrador el nombre y el − n +). Así no se desborda en
        // ningún tamaño ni con el equipo acostado.
        final anchoTarjeta = (lugar.maxWidth - margen * 2 - espacio * (columnas - 1)) / columnas;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(margen, 4, margen, margen),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            mainAxisSpacing: espacio,
            crossAxisSpacing: espacio,
            mainAxisExtent: TarjetaProducto.alto(disenio, anchoTarjeta),
          ),
          itemCount: lista.length,
          itemBuilder: (_, i) => _tarjeta(lista[i]),
        );
      },
    );
  }

  Widget _tarjeta(ProductoEnVenta p) {
    final aviso = _stock[p.id]?.aviso;
    final quedan = _quedan(p.id);
    final sinStock = quedan != null && quedan <= 0;
    return TarjetaProducto(
      producto: p,
      cantidad: _cuenta.cantidadDe(p.id),
      quedan: quedan,
      enAviso: quedan != null && (sinStock || (aviso != null && quedan <= aviso)),
      imagen: _imagen(p.producto),
      alSumar: () => _sumar(p),
      alRestar: () => setState(() => _cuenta = _cuenta.restar(p.id)),
    );
  }

  ImageProvider? _imagen(ProductoBarra p) => ref.read(imagenDelProductoProvider)(p);

  Widget _renglon(RenglonVenta r) {
    final producto = _productos.where((x) => x.id == r.productoId).firstOrNull;
    final imagen = producto == null ? null : _imagen(producto.producto);
    return ListTile(
        key: Key('renglon_${r.productoId}'),
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: imagen == null
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: imagen,
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 34, height: 34),
                ),
              ),
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
  }

  Widget _total() {
    final t = TemaBarra.of(context);
    return Row(
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
                style: TextStyle(
                  fontSize: t.disenio == DisenioBarra.mostrador ? 34 : 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: t.total,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Los tres pagos con los colores del diseño. En Mostrador, en la tablet y la PC con
  /// lugar de alto, van como barras anchas una debajo de otra, con su letra chica.
  Widget _botonesPago({bool enFila = false}) {
    final t = TemaBarra.of(context);
    final puede = !_cuenta.estaVacia && !_cobrando;
    final apilados = t.pagosApilados && !enFila && MediaQuery.sizeOf(context).height >= 600;

    Widget boton(MedioBarra medio, String texto, String detalle, IconData icono, Color fondo, Color letra,
        {bool conBorde = false}) {
      final contenido = apilados
          ? Row(
              children: [
                Icon(icono, size: 20),
                const SizedBox(width: 10),
                Text(texto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 12),
                // Todo el resto del ancho es del detalle, contra el borde derecho.
                Expanded(
                  child: Text(
                    detalle,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                  ),
                ),
              ],
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, size: 18),
                  const SizedBox(width: 6),
                  Text(texto, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            );
      final estilo = ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? fondo.withValues(alpha: fondo.a * 0.35) : fondo,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? letra.withValues(alpha: 0.45) : letra,
        ),
        side: conBorde
            ? WidgetStateProperty.resolveWith((s) => BorderSide(
                  color: TemaBarra.dorado.withValues(alpha: s.contains(WidgetState.disabled) ? 0.35 : 1),
                  width: 1.5,
                ))
            : null,
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        padding: WidgetStateProperty.all(
          EdgeInsets.symmetric(horizontal: apilados ? 18 : 6, vertical: apilados ? 16 : 15),
        ),
      );
      final b = conBorde
          ? OutlinedButton(
              key: Key('pagar_${medio.name}'),
              style: estilo,
              onPressed: puede ? () => _cobrar(medio) : null,
              child: contenido,
            )
          : FilledButton(
              key: Key('pagar_${medio.name}'),
              style: estilo,
              onPressed: puede ? () => _cobrar(medio) : null,
              child: contenido,
            );
      return apilados ? b : Expanded(child: b);
    }

    final botones = [
      boton(MedioBarra.efectivo, 'EFECTIVO', 'con vuelto', Icons.payments_outlined, t.efectivo, Colors.white),
      boton(MedioBarra.transferencia, 'TRANSFERENCIA', 'Mercado Pago · QR', Icons.qr_code_2, t.transferencia,
          Colors.white),
      boton(MedioBarra.mixto, 'MIXTO', 'parte y parte', Icons.call_split, t.mixto, t.mixtoTexto,
          conBorde: t.mixtoConBorde),
    ];
    if (apilados) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [botones[0], const SizedBox(height: 8), botones[1], const SizedBox(height: 8), botones[2]],
      );
    }
    return Row(
      children: [botones[0], const SizedBox(width: 8), botones[1], const SizedBox(width: 8), botones[2]],
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
      color: TemaBarra.of(context).panel,
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
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: TemaBarra.of(context).total,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _botonesPago(enFila: true),
            ],
          ),
        ),
      ),
    );
  }
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
