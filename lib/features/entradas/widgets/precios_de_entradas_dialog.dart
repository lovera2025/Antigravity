import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../barra/cuentas/pesos.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/services/lugares_al_sorteo.dart';
import '../cuentas/precio_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import '../providers/entradas_providers.dart';

/// PRECIOS: el jefe pone el precio de la entrada de una fiesta (6.9.0).
/// Devuelve lo guardado, o null si se canceló.
///
/// **Solo en modo jefe**, con doble llave: quien lo abre ya preguntó, y
/// `_guardar` vuelve sin escribir si `esRolJefeProvider` da falso
/// (`test/solo_modo_jefe_test.dart`). [quien] es quién queda anotado.
///
/// [lugares]: lo que cada familia tenía al sorteo, para decir a qué le toca el
/// descuento (17-nov-2026). En una fiesta sorteada antes de esa regla,
/// [revisarLugares] abre la lista para aceptar y devuelve cómo quedó (null si
/// no cambió nada). La lista no vive acá: lee los alumnos y sus pagos, que la
/// venta de entradas no toca.
Future<ConfigEntradas?> mostrarPreciosDeEntradas(
  BuildContext context, {
  required String eventoId,
  required String fiesta,
  required String quien,
  FotoDeLosLugares? lugares,
  RevisarLugares? revisarLugares,
}) =>
    showDialog<ConfigEntradas>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PreciosDeEntradasDialog(
        eventoId: eventoId,
        fiesta: fiesta,
        quien: quien,
        lugares: lugares,
        revisarLugares: revisarLugares,
      ),
    );

/// Abre la lista de los lugares agregados después del sorteo. Devuelve lo que
/// rige después, o null si no cambió nada.
typedef RevisarLugares = Future<FotoDeLosLugares?> Function(
  BuildContext context,
);

class PreciosDeEntradasDialog extends ConsumerStatefulWidget {
  final String eventoId;
  final String fiesta;
  final String quien;
  final FotoDeLosLugares? lugares;
  final RevisarLugares? revisarLugares;

  const PreciosDeEntradasDialog({
    super.key,
    required this.eventoId,
    required this.fiesta,
    required this.quien,
    this.lugares,
    this.revisarLugares,
  });

  @override
  ConsumerState<PreciosDeEntradasDialog> createState() =>
      _PreciosDeEntradasDialogState();
}

class _PreciosDeEntradasDialogState
    extends ConsumerState<PreciosDeEntradasDialog> {
  final _valor = TextEditingController();
  final _anticipada = TextEditingController();
  final _hasta = TextEditingController();
  final _lugares = TextEditingController();
  final _recargo = TextEditingController();
  bool _aMano = false;

  /// Lo que había guardado (o una vacía): de ahí salen el id y cuándo nació.
  ConfigEntradas? _base;
  bool _cargando = true;
  bool _guardando = false;
  String? _problema;

  /// Lo que cada familia tenía al sorteo: cambia si acá se acepta la lista.
  FotoDeLosLugares? _lugaresAlSorteo;

  @override
  void initState() {
    super.initState();
    _lugaresAlSorteo = widget.lugares;
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_valor, _anticipada, _hasta, _lugares, _recargo]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _entero(double? v) =>
      v == null || v <= 0 ? '' : v.round().toString();

  static String _porcentaje(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v'.replaceAll('.', ',');

  Future<void> _cargar() async {
    ConfigEntradas? guardada;
    try {
      guardada = await ref.read(entradasDelJefeProvider).config(widget.eventoId);
    } catch (_) {
      guardada = null;
    }
    if (!mounted) return;
    final c = guardada ??
        ConfigEntradas.vacia(widget.eventoId, ahora: DateTime.now());
    setState(() {
      _base = c;
      _valor.text = _entero(c.valorEntrada);
      _anticipada.text = _entero(c.precioAnticipada);
      _hasta.text = PrecioDeEntradas.textoDelDia(c.anticipadaHasta);
      _lugares.text = _porcentaje(c.descuentoLugaresPct);
      _recargo.text = _porcentaje(c.recargoPct);
      _aMano = c.descuentoAMano;
      _cargando = false;
    });
  }

  /// Los pesos de un casillero. Null: vacío.
  static double? _pesos(String texto) {
    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    return digitos.isEmpty ? null : double.tryParse(digitos);
  }

  /// El porcentaje de un casillero. Null: no es un número. Vacío es 0.
  static double? _pct(String texto) {
    final t = texto.trim().replaceAll(',', '.');
    return t.isEmpty ? 0 : double.tryParse(t);
  }

  /// "Cada una: $ 5.000", con lo que hay escrito. Null si todavía no se puede
  /// calcular.
  String? get _cadaUna {
    final valor = _pesos(_valor.text);
    final pct = _pct(_lugares.text);
    if (valor == null || valor <= 0 || pct == null || pct < 0 || pct > 100) {
      return null;
    }
    return 'Cada una: ${pesos(RenglonEntradas.precioCon(valor, pct))}';
  }

  /// Qué está mal en lo escrito, en palabras. Null: se puede guardar.
  String? _loQueFalta() {
    final valor = _pesos(_valor.text) ?? 0;
    final anticipada = _pesos(_anticipada.text) ?? 0;
    final hasta = _hasta.text.trim();
    if ((anticipada > 0) != hasta.isNotEmpty) {
      return 'La anticipada lleva su precio y hasta qué día: poné las dos '
          'cosas o ninguna.';
    }
    if (hasta.isNotEmpty && PrecioDeEntradas.diaDeTexto(hasta) == null) {
      return 'Ese día no existe: escribilo como 28/11/2026.';
    }
    if (anticipada > 0 && valor <= 0) {
      return 'Para la anticipada, primero poné el valor de la entrada.';
    }
    final lugares = _pct(_lugares.text);
    if (lugares == null || lugares < 0 || lugares > 100) {
      return 'El porcentaje de la mesa adicional y las sillas extra va de 0 a 100.';
    }
    final recargo = _pct(_recargo.text);
    if (recargo == null || recargo < 0 || recargo > 100) {
      return 'El recargo va de 0 a 100.';
    }
    return null;
  }

  /// La segunda llave: sin modo jefe no se guarda, aunque alguien llegue hasta
  /// acá con el botón apagado.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    setState(() => _problema = '$kSoloEnModoJefe: los precios los pone el jefe.');
    return true;
  }

  Future<void> _guardar() async {
    if (_frenaSinModoJefe()) return;
    final base = _base;
    if (base == null) return;
    final falta = _loQueFalta();
    if (falta != null) {
      setState(() => _problema = falta);
      return;
    }
    setState(() {
      _guardando = true;
      _problema = null;
    });
    try {
      final hasta = _hasta.text.trim();
      final nueva = base.conPrecios(
        valorEntrada: _pesos(_valor.text),
        precioAnticipada: _pesos(_anticipada.text),
        anticipadaHasta:
            hasta.isEmpty ? null : PrecioDeEntradas.diaDeTexto(hasta),
        descuentoLugaresPct: _pct(_lugares.text)!,
        recargoPct: _pct(_recargo.text)!,
        descuentoAMano: _aMano,
      );
      final guardada = await ref
          .read(entradasDelJefeProvider)
          .guardarConfig(nueva, quien: widget.quien);
      ref.invalidate(configDeEntradasProvider(widget.eventoId));
      avisarQueCambioLaVenta(ref, widget.eventoId);
      if (mounted) Navigator.pop(context, guardada);
    } on ArgumentError {
      if (mounted) {
        setState(() {
          _guardando = false;
          _problema = 'Revisá los precios: algo no cierra.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _problema = 'No se pudieron guardar los precios. Probá de nuevo.';
        });
      }
    }
  }

  Future<void> _elegirDia() async {
    final hoy = DateTime.now();
    final escrito = PrecioDeEntradas.diaDeTexto(_hasta.text);
    final elegido = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(escrito ?? '') ?? hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
      helpText: 'La anticipada, hasta el día',
    );
    if (elegido == null || !mounted) return;
    setState(() {
      _hasta.text =
          PrecioDeEntradas.textoDelDia(ConfigEntradas.diaDe(elegido));
      _problema = null;
    });
  }

  Future<void> _revisarLugares() async {
    final revisar = widget.revisarLugares;
    if (revisar == null) return;
    final nueva = await revisar(context);
    if (nueva != null && mounted) setState(() => _lugaresAlSorteo = nueva);
  }

  /// A qué le toca el descuento de los lugares en esta fiesta.
  Widget? _notaDeLosLugares(TextStyle ayuda) {
    final foto = _lugaresAlSorteo;
    if (foto == null) return null;
    switch (foto.estado) {
      case EstadoDeLosLugares.sinSorteo:
        return Text(
          'Vale para lo que cada familia tenga cargado el día del sorteo. Lo '
          'que agregue después paga la entrada entera.',
          key: const Key('precio_lugares_sin_sorteo'),
          style: ayuda,
        );
      case EstadoDeLosLugares.anotados:
        final del = foto.del ?? foto.sorteoEl;
        return Text(
          'Vale para lo que cada familia tenía cargado al sorteo'
          '${del == null ? '' : ' del ${ArTime.formatFechaHora(del)}'}. Lo '
          'que agregó después paga la entrada entera.',
          key: const Key('precio_lugares_anotados'),
          style: ayuda,
        );
      case EstadoDeLosLugares.sinAnotar:
        final color = Theme.of(context).colorScheme.error;
        return Column(
          key: const Key('precio_lugares_sin_revisar'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta fiesta se sorteó antes de la regla "lo que se agrega '
              'después del sorteo paga la entrada entera". Hasta que aceptes '
              'la lista, todo va con descuento.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (widget.revisarLugares != null)
              TextButton(
                key: const Key('precio_revisar_lugares'),
                onPressed: _guardando ? null : _revisarLugares,
                child: const Text('REVISAR LA LISTA'),
              ),
          ],
        );
    }
  }

  Widget _plata(String clave, TextEditingController c, String rotulo) =>
      TextField(
        key: Key(clave),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: rotulo, prefixText: r'$ '),
        onChanged: (_) => setState(() => _problema = null),
      );

  Widget _porciento(String clave, TextEditingController c, String rotulo) =>
      TextField(
        key: Key(clave),
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(labelText: rotulo, suffixText: '%'),
        onChanged: (_) => setState(() => _problema = null),
      );

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final gris = Theme.of(context).hintColor;
    final ayuda = TextStyle(fontSize: 12, color: gris);
    final sinPrecio = (_pesos(_valor.text) ?? 0) <= 0;
    final cadaUna = _cadaUna;
    final notaDeLosLugares = _notaDeLosLugares(ayuda);

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Precios de las entradas'),
          Text(
            widget.fiesta,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: gris),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _cargando
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _plata('precio_valor', _valor, 'Valor de la entrada'),
                    if (sinPrecio)
                      Padding(
                        key: const Key('precio_sin_valor'),
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Sin precio, esta fiesta no se puede vender.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _plata(
                            'precio_anticipada',
                            _anticipada,
                            'Anticipada (opcional)',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('precio_hasta'),
                            controller: _hasta,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: 'hasta el día',
                              hintText: 'dd/mm/aaaa',
                              suffixIcon: IconButton(
                                tooltip: 'Elegir el día',
                                icon: const Icon(Icons.event),
                                onPressed: _elegirDia,
                              ),
                            ),
                            onChanged: (_) => setState(() => _problema = null),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Las dos cosas o ninguna. El último día rige entero.',
                        style: ayuda,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Entradas de la mesa adicional y las sillas extra',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 200,
                          child: _porciento(
                            'precio_lugares',
                            _lugares,
                            'Descuento',
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (cadaUna != null)
                          Expanded(
                            child: Text(
                              cadaUna,
                              key: const Key('precio_cada_una'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Siempre sobre el valor de la entrada, nunca sobre la '
                        'anticipada.',
                        style: ayuda,
                      ),
                    ),
                    if (notaDeLosLugares != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: notaDeLosLugares,
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 250,
                      child: _porciento(
                        'precio_recargo',
                        _recargo,
                        'Recargo por transferencia',
                      ),
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      key: const Key('precio_a_mano'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _aMano,
                      onChanged: (v) => setState(() => _aMano = v ?? false),
                      title: const Text('El vendedor puede poner descuentos'),
                      subtitle: const Text('Destildado: solo en modo jefe.'),
                    ),
                    Text(
                      'Cambiar el precio no toca ninguna venta hecha.',
                      style: ayuda,
                    ),
                    if (_problema != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _problema!,
                          key: const Key('precios_problema'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('precios_cancelar'),
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        Tooltip(
          message: esJefe ? 'Guardar los precios' : kSoloEnModoJefe,
          child: FilledButton(
            key: const Key('precios_guardar'),
            onPressed: !esJefe || _cargando || _guardando ? null : _guardar,
            child: const Text('GUARDAR'),
          ),
        ),
      ],
    );
  }
}
