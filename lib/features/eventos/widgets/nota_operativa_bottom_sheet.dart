import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/nota_operativa_contrato.dart';
import '../repositories/notas_operativas_contrato_repository.dart';
import '../../caja_sesiones/services/caja_auto_sync_service.dart';

const _gold = Color(0xFFD4AF37);

/// Bottom sheet para crear / editar / borrar nota operativa (no contable).
Future<void> showNotaOperativaSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ContratoAlumno alumno,
  NotaOperativaContrato? existente,
  required VoidCallback onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _NotaOperativaSheetBody(
      alumno: alumno,
      existente: existente,
      onChanged: onChanged,
    ),
  );
}

class _NotaOperativaSheetBody extends ConsumerStatefulWidget {
  final ContratoAlumno alumno;
  final NotaOperativaContrato? existente;
  final VoidCallback onChanged;

  const _NotaOperativaSheetBody({
    required this.alumno,
    required this.existente,
    required this.onChanged,
  });

  @override
  ConsumerState<_NotaOperativaSheetBody> createState() =>
      _NotaOperativaSheetBodyState();
}

class _NotaOperativaSheetBodyState
    extends ConsumerState<_NotaOperativaSheetBody> {
  late final TextEditingController _ctrl;
  late bool _resuelto;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existente?.texto ?? '');
    _resuelto = widget.existente?.resuelto ?? false;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Escribí algo en la nota o usá Eliminar.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final checkpoint = DateTime.now().toUtc();
      await ref
          .read(notasOperativasContratoRepositoryProvider)
          .guardar(
            contratoAlumnoId: widget.alumno.id,
            texto: texto,
            resuelto: _resuelto,
          );
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(startedAt: checkpoint, isPayment: false);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nota guardada'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    if (widget.existente == null || !widget.existente!.tieneTexto) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '¿Borrar nota?',
          style: GoogleFonts.oswald(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Se elimina solo este recordatorio. No cambia pagos ni saldos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _guardando = true);
    try {
      final checkpoint = DateTime.now().toUtc();
      await ref
          .read(notasOperativasContratoRepositoryProvider)
          .eliminar(widget.alumno.id);
      await ref
          .read(cajaAutoSyncServiceProvider)
          .afterMassiveMutation(startedAt: checkpoint, isPayment: false);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nota eliminada'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    final bgTop = isDark ? const Color(0xFF161018) : const Color(0xFFFFFBF5);
    final subtle = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.06,
    );

    final tieneGuardada =
        widget.existente != null && widget.existente!.tieneTexto;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: bgTop,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
          border: Border.all(color: _gold.withValues(alpha: 0.28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _gold.withValues(alpha: 0.22),
                            _gold.withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        Icons.edit_note_rounded,
                        color: _gold.withValues(alpha: 0.95),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NOTA OPERATIVA',
                            style: GoogleFonts.oswald(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.alumno.nombreAlumno,
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Solo recordatorio interno. No modifica cuotas, mora ni pagos.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.48),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: subtle,
                  borderRadius: BorderRadius.circular(18),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: 5,
                    minLines: 3,
                    style: GoogleFonts.outfit(fontSize: 15, height: 1.45),
                    decoration: InputDecoration(
                      hintText:
                          'Ej.: Quedaron \$50 del mes pasado para el próximo cobro…',
                      hintStyle: TextStyle(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.28),
                        fontWeight: FontWeight.w500,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.all(16),
                      errorText: _error,
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Material(
                    color: _resuelto
                        ? Colors.green.withValues(alpha: isDark ? 0.12 : 0.09)
                        : Colors.orange.withValues(alpha: isDark ? 0.1 : 0.06),
                    child: SwitchListTile.adaptive(
                      value: _resuelto,
                      onChanged: _guardando
                          ? null
                          : (v) => setState(() {
                              _resuelto = v;
                            }),
                      activeThumbColor: _resuelto
                          ? Colors.green.shade600
                          : _gold,
                      title: Text(
                        _resuelto
                            ? 'Marcado como hecho'
                            : 'Pendiente de resolver',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        _resuelto
                            ? 'Podés seguir editando o borrar cuando quieras.'
                            : 'Cuando lo atiendas el mes que viene, activá esto.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      secondary: Icon(
                        _resuelto
                            ? Icons.task_alt_rounded
                            : Icons.pending_actions_rounded,
                        color: _resuelto
                            ? Colors.green.shade600
                            : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _guardando ? null : _eliminar,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent.withValues(alpha: 0.9),
                      ),
                      label: Text(
                        tieneGuardada ? 'Eliminar' : 'Cerrar',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: tieneGuardada ? Colors.redAccent : null,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: tieneGuardada
                            ? Colors.redAccent
                            : null,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black54,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 20),
                      label: Text(
                        _guardando ? 'GUARDANDO…' : 'GUARDAR',
                        style: GoogleFonts.oswald(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
