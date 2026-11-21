import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/cuentas/pesos.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/texto_busqueda.dart';
import '../cuentas/para_rendir.dart';
import '../cuentas/precio_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import 'para_rendir_comun.dart';

/// Lo que se eligió en RENDIR: de qué bloque, cuántas vendió (con su plata),
/// cuántas devuelve sin vender (con sus números) y cómo paga lo vendido.
/// [medio] null: solo devuelve (GUARDAR LA DEVOLUCIÓN), sin caja ni plata.
class PedidoDeRendicion {
  final BloqueParaRendir bloque;
  final int vendidas;
  final int devueltas;
  final List<TramoTalonario> numerosDevueltos;
  final MedioBarra? medio;

  const PedidoDeRendicion({
    required this.bloque,
    required this.vendidas,
    required this.devueltas,
    required this.numerosDevueltos,
    required this.medio,
  });

  /// El renglón de la venta: al precio y con el nombre del día en que se las
  /// llevó (`ParaRendir.renglon`, lo mismo que guarda el repositorio).
  RenglonEntradas get renglon => ParaRendir.renglon(bloque, vendidas);

  /// Lo que se cobra: lo vendido al precio del bloque, sin recargo.
  double get aCobrar => vendidas < 1 ? 0 : renglon.subtotal;
}

/// RENDIR, desde el aviso de VENDER (21-nov-2026, sección 5 de la SPEC): se
/// busca a quien rinde, se carga cuántas vendió y cuántas devuelve sin vender
/// (con los números propuestos), y se elige cómo paga lo vendido, o GUARDAR LA
/// DEVOLUCIÓN si solo devuelve.
///
/// **No escribe nada**: devuelve lo elegido (o null si se volvió) y VENDER
/// guarda, con su llave (`_rendir`). Lo que puede y no puede, con las palabras
/// de quien la usa, lo dice `ParaRendir.errorAlRendir`; acá no hay otra cuenta.
///
/// [hayCaja]: si quien cobra tiene la caja abierta. Sin ella, lo vendido pide
/// ABRIR LA CAJA, que abre la de VENDER ([abrirLaCaja], que dice si quedó
/// abierta). [inicial]: lo que se había cargado, si se vuelve del cobro sin
/// confirmar. [config] y [hoyAr]: para avisar si hoy rige otro precio.
///
/// En la PC es una ventana al centro; en el celular, una hoja desde abajo.
Future<PedidoDeRendicion?> mostrarRendirEntradas(
  BuildContext context, {
  required ParaRendir cuenta,
  required bool hayCaja,
  required Future<bool> Function() abrirLaCaja,
  Map<String, String> divisiones = const {},
  ConfigEntradas? config,
  DateTime? hoyAr,
  PedidoDeRendicion? inicial,
}) {
  final hoja = RendirEntradasHoja(
    cuenta: cuenta,
    hayCaja: hayCaja,
    abrirLaCaja: abrirLaCaja,
    divisiones: divisiones,
    config: config,
    hoyAr: hoyAr,
    inicial: inicial,
  );
  if (CortesPantalla.esCelular(MediaQuery.sizeOf(context).width)) {
    return showModalBottomSheet<PedidoDeRendicion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => hoja,
    );
  }
  return showDialog<PedidoDeRendicion>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: hoja),
    ),
  );
}

class RendirEntradasHoja extends StatefulWidget {
  const RendirEntradasHoja({
    super.key,
    required this.cuenta,
    required this.hayCaja,
    required this.abrirLaCaja,
    this.divisiones = const {},
    this.config,
    this.hoyAr,
    this.inicial,
  });

  final ParaRendir cuenta;
  final bool hayCaja;
  final Future<bool> Function() abrirLaCaja;
  final Map<String, String> divisiones;
  final ConfigEntradas? config;
  final DateTime? hoyAr;
  final PedidoDeRendicion? inicial;

  @override
  State<RendirEntradasHoja> createState() => _RendirEntradasHojaState();
}

class _RendirEntradasHojaState extends State<RendirEntradasHoja> {
  final _buscar = TextEditingController();
  final _del = TextEditingController();
  final _al = TextEditingController();
  final _del2 = TextEditingController();

  BloqueParaRendir? _bloque;
  int _vendidas = 0;
  int _devueltas = 0;
  bool _dosTramos = false;

  /// Quien cobra escribió los números de lo que devuelve: ya no se le
  /// proponen otros.
  bool _numerosTocados = false;
  late bool _hayCaja = widget.hayCaja;
  bool _abriendo = false;

  /// Los que tienen algo para rendir: los bloques en pie con algo sin rendir.
  List<BloqueParaRendir> get _conAlgo => [
        for (final b in widget.cuenta.bloques)
          if (!b.anulado && b.sinRendir > 0) b,
      ];

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    if (i != null) {
      // Lo que se había cargado, con el bloque como está ahora.
      _bloque = widget.cuenta.bloque(i.bloque.id) ?? i.bloque;
      _vendidas = i.vendidas;
      _devueltas = i.devueltas;
      _ponerNumeros(i.numerosDevueltos);
      _numerosTocados = true;
    } else if (_conAlgo.length == 1) {
      // Uno solo: ya viene elegido.
      _bloque = _conAlgo.single;
    }
  }

  @override
  void dispose() {
    for (final c in [_buscar, _del, _al, _del2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _elegir(BloqueParaRendir b) => setState(() {
        _bloque = b;
        _vendidas = 0;
        _devueltas = 0;
        _numerosTocados = false;
        _ponerNumeros(const []);
      });

  void _ponerNumeros(List<TramoTalonario> tramos) {
    _dosTramos = tramos.length == 2;
    _del.text = tramos.isEmpty || tramos.length > 2 ? '' : '${tramos.first.desde}';
    _al.text = _dosTramos ? '${tramos.first.hasta}' : '';
    _del2.text = _dosTramos ? '${tramos.last.desde}' : '';
  }

  /// Con cada cambio de lo que devuelve, los números propuestos: los últimos
  /// que todavía tiene. Si quien cobra ya los escribió, no se tocan.
  void _proponer() {
    final b = _bloque;
    if (b == null || _numerosTocados) return;
    _ponerNumeros(ParaRendir.proponerDevueltos(b, _devueltas));
  }

  /// Los números escritos de lo que devuelve. Con un solo tramo, el "al" sale
  /// solo, como en la entrega y en VENDER.
  List<TramoTalonario> get _tramos {
    if (_devueltas < 1) return const [];
    final del = int.tryParse(_del.text.trim());
    if (del == null) return const [];
    if (!_dosTramos) return [TramoTalonario(del, del + _devueltas - 1)];
    final al = int.tryParse(_al.text.trim());
    if (al == null) return [TramoTalonario(del, del)];
    final primero = TramoTalonario(del, al);
    final resto = _devueltas - primero.cantidad;
    final del2 = int.tryParse(_del2.text.trim());
    if (del2 == null || resto < 1) return [primero];
    return [primero, TramoTalonario(del2, del2 + resto - 1)];
  }

  String? get _error {
    final b = _bloque;
    if (b == null) return 'Elegí a quien rinde.';
    return ParaRendir.errorAlRendir(
      b,
      vendidas: _vendidas,
      devueltas: _devueltas,
      numerosDevueltos: _tramos,
      hayCaja: _hayCaja,
    );
  }

  Future<void> _abrirLaCaja() async {
    setState(() => _abriendo = true);
    final abierta = await widget.abrirLaCaja();
    if (!mounted) return;
    setState(() {
      _abriendo = false;
      _hayCaja = _hayCaja || abierta;
    });
  }

  void _listo(MedioBarra? medio) {
    final b = _bloque;
    if (b == null || _error != null) return;
    Navigator.of(context).pop(PedidoDeRendicion(
      bloque: b,
      vendidas: _vendidas,
      devueltas: _devueltas,
      numerosDevueltos: _tramos,
      medio: _vendidas > 0 ? medio : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final b = _bloque;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          key: const Key('rendir_hoja'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rendir entradas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ..._quien(),
            if (b != null) ...[
              const SizedBox(height: 10),
              _tarjeta(b),
              ?_otroPrecio(b),
              const SizedBox(height: 12),
              _cuantas(b),
              if (_devueltas > 0) ...[
                const SizedBox(height: 12),
                _numeros(),
              ],
              const SizedBox(height: 10),
              ..._pie(b),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('rendir_volver'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('VOLVER'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El buscador y la lista de quienes tienen algo para rendir.
  List<Widget> _quien() {
    final todos = _conAlgo;
    if (todos.isEmpty) {
      return [
        Text(
          'Nadie tiene entradas para rendir.',
          key: const Key('rendir_nadie'),
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ];
    }
    // Una persona con dos bloques sale dos veces: los números las distinguen.
    final q = _buscar.text.trim();
    final lista = [
      for (final x in todos)
        if (q.isEmpty || coincideTextoBusqueda([x.persona, x.contacto], q)) x,
    ];
    final seleccion = Theme.of(context).colorScheme.secondaryContainer;
    return [
      TextField(
        key: const Key('rendir_buscar'),
        controller: _buscar,
        decoration: const InputDecoration(
          labelText: 'Buscar a quien rinde',
          hintText: 'Apellido',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 6),
      if (lista.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Nadie con ese nombre tiene entradas sin rendir.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, x) in lista.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Material(
                  color: x.id == _bloque?.id ? seleccion : Colors.transparent,
                  child: InkWell(
                    key: Key('rendir_bloque_${x.id}'),
                    onTap: () => _elegir(x),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: x.persona,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: ' · le quedan ${x.sinRendir} · '
                                  'del ${TramoTalonario.legible(x.tramos)}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// "PÉREZ, JUAN · de afuera — se llevó 20 el lun 16/11 · del 1201 al 1220 ·
  /// Entrada anticipada · le quedan 20".
  Widget _tarjeta(BloqueParaRendir b) => Container(
        key: const Key('rendir_tarjeta'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0x14D4AF37),
          border: Border.all(color: const Color(0x80D4AF37)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  b.persona,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                ChipDeQuienLleva(
                  esAlumno: b.esDeUnAlumno,
                  division: widget.divisiones[b.contratoAlumnoId],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${seLlevoParaRendir(b)} · ${nombreDelPrecioParaRendir(b.nombrePrecio)} · '
              'le quedan ${b.sinRendir}',
              key: const Key('rendir_tarjeta_texto'),
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ],
        ),
      );

  /// Si hoy la entrada vale otra cosa: rinde igual al precio del día en que se
  /// las llevó.
  Widget? _otroPrecio(BloqueParaRendir b) {
    final hoy = widget.hoyAr;
    if (hoy == null) return null;
    final deHoy = PrecioDeEntradas.deHoy(widget.config, hoy);
    if (deHoy == null || centavos(deHoy) == centavos(b.precioDeCadaUna)) return null;
    return Padding(
      key: const Key('rendir_otro_precio'),
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Se las llevó a ${pesos(b.precioDeCadaUna)} '
        '(${nombreDelPrecioParaRendir(b.nombrePrecio).toLowerCase()}): rinde a ese '
        'precio, aunque hoy la entrada valga ${pesos(deHoy)}.',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6D5A10),
        ),
      ),
    );
  }

  /// Vendió · Devuelve sin vender · Le quedan.
  Widget _cuantas(BloqueParaRendir b) {
    final lleno = _vendidas + _devueltas >= b.sinRendir;
    final quedan = (b.sinRendir - _vendidas - _devueltas).clamp(0, b.sinRendir);
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _Contador(
          clave: 'rendir_vendio',
          rotulo: 'Vendió',
          valor: _vendidas,
          puedeSumar: !lleno,
          alCambiar: (n) => setState(() => _vendidas = n),
        ),
        _Contador(
          clave: 'rendir_devuelve',
          rotulo: 'Devuelve sin vender',
          valor: _devueltas,
          puedeSumar: !lleno,
          alCambiar: (n) => setState(() {
            _devueltas = n;
            _proponer();
          }),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Le quedan', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            // Del alto de los botones de al lado, así el número queda a la
            // altura de los otros dos.
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerLeft,
                // Sin esto ocupa todo el ancho y baja de renglón.
                widthFactor: 1,
                child: Text(
                  '$quedan',
                  key: const Key('rendir_le_quedan'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Los números de lo que devuelve: vienen propuestos (los últimos que todavía
  /// tiene); se pueden cambiar.
  Widget _numeros() {
    Widget campo(String clave, TextEditingController c, String rotulo) => SizedBox(
          width: 110,
          child: TextField(
            key: Key(clave),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: rotulo, isDense: true),
            onChanged: (_) => setState(() => _numerosTocados = true),
          ),
        );
    final tramos = _tramos;
    final ultimo = tramos.isEmpty ? null : tramos.last;
    final al = Text(
      ultimo == null || (_dosTramos && tramos.length < 2) ? 'al …' : 'al ${ultimo.hasta}',
      key: const Key('rendir_al_calculado'),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Números de las que devuelve (vienen propuestos)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            campo('rendir_del', _del, 'Del'),
            if (!_dosTramos) al,
            if (_dosTramos) ...[
              campo('rendir_al', _al, 'Al'),
              campo('rendir_del_2', _del2, 'Del'),
              al,
            ],
            TextButton(
              key: const Key('rendir_dos_tramos'),
              onPressed: () => setState(() {
                _dosTramos = !_dosTramos;
                _numerosTocados = true;
                _al.clear();
                _del2.clear();
              }),
              child: Text(_dosTramos ? 'Un solo tramo' : 'Saltan: dos tramos'),
            ),
          ],
        ),
      ],
    );
  }

  /// Lo de abajo: el error, "A cobrar" con los medios (o ABRIR LA CAJA), o
  /// GUARDAR LA DEVOLUCIÓN si solo devuelve.
  List<Widget> _pie(BloqueParaRendir b) {
    final error = _error;
    final sinCaja = _vendidas > 0 && !_hayCaja;
    // Mientras no cargó nada es una guía, no un error: en gris, como "falta
    // quién compra" en VENDER.
    final color = _vendidas + _devueltas == 0
        ? Colors.grey.shade700
        : Theme.of(context).colorScheme.error;
    final hijos = <Widget>[
      // Sin caja, el aviso de abajo ya lo dice: no se repite en rojo.
      if (error != null && !(sinCaja && error == 'Para cobrar lo vendido, abrí la caja.'))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            error,
            key: const Key('rendir_error'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
          ),
        ),
    ];
    if (_vendidas < 1) {
      hijos.add(Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          key: const Key('rendir_guardar_devolucion'),
          onPressed: error == null ? () => _listo(null) : null,
          child: const Text('GUARDAR LA DEVOLUCIÓN'),
        ),
      ));
      return hijos;
    }
    if (sinCaja) {
      final naranja = Colors.orange.shade800;
      hijos.add(Container(
        key: const Key('rendir_sin_caja'),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: naranja.withValues(alpha: 0.08),
          border: Border.all(color: naranja.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Para cobrar lo vendido, abrí la caja.',
                style: TextStyle(fontWeight: FontWeight.w700, color: naranja),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('rendir_abrir_caja'),
              onPressed: _abriendo ? null : _abrirLaCaja,
              child: const Text('ABRIR LA CAJA'),
            ),
          ],
        ),
      ));
      return hijos;
    }
    final renglon = ParaRendir.renglon(b, _vendidas);
    hijos.addAll([
      const Divider(thickness: 2, color: Color(0x80D4AF37)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              'A cobrar: $_vendidas × ${pesos(renglon.precio)}',
              key: const Key('rendir_a_cobrar'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            pesos(renglon.subtotal),
            key: const Key('rendir_total'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, caja) {
          final medios = [
            ('rendir_efectivo', 'EFECTIVO', MedioBarra.efectivo),
            ('rendir_transferencia', 'TRANSFERENCIA', MedioBarra.transferencia),
            ('rendir_mixto', 'MIXTO', MedioBarra.mixto),
          ];
          Widget boton(String clave, String texto, MedioBarra medio) => FilledButton(
                key: Key(clave),
                onPressed: error == null ? () => _listo(medio) : null,
                child: Text(texto),
              );
          // En un celular, uno debajo del otro, como en VENDER. (La ventana de
          // la PC mide menos que el corte de VENDER: acá se mira su ancho.)
          if (caja.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (clave, texto, medio) in medios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: boton(clave, texto, medio),
                  ),
              ],
            );
          }
          return Row(
            children: [
              for (final (clave, texto, medio) in medios)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: boton(clave, texto, medio),
                  ),
                ),
            ],
          );
        },
      ),
    ]);
    return hijos;
  }
}

/// − cantidad + con su rótulo arriba.
class _Contador extends StatelessWidget {
  const _Contador({
    required this.clave,
    required this.rotulo,
    required this.valor,
    required this.puedeSumar,
    required this.alCambiar,
  });

  final String clave;
  final String rotulo;
  final int valor;
  final bool puedeSumar;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('${clave}_menos'),
                tooltip: 'Una menos',
                onPressed: valor <= 0 ? null : () => alCambiar(valor - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$valor',
                  key: Key('${clave}_cantidad'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: Key('${clave}_mas'),
                tooltip: 'Una más',
                onPressed: puedeSumar ? () => alCambiar(valor + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      );
}
