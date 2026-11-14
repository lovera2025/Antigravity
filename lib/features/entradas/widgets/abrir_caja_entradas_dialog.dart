import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../barra/cuentas/pesos.dart';
import '../../barra/widgets/pesos_enteros_formatter.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../datos/entradas_repositorio.dart';
import '../providers/entradas_providers.dart';

/// Lo que se le dice a quien llega a vender sin la llave.
const kSinPermisoParaVender =
    'Para vender entradas hace falta el permiso "Vende entradas" o el modo jefe.';

/// Lo que dice VENDER cuando la fiesta todavía no tiene precio.
const kLaFiestaNoTienePrecio =
    'El jefe todavía no puso el precio de la entrada de esta fiesta';

/// VENDER sin caja abierta la pide: **"Abrir la caja de entradas"**, con su
/// cambio inicial (puede ser 0). Devuelve la caja abierta, o null si volvió.
///
/// Una caja de entradas es **por fiesta**, y aparte de la de cuotas y de la de
/// la barra. Si ese operador ya tiene una abierta en este equipo, el
/// repositorio devuelve esa: tocar dos veces no abre dos.
Future<CajaEntradas?> abrirCajaDeEntradas(
  BuildContext context, {
  required String eventoId,
  required String fiesta,
  required String? operadorId,
  required String operadorNombre,
}) =>
    showDialog<CajaEntradas>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AbrirCajaEntradasDialog(
        eventoId: eventoId,
        fiesta: fiesta,
        operadorId: operadorId,
        operadorNombre: operadorNombre,
      ),
    );

class AbrirCajaEntradasDialog extends ConsumerStatefulWidget {
  final String eventoId;
  final String fiesta;

  /// Null: la abre el jefe.
  final String? operadorId;
  final String operadorNombre;

  const AbrirCajaEntradasDialog({
    super.key,
    required this.eventoId,
    required this.fiesta,
    required this.operadorId,
    required this.operadorNombre,
  });

  @override
  ConsumerState<AbrirCajaEntradasDialog> createState() =>
      _AbrirCajaEntradasDialogState();
}

class _AbrirCajaEntradasDialogState
    extends ConsumerState<AbrirCajaEntradasDialog> {
  final _cambio = TextEditingController();
  bool _cargando = true;
  bool _abriendo = false;
  bool _tienePrecio = false;

  /// Otra caja abierta de esta misma persona, en otro equipo (bajó de la nube).
  bool _hayOtraEnOtroEquipo = false;
  String? _problema;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cambio.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final repo = ref.read(entradasDeLaCajaProvider);
    var tienePrecio = false;
    var otra = false;
    try {
      tienePrecio = (await repo.config(widget.eventoId))?.tienePrecio ?? false;
      final mia = await repo.cajaAbierta(
        eventoId: widget.eventoId,
        operadorId: widget.operadorId,
      );
      otra = mia == null &&
          (await repo.cajas(widget.eventoId)).any(
            (c) => c.abierta && c.operadorId == widget.operadorId,
          );
    } catch (_) {
      // Sin poder leer, se muestra como sin precio: no se abre a ciegas.
    }
    if (!mounted) return;
    setState(() {
      _tienePrecio = tienePrecio;
      _hayOtraEnOtroEquipo = otra;
      _cargando = false;
    });
  }

  /// La llave: sin el permiso de vender (o el modo jefe) no se abre una caja.
  bool _frenaSinPermiso() {
    if (ref.read(puedeVenderEntradasProvider)) return false;
    setState(() => _problema = kSinPermisoParaVender);
    return true;
  }

  Future<void> _abrir() async {
    if (_frenaSinPermiso()) return;
    setState(() {
      _abriendo = true;
      _problema = null;
    });
    try {
      final caja = await ref.read(entradasDeLaCajaProvider).abrirCaja(
            eventoId: widget.eventoId,
            operadorId: widget.operadorId,
            operadorNombre: widget.operadorNombre,
            cambioInicial:
                (PesosEnterosFormatter.leer(_cambio.text) ?? 0).toDouble(),
          );
      if (mounted) Navigator.pop(context, caja);
    } catch (_) {
      if (mounted) {
        setState(() {
          _abriendo = false;
          _problema = 'No se pudo abrir la caja. Probá de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).hintColor;
    final naranja = Colors.orange.shade800;
    final cambio = (PesosEnterosFormatter.leer(_cambio.text) ?? 0).toDouble();

    return AlertDialog(
      title: const Text('Abrir la caja de entradas'),
      content: SizedBox(
        width: 420,
        child: _cargando
            ? const SizedBox(
                height: 90,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.fiesta} · vende ${widget.operadorNombre}',
                    style: TextStyle(color: gris),
                  ),
                  const SizedBox(height: 14),
                  if (!_tienePrecio) ...[
                    Text(
                      kLaFiestaNoTienePrecio,
                      key: const Key('abrir_caja_sin_precio'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sin precio no se abre la caja. Se pone en ENTRADAS → PRECIOS.',
                      style: TextStyle(fontSize: 12.5, color: gris),
                    ),
                  ] else ...[
                    TextField(
                      key: const Key('abrir_caja_cambio'),
                      controller: _cambio,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [PesosEnterosFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Cambio inicial',
                        prefixText: r'$ ',
                        hintText: '0',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _abriendo ? null : _abrir(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Puede ser 0. Es la plata con que arranca para dar vuelto: '
                      '${pesos(cambio)}.',
                      style: TextStyle(fontSize: 12.5, color: gris),
                    ),
                    if (_hayOtraEnOtroEquipo)
                      Padding(
                        key: const Key('abrir_caja_otra'),
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Ya hay una caja de entradas abierta a nombre de '
                          '${widget.operadorNombre} en otro equipo. Esta se abre '
                          'igual: son dos cajas.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: naranja,
                          ),
                        ),
                      ),
                  ],
                  if (_problema != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _problema!,
                        key: const Key('abrir_caja_problema'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const Key('abrir_caja_volver'),
          onPressed: _abriendo ? null : () => Navigator.pop(context),
          child: const Text('VOLVER'),
        ),
        if (!_cargando && _tienePrecio)
          FilledButton(
            key: const Key('abrir_caja_abrir'),
            onPressed: _abriendo ? null : _abrir,
            child: const Text('ABRIR LA CAJA'),
          ),
      ],
    );
  }
}
