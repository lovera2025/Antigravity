import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cuentas/pesos.dart';
import '../cuentas/vales_de_barra.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/ticket_esc_pos.dart';

/// Manda un papel a la impresora. True si salió.
typedef ImprimirPapel = Future<bool> Function(List<LineaTicket> lineas);

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

/// Después de cobrar, cómo salen los vales de la venta (pedido del jefe, 3-nov). Se pasa
/// de una forma a la otra cuando se quiere:
/// - **TODO JUNTO**: un vale con todo lo que queda (al principio, toda la compra);
/// - **POR SEPARADO**: cada bebida con su casilla "vale por" y su IMPRIMIR. **Cada vale lo
///   arma la cajera:** escribe por cuánto, imprime, y la casilla queda vacía para el
///   próximo, hasta que no quede ninguna. Vacía, el vale es por todas las que quedan.
///
/// **Un vale por papel:** cada IMPRIMIR saca uno solo, nunca una tira. Lo que ya salió en
/// un vale no vuelve a salir: TODO JUNTO lleva solo lo que queda.
class ElegirVales extends StatefulWidget {
  final VentaBarra venta;
  final CajaBarra caja;
  final String fiesta;
  final ImprimirPapel imprimir;

  const ElegirVales({
    super.key,
    required this.venta,
    required this.caja,
    required this.fiesta,
    required this.imprimir,
  });

  @override
  State<ElegirVales> createState() => _ElegirValesState();
}

class _ElegirValesState extends State<ElegirVales> {
  _Forma? _forma;
  late final _bebidas = [for (final r in widget.venta.renglones) _Bebida(r)];

  /// Cuántos vales salieron de la venta: el próximo lleva el siguiente número.
  int _valesImpresos = 0;
  bool _imprimiendo = false;
  String? _aviso;

  bool get _todoImpreso => _bebidas.every((b) => b.terminada);

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
    if (!mounted) return salio;
    setState(() {
      _imprimiendo = false;
      if (salio) {
        _valesImpresos++;
      } else {
        _aviso = 'No salió el vale. ¿La impresora está prendida y cerca? Tocá de nuevo.';
      }
    });
    return salio;
  }

  /// Un vale con todo lo que queda. Si es el primero de la venta, es el único: sin número.
  Future<void> _imprimirTodoJunto() async {
    if (_todoImpreso) return;
    final vale = _valesImpresos == 0
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
            Text('Cobrado ${pesos(v.total)}', style: tema.textTheme.titleMedium),
            Text(numero, style: tema.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        Text('¿Cómo se imprime?', style: tema.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _botonForma(
                _Forma.todoJunto,
                'TODO JUNTO',
                _valesImpresos == 0 ? 'Un vale con todo' : 'Un vale con lo que queda',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _botonForma(_Forma.porSeparado, 'POR SEPARADO', 'Para ir retirando de a poco')),
          ],
        ),
        const SizedBox(height: 12),
        if (_forma == _Forma.todoJunto) _todoJunto(tema),
        if (_forma == _Forma.porSeparado)
          for (var i = 0; i < _bebidas.length; i++) _sector(tema, i),
        if (_forma != null) ...[
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
      color: _todoImpreso ? tema.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _todoImpreso
            ? const _Listo('Todo impreso')
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    _valesImpresos == 0 ? 'Un solo vale: $queda' : 'Un vale con lo que queda: $queda',
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

  String _queFalta() {
    final faltan = [
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
