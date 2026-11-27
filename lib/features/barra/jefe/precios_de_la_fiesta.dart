import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/cuenta_del_proveedor.dart' show costoDeUnTrago;
import '../cuentas/pesos.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/papel_en_pantalla.dart';
import '../impresion/ticket_esc_pos.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/papel_de_la_barra.dart';
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

/// La plata de PRECIOS redondeada a pesos: lo que cuesta un trago es "más o menos, para
/// calcularle" (el jefe), y los centavos solo molestan al leer.
String _pesosRedondos(int centavos) => pesos((centavos / 100).roundToDouble());

/// Un producto en PRECIOS, como lo está escribiendo el jefe.
class _Fila {
  final ProductoBarra producto;
  final PrecioBarra? base;
  bool va;
  final TextEditingController precio;
  final TextEditingController stock;
  final TextEditingController aviso;

  /// El precio de lista (lo que cobra el proveedor) y, de una botella de los tragos,
  /// cuántos cc trae (`barra_costos`, v84; maqueta aprobada el 27-nov).
  final CostoBarra? baseCosto;
  final TextEditingController lista;
  final TextEditingController trae;

  _Fila(this.producto, this.base, this.baseCosto)
      : va = base?.activo ?? false,
        precio = TextEditingController(
          text: base == null ? '' : PesosEnterosFormatter.escribir(base.precio),
        ),
        stock = TextEditingController(text: base?.stockInicial?.toString() ?? ''),
        aviso = TextEditingController(text: base?.avisoStock?.toString() ?? ''),
        lista = TextEditingController(text: PesosConCentavosFormatter.escribir(baseCosto?.precioLista)),
        trae = TextEditingController(text: PesosEnterosFormatter.escribir(baseCosto?.contenidoCc));

  double? get listaNum => PesosConCentavosFormatter.leer(lista.text);
  int? get traeNum => PesosEnterosFormatter.leer(trae.text);

  /// Si cambió el precio de lista o lo que trae la botella.
  bool get cambioCosto {
    final b = baseCosto;
    final l = listaNum, t = traeNum;
    if (b == null) return l != null || t != null;
    return centavos(l ?? -1) != centavos(b.precioLista ?? -1) || t != b.contenidoCc;
  }

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
    lista.dispose();
    trae.dispose();
  }
}

/// Un ingrediente de la receta de un trago, como lo está escribiendo el jefe. Sacarlo
/// lo apaga ([activo]): no se borra.
class _Ingrediente {
  final RecetaBarra? base;
  String? ingredienteId;
  UnidadDeReceta unidad;
  final TextEditingController cantidad;
  bool activo;

  _Ingrediente(this.base)
      : ingredienteId = base?.ingredienteId,
        unidad = base?.unidad ?? UnidadDeReceta.cc,
        cantidad = TextEditingController(text: base?.cantidad.toString() ?? ''),
        activo = base?.activo ?? true;

  int? get cantidadNum => PesosEnterosFormatter.leer(cantidad.text);

  bool get cambio {
    final b = base;
    if (b == null) return activo && ingredienteId != null;
    return activo != b.activo || cantidadNum != b.cantidad || unidad != b.unidad;
  }

  /// Como receta, para la cuenta de lo que cuesta. Null: todavía sin elegir o sin cantidad.
  RecetaBarra? comoReceta(String eventoId, String tragoId) {
    final id = ingredienteId, n = cantidadNum;
    if (!activo || id == null || n == null || n <= 0 || id == tragoId) return null;
    return RecetaBarra.para(
      eventoId: eventoId,
      productoId: tragoId,
      ingredienteId: id,
      cantidad: n,
      unidad: unidad,
      ahora: DateTime.utc(2000),
    );
  }

  void dispose() => cantidad.dispose();
}

class _PreciosDeLaFiestaVistaState extends ConsumerState<PreciosDeLaFiestaVista> {
  final _filas = <_Fila>[];
  PreciosDeLaFiesta? _datos;
  List<ProductoBarra>? _productos;

  /// El precio de lista y las recetas guardadas (v84): solo el jefe ve esta pantalla.
  ListaDelProveedor? _proveedor;

  /// Lo que lleva cada trago, como lo está escribiendo el jefe (por el id del trago).
  final _recetas = <String, List<_Ingrediente>>{};


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
    _soltarRecetas();
    super.dispose();
  }

  void _soltarRecetas() {
    for (final lista in _recetas.values) {
      for (final i in lista) {
        i.dispose();
      }
    }
    _recetas.clear();
  }

  void _cargar(List<ProductoBarra> productos, PreciosDeLaFiesta datos, ListaDelProveedor proveedor) {
    for (final f in _filas) {
      f.dispose();
    }
    _filas
      ..clear()
      ..addAll([
        for (final p in productos)
          if (p.activo) _Fila(p, datos.de(p.id), proveedor.costoDe(p.id)),
      ]);
    _soltarRecetas();
    for (final r in proveedor.recetas) {
      (_recetas[r.productoId] ??= []).add(_Ingrediente(r));
    }
    _recargo = datos.recargo?.pct ?? 0;
    _datos = datos;
    _productos = productos;
    _proveedor = proveedor;
  }

  List<_Ingrediente> _ingredientesDe(String tragoId) =>
      [for (final i in _recetas[tragoId] ?? const <_Ingrediente>[]) if (i.activo) i];

  /// Un trago: tiene receta, o es de la categoría de los tragos (para poder ponérsela).
  bool _esTrago(_Fila f) =>
      _ingredientesDe(f.producto.id).isNotEmpty || f.producto.categoria.toLowerCase().contains('trago');

  /// Lo que va por cc en algún trago: son las botellas, que no se venden solas.
  Set<String> get _botellas => {
        for (final e in _recetas.entries)
          for (final i in e.value)
            if (i.activo && i.unidad == UnidadDeReceta.cc && i.ingredienteId != null) i.ingredienteId!,
      };

  _Fila? _filaDe(String productoId) {
    for (final f in _filas) {
      if (f.producto.id == productoId) return f;
    }
    return null;
  }

  /// Lo que cuesta [tragoId] con lo escrito ahora (la misma cuenta que GANANCIA).
  ({int? centavos, List<String> faltan}) _costoDe(String tragoId) => costoDeUnTrago(
        [
          for (final i in _ingredientesDe(tragoId))
            if (i.comoReceta(widget.fiesta.id, tragoId) case final r?) r,
        ],
        lista: (id) => _filaDe(id)?.listaNum,
        contenidoCc: (id) => _filaDe(id)?.traeNum,
      );

  int get _cambiosDeRecetas => [
        for (final lista in _recetas.values)
          for (final i in lista)
            if (i.cambio) i,
      ].length;

  int get _cambios =>
      _filas.where((f) => f.cambio || f.cambioCosto).length + _cambiosDeRecetas + (_recargoCambio ? 1 : 0);

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
    for (final e in _recetas.entries) {
      for (final i in e.value) {
        if (!i.activo || i.ingredienteId == null) continue;
        if ((i.cantidadNum ?? 0) <= 0) {
          final trago = _filaDe(e.key)?.producto.nombre ?? 'un trago';
          final de = _filaDe(i.ingredienteId!)?.producto.nombre ?? 'un ingrediente';
          _decir('Falta cuánto lleva de $de el $trago.', error: true);
          return;
        }
      }
    }
    setState(() => _guardando = true);
    final barra = ref.read(barraDelJefeProvider);
    final subir = ref.read(subirDeLaBarraProvider);
    final quien = quienEsElJefe(ref);
    var guardados = 0;
    var costos = 0, ingredientes = 0;
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
      // El precio de lista y lo que trae cada botella (solo el jefe; no salen a la red).
      for (final f in _filas) {
        if (!f.cambioCosto) continue;
        final guardado = await barra.guardarCosto(
          CostoBarra.para(
            eventoId: widget.fiesta.id,
            productoId: f.producto.id,
            precioLista: f.listaNum,
            contenidoCc: f.traeNum,
            ahora: DateTime.now(),
          ),
          quien: quien,
        );
        unawaited(subir('barra_costos', guardado.id));
        costos++;
      }
      for (final e in _recetas.entries) {
        for (final i in e.value) {
          if (!i.cambio || i.ingredienteId == null) continue;
          final guardado = await barra.guardarReceta(
            RecetaBarra.para(
              eventoId: widget.fiesta.id,
              productoId: e.key,
              ingredienteId: i.ingredienteId!,
              cantidad: i.cantidadNum ?? i.base?.cantidad ?? 1,
              unidad: i.unidad,
              activo: i.activo,
              ahora: DateTime.now(),
            ),
            quien: quien,
          );
          unawaited(subir('barra_recetas', guardado.id));
          ingredientes++;
        }
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
    ref.invalidate(listaDelProveedorProvider(widget.fiesta.id));
    ref.invalidate(cajasDelJefeProvider(widget.fiesta.id));
    if (!mounted) return;
    setState(() => _guardando = false);
    // Con precios y recargo juntos, se dicen los dos: decía solo los precios (lo encontró
    // el recorrido con el mouse del 7-nov).
    final partes = [
      if (guardados > 0) guardados == 1 ? '1 precio' : '$guardados precios',
      if (costos > 0) costos == 1 ? '1 precio de lista' : '$costos precios de lista',
      if (ingredientes > 0) 'las recetas',
      if (conRecargo) 'el recargo',
    ];
    _decir(switch (partes.length) {
      0 => 'No había nada para guardar.',
      1 when conRecargo => 'Guardado el recargo.',
      1 => 'Guardado: ${partes.single}.',
      _ => 'Guardado: ${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}.',
    });
  }

  void _descartar() {
    final d = _datos, p = _productos, l = _proveedor;
    if (d == null || p == null || l == null) return;
    setState(() => _cargar(p, d, l));
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
    // También el precio de lista, lo que trae cada botella y las recetas (maqueta del 27-nov).
    final costos = await barra.costos(origen.id);
    final recetas = await barra.recetas(origen.id);
    if (!mounted) return;
    var copiados = 0;
    setState(() {
      for (final f in _filas) {
        final de = precios.where((p) => p.productoId == f.producto.id).firstOrNull;
        if (de != null) {
          f.va = true;
          f.precio.text = PesosEnterosFormatter.escribir(de.precio);
          copiados++;
        }
        final costo = costos.where((c) => c.productoId == f.producto.id).firstOrNull;
        if (costo != null) {
          f.lista.text = PesosConCentavosFormatter.escribir(costo.precioLista);
          f.trae.text = PesosEnterosFormatter.escribir(costo.contenidoCc);
        }
      }
      final enElCatalogo = {for (final f in _filas) f.producto.id};
      final tragos = {for (final r in recetas) if (enElCatalogo.contains(r.productoId)) r.productoId};
      for (final trago in tragos) {
        final lista = _recetas[trago] ??= [];
        final deOrigen = [
          for (final r in recetas)
            if (r.productoId == trago && enElCatalogo.contains(r.ingredienteId)) r,
        ];
        // Lo que esta fiesta tenía y aquella no lleva, se saca; lo demás queda como allá.
        for (final i in lista) {
          if (!deOrigen.any((r) => r.ingredienteId == i.ingredienteId)) i.activo = false;
        }
        for (final r in deOrigen) {
          final ya = lista.where((i) => i.ingredienteId == r.ingredienteId).firstOrNull;
          final i = ya ?? (_Ingrediente(null)..ingredienteId = r.ingredienteId);
          if (ya == null) lista.add(i);
          i
            ..activo = true
            ..unidad = r.unidad
            ..cantidad.text = r.cantidad.toString();
        }
      }
      if (recargo != null) _recargo = recargo.pct;
    });
    final nombre = EventoPresentacion.tituloPrincipal(origen);
    _decir(error: copiados == 0, copiados == 0
        ? '$nombre no tiene precios de productos que estén en el catálogo.'
        : 'Se copiaron $copiados precios de $nombre${recargo != null ? ' y su recargo' : ''}, con el precio '
            'de lista y las recetas. El stock no se copia. Revisá y tocá GUARDAR CAMBIOS.');
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
          : siNoSalio(ref.read(papelDeLaBarraProvider),
              'No salió. ¿La impresora está prendida y cerca de esta PC? Si no, guardala como PDF.'),
      error: !salio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoDelJefeProvider);
    final precios = ref.watch(preciosDelJefeProvider(widget.fiesta.id));
    // El precio de lista, lo que se gana y las recetas: **solo el jefe** (audio 77; lo
    // recordó el usuario el 27-nov). Sin modo jefe ni se leen.
    final veCosto = ReglasDeLaBarra.veElCostoYLaGanancia(ref.watch(rolEnLaBarraProvider));
    final AsyncValue<ListaDelProveedor> deLaLista =
        veCosto ? ref.watch(listaDelProveedorProvider(widget.fiesta.id)) : const AsyncData(ListaDelProveedor());
    final esJefe = ref.watch(esRolJefeProvider);
    final imagen = ref.watch(imagenDelProductoProvider);
    if (catalogo.hasError || precios.hasError || deLaLista.hasError) {
      return const Center(child: Text('No se pudieron leer los precios.'));
    }
    final productos = catalogo.value;
    final datos = precios.value;
    final proveedor = deLaLista.value;
    if (productos == null || datos == null || proveedor == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if ((!identical(datos, _datos) || !identical(productos, _productos) || !identical(proveedor, _proveedor)) &&
        (_cambios == 0 || _recargarAlLlegar)) {
      _cargar(productos, datos, proveedor);
      _recargarAlLlegar = false;
    }

    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth >= 1000;
      // Con el precio de lista hay siete columnas: si no entran, cada producto va en
      // dos renglones (con el nombre de cada casilla).
      final angosto = (ancho ? caja.maxWidth - 300 : caja.maxWidth) < 820;
      final botellas = _botellas;
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
          if (!angosto) _Encabezado(conCosto: veCosto),
          for (final f in _filas)
            // Una botella de los tragos que no se vende sola va abajo, en su bloque.
            if (f.va || !botellas.contains(f.producto.id)) ...[
              _FilaDePrecio(
                fila: f,
                imagen: imagen(f.producto),
                angosto: angosto,
                esJefe: esJefe,
                conCosto: veCosto,
                trago: _ingredientesDe(f.producto.id).isNotEmpty ? _costoDe(f.producto.id) : null,
                debajoDelNombre: veCosto && _esTrago(f) ? _lineaDeLaReceta(f, esJefe) : null,
                onCambio: () => setState(() {}),
              ),
            ],
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
          // En la web no hay impresora: queda el PDF.
          if (!ref.watch(enLaWebProvider))
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

  /// "200 cc Fernet 750 + 500 cc Coca-Cola 2,25": cómo se prepara un trago, en una línea
  /// chica debajo de su nombre (pedido del usuario, 27-nov: "como mucho un pequeño
  /// subtexto"). Solo en PRECIOS del jefe.
  String _comoSePrepara(String tragoId) => [
        for (final i in _ingredientesDe(tragoId))
          if (i.ingredienteId != null && (i.cantidadNum ?? 0) > 0)
            '${i.cantidadNum} ${i.unidad == UnidadDeReceta.cc ? 'cc' : (i.cantidadNum == 1 ? 'unidad de' : 'unidades de')} '
                '${_filaDe(i.ingredienteId!)?.producto.nombre ?? ''}',
      ].join(' + ');

  /// La línea chica debajo del nombre del trago: tocándola se abre cómo se prepara.
  Widget _lineaDeLaReceta(_Fila trago, bool esJefe) {
    final id = trago.producto.id;
    final texto = _comoSePrepara(id);
    return InkWell(
      key: Key('jefe_receta_$id'),
      onTap: () => _abrirReceta(trago, esJefe),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                texto.isEmpty ? 'Agregar cómo se prepara' : texto,
                key: Key('jefe_receta_texto_$id'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: texto.isEmpty ? TemaBarra.dorado : const Color(0xFFA7A29A),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: Color(0xFFA7A29A)),
          ],
        ),
      ),
    );
  }

  /// La ventanita de cómo se prepara un trago: lo que lleva y, de cada cosa, su precio de
  /// lista (y cuánto trae la botella). Lo que se escribe acá se guarda con GUARDAR CAMBIOS,
  /// junto con lo demás de PRECIOS.
  Future<void> _abrirReceta(_Fila trago, bool esJefe) => showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setVentana) {
            void cambio(VoidCallback fn) {
              setState(fn);
              setVentana(() {});
            }

            return AlertDialog(
              title: Text('${trago.producto.nombre} · cómo se prepara'),
              content: SizedBox(width: 620, child: SingleChildScrollView(child: _receta(trago, esJefe, cambio))),
              actions: [
                FilledButton(
                  key: const Key('jefe_receta_listo'),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('LISTO'),
                ),
              ],
            );
          },
        ),
      );

  Widget _receta(_Fila trago, bool esJefe, void Function(VoidCallback) cambio) {
    final id = trago.producto.id;
    final ingredientes = _ingredientesDe(id);
    final opciones = [
      for (final f in _filas)
        if (f.producto.id != id) f.producto,
    ];
    final costo = _costoDe(id);
    final precio = trago.precioNum;
    final faltan = [for (final x in costo.faltan) _filaDe(x)?.producto.nombre ?? 'un ingrediente'];
    final resumen = costo.centavos == null
        ? (faltan.isEmpty
            ? 'Elegí lo que lleva y cuánto.'
            : 'Falta el precio de lista de ${faltan.join(', ')}.')
        : 'Cuesta ${_pesosRedondos(costo.centavos!)}'
            '${precio == null ? '' : ' · ganás ${_pesosRedondos(precio * 100 - costo.centavos!)} por trago'}';
    Widget plata(Key key, TextEditingController c, {required bool pesos, String? sufijo}) => SizedBox(
          width: pesos ? 130 : 100,
          child: TextField(
            key: key,
            controller: c,
            enabled: esJefe,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [pesos ? const PesosConCentavosFormatter() : const PesosEnterosFormatter()],
            decoration: InputDecoration(isDense: true, prefixText: pesos ? '\$ ' : null, suffixText: sufijo),
            onChanged: (_) => cambio(() {}),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (n, i) in ingredientes.indexed) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  key: Key('jefe_ingrediente_${id}_$n'),
                  initialValue: i.ingredienteId,
                  isExpanded: true,
                  hint: const Text('Elegí qué lleva'),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final o in opciones) DropdownMenuItem(value: o.id, child: Text(o.nombre)),
                  ],
                  onChanged: esJefe ? (v) => cambio(() => i.ingredienteId = v) : null,
                ),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  key: Key('jefe_cantidad_${id}_$n'),
                  controller: i.cantidad,
                  enabled: esJefe,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(isDense: true, suffixText: i.unidad == UnidadDeReceta.cc ? 'cc' : 'u.'),
                  onChanged: (_) => cambio(() {}),
                ),
              ),
              SegmentedButton<UnidadDeReceta>(
                key: Key('jefe_unidad_${id}_$n'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: UnidadDeReceta.cc, label: Text('cc')),
                  ButtonSegment(value: UnidadDeReceta.unidad, label: Text('entero')),
                ],
                selected: {i.unidad},
                onSelectionChanged: esJefe ? (v) => cambio(() => i.unidad = v.first) : null,
              ),
              IconButton(
                key: Key('jefe_sacar_${id}_$n'),
                tooltip: 'Sacar',
                onPressed: esJefe
                    ? () => cambio(() {
                          if (i.base == null) {
                            _recetas[id]?.remove(i);
                          } else {
                            i.activo = false;
                          }
                        })
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          // De lo que lleva: lo que cobra el proveedor (y cuánto trae la botella), acá mismo.
          if (i.ingredienteId case final ing? when _filaDe(ing) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    i.unidad == UnidadDeReceta.cc ? 'Precio de lista de la botella' : 'Precio de lista de cada una',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
                  ),
                  plata(Key('jefe_botella_lista_$ing'), _filaDe(ing)!.lista, pesos: true),
                  if (i.unidad == UnidadDeReceta.cc) ...[
                    const Text('trae', style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A))),
                    plata(Key('jefe_botella_trae_$ing'), _filaDe(ing)!.trae, pesos: false, sufijo: 'cc'),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: Key('jefe_agregar_ingrediente_$id'),
              onPressed: esJefe ? () => cambio(() => (_recetas[id] ??= []).add(_Ingrediente(null))) : null,
              icon: const Icon(Icons.add),
              label: const Text('AGREGAR'),
            ),
            Text(
              resumen,
              key: Key('jefe_receta_cuesta_$id'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: costo.centavos == null ? const Color(0xFFF2D77C) : const Color(0xFFF3EFE4),
              ),
            ),
          ],
        ),
      ],
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
  /// Con el precio de lista y lo que se gana: solo el jefe.
  final bool conCosto;

  const _Encabezado({required this.conCosto});

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          const SizedBox(width: 56, child: Text('VA', style: estilo)),
          const Expanded(child: Text('PRODUCTO', style: estilo)),
          SizedBox(width: 130, child: Text(conCosto ? 'VENDO A' : 'PRECIO', style: estilo)),
          const SizedBox(width: 10),
          const SizedBox(width: 112, child: Text('STOCK', style: estilo)),
          const SizedBox(width: 10),
          const SizedBox(width: 112, child: Text('AVISAR DESDE', style: estilo)),
          if (conCosto) ...const [
          SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'PRECIO DE LISTA\n'),
                TextSpan(
                  text: 'lo que me cobra el proveedor',
                  style: TextStyle(fontSize: 11, letterSpacing: 0, fontWeight: FontWeight.w500),
                ),
              ]),
              style: estilo,
            ),
          ),
          SizedBox(width: 10),
          SizedBox(width: 90, child: Text('GANO', style: estilo, textAlign: TextAlign.right)),
          ],
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

  /// De un trago: lo que cuesta por su receta (no se escribe). Null: no es un trago.
  final ({int? centavos, List<String> faltan})? trago;

  /// Con el precio de lista y lo que se gana: solo el jefe.
  final bool conCosto;

  /// Debajo del nombre de un trago: cómo se prepara, en chico.
  final Widget? debajoDelNombre;

  const _FilaDePrecio({
    required this.fila,
    required this.imagen,
    required this.angosto,
    required this.esJefe,
    required this.onCambio,
    this.trago,
    this.conCosto = true,
    this.debajoDelNombre,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                f.producto.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              ?debajoDelNombre,
            ],
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
    final precio = casilla('jefe_precio', f.precio, angosto ? 'Vendo a' : 'Precio', plata: true);
    final stock = casilla('jefe_stock', f.stock, 'Stock', pista: 'sin control');
    // "Avisar desde" no entra en la casilla de un celular.
    final aviso = casilla('jefe_aviso', f.aviso, 'Aviso', pista: '—');
    // El precio de lista: lo escribe el jefe; en un trago sale de la receta.
    final t = trago;
    final listaEnCentavos = t != null ? t.centavos : (f.listaNum == null ? null : centavos(f.listaNum!));
    final Widget lista = t != null
        ? Tooltip(
            key: Key('jefe_lista_de_la_receta_$id'),
            message: 'Sale de cómo se prepara',
            child: Text(
              t.centavos == null ? '—' : _pesosRedondos(t.centavos!),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFA7A29A)),
            ),
          )
        : TextField(
            key: Key('jefe_lista_$id'),
            controller: f.lista,
            enabled: esJefe,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            inputFormatters: const [PesosConCentavosFormatter()],
            decoration: InputDecoration(
              isDense: true,
              prefixText: '\$ ',
              labelText: angosto ? 'Precio de lista' : null,
            ),
            onChanged: (_) => onCambio(),
          );
    final vende = f.precioNum;
    final gano = Text(
      vende == null || listaEnCentavos == null ? '—' : _pesosRedondos(vende * 100 - listaEnCentavos),
      key: Key('jefe_gano_$id'),
      textAlign: TextAlign.right,
      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFA7A29A)),
    );

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
              if (conCosto) const SizedBox(height: 8),
              if (conCosto)
              Row(
                children: [
                  Expanded(flex: 3, child: lista),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('Gano ', style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A))),
                        Flexible(child: gano),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 56, child: Align(alignment: Alignment.centerLeft, child: check)),
              Expanded(child: nombre),
              SizedBox(width: 130, child: precio),
              const SizedBox(width: 10),
              SizedBox(width: 112, child: stock),
              const SizedBox(width: 10),
              SizedBox(width: 112, child: aviso),
              if (conCosto) ...[
                const SizedBox(width: 10),
                SizedBox(width: 140, child: lista),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: gano),
              ],
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
