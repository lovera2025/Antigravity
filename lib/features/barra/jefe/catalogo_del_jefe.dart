import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../estilos/fotos_de_la_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/imagen_de_producto.dart';
import 'barra_jefe_providers.dart';

/// CATÁLOGO: **uno solo para todas las fiestas** (el precio va en PRECIOS, por fiesta).
/// Cada producto con su nombre, su categoría y su foto, elegida de las que trae la app o
/// la que sale de su nombre. Lo que no se vende se da de baja: **nunca se borra** (las
/// ventas viejas lo siguen nombrando).
///
/// En la PC, la grilla y al lado el producto elegido; en tablet y celular, el producto se
/// edita en una ventana.
class CatalogoDelJefe extends ConsumerStatefulWidget {
  const CatalogoDelJefe({super.key});

  @override
  ConsumerState<CatalogoDelJefe> createState() => _CatalogoDelJefeState();
}

class _CatalogoDelJefeState extends ConsumerState<CatalogoDelJefe> {
  /// El que se edita al lado, en la PC. Null con [_nuevo]: uno nuevo.
  String? _elegido;
  bool _nuevo = false;

  /// Cambia cada vez que se elige otro, para que el editor arranque de cero.
  int _vuelta = 0;

  static const _anchoConPanel = 980.0;

  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('$kSoloEnModoJefe: el catálogo lo carga el jefe.')),
      );
    }
    return true;
  }

  /// Guarda el producto y lo manda a subir. True si quedó guardado.
  Future<bool> _guardarProducto(ProductoBarra producto, {required String aviso}) async {
    if (_frenaSinModoJefe()) return false;
    final ProductoBarra guardado;
    try {
      guardado = await ref
          .read(barraDelJefeProvider)
          .guardarProducto(producto, quien: quienEsElJefe(ref));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el producto. Probá de nuevo.')),
        );
      }
      return false;
    }
    unawaited(ref.read(subirDeLaBarraProvider)('barra_productos', guardado.id));
    ref.invalidate(catalogoDelJefeProvider);
    if (mounted) {
      setState(() {
        _elegido = guardado.id;
        _nuevo = false;
        _vuelta++;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
    }
    return true;
  }

  void _elegir(ProductoBarra? p, {required bool conPanel, required List<ProductoBarra> todos}) {
    if (conPanel) {
      setState(() {
        _elegido = p?.id;
        _nuevo = p == null;
        _vuelta++;
      });
      return;
    }
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogo) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _EditorDeProducto(
              producto: p,
              categorias: _categorias(todos),
              esJefe: ref.read(esRolJefeProvider),
              imagen: ref.read(imagenDelProductoProvider),
              onGuardar: (nuevo, aviso) async {
                final ok = await _guardarProducto(nuevo, aviso: aviso);
                if (ok && dialogo.mounted) Navigator.pop(dialogo);
              },
            ),
          ),
        ),
      ),
    ));
  }

  static List<String> _categorias(List<ProductoBarra> productos) {
    final vistas = <String>[];
    for (final p in productos) {
      final c = p.categoria.trim();
      if (c.isNotEmpty && !vistas.any((v) => v.toLowerCase() == c.toLowerCase())) vistas.add(c);
    }
    return vistas;
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoDelJefeProvider);
    final esJefe = ref.watch(esRolJefeProvider);
    final imagen = ref.watch(imagenDelProductoProvider);
    return catalogo.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('No se pudo leer el catálogo.')),
      data: (productos) => LayoutBuilder(
        builder: (context, caja) {
          final conPanel = caja.maxWidth >= _anchoConPanel;
          final elegido = _nuevo
              ? null
              : productos.where((p) => p.id == _elegido).firstOrNull ??
                  (conPanel ? productos.firstOrNull : null);
          final grilla = _Grilla(
            productos: productos,
            elegido: conPanel ? elegido?.id : null,
            imagen: imagen,
            esJefe: esJefe,
            onElegir: (p) => _elegir(p, conPanel: conPanel, todos: productos),
          );
          if (!conPanel) return grilla;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: grilla),
              const SizedBox(width: 20),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF17161A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF2A2830)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: _nuevo || elegido != null
                          ? _EditorDeProducto(
                              key: ValueKey('editor_${elegido?.id ?? 'nuevo'}_$_vuelta'),
                              producto: elegido,
                              categorias: _categorias(productos),
                              esJefe: esJefe,
                              imagen: imagen,
                              onGuardar: (p, aviso) => _guardarProducto(p, aviso: aviso),
                            )
                          : const Text('Tocá + PRODUCTO para cargar el primero.'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Grilla extends StatelessWidget {
  final List<ProductoBarra> productos;
  final String? elegido;
  final ImageProvider? Function(ProductoBarra) imagen;
  final bool esJefe;
  final ValueChanged<ProductoBarra?> onElegir;

  const _Grilla({
    required this.productos,
    required this.elegido,
    required this.imagen,
    required this.esJefe,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  '${productos.length} ${productos.length == 1 ? 'producto' : 'productos'} · un solo catálogo '
                  'para todas las fiestas · lo que no se vende se da de baja, nunca se borra',
                  key: const Key('jefe_catalogo_cuantos'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
                ),
                Tooltip(
                  message: esJefe ? 'Cargar un producto nuevo' : kSoloEnModoJefe,
                  child: FilledButton.icon(
                    key: const Key('jefe_producto_nuevo'),
                    onPressed: esJefe ? () => onElegir(null) : null,
                    icon: const Icon(Icons.add),
                    label: const Text('PRODUCTO', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (productos.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Todavía no hay productos. Cargá los que se venden en la barra, con + PRODUCTO.',
                key: Key('jefe_catalogo_vacio'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final p = productos[i];
                return _TarjetaDelCatalogo(
                  producto: p,
                  imagen: imagen(p),
                  elegido: p.id == elegido,
                  onTap: () => onElegir(p),
                );
              },
              childCount: productos.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _TarjetaDelCatalogo extends StatelessWidget {
  final ProductoBarra producto;
  final ImageProvider? imagen;
  final bool elegido;
  final VoidCallback onTap;

  const _TarjetaDelCatalogo({
    required this.producto,
    required this.imagen,
    required this.elegido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = producto;
    Widget foto = FotoDelProductoJefe(nombre: p.nombre, imagen: imagen);
    if (!p.activo) {
      foto = Opacity(
        opacity: 0.45,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
          child: foto,
        ),
      );
    }
    return Material(
      color: const Color(0xFF17161A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: elegido ? TemaBarra.dorado : const Color(0xFF2A2830), width: elegido ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('jefe_producto_${p.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 4 / 3, child: foto),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [if (p.categoria.isNotEmpty) p.categoria, if (!p.activo) 'DE BAJA'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.activo ? const Color(0xFFA7A29A) : const Color(0xFFF2B84B),
                      fontWeight: p.activo ? FontWeight.normal : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La foto de un producto, o su inicial si no tiene.
class FotoDelProductoJefe extends StatelessWidget {
  final String nombre;
  final ImageProvider? imagen;

  const FotoDelProductoJefe({super.key, required this.nombre, required this.imagen});

  @override
  Widget build(BuildContext context) {
    final inicial = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2412), Color(0xFF4A3C16)],
        ),
      ),
      child: Center(
        child: Text(
          nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase(),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFFECD07A)),
        ),
      ),
    );
    final i = imagen;
    if (i == null) return inicial;
    return Image(
      image: i,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => inicial,
    );
  }
}

/// El producto que se edita: nombre, categoría, foto y si está de baja. Con [producto]
/// en null, uno nuevo.
class _EditorDeProducto extends StatefulWidget {
  final ProductoBarra? producto;
  final List<String> categorias;
  final bool esJefe;
  final ImageProvider? Function(ProductoBarra) imagen;

  /// Guarda el producto con el aviso que se muestra.
  final Future<void> Function(ProductoBarra producto, String aviso) onGuardar;

  const _EditorDeProducto({
    super.key,
    required this.producto,
    required this.categorias,
    required this.esJefe,
    required this.imagen,
    required this.onGuardar,
  });

  @override
  State<_EditorDeProducto> createState() => _EditorDeProductoState();
}

class _EditorDeProductoState extends State<_EditorDeProducto> {
  late final _nombre = TextEditingController(text: widget.producto?.nombre ?? '');
  late final _categoria = TextEditingController(text: widget.producto?.categoria ?? '');
  late String? _foto = widget.producto?.imagenUrl;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _categoria.dispose();
    super.dispose();
  }

  /// El producto como queda con lo escrito, para la foto de muestra.
  ProductoBarra get _borrador {
    final base = widget.producto;
    return ProductoBarra(
      id: base?.id ?? 'nuevo',
      nombre: _nombre.text.trim(),
      categoria: _categoria.text.trim(),
      activo: base?.activo ?? true,
      orden: base?.orden ?? 0,
      imagenUrl: _foto,
      createdAt: base?.createdAt ?? '',
      updatedAt: base?.updatedAt ?? '',
    );
  }

  bool get _hayNombre => _nombre.text.trim().isNotEmpty;

  Future<void> _guardar({bool? activo}) async {
    if (!_hayNombre || _guardando) return;
    setState(() => _guardando = true);
    try {
      final base = widget.producto;
      final ProductoBarra listo;
      final String aviso;
      if (base == null) {
        listo = ProductoBarra.nuevo(
          nombre: _nombre.text,
          categoria: _categoria.text,
          imagenUrl: _foto,
          ahora: DateTime.now(),
        );
        aviso = '${listo.nombre}: cargado. Ahora ponele precio en PRECIOS.';
      } else {
        listo = base
            .conCambios(nombre: _nombre.text, categoria: _categoria.text, activo: activo)
            .conImagen(_foto);
        aviso = switch (activo) {
          false => '${listo.nombre}: dado de baja. Deja de ofrecerse; no se borra.',
          true => '${listo.nombre}: volvió al catálogo.',
          null => '${listo.nombre}: guardado.',
        };
      }
      await widget.onGuardar(listo, aviso);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _elegirFoto() async {
    final elegida = await showDialog<String>(
      context: context,
      builder: (_) => _BibliotecaDeFotos(actual: _foto),
    );
    if (elegida == null || !mounted) return;
    setState(() => _foto = elegida.isEmpty ? null : elegida);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.producto;
    final puede = widget.esJefe && !_guardando;
    final automatica = _foto == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          base == null ? 'PRODUCTO NUEVO' : 'EDITAR PRODUCTO',
          style: const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A)),
        ),
        const SizedBox(height: 10),
        // Baja: más alta, los botones quedaban debajo del borde en la PC.
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 170,
            child: FotoDelProductoJefe(nombre: _nombre.text, imagen: widget.imagen(_borrador)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              automatica ? 'Foto según el nombre' : 'Foto elegida de la biblioteca',
              key: const Key('jefe_producto_foto_cual'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
            ),
            TextButton(
              key: const Key('jefe_producto_foto'),
              onPressed: puede ? _elegirFoto : null,
              child: const Text('ELEGIR FOTO'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('jefe_producto_nombre'),
          controller: _nombre,
          enabled: widget.esJefe,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('jefe_producto_categoria'),
          controller: _categoria,
          enabled: widget.esJefe,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Categoría', hintText: 'Tragos, Cervezas, Sin alcohol…'),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.categorias.isNotEmpty && widget.esJefe) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in widget.categorias)
                ActionChip(
                  label: Text(c),
                  onPressed: () => setState(() => _categoria.text = c),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            if (base != null)
              OutlinedButton(
                key: const Key('jefe_producto_baja'),
                onPressed: puede && _hayNombre ? () => _guardar(activo: !base.activo) : null,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(base.activo ? 'DAR DE BAJA' : 'VOLVER A DAR DE ALTA'),
              ),
            FilledButton(
              key: const Key('jefe_producto_guardar'),
              onPressed: puede && _hayNombre ? () => _guardar() : null,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(base == null ? 'CARGAR' : 'GUARDAR', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.esJefe
              ? 'Llega a cada tablet cuando se prepara en la oficina, con internet.'
              : kSoloEnModoJefe,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
        ),
      ],
    );
  }
}

/// Las fotos que trae la app, para elegir una. Devuelve `biblioteca:<clave>`, o '' para
/// volver a la foto que sale del nombre.
class _BibliotecaDeFotos extends StatelessWidget {
  final String? actual;

  const _BibliotecaDeFotos({required this.actual});

  static String _nombre(String clave) {
    final t = clave.replaceAll('_', ' ');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Elegí la foto'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: FotoDeLaBarra.claves.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _Opcion(
                clave: 'automatica',
                elegida: actual == null,
                texto: 'Según el nombre',
                foto: const ColoredBox(
                  color: Color(0xFF241F12),
                  child: Center(child: Icon(Icons.auto_awesome, color: TemaBarra.dorado)),
                ),
                onTap: () => Navigator.pop(context, ''),
              );
            }
            final clave = FotoDeLaBarra.claves[i - 1];
            final valor = '${FotoDeLaBarra.prefijo}$clave';
            return _Opcion(
              clave: clave,
              elegida: actual == valor,
              texto: _nombre(clave),
              foto: Image.asset(
                FotoDeLaBarra.ruta(clave),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF241F12)),
              ),
              onTap: () => Navigator.pop(context, valor),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER')),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  final String clave;
  final bool elegida;
  final String texto;
  final Widget foto;
  final VoidCallback onTap;

  const _Opcion({
    required this.clave,
    required this.elegida,
    required this.texto,
    required this.foto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('jefe_foto_$clave'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: elegida ? TemaBarra.dorado : Colors.transparent,
                  width: 3,
                ),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: foto),
            ),
          ),
          const SizedBox(height: 4),
          Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
