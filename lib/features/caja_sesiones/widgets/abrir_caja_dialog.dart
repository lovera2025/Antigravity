import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/utils/currency_input_formatter.dart';
import '../providers/app_role_provider.dart';

Future<bool?> showAbrirCajaDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AbrirCajaDialog(),
  );
}

class AbrirCajaDialog extends ConsumerStatefulWidget {
  const AbrirCajaDialog({super.key});

  @override
  ConsumerState<AbrirCajaDialog> createState() => _AbrirCajaDialogState();
}

class _AbrirCajaDialogState extends ConsumerState<AbrirCajaDialog> {
  bool _conCambio = false;
  final _cambioCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  String? _etiqueta;
  bool _saving = false;
  String? _error;

  static const _presets = ['Mañana', 'Tarde'];

  @override
  void dispose() {
    _cambioCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  /// "hace 40 s" / "hace 3 min" / "hace 2 h". El dato concreto es lo que
  /// permite decidir bien: sin él, el operario adivina.
  static String _hace(Duration d) {
    if (d.inMinutes < 1) return 'hace ${d.inSeconds} s';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  /// Confirmación cuando figura una caja de este operador en otra PC.
  ///
  /// Nunca es una puerta cerrada: siempre hay salida en dos clics como máximo.
  /// El dato remoto puede estar viejo (cierre sin red, reloj desfasado,
  /// `device_id` regenerado) y un falso positivo no puede costarle el turno a
  /// alguien que hizo todo bien.
  Future<bool> _confirmarCajaAjena(CajaAjena ajena) async {
    final nombre = ref.read(appRoleProvider).operador?.nombre ?? 'este operador';
    final pc = ajena.sesion?.deviceId ?? 'otra PC';
    final cuando = _hace(ajena.antiguedad);

    final (String titulo, String cuerpo, String accion, bool accionPrimaria) =
        switch (ajena.estado) {
          EstadoCajaAjena.enUso => (
            'Caja en uso en otra PC',
            'La caja de $nombre está siendo usada en $pc · último movimiento '
                '$cuando.\n\nSi abrís acá, aquella se cierra sin arqueo.',
            'Abrir igual acá',
            false,
          ),
          EstadoCajaAjena.sinSenales => (
            'Quedó una caja sin cerrar',
            'La caja de $nombre quedó abierta en $pc y no da señales $cuando. '
                'Parece que esa PC se apagó sin cerrarla.\n\n'
                'Al tomarla, aquella se cierra sin arqueo y arrancás una nueva acá.',
            'Tomar la caja acá',
            true,
          ),
          _ => (
            'Figura una caja abierta',
            ajena.verificado
                ? 'Hay una caja de $nombre abierta en $pc que dejó de dar '
                      'señales $cuando. No se puede saber si sigue en uso o si '
                      'se cerró sin conexión.'
                : 'Hay una caja de $nombre registrada en $pc y no se pudo '
                      'verificar contra el servidor (sin conexión).',
            'Abrir acá',
            true,
          ),
        };

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(width: 420, child: Text(cuerpo)),
        actions: [
          if (accionPrimaria) ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(accion),
            ),
          ] else ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(accion),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
          ],
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmar() async {
    if (_etiqueta == null) {
      setState(() => _error = 'Elegí el turno Mañana o Tarde.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(appRoleProvider.notifier);
      // Con datos frescos: ¿este operador ya tiene la caja abierta en otra PC?
      final ajena = await notifier.estadoCajaEnOtroDispositivo();
      var tomar = false;
      if (ajena.requiereConfirmacion) {
        if (!mounted) return;
        if (!await _confirmarCajaAjena(ajena)) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        tomar = true;
      }
      final cambio = _conCambio
          ? CurrencyInputFormatter.parse(_cambioCtrl.text)
          : 0.0;
      await notifier.abrirSesionCaja(
        cambioInicial: cambio,
        notaApertura: _notaCtrl.text,
        etiqueta: _etiqueta!,
        tomarDeOtroDispositivo: tomar,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = ref.watch(appRoleProvider).operador;
    const gold = Color(0xFFD4AF37);

    return AlertDialog(
      title: Text('Abrir caja${op != null ? ' · ${op.nombre}' : ''}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Iniciar con cambio'),
                subtitle: const Text('Si está apagado, arrancás en \$0'),
                value: _conCambio,
                activeThumbColor: gold,
                onChanged: (v) => setState(() => _conCambio = v),
              ),
              if (_conCambio) ...[
                TextField(
                  controller: _cambioCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Cambio inicial',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Turno (obligatorio)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in _presets)
                    ChoiceChip(
                      label: Text(p),
                      selected: _etiqueta == p,
                      onSelected: (sel) => setState(() {
                        _etiqueta = sel ? p : null;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notaCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota de apertura',
                  hintText: 'Ej. cambio incompleto, sigo de ayer…',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || _etiqueta == null ? null : _confirmar,
          style: FilledButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: Colors.black,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Abrir caja'),
        ),
      ],
    );
  }
}
