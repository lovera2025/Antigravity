import 'package:flutter/material.dart';

import '../cuentas/stock_por_barra.dart';
import '../datos/barra_repositorio.dart';
import 'stock_de_la_fiesta.dart';
import 'texto_del_stock.dart';

/// Las ventanas del repositor (decididas por el usuario con la maqueta del 25-nov-2026):
/// REPONER, FALTANTE, ANOTAR LO QUE HAY y ENTRÓ MERCADERÍA.
///
/// **Ninguna guarda nada**: devuelven el movimiento armado y lo guarda STOCK, con su
/// llave. **Ninguna hace cuentas**: lo que se puede (no más de lo que hay en el depósito,
/// no más de lo que tiene una barra) y lo que falta lo dice [StockPorBarra].

const _ambar = Color(0xFFF2B84B);
const _rojo = Color(0xFFFF8F82);
const _gris = Color(0xFFA7A29A);

Widget _rotulo(String texto) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: _gris),
      ),
    );

/// Una opción entre varias, con chips.
class _Opciones<T> extends StatelessWidget {
  const _Opciones({
    required this.clave,
    required this.opciones,
    required this.elegida,
    required this.nombre,
    required this.alElegir,
  });

  final String clave;
  final List<T> opciones;
  final T? elegida;
  final String Function(T) nombre;
  final ValueChanged<T> alElegir;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < opciones.length; i++)
            ChoiceChip(
              key: Key('${clave}_$i'),
              label: Text(nombre(opciones[i])),
              selected: opciones[i] == elegida,
              onSelected: (_) => alElegir(opciones[i]),
            ),
        ],
      );
}

/// − 12 ＋, con atajos (+6 +12 +24).
class _Cuanto extends StatelessWidget {
  const _Cuanto({
    required this.clave,
    required this.valor,
    required this.alCambiar,
    this.atajos = const [],
    this.minimo = 0,
  });

  final String clave;
  final int valor;
  final ValueChanged<int> alCambiar;
  final List<int> atajos;
  final int minimo;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton.filledTonal(
            key: Key('${clave}_menos'),
            onPressed: valor > minimo ? () => alCambiar(valor - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$valor',
              key: Key('${clave}_valor'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton.filledTonal(
            key: Key('${clave}_mas'),
            onPressed: () => alCambiar(valor + 1),
            icon: const Icon(Icons.add),
          ),
          for (final n in atajos)
            OutlinedButton(
              key: Key('${clave}_mas_$n'),
              onPressed: () => alCambiar(valor + n),
              child: Text('+$n'),
            ),
        ],
      );
}

Widget _error(String? texto, {String clave = 'stock_error'}) => texto == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(texto, key: Key(clave), style: const TextStyle(color: _rojo, fontWeight: FontWeight.w700)),
      );

AlertDialog _ventana({
  required String titulo,
  required List<Widget> cuerpo,
  required String boton,
  required String claveBoton,
  required VoidCallback? alGuardar,
  required BuildContext context,
}) =>
    AlertDialog(
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cuerpo,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER')),
        FilledButton(key: Key(claveBoton), onPressed: alGuardar, child: Text(boton)),
      ],
    );

// ── REPONER ──────────────────────────────────────────────────────────────────

/// REPONER: qué, a qué barra, de dónde (del depósito, o de la otra barra diciendo por
/// qué) y cuánto; y abajo, cuántas quedan ahora en la barra (viene la cuenta; si contó
/// otra cosa, la corrige y dice qué pasó).
Future<MovimientoDeStock?> pedirReposicion(
  BuildContext context, {
  required StockDeLaFiesta datos,
  required DateTime Function() ahora,
  String? productoId,
  String? barra,
}) =>
    showDialog<MovimientoDeStock>(
      context: context,
      builder: (_) => _ReponerDialog(datos: datos, ahora: ahora, productoId: productoId, barra: barra),
    );

class _ReponerDialog extends StatefulWidget {
  const _ReponerDialog({required this.datos, required this.ahora, this.productoId, this.barra});

  final StockDeLaFiesta datos;
  final DateTime Function() ahora;
  final String? productoId;
  final String? barra;

  @override
  State<_ReponerDialog> createState() => _ReponerDialogState();
}

class _ReponerDialogState extends State<_ReponerDialog> {
  late String? _producto = widget.productoId ?? widget.datos.productos.firstOrNull;
  late String? _barra = widget.barra ?? widget.datos.barras.firstOrNull;
  bool _deOtraBarra = false;
  int _cantidad = 12;

  /// Lo que dejó dicho que queda. Null: la cuenta del programa.
  int? _quedan;
  String? _motivo;
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  StockPorBarra get _stock => widget.datos.stock;

  /// La otra barra, si hay dos.
  String? get _otra {
    for (final b in widget.datos.barras) {
      if (b != _barra) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    final p = _producto, b = _barra, otra = _otra;
    if (p == null || b == null) {
      return AlertDialog(
        title: const Text('REPONER'),
        content: const Text('El jefe todavía no repartió ningún producto entre las barras.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER'))],
      );
    }
    final deOtra = _deOtraBarra && otra != null;
    final enElDeposito = _stock.cuantoSePuedeReponer(p);
    final tenia = _stock.en(b, p)?.queda ?? 0;
    final cuenta = tenia + _cantidad;
    final contadas = _quedan ?? cuenta;
    // Lo contado menos lo que da la cuenta: lo dice la cuenta del stock.
    final ajuste = _stock.ajustePara(b, p, contadas, ademas: _cantidad);
    final porque = _nota.text;
    final error = (deOtra
            ? _stock.errorAlPasar(p, otra, b, _cantidad, porque)
            : _stock.errorAlReponer(p, b, _cantidad)) ??
        StockPorBarra.errorDelAjuste(ajuste, _motivo);
    final motivos = ajuste < 0 ? kMotivosQueFaltan : kMotivosQueSobran;

    MovimientoDeStock armar() {
      // Solo queda como un conteo si contó otra cosa: si deja la cuenta del programa, es
      // una reposición y nada más.
      final contado = ajuste != 0;
      final nota = porque.trim().isEmpty ? null : porque.trim();
      final responde = _stock.enCaminoDe(b, p)?.aviso.id;
      return deOtra
          ? MovimientoDeStock.traspaso(
              eventoId: d.eventoId,
              productoId: p,
              desdeBarra: otra,
              haciaBarra: b,
              cantidad: _cantidad,
              porque: porque,
              contadas: contado ? contadas : null,
              foto: contado ? _stock.fotoDe(b, p) : null,
              ajuste: contado ? ajuste : 0,
              motivo: contado ? _motivo : null,
              respondeA: responde,
              ahora: widget.ahora(),
            )
          : MovimientoDeStock.reposicion(
              eventoId: d.eventoId,
              productoId: p,
              barra: b,
              cantidad: _cantidad,
              contadas: contado ? contadas : null,
              foto: contado ? _stock.fotoDe(b, p) : null,
              ajuste: contado ? ajuste : 0,
              motivo: contado ? _motivo : null,
              nota: nota,
              respondeA: responde,
              ahora: widget.ahora(),
            );
    }

    return _ventana(
      context: context,
      titulo: 'REPONER',
      boton: 'GUARDAR',
      claveBoton: 'reponer_guardar',
      alGuardar: error == null ? () => Navigator.pop(context, armar()) : null,
      cuerpo: [
        _rotulo('QUÉ'),
        _Opciones<String>(
          clave: 'reponer_producto',
          opciones: d.productos,
          elegida: p,
          nombre: d.nombreDe,
          alElegir: (x) => setState(() {
            _producto = x;
            _quedan = null;
            _motivo = null;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${d.nombreDe(p)}: el jefe cargó ${d.generalDe(p) ?? 0} al principio · '
            'en el depósito ${enElDeposito == 1 ? 'queda 1' : 'quedan $enElDeposito'}.',
            key: const Key('reponer_del_jefe'),
            style: const TextStyle(fontSize: 13, color: _gris),
          ),
        ),
        _rotulo('A QUÉ BARRA'),
        _Opciones<String>(
          clave: 'reponer_barra',
          opciones: d.barras,
          elegida: b,
          nombre: (x) => x,
          alElegir: (x) => setState(() {
            _barra = x;
            _quedan = null;
            _motivo = null;
          }),
        ),
        if (otra != null) ...[
          _rotulo('DE DÓNDE'),
          _Opciones<bool>(
            clave: 'reponer_desde',
            opciones: const [false, true],
            elegida: deOtra,
            nombre: (x) => x ? 'De la $otra' : 'Del depósito',
            alElegir: (x) => setState(() => _deOtraBarra = x),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              deOtra
                  ? 'La $otra tiene ${_stock.cuantoSePuedePasar(otra, p)}: pasa de ahí a la $b.'
                  : 'Como mucho, lo que queda en el depósito ($enElDeposito).',
              style: const TextStyle(fontSize: 13, color: _gris),
            ),
          ),
        ],
        _rotulo('CUÁNTO'),
        _Cuanto(
          clave: 'reponer_cantidad',
          valor: _cantidad,
          minimo: 1,
          atajos: const [6, 12, 24],
          alCambiar: (n) => setState(() {
            _cantidad = n;
            _quedan = null;
            _motivo = null;
          }),
        ),
        _rotulo(deOtra ? '¿POR QUÉ? (HACE FALTA)' : 'NOTA (SI QUERÉS)'),
        TextField(
          key: const Key('reponer_nota'),
          controller: _nota,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: deOtra ? 'En la $otra casi no la piden…' : 'De dónde las saqué, algo para acordarse…',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        _rotulo('¿CUÁNTAS QUEDAN AHORA EN LA ${b.toUpperCase()}?'),
        _Cuanto(
          clave: 'reponer_quedan',
          valor: contadas < 0 ? 0 : contadas,
          alCambiar: (n) => setState(() {
            _quedan = n;
            _motivo = null;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            cuentaDeLaReposicion(tenia: tenia, trae: _cantidad),
            key: const Key('reponer_cuenta'),
            style: TextStyle(fontSize: 13, color: tenia < 0 ? _ambar : _gris),
          ),
        ),
        if (ajuste != 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              ajuste < 0
                  ? 'Contaste ${-ajuste} menos que la cuenta. ¿Qué pasó con ${-ajuste == 1 ? 'esa' : 'esas'}?'
                  : 'Contaste $ajuste más que la cuenta. ¿De dónde salieron?',
              key: const Key('reponer_no_da'),
              style: const TextStyle(color: _ambar, fontWeight: FontWeight.w700),
            ),
          ),
          _Opciones<String>(
            clave: 'reponer_motivo',
            opciones: motivos,
            elegida: _motivo,
            nombre: (x) => x,
            alElegir: (x) => setState(() => _motivo = x),
          ),
        ],
        _error(error, clave: 'reponer_error'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Al guardar, a las cajeras de la $b y a la encargada les sale el aviso de que se repuso.',
            style: const TextStyle(fontSize: 12, color: _gris),
          ),
        ),
      ],
    );
  }
}

// ── FALTANTE ─────────────────────────────────────────────────────────────────

/// FALTANTE: lo que falta y no es una venta (rota, congelada, vencida, se perdió u otro).
Future<MovimientoDeStock?> pedirFaltante(
  BuildContext context, {
  required StockDeLaFiesta datos,
  required DateTime Function() ahora,
  String? lugar,
}) =>
    showDialog<MovimientoDeStock>(
      context: context,
      builder: (_) => _FaltanteDialog(datos: datos, ahora: ahora, lugar: lugar),
    );

class _FaltanteDialog extends StatefulWidget {
  const _FaltanteDialog({required this.datos, required this.ahora, this.lugar});

  final StockDeLaFiesta datos;
  final DateTime Function() ahora;
  final String? lugar;

  @override
  State<_FaltanteDialog> createState() => _FaltanteDialogState();
}

class _FaltanteDialogState extends State<_FaltanteDialog> {
  late String? _producto = widget.datos.productos.firstOrNull;
  late String _lugar = widget.lugar ?? widget.datos.barras.firstOrNull ?? kDeposito;
  int _cantidad = 1;
  String? _motivo;
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    final p = _producto;
    final lugares = [...d.barras, kDeposito];
    final nota = _nota.text.trim();
    final error = p == null
        ? 'El jefe todavía no repartió ningún producto.'
        : d.stock.errorAlDescontar(p, _lugar, _cantidad, _motivo) ??
            (_motivo == 'Otro' && nota.isEmpty ? 'Contá qué pasó.' : null);
    return _ventana(
      context: context,
      titulo: 'FALTANTE',
      boton: 'GUARDAR EL FALTANTE',
      claveBoton: 'faltante_guardar',
      alGuardar: error != null || p == null
          ? null
          : () => Navigator.pop(
                context,
                MovimientoDeStock.faltante(
                  eventoId: d.eventoId,
                  productoId: p,
                  lugar: _lugar,
                  cantidad: _cantidad,
                  motivo: _motivo!,
                  nota: nota.isEmpty ? null : nota,
                  ahora: widget.ahora(),
                ),
              ),
      cuerpo: [
        _rotulo('QUÉ'),
        _Opciones<String>(
          clave: 'faltante_producto',
          opciones: d.productos,
          elegida: p,
          nombre: d.nombreDe,
          alElegir: (x) => setState(() => _producto = x),
        ),
        _rotulo('CUÁNTAS'),
        _Cuanto(
          clave: 'faltante_cantidad',
          valor: _cantidad,
          minimo: 1,
          alCambiar: (n) => setState(() => _cantidad = n),
        ),
        _rotulo('DE DÓNDE'),
        _Opciones<String>(
          clave: 'faltante_lugar',
          opciones: lugares,
          elegida: _lugar,
          nombre: nombreDelLugar,
          alElegir: (x) => setState(() => _lugar = x),
        ),
        _rotulo('POR QUÉ'),
        _Opciones<String>(
          clave: 'faltante_motivo',
          opciones: kMotivosQueFaltan,
          elegida: _motivo,
          nombre: (x) => x,
          alElegir: (x) => setState(() => _motivo = x),
        ),
        _rotulo(_motivo == 'Otro' ? 'NOTA (HACE FALTA)' : 'NOTA (SI QUERÉS)'),
        TextField(
          key: const Key('faltante_nota'),
          controller: _nota,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        _error(error, clave: 'faltante_error'),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'No es una venta: no cambia la plata de ninguna caja. Resta del stock y queda escrito con '
            'la hora y quién lo anotó.',
            style: TextStyle(fontSize: 12, color: _gris),
          ),
        ),
      ],
    );
  }
}

// ── ANOTAR LO QUE HAY ────────────────────────────────────────────────────────

/// ANOTAR LO QUE HAY en una barra o en el depósito: si no da la cuenta, pide el motivo.
Future<MovimientoDeStock?> pedirConteo(
  BuildContext context, {
  required StockDeLaFiesta datos,
  required DateTime Function() ahora,
  required String lugar,
}) =>
    showDialog<MovimientoDeStock>(
      context: context,
      builder: (_) => _ConteoDialog(datos: datos, ahora: ahora, lugar: lugar),
    );

class _ConteoDialog extends StatefulWidget {
  const _ConteoDialog({required this.datos, required this.ahora, required this.lugar});

  final StockDeLaFiesta datos;
  final DateTime Function() ahora;
  final String lugar;

  @override
  State<_ConteoDialog> createState() => _ConteoDialogState();
}

class _ConteoDialogState extends State<_ConteoDialog> {
  late String? _producto = widget.datos.en(widget.lugar).firstOrNull?.productoId;
  int? _contadas;
  String? _motivo;

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    final p = _producto;
    final productos = [for (final s in d.en(widget.lugar)) s.productoId];
    final hay = p == null ? 0 : (d.stock.en(widget.lugar, p)?.queda ?? 0);
    final contadas = _contadas ?? (hay < 0 ? 0 : hay);
    final ajuste = p == null ? 0 : d.stock.ajustePara(widget.lugar, p, contadas);
    final error = p == null ? 'Acá no se lleva el stock de ningún producto.' : StockPorBarra.errorDelAjuste(ajuste, _motivo);
    return _ventana(
      context: context,
      titulo: 'ANOTAR LO QUE HAY · ${nombreDelLugar(widget.lugar).toUpperCase()}',
      boton: 'GUARDAR',
      claveBoton: 'conteo_guardar',
      alGuardar: error != null || p == null
          ? null
          : () => Navigator.pop(
                context,
                MovimientoDeStock.conteo(
                  eventoId: d.eventoId,
                  productoId: p,
                  lugar: widget.lugar,
                  contadas: contadas,
                  foto: d.stock.fotoDe(widget.lugar, p),
                  ajuste: ajuste,
                  motivo: ajuste == 0 ? null : _motivo,
                  ahora: widget.ahora(),
                ),
              ),
      cuerpo: [
        _rotulo('QUÉ'),
        _Opciones<String>(
          clave: 'conteo_producto',
          opciones: productos,
          elegida: p,
          nombre: d.nombreDe,
          alElegir: (x) => setState(() {
            _producto = x;
            _contadas = null;
            _motivo = null;
          }),
        ),
        _rotulo('CUÁNTAS HAY'),
        _Cuanto(
          clave: 'conteo_contadas',
          valor: contadas,
          alCambiar: (n) => setState(() {
            _contadas = n;
            _motivo = null;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'La cuenta del programa da $hay.',
            key: const Key('conteo_cuenta'),
            style: const TextStyle(fontSize: 13, color: _gris),
          ),
        ),
        if (ajuste != 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              ajuste < 0
                  ? '${-ajuste == 1 ? 'Falta 1' : 'Faltan ${-ajuste}'}. ¿Qué pasó?'
                  : '${ajuste == 1 ? 'Sobra 1' : 'Sobran $ajuste'}. ¿De dónde salieron?',
              key: const Key('conteo_no_da'),
              style: const TextStyle(color: _ambar, fontWeight: FontWeight.w700),
            ),
          ),
          _Opciones<String>(
            clave: 'conteo_motivo',
            opciones: ajuste < 0 ? kMotivosQueFaltan : kMotivosQueSobran,
            elegida: _motivo,
            nombre: (x) => x,
            alElegir: (x) => setState(() => _motivo = x),
          ),
        ],
        _error(error, clave: 'conteo_error'),
      ],
    );
  }
}

// ── ENTRÓ MERCADERÍA ─────────────────────────────────────────────────────────

/// ENTRÓ MERCADERÍA al depósito: cuánto y de dónde vino (hace falta decirlo). Recién ahí
/// se puede reponer más.
Future<MovimientoDeStock?> pedirEntrada(
  BuildContext context, {
  required StockDeLaFiesta datos,
  required DateTime Function() ahora,
}) =>
    showDialog<MovimientoDeStock>(
      context: context,
      builder: (_) => _EntradaDialog(datos: datos, ahora: ahora),
    );

class _EntradaDialog extends StatefulWidget {
  const _EntradaDialog({required this.datos, required this.ahora});

  final StockDeLaFiesta datos;
  final DateTime Function() ahora;

  @override
  State<_EntradaDialog> createState() => _EntradaDialogState();
}

class _EntradaDialogState extends State<_EntradaDialog> {
  late String? _producto = widget.datos.productos.firstOrNull;
  int _cantidad = 12;
  final _deDonde = TextEditingController();

  @override
  void dispose() {
    _deDonde.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    final p = _producto;
    final error = p == null
        ? 'El jefe todavía no repartió ningún producto.'
        : StockPorBarra.errorAlEntrar(_cantidad, _deDonde.text);
    return _ventana(
      context: context,
      titulo: 'ENTRÓ MERCADERÍA',
      boton: 'GUARDAR',
      claveBoton: 'entrada_guardar',
      alGuardar: error != null || p == null
          ? null
          : () => Navigator.pop(
                context,
                MovimientoDeStock.entrada(
                  eventoId: d.eventoId,
                  productoId: p,
                  cantidad: _cantidad,
                  deDonde: _deDonde.text,
                  ahora: widget.ahora(),
                ),
              ),
      cuerpo: [
        _rotulo('QUÉ'),
        _Opciones<String>(
          clave: 'entrada_producto',
          opciones: d.productos,
          elegida: p,
          nombre: d.nombreDe,
          alElegir: (x) => setState(() => _producto = x),
        ),
        _rotulo('CUÁNTO ENTRÓ'),
        _Cuanto(
          clave: 'entrada_cantidad',
          valor: _cantidad,
          minimo: 1,
          atajos: const [6, 12, 24],
          alCambiar: (n) => setState(() => _cantidad = n),
        ),
        _rotulo('DE DÓNDE VINO (HACE FALTA)'),
        TextField(
          key: const Key('entrada_de_donde'),
          controller: _deDonde,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Lo trajo el proveedor, se compró en el súper…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        _error(error, clave: 'entrada_error'),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Suma al depósito: recién ahí se puede reponer más. El jefe lo ve.',
            style: TextStyle(fontSize: 12, color: _gris),
          ),
        ),
      ],
    );
  }
}
