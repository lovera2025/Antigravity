import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../dibujo/pintor_plano.dart' show EncuadrePlano;
import '../estilos/estilo_plano.dart';
import '../modelo/estado_plano.dart';
import '../services/plano_de_la_fiesta.dart';
import 'vista_plano.dart';

/// Dónde van las mesas "lejos" de una familia (6.5.0, pedido del usuario el
/// 9-nov): el jefe toca, en el salón de la fiesta, las mesas libres de la zona
/// donde las quiere. **Se abre encima del cartel del sorteo**: no hace falta ir
/// a PLANO.
///
/// El sorteo las pone ahí si están libres y no tocan a la familia; si la zona se
/// llena, lo más lejos que pueda, y lo avisa (`SorteoConPlano`).
class ElegirZonaDialog extends StatefulWidget {
  const ElegirZonaDialog({
    super.key,
    required this.plano,
    required this.alumnos,
    required this.nombre,
    required this.necesita,
    this.elegidas = const {},
  });

  final PlanoEvento plano;
  final List<ContratoAlumno> alumnos;

  /// La familia: "RÍOS, MATEO".
  final String nombre;

  /// Cuántas van lejos.
  final int necesita;
  final Set<int> elegidas;

  /// Las mesas elegidas, o null si se canceló.
  static Future<Set<int>?> abrir(
    BuildContext context, {
    required PlanoEvento plano,
    required List<ContratoAlumno> alumnos,
    required String nombre,
    required int necesita,
    Set<int> elegidas = const {},
  }) =>
      showDialog<Set<int>>(
        context: context,
        builder: (_) => ElegirZonaDialog(
          plano: plano,
          alumnos: alumnos,
          nombre: nombre,
          necesita: necesita,
          elegidas: elegidas,
        ),
      );

  @override
  State<ElegirZonaDialog> createState() => _ElegirZonaDialogState();
}

class _ElegirZonaDialogState extends State<ElegirZonaDialog> {
  late final _fiesta = PlanoDeLaFiesta.desde(
    armado: widget.plano.armado,
    config: widget.plano.config,
    alumnos: widget.alumnos,
  );
  late final _tema =
      TemaPlano.de(widget.plano.estiloPlano ?? EstiloPlano.gala);
  late final Set<int> _sel = {...widget.elegidas};
  late String _hoja = _primeraHoja();
  final _zoom = TransformationController();
  String? _aviso;

  String _primeraHoja() {
    final a = widget.plano.armado;
    for (final h in a.hojas) {
      if (a.mesasDeHoja(h.id).isNotEmpty) return h.id;
    }
    return a.hojas.first.id;
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Por qué no se puede elegir [n], o null si está libre.
  String? _porQueNo(int n) {
    final info = _fiesta.estado.info(n);
    switch (info.estado) {
      case EstadoMesa.vacia:
        return null;
      case EstadoMesa.ocupada:
      case EstadoMesa.conflicto:
        final quien = info.ocupante?.nombre;
        return quien == null
            ? 'La mesa $n ya tiene familia.'
            : 'La mesa $n ya es de $quien.';
      case EstadoMesa.fijada:
        return 'La mesa $n está fijada para ${info.fijadaPara?.nombre ?? 'otra familia'}.';
      case EstadoMesa.libre:
        return 'La mesa $n se dejó libre a propósito.';
    }
  }

  void _tocar(int n) {
    final no = _porQueNo(n);
    setState(() {
      if (no != null) {
        _aviso = no;
        return;
      }
      _aviso = null;
      if (!_sel.remove(n)) _sel.add(n);
    });
  }

  void _listo() {
    if (_sel.isEmpty) {
      setState(() => _aviso = 'Marcá al menos una mesa libre.');
      return;
    }
    Navigator.of(context).pop({..._sel});
  }

  @override
  Widget build(BuildContext context) {
    final armado = widget.plano.armado;
    final tam = MediaQuery.sizeOf(context);
    final elegidas = _sel.toList()..sort();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(1100, tam.width - 48),
        height: math.min(760, tam.height - 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dónde van las lejos de ${widget.nombre}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Tocá las mesas libres de la zona; otra vez, para sacarla. '
                'Necesita ${widget.necesita}. Si la zona se llena, van lo más '
                'lejos que se pueda y el sorteo te avisa.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              if (armado.hojas.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final h in armado.hojas)
                      if (armado.mesasDeHoja(h.id).isNotEmpty)
                        ChoiceChip(
                          label: Text(h.titulo.isEmpty ? 'Hoja' : h.titulo),
                          selected: h.id == _hoja,
                          onSelected: (_) => setState(() {
                            _hoja = h.id;
                            _zoom.value = Matrix4.identity();
                          }),
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final hoja = armado.hoja(_hoja);
                    if (hoja == null) return const SizedBox.shrink();
                    final base = EncuadrePlano.de(hoja.caja, c.biggest).escala;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: _tema.fondo,
                        child: InteractiveViewer(
                          transformationController: _zoom,
                          minScale: 1,
                          maxScale: 6,
                          child: AnimatedBuilder(
                            animation: _zoom,
                            builder: (context, _) => VistaPlano(
                              key: const ValueKey('zona_plano'),
                              armado: armado,
                              hoja: _hoja,
                              tema: _tema,
                              estado: _fiesta.estado,
                              resaltadas: _sel,
                              animar: false,
                              zoom: NivelDetalle.zoomQueCuenta(
                                armado.radio * base,
                                _zoom.value.getMaxScaleOnAxis(),
                              ),
                              onTapMesa: _tocar,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (_aviso != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _aviso!,
                    key: const ValueKey('zona_aviso'),
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      elegidas.isEmpty
                          ? 'Ninguna elegida todavía'
                          : 'Elegidas: ${elegidas.join(', ')} · necesita '
                              '${widget.necesita}',
                      key: const ValueKey('zona_elegidas'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCELAR'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('zona_listo'),
                    onPressed: _listo,
                    child: const Text('LISTO'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
