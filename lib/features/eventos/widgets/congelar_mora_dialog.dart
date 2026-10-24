import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/utils/solo_jefe.dart';
import '../../mi_empresa/providers/finanzas_provider.dart';
import '../repositories/mora_congelada_repository.dart';
import '../services/mora_congelada.dart';
import '../services/mora_cuota_calculator.dart';

/// El celeste de la mora congelada (6.2.1): el usuario lo pidió así, para que
/// se vea de un vistazo quién está "tocado con eso".
const Color kCelesteCongelada = Color(0xFF039BE5);

/// La mora de hoy de cada cuota vencida, neta de lo ya cobrado (la misma que
/// se cobra).
List<MoraCuotaDetalle> moraPorCuotaHoy(
  ContratoAlumno a, {
  required double moraCobradaHistorial,
  required DateTime hoy,
}) =>
    MoraCuotaCalculator.desglosePendiente(
      MoraCuotaCalculator.calcularDesglose(a, hoy),
      MoraCuotaCalculator.moraCobradaParaFifo(
        moraCobradaHistorial: moraCobradaHistorial,
        moraCobradaOffset: a.moraCobradaOffset,
      ),
    );

/// La suma de [cuotas] (null = todas).
double montoDeCuotas(List<MoraCuotaDetalle> desglose, Set<int>? cuotas) =>
    double.parse(desglose
        .where((d) => cuotas == null || cuotas.contains(d.numeroCuota))
        .fold<double>(0, (s, d) => s + d.interesBruto)
        .toStringAsFixed(2));

/// Lo que dicen los dos botones al descongelar, antes de tocar nada:
/// **Mantener** deja lo congelado; **Recalcular** es la mora como si nunca se
/// hubiera congelado (la misma cuenta, sin esas pausas).
({double mantener, double recalcular}) montosAlDescongelar(
  ContratoAlumno a,
  MoraCongelada actual, {
  Set<int>? cuotas,
  required double moraCobradaHistorial,
  required DateTime hoy,
}) {
  double montoCon(MoraCongelada m) => MoraCongelada.conPausas(
        a.id,
        m,
        () => montoDeCuotas(
          moraPorCuotaHoy(a, moraCobradaHistorial: moraCobradaHistorial, hoy: hoy),
          cuotas,
        ),
      );
  return (
    mantener: montoCon(actual),
    recalcular: montoCon(
      actual.recalcular(cuotas: cuotas, cuotasPagadas: a.cuotasPagadas, dia: hoy),
    ),
  );
}

/// "Mora congelada desde 23/10 · C4, C5" (o "· todas las cuotas"), o null.
String? textoMoraCongelada(MoraCongelada m) {
  final desde = m.desde;
  if (desde == null) return null;
  final cuales = m.todasCongeladas
      ? 'todas las cuotas'
      : (m.cuotasCongeladas.toList()..sort()).map((n) => 'C$n').join(', ');
  return 'Mora congelada desde ${ArTime.formatFechaCorta(desde)} · $cuales';
}

/// El aviso celeste, para todos (también el operario, que no tiene el botón):
/// en ESTADO DE DEUDA, en la ventana de cobro y en Mi Empresa → Cobro.
class AvisoMoraCongelada extends StatelessWidget {
  final String contratoId;
  final double tamano;

  const AvisoMoraCongelada({super.key, required this.contratoId, this.tamano = 9});

  @override
  Widget build(BuildContext context) {
    final texto = textoMoraCongelada(MoraCongelada.de(contratoId));
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ac_unit, size: tamano + 2, color: kCelesteCongelada),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              texto,
              key: Key('mora_congelada_$contratoId'),
              style: TextStyle(
                fontSize: tamano,
                fontWeight: FontWeight.w700,
                color: kCelesteCongelada,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Congelar la mora de un alumno (grilla del evento masivo, solo modo jefe).
///
/// Sin nada congelado abre **Congelar**: las cuotas vencidas con su mora de hoy
/// y "Todas, también las que se venzan". Con algo congelado abre **Mora
/// congelada**: Mantener ese precio o Recalcular, con el monto de cada uno a la
/// vista, y "Congelar otra cuota".
class CongelarMoraDialog extends ConsumerStatefulWidget {
  final ContratoAlumno contrato;
  final double moraCobradaHistorial;

  /// El día de la cuenta; null = hoy. Lo usan los tests y las muestras.
  final DateTime? hoy;

  const CongelarMoraDialog({
    super.key,
    required this.contrato,
    required this.moraCobradaHistorial,
    this.hoy,
  });

  @override
  ConsumerState<CongelarMoraDialog> createState() => _CongelarMoraDialogState();
}

class _CongelarMoraDialogState extends ConsumerState<CongelarMoraDialog> {
  late MoraCongelada _actual;
  late bool _congelando;
  final Set<int> _elegidas = {};
  bool _todas = false;
  bool _guardando = false;

  DateTime get _hoy {
    final h = widget.hoy ?? ArTime.nowAr();
    return DateTime(h.year, h.month, h.day);
  }

  ContratoAlumno get _a => widget.contrato;

  @override
  void initState() {
    super.initState();
    _actual = MoraCongelada.de(_a.id);
    _congelando = !_actual.algoCongelado;
    _elegirTodoLoQueCorresponde();
  }

  void _elegirTodoLoQueCorresponde() {
    _elegidas.clear();
    if (_congelando) {
      _elegidas.addAll(_vencidasSinCongelar.map((d) => d.numeroCuota));
    } else {
      _elegidas.addAll(_actual.cuotasCongeladas);
    }
  }

  List<MoraCuotaDetalle> get _desgloseHoy => moraPorCuotaHoy(
        _a,
        moraCobradaHistorial: widget.moraCobradaHistorial,
        hoy: _hoy,
      );

  List<MoraCuotaDetalle> get _vencidasSinCongelar =>
      _desgloseHoy.where((d) => !_actual.congeladaHoy(d.numeroCuota)).toList();

  /// Freno de modo jefe al principio de cada cosa que guarda: el botón ya no
  /// aparece sin modo jefe; esta es la segunda llave.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('$kSoloEnModoJefe: congelar la mora lo hace el jefe.'),
        ),
      );
    }
    return true;
  }

  Future<void> _guardar(MoraCongelada nueva, String hecho) async {
    if (_frenaSinModoJefe()) return;
    setState(() => _guardando = true);
    try {
      await ref.read(moraCongeladaRepositoryProvider).guardar(
            contratoAlumnoId: _a.id,
            eventoId: _a.eventoId,
            mora: nueva,
          );
      ref.read(finanzasProvider.notifier).recargar();
      ref.read(contratosMutationTickProvider.notifier).bump();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('$hecho: ${_a.nombreAlumno}.'), backgroundColor: kCelesteCongelada),
      );
    } catch (e) {
      debugPrint('congelar mora: $e');
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. No cambió nada: volvé a intentar.')),
      );
    }
  }

  void _congelar() => _guardar(
        _actual.congelar(cuotas: _elegidas, todas: _todas, dia: _hoy),
        'Mora congelada',
      );

  Set<int>? get _cuotasADescongelar => _actual.todasCongeladas ? null : Set.of(_elegidas);

  void _mantener() => _guardar(
        _actual.mantener(cuotas: _cuotasADescongelar, dia: _hoy),
        'Descongelada, con el precio que tenía',
      );

  void _recalcular() => _guardar(
        _actual.recalcular(cuotas: _cuotasADescongelar, cuotasPagadas: _a.cuotasPagadas, dia: _hoy),
        'Descongelada y recalculada',
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.ac_unit, color: kCelesteCongelada, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _congelando ? 'Congelar mora' : 'Mora congelada',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kCelesteCongelada),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(child: _congelando ? _vistaCongelar() : _vistaCongelada()),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cerrar'),
        ),
        if (_congelando)
          FilledButton.icon(
            key: const Key('congelar_ok'),
            onPressed: _guardando || (!_todas && _elegidas.isEmpty) ? null : _congelar,
            style: FilledButton.styleFrom(backgroundColor: kCelesteCongelada),
            icon: const Icon(Icons.ac_unit, size: 18),
            label: const Text('Congelar'),
          ),
      ],
    );
  }

  Widget _renglon(MoraCuotaDetalle d, {required bool marcado, ValueChanged<bool?>? onChanged, bool celeste = false}) {
    return CheckboxListTile(
      key: Key('cuota_${d.numeroCuota}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: kCelesteCongelada,
      value: marcado,
      onChanged: _guardando ? null : onChanged,
      title: Text('Cuota ${d.numeroCuota} (${d.mesLabel})', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${d.diasMora} días de mora'),
      secondary: Text(
        d.interesBruto.toCurrency(),
        style: TextStyle(fontWeight: FontWeight.w900, color: celeste ? kCelesteCongelada : null),
      ),
    );
  }

  /// La acción arriba y el monto abajo, en negrita: así no se corta el número.
  Widget _textoBoton(String accion, double monto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(accion, textAlign: TextAlign.center),
            Text(
              monto.toCurrency(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  Widget _notaFicha() {
    final tracked = _a.moraPendienteTracked;
    if (tracked <= 0.01) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'La mora de cuotas ya pagadas (${tracked.toCurrency()}) no crece: queda igual.',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  Widget _vistaCongelar() {
    final vencidas = _vencidasSinCongelar;
    final elegidas = _todas ? null : _elegidas;
    final queda = montoDeCuotas(vencidas, elegidas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vencidas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No tiene cuotas vencidas con mora. Con "Todas", las que se venzan no van a sumar.'),
          ),
        for (final d in vencidas)
          _renglon(
            d,
            marcado: _todas || _elegidas.contains(d.numeroCuota),
            onChanged: _todas
                ? null
                : (v) => setState(() => v == true ? _elegidas.add(d.numeroCuota) : _elegidas.remove(d.numeroCuota)),
          ),
        const Divider(),
        SwitchListTile(
          key: const Key('congelar_todas'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeThumbColor: kCelesteCongelada,
          value: _todas,
          onChanged: _guardando ? null : (v) => setState(() => _todas = v),
          title: const Text('Todas, también las que se venzan', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('El alumno entero: ninguna cuota suma mora mientras dure.'),
        ),
        const SizedBox(height: 6),
        Text(
          'Queda congelada en ${queda.toCurrency()}',
          key: const Key('congelar_queda'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kCelesteCongelada),
        ),
        _notaFicha(),
      ],
    );
  }

  Widget _vistaCongelada() {
    final todas = _actual.todasCongeladas;
    final desglose = _desgloseHoy;
    final congeladas = todas
        ? desglose
        : desglose.where((d) => _actual.cuotasCongeladas.contains(d.numeroCuota)).toList();
    final montos = montosAlDescongelar(
      _a,
      _actual,
      cuotas: _cuotasADescongelar,
      moraCobradaHistorial: widget.moraCobradaHistorial,
      hoy: _hoy,
    );
    final nada = !todas && _elegidas.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          textoMoraCongelada(_actual) ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700, color: kCelesteCongelada),
        ),
        const SizedBox(height: 6),
        if (todas)
          const Text(
            'Se congeló con "Todas": se descongela entera.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        for (final d in congeladas)
          _renglon(
            d,
            celeste: true,
            marcado: todas || _elegidas.contains(d.numeroCuota),
            onChanged: todas
                ? null
                : (v) => setState(() => v == true ? _elegidas.add(d.numeroCuota) : _elegidas.remove(d.numeroCuota)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('descongelar_mantener'),
                onPressed: _guardando || nada ? null : _mantener,
                child: _textoBoton('Mantener ese precio', montos.mantener),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('descongelar_recalcular'),
                onPressed: _guardando || nada ? null : _recalcular,
                child: _textoBoton('Recalcular', montos.recalcular),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Mantener: queda el monto congelado y desde hoy vuelve a sumar. '
          'Recalcular: como si nunca se hubiera congelado.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        if (!todas && _vencidasSinCongelar.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('congelar_otra'),
              onPressed: _guardando
                  ? null
                  : () => setState(() {
                        _congelando = true;
                        _elegirTodoLoQueCorresponde();
                      }),
              icon: const Icon(Icons.ac_unit, size: 16),
              label: const Text('Congelar otra cuota'),
            ),
          ),
        ],
        _notaFicha(),
      ],
    );
  }
}
