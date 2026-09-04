import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../egresos/services/egreso_concepto_sugerencias.dart';
import '../models/compromiso_personal.dart';
import '../providers/compromisos_personal_provider.dart';

/// Abre una cuenta pendiente con una persona: lo que se le debe por un trabajo
/// que hizo o por un producto, para después ir descontando a medida que se paga.
class NuevoCompromisoDialog extends ConsumerStatefulWidget {
  /// Nombre precargado, cuando se abre desde la fila de una persona.
  final String? personaInicial;

  const NuevoCompromisoDialog({super.key, this.personaInicial});

  @override
  ConsumerState<NuevoCompromisoDialog> createState() =>
      _NuevoCompromisoDialogState();
}

class _NuevoCompromisoDialogState extends ConsumerState<NuevoCompromisoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _personaController = TextEditingController();
  final _conceptoController = TextEditingController();
  final _montoController = TextEditingController();
  final _notaController = TextEditingController();

  static const _gold = Color(0xFFD4AF37);

  String _tipo = kTipoCompromisoTrabajo;
  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  EgresoConceptoSugerencias _sugerencias =
      EgresoConceptoSugerencias.fromFilas(const []);

  @override
  void initState() {
    super.initState();
    _personaController.text = widget.personaInicial ?? '';
    _cargarSugerencias();
  }

  @override
  void dispose() {
    _personaController.dispose();
    _conceptoController.dispose();
    _montoController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _cargarSugerencias() async {
    try {
      final filas =
          await ref.read(egresosRepositoryProvider).getFilasSugerenciasConcepto();
      if (mounted) {
        setState(() => _sugerencias = EgresoConceptoSugerencias.fromFilas(filas));
      }
    } catch (_) {
      // Sin sugerencias se escribe el nombre a mano: no vale trabar el alta.
    }
  }

  /// Solo gente a la que ya se le pagó como Personal/Operadores. La sección es
  /// de cuentas con el personal; ofrecer proveedores acá sería ruido.
  Iterable<String> _nombresDePersonal(String query) {
    return _sugerencias.filtrarNombres(query).where(
          (n) => esCategoriaOperador(_sugerencias.ultimaCategoriaGuardada(n)),
        );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final monto = double.parse(
        _montoController.text.replaceAll('.', '').replaceAll(',', '.'),
      );
      await ref.read(compromisosPersonalProvider.notifier).crear(
            persona: _sugerencias.nombreCanonico(_personaController.text),
            tipo: _tipo,
            montoTotal: monto,
            concepto: _conceptoController.text,
            fechaInicio: _fecha,
            nota: _notaController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la cuenta: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('Nueva cuenta pendiente'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lo que le debés a esta persona. Después vas registrando los '
                  'pagos y la cuenta se va descontando sola.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 16),
                Autocomplete<String>(
                  optionsBuilder: (v) => _nombresDePersonal(v.text),
                  onSelected: (v) => _personaController.text = v,
                  fieldViewBuilder: (context, ctrl, focusNode, onSubmitted) {
                    if (ctrl.text != _personaController.text &&
                        _personaController.text.isNotEmpty &&
                        ctrl.text.isEmpty) {
                      ctrl.text = _personaController.text;
                    }
                    return TextFormField(
                      controller: ctrl,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Persona',
                        hintText: 'Buscá una ya cargada o escribí una nueva',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onChanged: (v) => _personaController.text = v,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: kTipoCompromisoTrabajo,
                        label: Text('Trabajo'),
                        icon: Icon(Icons.handyman_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: kTipoCompromisoProducto,
                        label: Text('Producto'),
                        icon: Icon(Icons.inventory_2_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: kTipoCompromisoOtro,
                        label: Text('Otro'),
                        icon: Icon(Icons.more_horiz_rounded, size: 16),
                      ),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (s) => setState(() => _tipo = s.first),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _conceptoController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Sonido del sábado, parlante JBL…',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _montoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final v = double.parse(newValue.text) / 100;
                      final t = v.toFormattedNumber();
                      return newValue.copyWith(
                        text: t,
                        selection: TextSelection.collapsed(offset: t.length),
                      );
                    }),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monto que le debo (\$)',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                    hintText: '0,00',
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty || v == '0,00') ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Desde', style: TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${_fecha.day.toString().padLeft(2, '0')}/'
                    '${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final elegida = await showDatePicker(
                        context: context,
                        initialDate: _fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (elegida != null) setState(() => _fecha = elegida);
                    },
                    child: const Text('CAMBIAR'),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notaController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('CREAR CUENTA'),
        ),
      ],
    );
  }
}
