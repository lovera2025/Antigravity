import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/evento.dart';
import '../../barra/cuentas/pesos.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/services/lugares_al_sorteo.dart';
import '../cuentas/eleccion_de_precios.dart';
import '../cuentas/precio_de_entradas.dart';
import '../cuentas/precios_en_otras_fiestas.dart';
import '../datos/entradas_repositorio.dart';
import '../providers/entradas_providers.dart';
import 'precios_en_otras_fiestas_dialog.dart';

/// PRECIOS: el jefe pone el precio de la entrada de una fiesta (6.9.0; desde la
/// 6.9.3, primero "¿Qué se vende ahora? Anticipada · General" y sin nada
/// opcional). Devuelve lo guardado, o null si se canceló.
///
/// **Solo en modo jefe**, con doble llave: quien lo abre ya preguntó, y
/// `_guardar` vuelve sin escribir si `esRolJefeProvider` da falso
/// (`test/solo_modo_jefe_test.dart`). [quien] es quién queda anotado.
///
/// [fechaFiesta]: el día de la fiesta, para proponer hasta cuándo vale la
/// anticipada (el día anterior). Sin ella no se propone ninguno.
///
/// [lugares]: lo que cada familia tenía al sorteo, para decir a qué le toca el
/// descuento (17-nov-2026). En una fiesta sorteada antes de esa regla,
/// [revisarLugares] abre la lista para aceptar y devuelve cómo quedó (null si
/// no cambió nada). La lista no vive acá: lee los alumnos y sus pagos, que la
/// venta de entradas no toca.
///
/// [otrasFiestas] (22-nov-2026): las fiestas que vienen. Guardado, si hay otras,
/// salta "¿Poner estos precios también en otras fiestas?"
/// ([mostrarPreciosEnOtrasFiestas]); la de acá se saca sola de la lista.
Future<ConfigEntradas?> mostrarPreciosDeEntradas(
  BuildContext context, {
  required String eventoId,
  required String fiesta,
  required String quien,
  DateTime? fechaFiesta,
  FotoDeLosLugares? lugares,
  RevisarLugares? revisarLugares,
  OtrasFiestas? otrasFiestas,
}) =>
    showDialog<ConfigEntradas>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PreciosDeEntradasDialog(
        eventoId: eventoId,
        fiesta: fiesta,
        quien: quien,
        fechaFiesta: fechaFiesta,
        lugares: lugares,
        revisarLugares: revisarLugares,
        otrasFiestas: otrasFiestas,
      ),
    );

/// Las fiestas que vienen, para ofrecer los mismos precios en otras.
typedef OtrasFiestas = Future<List<Evento>> Function();

/// Abre la lista de los lugares agregados después del sorteo. Devuelve lo que
/// rige después, o null si no cambió nada.
typedef RevisarLugares = Future<FotoDeLosLugares?> Function(
  BuildContext context,
);

class PreciosDeEntradasDialog extends ConsumerStatefulWidget {
  final String eventoId;
  final String fiesta;
  final String quien;
  final DateTime? fechaFiesta;
  final FotoDeLosLugares? lugares;
  final RevisarLugares? revisarLugares;
  final OtrasFiestas? otrasFiestas;

  const PreciosDeEntradasDialog({
    super.key,
    required this.eventoId,
    required this.fiesta,
    required this.quien,
    this.fechaFiesta,
    this.lugares,
    this.revisarLugares,
    this.otrasFiestas,
  });

  @override
  ConsumerState<PreciosDeEntradasDialog> createState() =>
      _PreciosDeEntradasDialogState();
}

class _PreciosDeEntradasDialogState
    extends ConsumerState<PreciosDeEntradasDialog> {
  /// El precio de la General (`valor_entrada`). Es el mismo casillero con
  /// ANTICIPADA y con GENERAL: cambiar de opinión arriba no lo borra.
  final _general = TextEditingController();
  final _anticipada = TextEditingController();
  final _hasta = TextEditingController();
  final _lugares = TextEditingController();
  final _recargo = TextEditingController();
  bool _aMano = false;

  /// Lo elegido arriba. Null: todavía nada (la fiesta no tiene precio).
  QueSeVende? _que;

  /// "La anticipada terminó el dd/mm", si la guardada ya pasó su día.
  String? _notaDeLaAnticipada;

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
    for (final c in [_general, _anticipada, _hasta, _lugares, _recargo]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _entero(double? v) =>
      v == null || v <= 0 ? '' : v.round().toString();

  static String _porcentaje(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : '$v'.replaceAll('.', ',');
  }

  /// El momento de ahora en Argentina: decide si la anticipada todavía rige y
  /// qué día ya pasó. Los tests lo fijan.
  DateTime get _hoy => ref.read(hoyEnArgentinaProvider)();

  Future<void> _cargar() async {
    ConfigEntradas? guardada;
    try {
      guardada = await ref.read(entradasDelJefeProvider).config(widget.eventoId);
    } catch (_) {
      guardada = null;
    }
    if (!mounted) return;
    // Lo que se ve elegido sale de las columnas y del día de hoy, con la misma
    // regla que cobra: no se guarda aparte.
    final leida =
        EleccionDePrecios.leer(guardada, _hoy, fiesta: widget.fechaFiesta);
    setState(() {
      _base = guardada ??
          ConfigEntradas.vacia(widget.eventoId, ahora: DateTime.now());
      _que = leida.queSeVende;
      _notaDeLaAnticipada = leida.notaDeLaAnticipada;
      _general.text = _entero(leida.general);
      _anticipada.text = _entero(leida.anticipada);
      _hasta.text = PrecioDeEntradas.textoDelDia(leida.hasta);
      _lugares.text = _porcentaje(leida.descuentoLugaresPct);
      _recargo.text = _porcentaje(leida.recargoPct);
      _aMano = leida.descuentoAMano;
      _cargando = false;
    });
  }

  /// Los pesos de un casillero. Null: vacío.
  static double? _pesos(String texto) {
    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    return digitos.isEmpty ? null : double.tryParse(digitos);
  }

  /// El porcentaje de un casillero. **Null: vacío, que no vale 0** (hay que
  /// escribir el número). NaN: lo escrito no es un número.
  static double? _pct(String texto) {
    final t = texto.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t) ?? double.nan;
  }

  /// Lo que hay escrito, para la cuenta ([EleccionDePrecios]).
  EleccionDePrecios get _escrito {
    final hasta = _hasta.text.trim();
    return EleccionDePrecios(
      queSeVende: _que,
      general: _pesos(_general.text),
      anticipada: _pesos(_anticipada.text),
      // Un día mal escrito va tal cual: la cuenta dice que no existe.
      hasta: hasta.isEmpty ? null : (PrecioDeEntradas.diaDeTexto(hasta) ?? hasta),
      descuentoLugaresPct: _pct(_lugares.text),
      recargoPct: _pct(_recargo.text),
      descuentoAMano: _aMano,
    );
  }

  /// "Cada una: $ 5.000", con lo que hay escrito. Null si todavía no se puede
  /// calcular.
  String? get _cadaUna {
    final general = _pesos(_general.text);
    final pct = _pct(_lugares.text);
    if (_que == null ||
        general == null ||
        general <= 0 ||
        pct == null ||
        pct.isNaN ||
        pct < 0 ||
        pct > 100) {
      return null;
    }
    return 'Cada una: ${pesos(RenglonEntradas.precioCon(general, pct))}';
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
    final hoy = _hoy;
    final escrito = _escrito;
    final falta = escrito.loQueFalta(hoy);
    if (falta != null) {
      setState(() => _problema = falta);
      return;
    }
    setState(() {
      _guardando = true;
      _problema = null;
    });
    try {
      // Las columnas salen de la cuenta, que vuelve a frenar con `conPrecios`.
      final nueva = escrito.enColumnas(base, hoyAr: hoy);
      final guardada = await ref
          .read(entradasDelJefeProvider)
          .guardarConfig(nueva, quien: widget.quien);
      ref.invalidate(configDeEntradasProvider(widget.eventoId));
      avisarQueCambioLaVenta(ref, widget.eventoId);
      // Guardado acá: si hay otras fiestas, se ofrece poner lo mismo
      // (22-nov-2026). Ese cartel guarda con su propia llave.
      final otras = await _lasOtrasFiestas();
      if (otras.isNotEmpty && mounted) {
        await mostrarPreciosEnOtrasFiestas(
          context,
          elegido: escrito,
          fechaDeEstaFiesta: widget.fechaFiesta,
          fiestas: otras,
          quien: widget.quien,
        );
      }
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

  /// Las fiestas que vienen, sin esta ni la de anoche
  /// ([PreciosEnOtrasFiestas.seOfrece]). Si no se pueden leer, ninguna: lo de
  /// acá ya quedó guardado.
  Future<List<Evento>> _lasOtrasFiestas() async {
    final leer = widget.otrasFiestas;
    if (leer == null) return const [];
    final hoy = _hoy;
    try {
      return [
        for (final e in await leer())
          if (e.id != widget.eventoId &&
              PreciosEnOtrasFiestas.seOfrece(e.fechaEvento, hoy))
            e,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _elegirDia() async {
    final ahora = _hoy;
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final hasta = DateTime(hoy.year + 3);
    final escrito =
        DateTime.tryParse(PrecioDeEntradas.diaDeTexto(_hasta.text) ?? '');
    final inicial = escrito == null || escrito.isBefore(hoy)
        ? hoy
        : (escrito.isAfter(hasta) ? hasta : escrito);
    final elegido = await showDatePicker(
      context: context,
      initialDate: inicial,
      // Un día que ya pasó no se ofrece: la anticipada vale de hoy en adelante.
      firstDate: hoy,
      lastDate: hasta,
      helpText: 'La anticipada vale hasta el día',
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
          'que agregue después paga el precio del día, sin descuento.',
          key: const Key('precio_lugares_sin_sorteo'),
          style: ayuda,
        );
      case EstadoDeLosLugares.anotados:
        final del = foto.del ?? foto.sorteoEl;
        return Text(
          'Vale para lo que cada familia tenía cargado al sorteo'
          '${del == null ? '' : ' del ${ArTime.formatFechaHora(del)}'}. Lo '
          'que agregó después paga el precio del día, sin descuento.',
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
              'después del sorteo paga el precio del día, sin descuento". '
              'Hasta que aceptes la lista, todo va con descuento.',
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

  /// Arriba de todo: qué se vende ahora. Tocar la elegida no la saca: una vez
  /// elegida, siempre hay una.
  Widget _queSeVende() => SegmentedButton<QueSeVende>(
        key: const Key('precio_que_se_vende'),
        showSelectedIcon: false,
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(
            value: QueSeVende.anticipada,
            label: Text('ANTICIPADA', key: Key('precio_se_vende_anticipada')),
          ),
          ButtonSegment(
            value: QueSeVende.general,
            label: Text('GENERAL', key: Key('precio_se_vende_general')),
          ),
        ],
        selected: _que == null ? const <QueSeVende>{} : {_que!},
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          setState(() {
            _que = s.first;
            _problema = null;
          });
        },
      );

  /// Con ANTICIPADA: su precio, hasta qué día y el precio de la General. El
  /// precio y el día van lado a lado; en un ancho chico, uno debajo del otro
  /// (lado a lado, "Vale hasta el día (inclusive)" se cortaba).
  List<Widget> _conAnticipada(TextStyle ayuda) {
    final precio =
        _plata('precio_anticipada', _anticipada, 'Precio de la anticipada');
    final dia = TextField(
      key: const Key('precio_hasta'),
      controller: _hasta,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: 'Vale hasta el día (inclusive)',
        hintText: 'dd/mm/aaaa',
        suffixIcon: IconButton(
          tooltip: 'Elegir el día',
          icon: const Icon(Icons.event),
          onPressed: _elegirDia,
        ),
      ),
      onChanged: (_) => setState(() => _problema = null),
    );
    return [
      LayoutBuilder(
        builder: (context, lugar) => lugar.maxWidth < 440
            ? Column(
                children: [precio, const SizedBox(height: 14), dia],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: precio),
                  const SizedBox(width: 10),
                  Expanded(child: dia),
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Termina sola: el día siguiente ya se cobra la General.',
          style: ayuda,
        ),
      ),
      const SizedBox(height: 14),
      // Cuándo rige va abajo, no en el rótulo: en el celular, "Precio de la
      // General (cuando termina la anticipada)" se cortaba (muestras del 20-nov).
      _plata('precio_valor', _general, 'Precio de la General'),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Se cobra cuando termina la anticipada.', style: ayuda),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final gris = Theme.of(context).hintColor;
    final ayuda = TextStyle(fontSize: 12, color: gris);
    final sinPrecio = _que == null || (_pesos(_general.text) ?? 0) <= 0;
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
                    const Text(
                      '¿Qué se vende ahora?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _queSeVende(),
                    if (_notaDeLaAnticipada != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _notaDeLaAnticipada!,
                          key: const Key('precio_anticipada_termino'),
                          style: ayuda,
                        ),
                      ),
                    if (_que == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Elegí qué se vende para poner su precio.',
                          key: const Key('precio_elegi'),
                          style: ayuda,
                        ),
                      ),
                    if (_que == QueSeVende.anticipada) ...[
                      const SizedBox(height: 14),
                      ..._conAnticipada(ayuda),
                    ],
                    if (_que == QueSeVende.general) ...[
                      const SizedBox(height: 14),
                      _plata('precio_valor', _general, 'Precio de la General'),
                    ],
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
                    const SizedBox(height: 18),
                    const Text(
                      'Entradas de la mesa adicional y las sillas extra',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    // En un ancho chico, "Cada una" va debajo del descuento: al
                    // lado se partía en tres renglones (muestras del 20-nov).
                    LayoutBuilder(
                      builder: (context, lugar) {
                        final descuento = SizedBox(
                          width: 200,
                          child: _porciento('precio_lugares', _lugares, 'Descuento'),
                        );
                        final texto = cadaUna == null
                            ? null
                            : Text(
                                cadaUna,
                                key: const Key('precio_cada_una'),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              );
                        if (lugar.maxWidth < 440) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              descuento,
                              if (texto != null) ...[
                                const SizedBox(height: 8),
                                texto,
                              ],
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            descuento,
                            const SizedBox(width: 12),
                            if (texto != null) Expanded(child: texto),
                          ],
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Pagan el precio de la General con este descuento, '
                        'nunca el de la anticipada.',
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
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Los dos porcentajes van con su número: 0 si no hay.',
                        style: ayuda,
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
                      title: const Text('Quien vende puede poner descuentos'),
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
