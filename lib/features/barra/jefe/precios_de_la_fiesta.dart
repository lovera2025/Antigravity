import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/papel_en_pantalla.dart';
import '../impresion/ticket_esc_pos.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/fiestas_del_jefe.dart';
import '../services/imagen_de_producto.dart';
import '../widgets/pesos_enteros_formatter.dart';
import 'barra_jefe_providers.dart';
import 'catalogo_del_jefe.dart';

/// PRECIOS de una fiesta: qué productos del catálogo van, a cuánto, cuántos hay y desde
/// cuántos avisar; el recargo por transferencia de la fiesta; COPIAR DE OTRA FIESTA; y
/// la lista de precios en papel (58 mm, nunca A4).
///
/// Se escribe todo y se guarda junto con GUARDAR CAMBIOS: así el jefe no guarda a medias
/// mientras escribe. Sacar un producto de la fiesta **no lo borra**: queda la fila, sin
/// ofrecerse.
class PreciosDeLaFiestaVista extends ConsumerStatefulWidget {
  final Evento fiesta;

  /// Las demás fiestas, para COPIAR DE OTRA FIESTA.
  final List<Evento> otras;

  const PreciosDeLaFiestaVista({super.key, required this.fiesta, required this.otras});

  @override
  ConsumerState<PreciosDeLaFiestaVista> createState() => _PreciosDeLaFiestaVistaState();
}

/// Un producto en PRECIOS, como lo está escribiendo el jefe.
class _Fila {
  final ProductoBarra producto;
  final PrecioBarra? base;
  bool va;
  final TextEditingController precio;
  final TextEditingController stock;
  final TextEditingController aviso;

  _Fila(this.producto, this.base)
      : va = base?.activo ?? false,
        precio = TextEditingController(
          text: base == null ? '' : PesosEnterosFormatter.escribir(base.precio),
        ),
        stock = TextEditingController(text: base?.stockInicial?.toString() ?? ''),
        aviso = TextEditingController(text: base?.avisoStock?.toString() ?? '');

  int? get precioNum => PesosEnterosFormatter.leer(precio.text);
  int? get stockNum => PesosEnterosFormatter.leer(stock.text);

  /// Sin stock no hay desde cuántos avisar.
  int? get avisoNum => stockNum == null ? null : PesosEnterosFormatter.leer(aviso.text);

  bool get cambio {
    final b = base;
    if (b == null) return va;
    return va != b.activo ||
        precioNum != b.precio.round() ||
        stockNum != b.stockInicial ||
        avisoNum != (b.stockInicial == null ? null : b.avisoStock);
  }

  void dispose() {
    precio.dispose();
    stock.dispose();
    aviso.dispose();
  }
}

class _PreciosDeLaFiestaVistaState extends ConsumerState<PreciosDeLaFiestaVista> {
  final _filas = <_Fila>[];
  PreciosDeLaFiesta? _datos;
  List<ProductoBarra>? _productos;
  double _recargo = 0;
  bool _guardando = false;

  /// Recién guardado: lo próximo que llegue de la base se carga aunque lo escrito
  /// difiera de lo de antes (es lo guardado).
  bool _recargarAlLlegar = false;

  /// Lo último que pasó, dicho arriba de la lista. **No en un SnackBar:** taparía
  /// GUARDAR CAMBIOS, que está abajo (la misma razón que en el plano).
  ({String texto, bool error})? _aviso;

  void _decir(String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (texto: texto, error: error));
  }

  String get _titulo => EventoPresentacion.tituloPrincipal(widget.fiesta);

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  void _cargar(List<ProductoBarra> productos, PreciosDeLaFiesta datos) {
    for (final f in _filas) {
      f.dispose();
    }
    _filas
      ..clear()
      ..addAll([for (final p in productos) if (p.activo) _Fila(p, datos.de(p.id))]);
    _recargo = datos.recargo?.pct ?? 0;
    _datos = datos;
    _productos = productos;
  }

  int get _cambios =>
      _filas.where((f) => f.cambio).length + (_recargoCambio ? 1 : 0);

  bool get _recargoCambio => _recargo != (_datos?.recargo?.pct ?? 0);

  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    _decir('$kSoloEnModoJefe: los precios los pone el jefe.');
    return true;
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (_frenaSinModoJefe()) return;
    final sinPrecio = [for (final f in _filas) if (f.va && f.precioNum == null) f.producto.nombre];
    if (sinPrecio.isNotEmpty) {
      _decir('Falta el precio de ${sinPrecio.join(', ')}.', error: true);
      return;
    }
    setState(() => _guardando = true);
    final barra = ref.read(barraDelJefeProvider);
    final subir = ref.read(subirDeLaBarraProvider);
    final quien = quienEsElJefe(ref);
    var guardados = 0;
    var conRecargo = false;
    try {
      for (final (i, f) in _filas.indexed) {
        if (!f.cambio) continue;
        final b = f.base;
        final PrecioBarra listo;
        if (b == null) {
          listo = PrecioBarra.para(
            eventoId: widget.fiesta.id,
            productoId: f.producto.id,
            precio: f.precioNum!.toDouble(),
            orden: i,
            stockInicial: f.stockNum,
            avisoStock: f.avisoNum,
            ahora: DateTime.now(),
          );
        } else {
          listo = PrecioBarra(
            id: b.id,
            eventoId: b.eventoId,
            productoId: b.productoId,
            precio: (f.precioNum ?? b.precio).toDouble(),
            activo: f.va,
            orden: b.orden,
            stockInicial: f.stockNum,
            avisoStock: f.avisoNum,
            hechoPor: b.hechoPor,
            deviceId: b.deviceId,
            createdAt: b.createdAt,
            updatedAt: b.updatedAt,
          );
        }
        final guardado = await barra.guardarPrecio(listo, quien: quien);
        unawaited(subir('barra_precios', guardado.id));
        guardados++;
      }
      if (_recargoCambio) {
        final viejo = _datos?.recargo;
        final listo = viejo == null
            ? RecargoBarra.para(eventoId: widget.fiesta.id, pct: _recargo, ahora: DateTime.now())
            : viejo.conPct(_recargo);
        final guardado = await barra.guardarRecargo(listo, quien: quien);
        unawaited(subir('barra_recargos', guardado.id));
        conRecargo = true;
      }
    } catch (_) {
      _decir('No se pudo guardar todo. Revisá y probá de nuevo.', error: true);
      if (mounted) setState(() => _guardando = false);
      return;
    }
    _recargarAlLlegar = true;
    ref.invalidate(preciosDelJefeProvider(widget.fiesta.id));
    ref.invalidate(cajasDelJefeProvider(widget.fiesta.id));
    if (!mounted) return;
    setState(() => _guardando = false);
    // Con precios y recargo juntos, se dicen los dos: decía solo los precios (lo encontró
    // el recorrido con el mouse del 7-nov).
    final yRecargo = conRecargo ? ' y el recargo' : '';
    _decir(switch (guardados) {
      0 => 'Guardado el recargo.',
      1 => 'Guardado: 1 precio$yRecargo.',
      _ => 'Guardado: $guardados precios$yRecargo.',
    });
  }

  void _descartar() {
    final d = _datos, p = _productos;
    if (d == null || p == null) return;
    setState(() => _cargar(p, d));
  }

  Future<void> _copiar() async {
    final origen = await showDialog<Evento>(
      context: context,
      builder: (_) => _CopiarDeOtraFiesta(otras: widget.otras),
    );
    if (origen == null || !mounted) return;
    final barra = ref.read(barraDelJefeProvider);
    final precios = await barra.precios(origen.id);
    final recargo = await barra.recargo(origen.id);
    if (!mounted) return;
    var copiados = 0;
    setState(() {
      for (final f in _filas) {
        final de = precios.where((p) => p.productoId == f.producto.id).firstOrNull;
        if (de == null) continue;
        f.va = true;
        f.precio.text = PesosEnterosFormatter.escribir(de.precio);
        copiados++;
      }
      if (recargo != null) _recargo = recargo.pct;
    });
    final nombre = EventoPresentacion.tituloPrincipal(origen);
    _decir(error: copiados == 0, copiados == 0
        ? '$nombre no tiene precios de productos que estén en el catálogo.'
        : 'Se copiaron $copiados precios de $nombre${recargo != null ? ' y su recargo' : ''}. '
            'El stock no se copia. Revisá y tocá GUARDAR CAMBIOS.');
  }

  List<LineaTicket> get _lista => ModeloTicket.deListaDePrecios(
        fiesta: _titulo,
        fecha: fechaDeLaFiesta(widget.fiesta.fechaEvento),
        productos: [
          for (final f in _filas)
            if (f.va && f.precioNum != null)
              (nombre: f.producto.nombre, categoria: f.producto.categoria, precio: f.precioNum!.toDouble()),
        ],
        recargoPct: _recargo,
      );

  Future<void> _pdf() => ref.read(guardarPdfDeLaBarraProvider)(
        _lista,
        titulo: 'Lista de precios',
        nombre: 'Lista de precios - $_titulo',
        context: context,
      );

  Future<void> _imprimir() async {
    final falta = await faltaLaImpresora(ref);
    if (falta != null) {
      _decir(falta, error: true);
      return;
    }
    bool salio;
    try {
      salio = await ref.read(papelDeLaBarraProvider).imprimir(_lista);
    } catch (_) {
      salio = false;
    }
    _decir(
      salio
          ? 'Salió la lista de precios.'
          : 'No salió. ¿La impresora está prendida y cerca de esta PC? Si no, guardala como PDF.',
      error: !salio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoDelJefeProvider);
    final precios = ref.watch(preciosDelJefeProvider(widget.fiesta.id));
    final esJefe = ref.watch(esRolJefeProvider);
    final imagen = ref.watch(imagenDelProductoProvider);
    if (catalogo.hasError || precios.hasError) {
      return const Center(child: Text('No se pudieron leer los precios.'));
    }
    final productos = catalogo.value;
    final datos = precios.value;
    if (productos == null || datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if ((!identical(datos, _datos) || !identical(productos, _productos)) &&
        (_cambios == 0 || _recargarAlLlegar)) {
      _cargar(productos, datos);
      _recargarAlLlegar = false;
    }

    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth >= 1000;
      final angosto = caja.maxWidth < 640;
      final aviso = _aviso;
      final arriba = [
        _barraDeArriba(esJefe),
        const SizedBox(height: 12),
        _tarjetaRecargo(esJefe),
        const SizedBox(height: 12),
        if (aviso != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              aviso.texto,
              key: const Key('jefe_precios_aviso'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: aviso.error ? const Color(0xFFFF8F82) : const Color(0xFF59D38A),
              ),
            ),
          ),
      ];
      final lista = [
        if (_filas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'El catálogo está vacío: primero cargá los productos en CATÁLOGO.',
              key: Key('jefe_precios_sin_productos'),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          if (datos.precios.where((p) => p.activo).isEmpty && _cambios == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Esta fiesta todavía no tiene precios. Tildá lo que va, o usá COPIAR DE OTRA FIESTA.',
                key: Key('jefe_precios_sin_precios'),
                style: TextStyle(color: Color(0xFFF2D77C)),
              ),
            ),
          if (!angosto) const _Encabezado(),
          for (final f in _filas)
            _FilaDePrecio(
              fila: f,
              imagen: imagen(f.producto),
              angosto: angosto,
              esJefe: esJefe,
              onCambio: () => setState(() {}),
            ),
        ],
      ];
      final papel = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ASÍ SALE LA LISTA · 58 mm',
            style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A)),
          ),
          const SizedBox(height: 8),
          PapelEnPantalla(_lista, key: const Key('jefe_lista_papel'), ancho: 260),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ancho
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...arriba,
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: ListView(children: [...lista, const SizedBox(height: 24)])),
                            const SizedBox(width: 20),
                            SizedBox(width: 280, child: SingleChildScrollView(child: papel)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [...arriba, ...lista, const SizedBox(height: 16), papel, const SizedBox(height: 24)],
                  ),
          ),
          if (_cambios > 0) _barraGuardar(esJefe),
        ],
      );
    });
  }

  Widget _barraDeArriba(bool esJefe) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            key: const Key('jefe_copiar'),
            onPressed: esJefe && widget.otras.isNotEmpty && !_guardando ? _copiar : null,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('COPIAR DE OTRA FIESTA'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
          OutlinedButton.icon(
            key: const Key('jefe_lista_imprimir'),
            onPressed: _imprimir,
            icon: const Icon(Icons.print_outlined),
            label: const Text('IMPRIMIR LISTA'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
          FilledButton.icon(
            key: const Key('jefe_lista_pdf'),
            onPressed: _pdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('LISTA · PDF 58 mm'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        ],
      );

  Widget _tarjetaRecargo(bool esJefe) {
    String pct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final puede = esJefe && !_guardando;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF17161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A3F1C)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Recargo por transferencia', style: TextStyle(fontWeight: FontWeight.w700)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  key: const Key('jefe_recargo_menos'),
                  tooltip: 'Bajar el recargo',
                  onPressed: puede && _recargo > 0
                      ? () => setState(() => _recargo = (_recargo - 1).clamp(0, RecargoBarra.pctMaximo).toDouble())
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    _recargo == 0 ? 'sin' : '${pct(_recargo)} %',
                    key: const Key('jefe_recargo_pct'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.outlined(
                  key: const Key('jefe_recargo_mas'),
                  tooltip: 'Subir el recargo',
                  onPressed: puede && _recargo < 30
                      ? () => setState(() => _recargo = (_recargo + 1).clamp(0, RecargoBarra.pctMaximo).toDouble())
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const Text(
              'Cada caja arranca cada cobro con este. Va sobre lo transferido, y la cajera lo puede '
              'cambiar en un cobro si hace falta.',
              style: TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraGuardar(bool esJefe) {
    final n = _cambios;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1D1910),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TemaBarra.dorado),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                n == 1 ? '1 cambio sin guardar' : '$n cambios sin guardar',
                key: const Key('jefe_precios_cambios'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('jefe_precios_descartar'),
                    onPressed: _guardando ? null : _descartar,
                    child: const Text('DESCARTAR'),
                  ),
                  Tooltip(
                    message: esJefe ? 'Guardar los cambios' : kSoloEnModoJefe,
                    child: FilledButton(
                      key: const Key('jefe_precios_guardar'),
                      onPressed: esJefe && !_guardando ? _guardar : null,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A));
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text('VA', style: estilo)),
          Expanded(child: Text('PRODUCTO', style: estilo)),
          SizedBox(width: 150, child: Text('PRECIO', style: estilo)),
          SizedBox(width: 12),
          SizedBox(width: 120, child: Text('STOCK', style: estilo)),
          SizedBox(width: 12),
          SizedBox(width: 120, child: Text('AVISAR DESDE', style: estilo)),
        ],
      ),
    );
  }
}

class _FilaDePrecio extends StatelessWidget {
  final _Fila fila;
  final ImageProvider? imagen;
  final bool angosto;
  final bool esJefe;
  final VoidCallback onCambio;

  const _FilaDePrecio({
    required this.fila,
    required this.imagen,
    required this.angosto,
    required this.esJefe,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    final f = fila;
    final id = f.producto.id;
    final check = IconButton(
      key: Key('jefe_va_$id'),
      tooltip: f.va ? 'Va en esta fiesta' : 'No va en esta fiesta',
      onPressed: esJefe
          ? () {
              f.va = !f.va;
              onCambio();
            }
          : null,
      style: IconButton.styleFrom(
        backgroundColor: f.va ? TemaBarra.dorado : Colors.transparent,
        foregroundColor: f.va ? const Color(0xFF141108) : const Color(0xFFF3EFE4),
        side: BorderSide(color: f.va ? TemaBarra.dorado : const Color(0xFF4A4752)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(f.va ? Icons.check : null, size: 22),
    );
    final nombre = Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 36,
            child: FotoDelProductoJefe(nombre: f.producto.nombre, imagen: imagen),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            f.producto.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    Widget casilla(String clave, TextEditingController c, String etiqueta, {bool plata = false, String? pista}) =>
        TextField(
          key: Key('${clave}_$id'),
          controller: c,
          enabled: esJefe,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          inputFormatters: [
            plata ? const PesosEnterosFormatter() : FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            isDense: true,
            prefixText: plata ? '\$ ' : null,
            labelText: angosto ? etiqueta : null,
            hintText: pista,
          ),
          onChanged: (_) => onCambio(),
        );
    final precio = casilla('jefe_precio', f.precio, 'Precio', plata: true);
    final stock = casilla('jefe_stock', f.stock, 'Stock', pista: 'sin control');
    // "Avisar desde" no entra en la casilla de un celular.
    final aviso = casilla('jefe_aviso', f.aviso, 'Aviso', pista: '—');

    final contenido = angosto
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [check, const SizedBox(width: 8), Expanded(child: nombre)]),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(flex: 3, child: precio),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: stock),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: aviso),
                ],
              ),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 56, child: Align(alignment: Alignment.centerLeft, child: check)),
              Expanded(child: nombre),
              SizedBox(width: 150, child: precio),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: stock),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: aviso),
            ],
          );
    return Opacity(
      opacity: f.va ? 1 : 0.6,
      child: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF2A2830)))),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: contenido),
      ),
    );
  }
}

/// COPIAR DE OTRA FIESTA: las demás, con cuántos precios tiene cada una. **Cuenta los
/// que se van a copiar**: los de productos que siguen en el catálogo. Contaba también los
/// de un producto dado de baja y decía "10 precios" para copiar 9 (recorrido del 7-nov).
class _CopiarDeOtraFiesta extends ConsumerWidget {
  final List<Evento> otras;

  const _CopiarDeOtraFiesta({required this.otras});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Copiar precios de otra fiesta'),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Se copian los productos que van y sus precios, y el recargo. El stock no: cada '
              'fiesta carga el suyo. Nada se guarda hasta que toques GUARDAR CAMBIOS.',
            ),
            const SizedBox(height: 8),
            for (final e in otras)
              Consumer(builder: (context, ref, _) {
                final precios = ref.watch(preciosDelJefeProvider(e.id)).value;
                final catalogo = ref.watch(catalogoDelJefeProvider).value;
                final activos = {for (final p in catalogo ?? const <ProductoBarra>[]) if (p.activo) p.id};
                final cuantos = precios == null || catalogo == null
                    ? null
                    : precios.precios.where((p) => p.activo && activos.contains(p.productoId)).length;
                return ListTile(
                  key: Key('jefe_copiar_de_${e.id}'),
                  enabled: cuantos != null && cuantos > 0,
                  title: Text(
                    EventoPresentacion.tituloPrincipal(e),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${fechaDeLaFiesta(e.fechaEvento)} · '
                    '${cuantos == null ? '…' : cuantos == 0 ? 'sin precios' : '$cuantos precios'}',
                  ),
                  onTap: () => Navigator.pop(context, e),
                );
              }),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER')),
      ],
    );
  }
}
