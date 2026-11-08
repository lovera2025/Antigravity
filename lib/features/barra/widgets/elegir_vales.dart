import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cuentas/pesos.dart';
import '../cuentas/silla_de_la_puerta.dart';
import '../cuentas/vales_de_barra.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/ticket_esc_pos.dart';
import '../services/papel_de_la_barra.dart' show kSinPapel;

/// Manda un papel a la impresora. True si salió.
typedef ImprimirPapel = Future<bool> Function(List<LineaTicket> lineas);

/// Anota un vale que salió (`barra_vales`), para poder reimprimir el mismo.
typedef AnotarVale = Future<void> Function(Vale vale);

enum _Forma { todoJunto, porSeparado }

/// Una bebida de la venta, con lo que ya salió en vales.
class _Bebida {
  final RenglonVenta renglon;
  final valePor = TextEditingController();

  /// Cuánto de esta bebida llevó cada vale en que salió, en orden: 3, 2...
  final impresos = <int>[];

  _Bebida(this.renglon);

  int get quedan => renglon.cantidad - impresos.fold<int>(0, (s, n) => s + n);
  int? get numero => valePor.text.trim().isEmpty ? null : int.tryParse(valePor.text.trim());

  /// Por cuánto sale el próximo vale: lo escrito o, vacío, todas las que quedan.
  int get proximo => numero ?? quedan;
  bool get valido => valePorValido(quedan, numero);
  bool get terminada => quedan == 0;
}

/// Una silla de la noche de la venta: sale de a una, cada una en su vale (6.4.0).
class _Silla {
  final RenglonVenta renglon;
  var impresas = 0;

  _Silla(this.renglon);

  int get quedan => renglon.cantidad - impresas;
  bool get terminada => quedan <= 0;
}

/// Después de cobrar, cómo salen los vales de la venta (pedido del jefe, 3-nov). Se pasa
/// de una forma a la otra cuando se quiere:
/// - **TODO JUNTO**: un vale con todo lo que queda (al principio, toda la compra);
/// - **POR SEPARADO**: cada bebida con su casilla "vale por" y su IMPRIMIR. **Cada vale lo
///   arma la cajera:** escribe por cuánto, imprime, y la casilla queda vacía para el
///   próximo, hasta que no quede ninguna. Vacía, el vale es por todas las que quedan.
///
/// **Un vale por papel:** cada IMPRIMIR saca uno solo, nunca una tira. Lo que ya salió en
/// un vale no vuelve a salir: TODO JUNTO lleva solo lo que queda.
///
/// **Las sillas de la noche ([esSillaDeLaPuerta]) salen aparte, una por vale** (6.4.0): no
/// van en TODO JUNTO ni en POR SEPARADO, cada una lleva su número, y su vale dice que se
/// lleva a la recepcionista. Así la puerta anota cada silla con un número distinto.
///
/// **Cada vale que sale se anota** ([anotar]): así una copia saca el mismo vale. Con
/// [yaSalieron] retoma una venta que quedó a la mitad (sin impresora, o se salió antes):
/// lo que ya salió no vuelve a salir, y el próximo vale sigue la numeración.
class ElegirVales extends StatefulWidget {
  final VentaBarra venta;
  final CajaBarra caja;
  final String fiesta;
  final ImprimirPapel imprimir;

  /// Cada vez que sale un vale: si ya no queda nada sin vale.
  final ValueChanged<bool>? alImprimir;

  /// Cada vale que salió, antes de dejar mandar otro. Si no se puede anotar, el vale
  /// igual salió: no se frena.
  final AnotarVale? anotar;

  /// Los vales originales de esta venta que ya salieron antes.
  final List<ValeBarra> yaSalieron;

  /// Si el vale que no salió fue porque la impresora dijo que no tiene papel.
  final bool Function()? sinPapel;

  const ElegirVales({
    super.key,
    required this.venta,
    required this.caja,
    required this.fiesta,
    required this.imprimir,
    this.alImprimir,
    this.anotar,
    this.yaSalieron = const [],
    this.sinPapel,
  });

  @override
  State<ElegirVales> createState() => _ElegirValesState();
}

class _ElegirValesState extends State<ElegirVales> {
  _Forma? _forma;
  late final _bebidas = [
    for (final r in widget.venta.renglones)
      if (!esSillaDeLaPuerta(r.nombre)) _Bebida(r),
  ];
  late final _sillas = [
    for (final r in widget.venta.renglones)
      if (esSillaDeLaPuerta(r.nombre)) _Silla(r),
  ];

  /// Cuántos vales salieron de la venta: el próximo lleva el siguiente número.
  int _valesImpresos = 0;
  bool _imprimiendo = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _retomar();
  }

  /// Lo que ya salió antes se descuenta, bebida por bebida, por el nombre: la venta se
  /// guardó con el nombre de ese momento, y el vale también.
  void _retomar() {
    final originales = [for (final v in widget.yaSalieron) if (!v.esCopia) v];
    if (originales.isEmpty) return;
    // El próximo vale sigue al número más alto que salió.
    final mayor = originales.map((v) => v.numeroVale ?? 0).fold<int>(0, math.max);
    _valesImpresos = math.max(mayor, originales.length);
    for (final v in originales) {
      for (final b in v.bebidas) {
        var falta = b.cantidad;
        for (final s in _sillas) {
          if (falta == 0) break;
          if (s.renglon.nombre != b.nombre || s.terminada) continue;
          final va = falta < s.quedan ? falta : s.quedan;
          s.impresas += va;
          falta -= va;
        }
        for (final x in _bebidas) {
          if (falta == 0) break;
          if (x.renglon.nombre != b.nombre || x.terminada) continue;
          final va = falta < x.quedan ? falta : x.quedan;
          x.impresos.add(va);
          falta -= va;
        }
      }
    }
  }

  bool get _bebidasImpresas => _bebidas.every((b) => b.terminada);
  bool get _todoImpreso => _bebidasImpresas && _sillas.every((s) => s.terminada);

  @override
  void dispose() {
    for (final b in _bebidas) {
      b.valePor.dispose();
    }
    super.dispose();
  }

  /// Manda un vale y dice si salió. Mientras se imprime, no se puede tocar otro.
  Future<bool> _mandar(Vale vale) async {
    setState(() {
      _imprimiendo = true;
      _aviso = null;
    });
    bool salio;
    try {
      salio = await widget.imprimir(ModeloTicket.deVale(
        vale,
        venta: widget.venta,
        caja: widget.caja,
        fiesta: widget.fiesta,
      ));
    } catch (_) {
      salio = false;
    }
    if (salio && widget.anotar != null) {
      try {
        await widget.anotar!(vale);
      } catch (e) {
        debugPrint('⚠️ Barra: el vale salió pero no se pudo anotar: $e');
      }
    }
    if (!mounted) return salio;
    setState(() {
      _imprimiendo = false;
      if (salio) {
        _valesImpresos++;
        // Después del setState de quien imprimió, que descuenta lo que salió.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.alImprimir?.call(_todoImpreso);
        });
      } else {
        _aviso = widget.sinPapel?.call() == true
            ? kSinPapel
            : 'No salió el vale. ¿La impresora está prendida y cerca? Tocá de nuevo.';
      }
    });
    return salio;
  }

  /// Un vale con todo lo que queda. Si es el primero de la venta y no hay sillas, es el
  /// único: sin número.
  Future<void> _imprimirTodoJunto() async {
    if (_bebidasImpresas) return;
    final vale = _valesImpresos == 0 && _sillas.isEmpty
        ? Vale.todoJunto(widget.venta)
        : Vale.conLoQueQueda(
            [for (final b in _bebidas) BebidaDelVale(b.quedan, b.renglon.nombre)],
            numero: _valesImpresos + 1,
          );
    final llevo = [for (final b in _bebidas) b.quedan];
    if (await _mandar(vale) && mounted) {
      setState(() {
        for (var i = 0; i < _bebidas.length; i++) {
          if (llevo[i] > 0) _bebidas[i].impresos.add(llevo[i]);
          _bebidas[i].valePor.clear();
        }
      });
    }
  }

  /// Un vale de una bebida, por lo escrito en su casilla. Si sale, la casilla se vacía
  /// para el próximo; si no, queda como estaba para volver a mandarlo.
  Future<void> _imprimirVale(_Bebida b) async {
    if (b.terminada || !b.valido) return;
    final cantidad = b.proximo;
    final vale = Vale.deUnaBebida(b.renglon, cantidad: cantidad, numero: _valesImpresos + 1);
    if (await _mandar(vale) && mounted) {
      setState(() {
        b.impresos.add(cantidad);
        b.valePor.clear();
      });
    }
  }

  /// El vale de una silla. Si es lo único de la venta (una sola silla, sin bebidas), sin
  /// número.
  Future<void> _imprimirSilla(_Silla s) async {
    if (s.terminada) return;
    final unico = _bebidas.isEmpty && _sillas.length == 1 && s.renglon.cantidad == 1;
    final vale = Vale.deUnaSilla(s.renglon, numero: unico ? null : _valesImpresos + 1);
    if (await _mandar(vale) && mounted) {
      setState(() => s.impresas++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final v = widget.venta;
    final numero = 'Caja ${widget.caja.numeroCaja} · N° ${v.numero.toString().padLeft(4, '0')}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            // Con el recargo, como "Venta guardada" de arriba: decía el total sin el recargo
            // (recorrido con el mouse del 7-nov).
            Text('Cobrado ${pesos(v.cobrado)}', key: const Key('vales_cobrado'), style: tema.textTheme.titleMedium),
            Text(numero, style: tema.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _sillas.length; i++) _tarjetaSilla(tema, i),
        if (_bebidas.isNotEmpty) ...[
          Text('¿Cómo se imprime?', style: tema.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _botonForma(
                  _Forma.todoJunto,
                  'TODO JUNTO',
                  _valesImpresos == 0 && _sillas.isEmpty
                      ? 'Un vale con todo'
                      : 'Un vale con lo que queda',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _botonForma(_Forma.porSeparado, 'POR SEPARADO', 'Para ir retirando de a poco')),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_forma == _Forma.todoJunto) _todoJunto(tema),
        if (_forma == _Forma.porSeparado)
          for (var i = 0; i < _bebidas.length; i++) _sector(tema, i),
        if (_forma != null || _bebidas.isEmpty) ...[
          const SizedBox(height: 4),
          Text(_queFalta(), key: const Key('falta-imprimir'), style: tema.textTheme.bodySmall),
        ],
        if (_aviso != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_aviso!, style: TextStyle(color: tema.colorScheme.error)),
          ),
      ],
    );
  }

  Widget _botonForma(_Forma forma, String titulo, String detalle) {
    final elegida = _forma == forma;
    final colores = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: Key(forma == _Forma.todoJunto ? 'forma-todo-junto' : 'forma-por-separado'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        side: BorderSide(
          width: elegida ? 2 : 1,
          color: elegida ? colores.primary : Theme.of(context).dividerColor,
        ),
        backgroundColor: elegida ? colores.primaryContainer : null,
      ),
      onPressed: _imprimiendo ? null : () => setState(() => _forma = forma),
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(detalle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _todoJunto(ThemeData tema) {
    final queda = [
      for (final b in _bebidas)
        if (b.quedan > 0) '${b.quedan} ${b.renglon.nombre.toLowerCase()}',
    ].join(', ');
    return Card(
      color: _bebidasImpresas ? tema.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _bebidasImpresas
            ? _Listo(_sillas.isEmpty ? 'Todo impreso' : 'Las bebidas, impresas')
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    _valesImpresos == 0 && _sillas.isEmpty
                        ? 'Un solo vale: $queda'
                        : 'Un vale con lo que queda: $queda',
                    key: const Key('lo-que-queda'),
                  ),
                  FilledButton.icon(
                    key: const Key('imprimir-todo-junto'),
                    onPressed: _imprimiendo ? null : _imprimirTodoJunto,
                    icon: const Icon(Icons.print),
                    label: const Text('IMPRIMIR'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sector(ThemeData tema, int i) {
    final b = _bebidas[i];
    final r = b.renglon;
    final hechos = b.impresos.isEmpty
        ? null
        : '${b.impresos.length == 1 ? 'Salió 1 vale' : 'Salieron ${b.impresos.length} vales'}: '
            '${b.impresos.join(' · ')}';
    final Widget abajo;
    if (b.terminada) {
      abajo = _Listo('Todo en vales: ${b.impresos.join(' · ')}');
    } else {
      final detalle = !b.valido
          ? 'Va de 1 a ${b.quedan}'
          : hechos == null
              ? 'Quedan ${b.quedan}'
              : 'Quedan ${b.quedan} · $hechos';
      abajo = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 96,
            child: TextField(
              key: Key('vale-por-$i'),
              controller: b.valePor,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: 'vale por', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Text(
            detalle,
            key: Key('detalle-$i'),
            style: b.valido ? null : TextStyle(color: tema.colorScheme.error),
          ),
          FilledButton.icon(
            key: Key('imprimir-$i'),
            onPressed: _imprimiendo || !b.valido ? null : () => _imprimirVale(b),
            icon: const Icon(Icons.print),
            label: Text(!b.valido
                ? 'IMPRIMIR'
                : b.numero == null
                    ? 'IMPRIMIR LAS ${b.quedan}'
                    : 'IMPRIMIR VALE POR ${b.proximo}'),
          ),
        ],
      );
    }
    return Card(
      color: b.terminada ? tema.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${r.cantidad} ${r.nombre.toUpperCase()}',
              style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            abajo,
          ],
        ),
      ),
    );
  }

  /// Una silla de la venta: un vale por silla, que la familia lleva a la recepcionista.
  Widget _tarjetaSilla(ThemeData tema, int i) {
    final s = _sillas[i];
    final r = s.renglon;
    return Card(
      key: Key('silla-$i'),
      color: s.terminada ? tema.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${r.cantidad} ${r.nombre.toUpperCase()}',
              style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Un vale por silla: la familia lo lleva a la recepcionista.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (s.terminada)
              _Listo(r.cantidad == 1 ? 'Vale impreso' : 'Los ${r.cantidad} vales impresos')
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    r.cantidad == 1
                        ? 'Falta el vale'
                        : 'Salieron ${s.impresas} de ${r.cantidad}',
                    key: Key('detalle-silla-$i'),
                  ),
                  FilledButton.icon(
                    key: Key('imprimir-silla-$i'),
                    onPressed: _imprimiendo ? null : () => _imprimirSilla(s),
                    icon: const Icon(Icons.print),
                    label: Text(r.cantidad == 1
                        ? 'IMPRIMIR EL VALE'
                        : 'IMPRIMIR VALE ${s.impresas + 1} DE ${r.cantidad}'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _queFalta() {
    final faltan = [
      for (final s in _sillas)
        if (!s.terminada) s.renglon.nombre.toLowerCase(),
      for (final b in _bebidas)
        if (!b.terminada) b.renglon.nombre.toLowerCase(),
    ];
    return faltan.isEmpty ? 'Todo impreso' : 'Falta imprimir: ${faltan.join(', ')}';
  }
}

class _Listo extends StatelessWidget {
  final String texto;
  const _Listo(this.texto);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 6),
          Flexible(child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      );
}
