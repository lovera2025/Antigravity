import 'package:flutter/material.dart';

import '../cuentas/pesos.dart';
import '../estilos/disenio_barra.dart';
import '../services/productos_para_vender.dart';

/// La tarjeta de un producto en VENDER, con el diseño del equipo ([TemaBarra]):
/// - **Noche dorada:** la foto arriba con el nombre encima, el precio dorado abajo y un
///   "+" que pasa a − n + cuando el producto está en la cuenta;
/// - **Mostrador:** tarjeta blanca, la foto, el nombre, el precio grande y el − n +
///   siempre abajo.
///
/// Sin foto, la inicial. Sin stock, la foto en gris y la tarjeta apagada. Tocarla suma
/// uno (la pantalla decide si antes pregunta por el stock).
class TarjetaProducto extends StatelessWidget {
  final ProductoEnVenta producto;
  final int cantidad;

  /// Lo que queda contando la cuenta. Null: no se controla.
  final int? quedan;

  /// Quedan pocos (o ninguno): la marca va en rojo.
  final bool enAviso;
  final ImageProvider? imagen;
  final VoidCallback alSumar;
  final VoidCallback alRestar;

  const TarjetaProducto({
    super.key,
    required this.producto,
    required this.cantidad,
    required this.quedan,
    required this.enAviso,
    required this.imagen,
    required this.alSumar,
    required this.alRestar,
  });

  bool get _sinStock => quedan != null && quedan! <= 0;

  String? get _textoStock => quedan == null
      ? null
      : _sinStock
          ? (cantidad > 0 ? 'Sin stock' : 'Agotado')
          : 'Quedan $quedan';

  /// Cuánto mide de alto una tarjeta de [ancho] en cada diseño: la foto va en 4:3.
  static double alto(DisenioBarra d, double ancho) => switch (d) {
        DisenioBarra.nocheDorada => ancho * 0.75 + 54,
        DisenioBarra.mostrador => (ancho - 16) * 0.75 + 138,
      };

  @override
  Widget build(BuildContext context) {
    final t = TemaBarra.of(context);
    final apagada = _sinStock && cantidad == 0;
    final tarjeta = t.disenio == DisenioBarra.nocheDorada ? _noche(t) : _mostrador(t);
    return Opacity(opacity: apagada ? 0.6 : 1, child: tarjeta);
  }

  // ── Noche dorada ─────────────────────────────────────────────────────────────

  Widget _noche(TemaBarra t) {
    final elegida = cantidad > 0;
    return Container(
      key: Key('producto_${producto.id}'),
      decoration: BoxDecoration(
        color: t.tarjeta,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: elegida ? t.elegida : t.tarjetaBorde, width: elegida ? 1.5 : 1),
        boxShadow: elegida
            ? [BoxShadow(color: t.elegida.withValues(alpha: 0.14), blurRadius: 20, offset: const Offset(0, 6))]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: alSumar,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _foto(t),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xBF000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    if (_textoStock != null) Positioned(top: 8, left: 8, child: _marca(t)),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Text(
                        producto.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.2,
                          shadows: [Shadow(color: Color(0x99000000), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            pesos(producto.precio.precio),
                            style: TextStyle(color: t.precio, fontWeight: FontWeight.w800, fontSize: t.precioTam),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (elegida)
                        _paso(t, chico: true)
                      else
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: t.elegida.withValues(alpha: 0.6), width: 1.5),
                          ),
                          child: Icon(Icons.add, size: 20, color: t.precio),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mostrador ────────────────────────────────────────────────────────────────

  Widget _mostrador(TemaBarra t) {
    final elegida = cantidad > 0;
    return Container(
      key: Key('producto_${producto.id}'),
      decoration: BoxDecoration(
        color: t.tarjeta,
        borderRadius: BorderRadius.circular(16),
        boxShadow: elegida ? [BoxShadow(color: t.elegida, spreadRadius: 3)] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: alSumar,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _foto(t),
                        if (_textoStock != null) Positioned(top: 8, left: 8, child: _marca(t)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.nombre, fontWeight: FontWeight.w700, fontSize: 14, height: 1.2),
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      pesos(producto.precio.precio),
                      style: TextStyle(
                        color: t.precio,
                        fontWeight: FontWeight.w800,
                        fontSize: t.precioTam,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _paso(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Las partes ───────────────────────────────────────────────────────────────

  Widget _foto(TemaBarra t) {
    final inicial = _Inicial(nombre: producto.nombre, tema: t);
    if (imagen == null) return inicial;
    final foto = Image(
      key: Key('foto_${producto.id}'),
      image: imagen!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Una foto que no está o no se puede leer nunca rompe la venta: va la inicial.
      errorBuilder: (_, _, _) => inicial,
    );
    if (!_sinStock || cantidad > 0) return foto;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.13, 0.42, 0.04, 0, 0, //
        0.13, 0.42, 0.04, 0, 0, //
        0.13, 0.42, 0.04, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: foto,
    );
  }

  Widget _marca(TemaBarra t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: enAviso ? t.marcaAviso : t.marcaFondo,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          _textoStock!,
          key: Key('stock_${producto.id}'),
          style: TextStyle(
            color: enAviso ? Colors.white : t.marcaTexto,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  /// El − n +. En Noche dorada aparece solo con el producto en la cuenta; en
  /// Mostrador está siempre, con el − apagado en cero.
  Widget _paso(TemaBarra t, {bool chico = false}) {
    final lado = chico ? 30.0 : 34.0;
    final mostrador = t.disenio == DisenioBarra.mostrador;
    Widget boton(IconData icono, VoidCallback? alTocar, Key key) {
      final icon = SizedBox(
        width: lado,
        height: lado,
        child: Icon(
          icono,
          size: 20,
          color: alTocar == null ? t.pasoTexto.withValues(alpha: 0.3) : t.pasoTexto,
        ),
      );
      return Padding(
        padding: EdgeInsets.all(mostrador ? 3 : 0),
        child: Material(
          color: mostrador ? Colors.white : Colors.transparent,
          shape: const CircleBorder(),
          elevation: mostrador ? 1 : 0,
          child: alTocar == null
              // Apagado, se come el toque: si no, pasaba a la tarjeta y el − sumaba uno.
              ? GestureDetector(key: key, behavior: HitTestBehavior.opaque, onTap: () {}, child: icon)
              : InkWell(key: key, customBorder: const CircleBorder(), onTap: alTocar, child: icon),
        ),
      );
    }

    final pildora = Container(
      decoration: BoxDecoration(color: t.pasoFondo, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: chico ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          boton(Icons.remove, cantidad > 0 ? alRestar : null, Key('tarjeta_restar_${producto.id}')),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 24),
            child: Text(
              '$cantidad',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.pasoTexto, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          boton(Icons.add, alSumar, Key('tarjeta_sumar_${producto.id}')),
        ],
      ),
    );
    return pildora;
  }
}

/// Sin foto: las iniciales del producto sobre un degradé del diseño.
class _Inicial extends StatelessWidget {
  final String nombre;
  final TemaBarra tema;

  const _Inicial({required this.nombre, required this.tema});

  String get _letras {
    final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    return palabras.map((p) => p.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tema.inicialDesde, tema.inicialHasta],
          ),
        ),
        child: Center(
          child: Text(
            _letras,
            key: const Key('inicial'),
            style: TextStyle(color: tema.inicialTexto, fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
      );
}
