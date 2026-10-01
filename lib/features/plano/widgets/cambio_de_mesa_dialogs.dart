import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/movimiento_mesas.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/salon_mesas.dart';
import '../services/cambios_de_mesa.dart';
import '../services/historial_sorteo.dart';

/// Motivos que se repiten, para no escribirlos cada vez.
const motivosParaFijar = [
  'Movilidad reducida',
  'Cerca del ingreso',
  'Cerca del escenario',
  'Pedido de la familia',
];
const motivosParaCambiar = [
  'Pedido de la familia',
  'Para estar con otra familia',
  'Movilidad reducida',
  'Error en el sorteo',
];
const motivosParaLibre = ['Columna', 'Paso de mozos', 'Reserva del salón'];

/// Pide confirmar un cambio en las mesas, mostrando antes cómo queda.
///
/// Devuelve el motivo escrito (vacío si no era obligatorio y no se escribió),
/// o null si se cancela.
Future<String?> confirmarCambioDeMesa({
  required BuildContext context,
  required String titulo,
  List<String> renglones = const [],
  List<String> avisos = const [],
  bool pedirMotivo = true,
  bool motivoObligatorio = true,
  List<String> sugerencias = const [],
  bool hayQueAvisarALaFamilia = false,
  String textoConfirmar = 'CONFIRMAR',
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmarCambioDialog(
        titulo: titulo,
        renglones: renglones,
        avisos: avisos,
        pedirMotivo: pedirMotivo,
        motivoObligatorio: motivoObligatorio,
        sugerencias: sugerencias,
        hayQueAvisarALaFamilia: hayQueAvisarALaFamilia,
        textoConfirmar: textoConfirmar,
      ),
    );

class ConfirmarCambioDialog extends StatefulWidget {
  final String titulo;

  /// Cómo queda: "GÓMEZ: 12, 13 → 40, 41".
  final List<String> renglones;
  final List<String> avisos;
  final bool pedirMotivo;
  final bool motivoObligatorio;
  final List<String> sugerencias;

  /// Alguna familia ya retiró sus entradas: hay que tildar que se le avisa.
  final bool hayQueAvisarALaFamilia;
  final String textoConfirmar;

  const ConfirmarCambioDialog({
    super.key,
    required this.titulo,
    this.renglones = const [],
    this.avisos = const [],
    this.pedirMotivo = true,
    this.motivoObligatorio = true,
    this.sugerencias = const [],
    this.hayQueAvisarALaFamilia = false,
    this.textoConfirmar = 'CONFIRMAR',
  });

  @override
  State<ConfirmarCambioDialog> createState() => _ConfirmarCambioDialogState();
}

class _ConfirmarCambioDialogState extends State<ConfirmarCambioDialog> {
  final _motivo = TextEditingController();
  bool _leAviso = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool get _listo =>
      (!widget.pedirMotivo ||
          !widget.motivoObligatorio ||
          _motivo.text.trim().isNotEmpty) &&
      (!widget.hayQueAvisarALaFamilia || _leAviso);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in widget.renglones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    r,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if (widget.avisos.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final a in widget.avisos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Expanded(child: Text(a)),
                      ],
                    ),
                  ),
              ],
              if (widget.pedirMotivo) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('motivo'),
                  controller: _motivo,
                  autofocus: true,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: widget.motivoObligatorio
                        ? '¿Por qué?'
                        : '¿Por qué? (si querés)',
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (widget.sugerencias.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in widget.sugerencias)
                        ActionChip(
                          label: Text(s),
                          onPressed: () => setState(() => _motivo.text = s),
                        ),
                    ],
                  ),
                ],
              ],
              if (widget.hayQueAvisarALaFamilia)
                CheckboxListTile(
                  key: const Key('le_aviso'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Le aviso a la familia'),
                  value: _leAviso,
                  onChanged: (v) => setState(() => _leAviso = v ?? false),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('confirmar'),
          onPressed:
              _listo ? () => Navigator.of(context).pop(_motivo.text.trim()) : null,
          child: Text(widget.textoConfirmar),
        ),
      ],
    );
  }
}

/// Elige para qué familia se fija una mesa, y por qué.
///
/// [resultadoDe] dice, para cada familia, qué mesas se le fijarían desde esa
/// mesa o por qué no se puede: así se ve antes de confirmar.
Future<({String alumnoId, String motivo})?> elegirFamiliaParaFijar({
  required BuildContext context,
  required int mesa,
  required List<ContratoAlumno> candidatos,
  required ({List<int> mesas, String? problema}) Function(String alumnoId)
      resultadoDe,
}) =>
    showDialog<({String alumnoId, String motivo})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FijarMesaDialog(
        mesa: mesa,
        candidatos: candidatos,
        resultadoDe: resultadoDe,
      ),
    );

class FijarMesaDialog extends StatefulWidget {
  final int mesa;

  /// Las familias que todavía no tienen mesa.
  final List<ContratoAlumno> candidatos;
  final ({List<int> mesas, String? problema}) Function(String alumnoId)
      resultadoDe;

  const FijarMesaDialog({
    super.key,
    required this.mesa,
    required this.candidatos,
    required this.resultadoDe,
  });

  @override
  State<FijarMesaDialog> createState() => _FijarMesaDialogState();
}

class _FijarMesaDialogState extends State<FijarMesaDialog> {
  final _busqueda = TextEditingController();
  final _motivo = TextEditingController();
  String? _elegida;

  @override
  void dispose() {
    _busqueda.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final consulta = _busqueda.text.trim();
    final lista = [
      for (final a in widget.candidatos)
        if (coincideTextoBusqueda([a.nombreAlumno, a.cursoDivision], consulta)) a,
    ];
    // Si el buscador dejó afuera a la que estaba elegida, deja de estarlo: no
    // se fija para una familia que no se ve.
    if (_elegida != null && !lista.any((a) => a.id == _elegida)) {
      _elegida = null;
    }
    final elegida = _elegida == null
        ? null
        : widget.candidatos.firstWhere((a) => a.id == _elegida);
    final resultado = elegida == null ? null : widget.resultadoDe(elegida.id);
    final sePuede = resultado != null && resultado.problema == null;
    final apellido =
        elegida == null ? '' : CambiosDeMesa.apellido(elegida);
    return AlertDialog(
      title: Text('Fijar desde la mesa ${widget.mesa}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.candidatos.isEmpty)
              const Text('Todas las familias ya tienen mesa.')
            else ...[
              TextField(
                key: const Key('buscar_familia'),
                controller: _busqueda,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar la familia',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: lista.isEmpty
                    ? const Center(child: Text('No hay ninguna con ese nombre.'))
                    : ListView(
                        children: [
                          for (final a in lista)
                            ListTile(
                              key: Key('familia_${a.id}'),
                              dense: true,
                              selected: a.id == _elegida,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08),
                              title: Text(a.nombreAlumno),
                              subtitle: Text([
                                if ((a.cursoDivision ?? '').trim().isNotEmpty)
                                  a.cursoDivision!.trim(),
                                SalonMesas.mesas(a) == 1
                                    ? '1 mesa'
                                    : '${SalonMesas.mesas(a)} mesas',
                              ].join(' · ')),
                              onTap: () => setState(() => _elegida = a.id),
                            ),
                        ],
                      ),
              ),
              if (resultado != null) ...[
                const SizedBox(height: 8),
                Text(
                  resultado.problema ??
                      (resultado.mesas.length == 1
                          ? 'A $apellido se le fija la mesa '
                              '${resultado.mesas.single}.'
                          : 'A $apellido se le fijan las mesas '
                              '${resultado.mesas.join(', ')}.'),
                  key: const Key('resultado_fijar'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: sePuede ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const Key('motivo'),
                controller: _motivo,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '¿Por qué?',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in motivosParaFijar)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => _motivo.text = s),
                    ),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('confirmar'),
          onPressed: sePuede && _motivo.text.trim().isNotEmpty
              ? () => Navigator.of(context).pop(
                    (alumnoId: _elegida!, motivo: _motivo.text.trim()),
                  )
              : null,
          child: const Text('FIJAR'),
        ),
      ],
    );
  }
}

/// El Historial de las mesas de la fiesta. Con [onDeshacer], los cambios que
/// siguen en pie se pueden volver atrás desde acá.
Future<void> mostrarHistorialSorteo({
  required BuildContext context,
  required HistorialSorteo historial,
  void Function(MovimientoMesas movimiento)? onDeshacer,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => HistorialSorteoDialog(
        historial: historial,
        onDeshacer: onDeshacer,
      ),
    );

class HistorialSorteoDialog extends StatelessWidget {
  final HistorialSorteo historial;
  final void Function(MovimientoMesas movimiento)? onDeshacer;

  const HistorialSorteoDialog({
    super.key,
    required this.historial,
    this.onDeshacer,
  });

  static IconData _icono(TipoRenglonHistorial t) => switch (t) {
        TipoRenglonHistorial.sorteo => Icons.casino,
        TipoRenglonHistorial.sorteoDeshecho => Icons.undo,
        TipoRenglonHistorial.sorteoRestaurado => Icons.restore_rounded,
        TipoRenglonHistorial.cambio => Icons.swap_horiz,
        TipoRenglonHistorial.mover => Icons.open_with,
        TipoRenglonHistorial.deshacer => Icons.undo,
        TipoRenglonHistorial.fijada => Icons.lock_outline,
        TipoRenglonHistorial.libre => Icons.block,
      };

  @override
  Widget build(BuildContext context) {
    final gris = Colors.grey.shade700;
    return AlertDialog(
      title: const Text('Historial de las mesas'),
      content: SizedBox(
        width: 560,
        child: historial.vacio
            ? const Text(
                'Todavía no se sorteó ni se cambió ninguna mesa en esta fiesta.',
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, r) in historial.renglones.indexed)
                    Padding(
                      key: Key('renglon_$i'),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_icono(r.tipo), size: 20, color: gris),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.titulo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: r.deshecho
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                for (final d in r.detalle) Text(d),
                                Text(
                                  [
                                    if (r.cuando != null)
                                      ArTime.formatFechaHora(r.cuando!),
                                    if ((r.quien ?? '').trim().isNotEmpty)
                                      r.quien!.trim(),
                                    if (r.deshecho) 'se deshizo',
                                  ].join(' · '),
                                  style: TextStyle(fontSize: 12, color: gris),
                                ),
                                if (r.movimiento != null &&
                                    !r.deshecho &&
                                    r.noSeDeshacePorque != null)
                                  Text(
                                    r.noSeDeshacePorque!,
                                    style: TextStyle(fontSize: 12, color: gris),
                                  ),
                              ],
                            ),
                          ),
                          if (onDeshacer != null && r.sePuedeDeshacer)
                            TextButton(
                              key: Key('deshacer_${r.movimiento!.id}'),
                              onPressed: () {
                                Navigator.of(context).pop();
                                onDeshacer!(r.movimiento!);
                              },
                              child: const Text('DESHACER'),
                            ),
                        ],
                      ),
                    ),
                  if (historial.sinRegistro.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Cambios sin registro (${historial.sinRegistro.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Mesas que hoy no son las del registro: se cambiaron a '
                      'mano, en Editar alumno.',
                      style: TextStyle(fontSize: 12, color: gris),
                    ),
                    const SizedBox(height: 4),
                    for (final c in historial.sinRegistro)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${c.nombre}: hoy ${c.hoy}; según el registro, '
                          '${c.segunElRegistro}.',
                        ),
                      ),
                  ],
                  if (onDeshacer == null &&
                      historial.renglones.any((r) => r.sePuedeDeshacer))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Para deshacer un cambio, abrí el Historial desde el '
                        'Plano del salón.',
                        key: const Key('donde_se_deshace'),
                        style: TextStyle(fontSize: 12, color: gris),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }
}
