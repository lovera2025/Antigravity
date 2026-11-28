import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/nombre_de_barra.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../repositor/stock_de_la_fiesta.dart';
import '../services/barras_del_salon.dart';
import 'barra_jefe_providers.dart';

const _gris = Color(0xFFA7A29A);
const _rojo = Color(0xFFFF8F82);
const _verde = Color(0xFF59D38A);

/// Lo escrito para un producto en una barra.
class _Casillas {
  _Casillas(StockEnLaBarra? hoy)
      : arranque = TextEditingController(text: hoy == null ? '' : '${hoy.arranque}'),
        aviso = TextEditingController(text: hoy?.aviso == null ? '' : '${hoy!.aviso}');

  final TextEditingController arranque;
  final TextEditingController aviso;

  /// Null: sin escribir (esa barra no lleva ese producto).
  int? get arranqueNum => int.tryParse(arranque.text.trim());

  /// Null: no avisa.
  int? get avisoNum => arranqueNum == null ? null : int.tryParse(aviso.text.trim());

  void soltar() {
    arranque.dispose();
    aviso.dispose();
  }
}

/// **STOCK POR BARRA** (decidido por el usuario el 25-nov-2026): el jefe reparte el stock
/// general de cada producto —con cuánto arranca cada barra— y pone el aviso de "está
/// quedando poco" **para cada barra**. Lo que no reparte queda en el depósito. Desde ahí,
/// el stock queda en manos del repositor.
///
/// Se llega desde PRECIOS de la fiesta. El stock general se carga en PRECIOS, como
/// siempre: acá solo se reparte. **Lo que se puede lo dice la cuenta**
/// (`StockPorBarra.errorDelReparto`: no más de lo que hay, una barra que ya usó parte no
/// baja de lo usado, y un producto ya contado no cambia). Guardar pregunta por el modo
/// jefe (`test/solo_modo_jefe_test.dart`).
class RepartoDelStockScreen extends ConsumerStatefulWidget {
  final Evento fiesta;

  const RepartoDelStockScreen({super.key, required this.fiesta});

  @override
  ConsumerState<RepartoDelStockScreen> createState() => _RepartoDelStockScreenState();
}

class _RepartoDelStockScreenState extends ConsumerState<RepartoDelStockScreen> {
  /// producto → barra → lo escrito. Se arma con la primera lectura.
  Map<String, Map<String, _Casillas>>? _casillas;
  bool _guardando = false;
  ({String texto, bool error})? _dicho;

  String get _id => widget.fiesta.id;

  @override
  void dispose() {
    for (final porBarra in (_casillas ?? const <String, Map<String, _Casillas>>{}).values) {
      for (final c in porBarra.values) {
        c.soltar();
      }
    }
    super.dispose();
  }

  /// La llave: el reparto lo hace el jefe, en modo jefe.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    if (mounted) setState(() => _dicho = (texto: kSoloEnModoJefe, error: true));
    return true;
  }

  /// El reparto activo de hoy para [productoId] en [barra], o null.
  static StockEnLaBarra? _hoy(StockDeLaFiesta datos, String productoId, String barra) {
    for (final r in datos.repartos) {
      if (r.productoId == productoId && r.activo && claveDeBarra(r.barra) == claveDeBarra(barra)) return r;
    }
    return null;
  }

  /// La fila guardada (también la sacada del reparto), para reusar su id y su fecha.
  static StockEnLaBarra? _guardada(StockDeLaFiesta datos, String productoId, String barra) {
    for (final r in datos.repartos) {
      if (r.productoId == productoId && claveDeBarra(r.barra) == claveDeBarra(barra)) return r;
    }
    return null;
  }

  /// Los productos con el stock general cargado en PRECIOS, por nombre.
  static List<PrecioBarra> _conStock(StockDeLaFiesta datos) => [
        for (final p in datos.precios)
          if (p.eventoId == datos.eventoId && p.stockInicial != null) p,
      ]..sort((a, b) => datos.nombreDe(a.productoId).toLowerCase().compareTo(datos.nombreDe(b.productoId).toLowerCase()));

  void _armar(StockDeLaFiesta datos) {
    if (_casillas != null) return;
    _casillas = {
      for (final p in _conStock(datos))
        p.productoId: {for (final b in kBarrasDelSalon) b: _Casillas(_hoy(datos, p.productoId, b))},
    };
  }

  /// Lo que cambió de [productoId] contra lo guardado: barra → lo escrito.
  Map<String, _Casillas> _cambiosDe(StockDeLaFiesta datos, String productoId) {
    final out = <String, _Casillas>{};
    for (final e in (_casillas?[productoId] ?? const <String, _Casillas>{}).entries) {
      final hoy = _hoy(datos, productoId, e.key);
      final c = e.value;
      if (c.arranqueNum != hoy?.arranque || c.avisoNum != hoy?.aviso) out[e.key] = c;
    }
    return out;
  }

  /// Por qué no se puede guardar lo escrito para [productoId], o null. Lo dice la cuenta.
  String? _errorDe(StockDeLaFiesta datos, PrecioBarra precio) {
    final p = precio.productoId;
    final cambios = _cambiosDe(datos, p);
    if (cambios.isEmpty) return null;
    // Sacar una barra del reparto (se borró el arranque).
    for (final e in cambios.entries) {
      if (e.value.arranqueNum == null && _hoy(datos, p, e.key) != null) {
        final no = datos.stock.errorAlSacarDelReparto(p, e.key);
        if (no != null) return no;
      }
    }
    final arranques = {
      for (final e in (_casillas![p]!).entries)
        if (e.value.arranqueNum != null) e.key: e.value.arranqueNum!,
    };
    // Solo cambió el aviso: no hay nada que repartir de nuevo.
    final cambiaElArranque = cambios.entries.any((e) => e.value.arranqueNum != _hoy(datos, p, e.key)?.arranque);
    if (!cambiaElArranque) return null;
    return datos.stock.errorDelReparto(p, precio.stockInicial, arranques);
  }

  Future<void> _guardarReparto(StockDeLaFiesta datos) async {
    if (_guardando || _frenaSinModoJefe()) return;
    final precios = _conStock(datos);
    if (precios.any((p) => _errorDe(datos, p) != null)) return;
    setState(() {
      _guardando = true;
      _dicho = null;
    });
    var guardadas = 0;
    try {
      final barra = ref.read(barraDelJefeProvider);
      final ahora = ref.read(relojDelJefeProvider)();
      final quien = quienEsElJefe(ref);
      for (final precio in precios) {
        final p = precio.productoId;
        for (final e in _cambiosDe(datos, p).entries) {
          final c = e.value;
          final ya = _guardada(datos, p, e.key);
          final StockEnLaBarra fila;
          if (c.arranqueNum == null) {
            // Se borró el arranque: esa barra deja de llevar ese producto. No se borra.
            if (ya == null || !ya.activo) continue;
            fila = ya.conCambios(activo: false);
          } else if (ya == null) {
            fila = StockEnLaBarra.para(
              eventoId: _id,
              productoId: p,
              barra: e.key,
              arranque: c.arranqueNum!,
              aviso: c.avisoNum,
              ahora: ahora,
            );
          } else {
            fila = ya.conCambios(
              arranque: c.arranqueNum,
              aviso: c.avisoNum,
              sinAviso: c.avisoNum == null,
              activo: true,
            );
          }
          final guardada = await barra.guardarReparto(fila, quien: quien);
          unawaited(ref.read(subirDeLaBarraProvider)('barra_stock_barras', guardada.id));
          guardadas++;
        }
      }
      ref.invalidate(stockDeLaFiestaProvider(_id));
      if (mounted) {
        setState(() => _dicho = (
              texto: guardadas == 0 ? 'No había nada para guardar.' : 'Guardado: el reparto ya está en las barras.',
              error: false,
            ));
      }
    } catch (_) {
      if (mounted) setState(() => _dicho = (texto: 'No se pudo guardar. Probá de nuevo.', error: true));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = temaDeVender(DisenioBarra.nocheDorada, base: Theme.of(context));
    return Theme(data: tema, child: Builder(builder: _pantalla));
  }

  Widget _pantalla(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final stock = ref.watch(stockDeLaFiestaProvider(_id));
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = CortesPantalla.esCelular(ancho) ? 12.0 : 24.0;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'STOCK POR BARRA',
              key: Key('reparto_titulo'),
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
          constraints: const BoxConstraints(maxWidth: 900),
          child: stock.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('No se pudo leer el stock. Volvé a entrar.')),
            data: (datos) {
              _armar(datos);
              return _cuerpo(datos, esJefe: esJefe, margen: margen);
            },
          ),
        ),
      ),
    );
  }

  Widget _cuerpo(StockDeLaFiesta datos, {required bool esJefe, required double margen}) {
    final precios = _conStock(datos);
    final errores = {for (final p in precios) p.productoId: _errorDe(datos, p)};
    final hayCambios = precios.any((p) => _cambiosDe(datos, p.productoId).isNotEmpty);
    final hayError = errores.values.any((e) => e != null);
    final dicho = _dicho;
    return ListView(
      key: const Key('reparto_lista'),
      padding: EdgeInsets.fromLTRB(margen, 8, margen, 24),
      children: [
        const Text(
          'Con cuánto arranca cada barra y desde cuánto se le avisa al repositor que está quedando '
          'poco. Lo que no repartís queda en el depósito. El stock general se carga en PRECIOS.',
          style: TextStyle(fontSize: 13, color: _gris),
        ),
        if (!esJefe)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '$kSoloEnModoJefe: se ve, pero para cambiarlo hace falta el modo jefe.',
              key: Key('reparto_sin_modo_jefe'),
              style: TextStyle(color: Color(0xFFF2B84B)),
            ),
          ),
        if (precios.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Ningún producto tiene el stock cargado. Cargalo en PRECIOS (la casilla "Stock") y '
              'guardá: recién ahí se puede repartir.',
              key: Key('reparto_sin_stock'),
            ),
          ),
        for (final precio in precios) _producto(datos, precio, errores[precio.productoId], esJefe: esJefe),
        if (dicho != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              dicho.texto,
              key: const Key('reparto_dicho'),
              style: TextStyle(color: dicho.error ? _rojo : _verde, fontWeight: FontWeight.w700),
            ),
          ),
        if (precios.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: esJefe ? 'Guardar el reparto' : kSoloEnModoJefe,
                child: FilledButton(
                  key: const Key('reparto_guardar'),
                  onPressed: !esJefe || _guardando || !hayCambios || hayError ? null : () => _guardarReparto(datos),
                  style: FilledButton.styleFrom(
                    backgroundColor: TemaBarra.dorado,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 46),
                  ),
                  child: const Text('GUARDAR EL REPARTO', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _producto(StockDeLaFiesta datos, PrecioBarra precio, String? error, {required bool esJefe}) {
    final p = precio.productoId;
    final porBarra = _casillas![p]!;
    final general = precio.stockInicial ?? 0;
    final repartido = porBarra.values.fold<int>(0, (s, c) => s + (c.arranqueNum ?? 0));
    Widget casilla(String clave, TextEditingController c, String etiqueta, {String? pista}) => SizedBox(
          width: 118,
          child: TextField(
            key: Key(clave),
            controller: c,
            enabled: esJefe && !_guardando,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            onChanged: (_) => setState(() => _dicho = null),
            decoration: InputDecoration(
              labelText: etiqueta,
              hintText: pista,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF17161A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: error == null ? const Color(0xFF2A2830) : _rojo),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            key: Key('reparto_producto_$p'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(datos.nombreDe(p), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    'Stock general: $general',
                    key: Key('reparto_general_$p'),
                    style: const TextStyle(fontSize: 13, color: _gris),
                  ),
                  Text(
                    'Queda en el depósito: ${general - repartido}',
                    key: Key('reparto_deposito_$p'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: general - repartido < 0 ? _rojo : _verde,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < kBarrasDelSalon.length; i++)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(kBarrasDelSalon[i].toUpperCase(),
                            style: const TextStyle(fontSize: 12, letterSpacing: 1, color: _gris)),
                        casilla('reparto_arranque_${p}_${i + 1}', porBarra[kBarrasDelSalon[i]]!.arranque, 'Arranca con',
                            pista: 'no lleva'),
                        casilla('reparto_aviso_${p}_${i + 1}', porBarra[kBarrasDelSalon[i]]!.aviso, 'Avisar con',
                            pista: 'no avisa'),
                      ],
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    key: Key('reparto_error_$p'),
                    style: const TextStyle(color: _rojo, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
