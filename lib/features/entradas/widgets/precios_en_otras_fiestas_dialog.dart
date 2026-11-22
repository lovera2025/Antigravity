import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../cuentas/eleccion_de_precios.dart';
import '../cuentas/precios_en_otras_fiestas.dart';
import '../datos/config_entradas.dart';
import '../providers/entradas_providers.dart';
import '../services/nombre_de_la_fiesta.dart';

/// Después de GUARDAR en PRECIOS: "¿Poner estos precios también en otras
/// fiestas?", con las fiestas que vienen para tildar las que se quiera (pedido
/// del usuario, 22-nov-2026: "sabés lo que es ir poniendo el precio fiesta por
/// fiesta"). **Ninguna viene tildada**: NO, SOLO ESTA deja todo como estaba.
///
/// [elegido] es lo que se acaba de guardar en la fiesta del día
/// [fechaDeEstaFiesta]; [fiestas], las otras (sin esa). Qué le toca a cada una
/// lo dice [PreciosEnOtrasFiestas]; cada una se guarda en su propia fila, por
/// el mismo camino que PRECIOS. **Solo en modo jefe, con doble llave** (quien lo
/// abre ya preguntó, y `_poner` vuelve a preguntar antes de escribir).
Future<void> mostrarPreciosEnOtrasFiestas(
  BuildContext context, {
  required EleccionDePrecios elegido,
  required DateTime? fechaDeEstaFiesta,
  required List<Evento> fiestas,
  required String quien,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PreciosEnOtrasFiestasDialog(
        elegido: elegido,
        fechaDeEstaFiesta: fechaDeEstaFiesta,
        fiestas: fiestas,
        quien: quien,
      ),
    );

class PreciosEnOtrasFiestasDialog extends ConsumerStatefulWidget {
  final EleccionDePrecios elegido;
  final DateTime? fechaDeEstaFiesta;
  final List<Evento> fiestas;
  final String quien;

  const PreciosEnOtrasFiestasDialog({
    super.key,
    required this.elegido,
    required this.fechaDeEstaFiesta,
    required this.fiestas,
    required this.quien,
  });

  @override
  ConsumerState<PreciosEnOtrasFiestasDialog> createState() =>
      _PreciosEnOtrasFiestasDialogState();
}

class _PreciosEnOtrasFiestasDialogState
    extends ConsumerState<PreciosEnOtrasFiestasDialog> {
  /// Lo que tiene hoy cada fiesta, por su id (null: sin config).
  final Map<String, ConfigEntradas?> _hoyTiene = {};
  final Set<String> _tildadas = {};
  late DiaDeLaAnticipada _dia;
  bool _cargando = true;
  bool _poniendo = false;
  String? _problema;

  /// Cuando terminó: en cuáles quedó y en cuáles no (con el motivo).
  List<String>? _quedaron;
  List<String> _noQuedaron = const [];

  DateTime get _hoy => ref.read(hoyEnArgentinaProvider)();

  bool get _esAnticipada => widget.elegido.queSeVende == QueSeVende.anticipada;

  @override
  void initState() {
    super.initState();
    _dia = PreciosEnOtrasFiestas.diaQueViene(
      widget.elegido,
      fechaDeEstaFiesta: widget.fechaDeEstaFiesta,
      hoyAr: _hoy,
    );
    _cargar();
  }

  Future<void> _cargar() async {
    final entradas = ref.read(entradasDelJefeProvider);
    for (final f in widget.fiestas) {
      try {
        _hoyTiene[f.id] = await entradas.config(f.id);
      } catch (_) {
        _hoyTiene[f.id] = null;
      }
    }
    if (mounted) setState(() => _cargando = false);
  }

  String? _problemaDe(Evento f) => PreciosEnOtrasFiestas.problema(
        widget.elegido,
        fechaFiesta: f.fechaEvento,
        dia: _dia,
        hoyAr: _hoy,
      );

  /// Las tildadas que se pueden poner con el día elegido.
  List<Evento> get _aPoner => [
        for (final f in widget.fiestas)
          if (_tildadas.contains(f.id) && _problemaDe(f) == null) f,
      ];

  /// La segunda llave: sin modo jefe no se guarda, aunque alguien llegue hasta
  /// acá con el botón apagado.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    setState(() => _problema = '$kSoloEnModoJefe: los precios los pone el jefe.');
    return true;
  }

  /// PONER EN N FIESTAS: una por una, cada una en su fila. Si una falla, las
  /// demás siguen, y al final se dice en cuáles quedó y en cuáles no.
  Future<void> _poner() async {
    if (_frenaSinModoJefe()) return;
    final fiestas = _aPoner;
    if (fiestas.isEmpty || _poniendo) return;
    setState(() {
      _poniendo = true;
      _problema = null;
    });
    final entradas = ref.read(entradasDelJefeProvider);
    final quedaron = <String>[];
    final noQuedaron = <String>[];
    for (final f in fiestas) {
      final nombre = nombreDeLaFiesta(f);
      try {
        final hoy = _hoy;
        final paraEsa = PreciosEnOtrasFiestas.paraLaFiesta(
          widget.elegido,
          fechaFiesta: f.fechaEvento,
          dia: _dia,
          hoyAr: hoy,
        );
        // Lo de esa fiesta recién leído: de ahí salen su id y cuándo nació.
        final base = await entradas.config(f.id) ??
            ConfigEntradas.vacia(f.id, ahora: DateTime.now());
        await entradas.guardarConfig(
          paraEsa.enColumnas(base, hoyAr: hoy),
          quien: widget.quien,
        );
        ref.invalidate(configDeEntradasProvider(f.id));
        avisarQueCambioLaVenta(ref, f.id);
        quedaron.add(nombre);
      } on ArgumentError catch (e) {
        noQuedaron.add('$nombre: ${e.message}');
      } catch (_) {
        noQuedaron.add('$nombre: no se pudo guardar.');
      }
    }
    if (!mounted) return;
    setState(() {
      _poniendo = false;
      _quedaron = quedaron;
      _noQuedaron = noQuedaron;
    });
  }

  String _fecha(DateTime? d) {
    if (d == null) return 'sin fecha';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year}';
  }

  Widget _queDia() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La anticipada vale hasta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SegmentedButton<DiaDeLaAnticipada>(
            key: const Key('precios_otras_dia'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: DiaDeLaAnticipada.elAnteriorDeCadaFiesta,
                label: const Text(
                  'EL DÍA ANTERIOR A CADA FIESTA',
                  key: Key('precios_otras_dia_anterior'),
                ),
              ),
              ButtonSegment(
                value: DiaDeLaAnticipada.elMismo,
                label: Text(
                  'EL ${PreciosEnOtrasFiestasDialogTextos.diaCorto(widget.elegido.hasta)}',
                  key: const Key('precios_otras_dia_mismo'),
                ),
              ),
            ],
            selected: {_dia},
            onSelectionChanged: _poniendo
                ? null
                : (s) => setState(() {
                      _dia = s.first;
                      _problema = null;
                    }),
          ),
        ],
      );

  Widget _fiesta(Evento f, Color gris, Color rojo) {
    final problema = _problemaDe(f);
    final tiene = PreciosEnOtrasFiestas.loQueTieneHoy(_hoyTiene[f.id], _hoy);
    return CheckboxListTile(
      key: Key('precios_otras_${f.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: problema == null && _tildadas.contains(f.id),
      onChanged: problema != null || _poniendo
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _tildadas.add(f.id);
                } else {
                  _tildadas.remove(f.id);
                }
              }),
      title: Text(
        '${nombreDeLaFiesta(f)} · ${_fecha(f.fechaEvento)}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        problema ?? 'Hoy: $tiene',
        key: Key('precios_otras_${f.id}_hoy'),
        style: TextStyle(fontSize: 12, color: problema == null ? gris : rojo),
      ),
    );
  }

  Widget _terminado(Color rojo) {
    final quedaron = _quedaron!;
    return Column(
      key: const Key('precios_otras_listo'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quedaron.isNotEmpty)
          Text(
            'Listo: los precios quedaron en '
            '${quedaron.length == 1 ? '1 fiesta' : '${quedaron.length} fiestas'}: '
            '${quedaron.join(', ')}.',
            key: const Key('precios_otras_quedaron'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        if (_noQuedaron.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'No quedaron en:',
            style: TextStyle(fontWeight: FontWeight.w700, color: rojo),
          ),
          for (final n in _noQuedaron)
            Text('· $n', style: TextStyle(color: rojo)),
          const SizedBox(height: 6),
          const Text('Esas se ponen desde PRECIOS de cada fiesta.'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final gris = Theme.of(context).hintColor;
    final rojo = Theme.of(context).colorScheme.error;
    final terminado = _quedaron != null;
    final cuantas = _aPoner.length;
    return AlertDialog(
      title: const Text('¿Poner estos precios también en otras fiestas?'),
      content: SizedBox(
        width: 520,
        child: _cargando
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : terminado
                ? _terminado(rojo)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PreciosEnOtrasFiestas.loQueSePone(widget.elegido, _dia),
                          key: const Key('precios_otras_que'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Y lo mismo de la mesa adicional, las sillas, el recargo y '
                          'los descuentos. Cambiar el precio no toca ninguna venta hecha.',
                          style: TextStyle(fontSize: 12, color: gris),
                        ),
                        if (_esAnticipada) ...[
                          const SizedBox(height: 14),
                          _queDia(),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Tildá las que quieras',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              key: const Key('precios_otras_todas'),
                              onPressed: _poniendo
                                  ? null
                                  : () => setState(() {
                                        for (final f in widget.fiestas) {
                                          if (_problemaDe(f) == null) {
                                            _tildadas.add(f.id);
                                          }
                                        }
                                      }),
                              child: const Text('TODAS'),
                            ),
                          ],
                        ),
                        for (final f in widget.fiestas) _fiesta(f, gris, rojo),
                        if (_problema != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _problema!,
                              key: const Key('precios_otras_problema'),
                              style: TextStyle(color: rojo, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: terminado
          ? [
              FilledButton(
                key: const Key('precios_otras_listo_cerrar'),
                onPressed: () => Navigator.pop(context),
                child: const Text('LISTO'),
              ),
            ]
          : [
              TextButton(
                key: const Key('precios_otras_no'),
                onPressed: _poniendo ? null : () => Navigator.pop(context),
                child: const Text('NO, SOLO ESTA'),
              ),
              Tooltip(
                message: esJefe ? 'Poner los precios en las tildadas' : kSoloEnModoJefe,
                child: FilledButton(
                  key: const Key('precios_otras_poner'),
                  onPressed: !esJefe || _cargando || _poniendo || cuantas == 0
                      ? null
                      : _poner,
                  child: Text(
                    cuantas == 0
                        ? 'PONER'
                        : 'PONER EN ${cuantas == 1 ? '1 FIESTA' : '$cuantas FIESTAS'}',
                  ),
                ),
              ),
            ],
    );
  }
}

/// Textos chicos del cartel.
class PreciosEnOtrasFiestasDialogTextos {
  const PreciosEnOtrasFiestasDialogTextos._();

  /// "28/11" de un `AAAA-MM-DD`, o "MISMO DÍA" si no hay día.
  static String diaCorto(String? dia) {
    if (!ConfigEntradas.diaValido(dia?.trim())) return 'MISMO DÍA';
    final p = dia!.trim().split('-');
    return '${p[2]}/${p[1]}';
  }
}
