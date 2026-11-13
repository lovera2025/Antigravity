import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../delegado/datos/link_del_delegado.dart';
import '../services/planilla_delegado.dart';
import '../services/planilla_delegado_bloqueo.dart';
import 'link_del_delegado_panel.dart';

/// El nombre del archivo que se le manda al delegado.
String nombreArchivoPlanillaDelegado(String institucion) {
  final limpio = institucion
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return 'Acompañantes y música - ${limpio.isEmpty ? 'institución' : limpio}.xlsx';
}

/// La ventana de PLANILLAS → "Acompañantes y música": exporta el Excel de la
/// institución para el delegado, y lo importa de vuelta.
///
/// **Importar empieza siempre como simulacro.** Al elegir el archivo no se
/// guarda nada: se muestra "Antes de guardar" —cuántos se cargan, cómo se leyó
/// cada uno, lo que cambia y lo que hay que revisar— y recién IMPORTAR escribe.
///
/// No sabe de archivos ni de la base: recibe qué hacer con cada cosa.
/// - [onGuardarArchivo]: pregunta dónde guardar y guarda. `false` si se canceló.
/// - [onElegirArchivo]: deja elegir un Excel y devuelve sus bytes. `null` si se
///   canceló.
/// - [onImportar]: guarda los cambios (todos o ninguno) y devuelve, si hay,
///   algo más para decir. Si tira, no se guardó nada.
///
/// **El link del delegado** (6.8.0): con [link], debajo del Excel va la sección
/// LINK PARA LOS DELEGADOS (`LinkDelDelegadoPanel`). TRAER LO CARGADO muestra
/// el mismo "Antes de guardar", armado con lo que cargaron por el link; lo
/// que todavía no enviaron va aparte, con un tilde para incluirlo. Guardar es
/// el mismo [onImportar]: del alumno solo entran acompañantes y música.
/// Después se le avisa a la nube qué se trajo, y eso no frena nada.
///
/// Devuelve `true` al cerrarse si se importó algo.
class AcompanantesMusicaDialog extends StatefulWidget {
  final String eventoId;
  final String institucion;

  /// Todos los alumnos de la fiesta, también los de baja.
  final List<ContratoAlumno> alumnos;

  final Future<bool> Function(Uint8List bytes, String nombre) onGuardarArchivo;
  final Future<Uint8List?> Function() onElegirArchivo;
  final Future<String?> Function(List<CambioDelegado> cambios) onImportar;

  /// El link del delegado de esta fiesta. Null: la sección no se muestra.
  final LinkDelDelegado? link;

  /// El link completo que se copia, a partir de la clave.
  final String Function(String clave)? urlDelLink;

  /// Abrir ya en la revisión de lo que mandaron (se llega así desde la
  /// alerta del Centro de Comando).
  final bool traerAlAbrir;

  /// Para las pruebas: cómo se elige el límite.
  final ElegirLimite? elegirLimite;

  /// Lo que se hace después de traer, cuando ya cambió lo que hay para traer.
  final VoidCallback? onTrajo;

  const AcompanantesMusicaDialog({
    super.key,
    required this.eventoId,
    required this.institucion,
    required this.alumnos,
    required this.onGuardarArchivo,
    required this.onElegirArchivo,
    required this.onImportar,
    this.link,
    this.urlDelLink,
    this.traerAlAbrir = false,
    this.elegirLimite,
    this.onTrajo,
  });

  @override
  State<AcompanantesMusicaDialog> createState() =>
      _AcompanantesMusicaDialogState();
}

class _AcompanantesMusicaDialogState extends State<AcompanantesMusicaDialog> {
  final _lista = ScrollController();

  /// Lo que quedó después de importar: se pisa lo que tenía cada alumno.
  late List<ContratoAlumno> _alumnos = widget.alumnos;

  /// El simulacro del archivo elegido. Null: todavía no se eligió ninguno.
  ResultadoPlanilla? _simulacro;
  bool _ocupado = false;
  bool _entendido = false;
  bool _importo = false;
  String? _dicho;
  bool _dichoEsError = false;

  /// Lo que cargaron los delegados, si el simulacro viene del link.
  List<CargaDelDelegado>? _cargas;
  bool _incluirSinEnviar = false;
  final _panel = GlobalKey<LinkDelDelegadoPanelState>();

  bool get _delLink => _cargas != null;

  /// Lo cargado por quien todavía no apretó Enviar.
  List<CargaDelDelegado> get _sinEnviar =>
      [for (final c in _cargas ?? const <CargaDelDelegado>[]) if (!c.entregado) c];

  /// Lo que entra en la revisión: lo enviado y, si se tildó, lo demás.
  List<CargaDelDelegado> get _incluidas => [
        for (final c in _cargas ?? const <CargaDelDelegado>[])
          if (c.entregado || _incluirSinEnviar) c,
      ];

  @override
  void initState() {
    super.initState();
    if (widget.traerAlAbrir && widget.link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _traerDelLink());
    }
  }

  @override
  void dispose() {
    _lista.dispose();
    super.dispose();
  }

  List<ContratoAlumno> get _activos =>
      PlanillaDelegado.alumnosDeLaPlanilla(_alumnos);

  int get _conAcompanantes => _activos
      .where((a) => PlanillaDelegado.limpios(a.nombresAcompanantes).isNotEmpty)
      .length;

  int get _conMusica =>
      _activos.where((a) => (a.musicaElegida ?? '').trim().isNotEmpty).length;

  void _decir(String texto, {bool error = false}) => setState(() {
    _dicho = texto;
    _dichoEsError = error;
  });

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      final planilla = exportarPlanillaDelegado(
        eventoId: widget.eventoId,
        institucion: widget.institucion,
        alumnos: _alumnos,
      );
      final guardo = await widget.onGuardarArchivo(
        planilla.bytes,
        nombreArchivoPlanillaDelegado(widget.institucion),
      );
      if (!mounted || !guardo) return;
      _decir(
        'Excel guardado, con ${_activos.length} alumno(s). Mandáselo al '
        'delegado: solo puede completar Acompañantes y Música.'
        '${planilla.cerrada ? '' : ' Esta vez salió sin cerrar: pedile que no '
                  'toque las otras columnas. Al importar se ignoran igual.'}',
      );
    } catch (_) {
      if (mounted) {
        _decir(
          'No se pudo guardar el Excel. Fijate que no esté abierto en otro '
          'programa y probá de nuevo.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _elegir() async {
    setState(() => _ocupado = true);
    try {
      final bytes = await widget.onElegirArchivo();
      if (!mounted || bytes == null) return;
      setState(() {
        _dicho = null;
        _entendido = false;
        _simulacro = PlanillaDelegado.comparar(
          lectura: PlanillaDelegado.leer(bytes),
          alumnos: _alumnos,
          eventoId: widget.eventoId,
          institucion: widget.institucion,
        );
      });
    } catch (_) {
      if (mounted) {
        _decir(
          'No se pudo leer el archivo. Fijate que no esté abierto en otro '
          'programa y probá de nuevo.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// TRAER LO CARGADO: lee lo que cargaron los delegados y arma la revisión.
  /// No guarda nada.
  Future<void> _traerDelLink() async {
    final link = widget.link;
    if (link == null || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      final cargas = await link.cargas(widget.eventoId);
      if (!mounted) return;
      setState(() {
        _dicho = null;
        _entendido = false;
        _incluirSinEnviar = false;
        _cargas = cargas;
        _simulacro = _simulacroDelLink();
      });
    } catch (_) {
      if (mounted) {
        _decir(
          'No se pudo traer lo cargado: hace falta internet. Probá de nuevo.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  ResultadoPlanilla _simulacroDelLink() => PlanillaDelegado.comparar(
        lectura: lecturaDeLasCargas(
          eventoId: widget.eventoId,
          fiesta: widget.institucion,
          cargas: _incluidas,
        ),
        alumnos: _alumnos,
        eventoId: widget.eventoId,
        institucion: widget.institucion,
      );

  Future<void> _importar() async {
    final cambios = _simulacro!.cambios;
    final link = widget.link;
    final traidas = _delLink ? [for (final c in _incluidas) c.alumnoId] : null;
    setState(() => _ocupado = true);
    try {
      final algoMas = await widget.onImportar(cambios);
      // Ya está guardado. Avisarle a la nube qué se trajo no puede frenar ni
      // deshacer nada: si falla, la alerta sigue hasta la próxima.
      var avisado = true;
      if (traidas != null && link != null) {
        try {
          await link.cambiar(widget.eventoId, 'traido', idsTraidos(traidas));
        } catch (_) {
          avisado = false;
        }
        widget.onTrajo?.call();
      }
      if (!mounted) return;
      final porId = {for (final c in cambios) c.alumno.id: c};
      setState(() {
        _importo = true;
        _alumnos = [
          for (final a in _alumnos)
            porId.containsKey(a.id)
                ? a.copyWith(
                    nombresAcompanantes: porId[a.id]!.acompanantes,
                    cantidadAcompanantes: porId[a.id]!.acompanantes?.length,
                    musicaElegida: porId[a.id]!.musica,
                  )
                : a,
        ];
        _simulacro = null;
        _cargas = null;
      });
      _decir(
        'Se cargaron ${cambios.length} alumno(s). Suben a la nube y llegan a '
        'las otras PCs.${algoMas == null ? '' : ' $algoMas'}'
        '${avisado ? '' : ' No se le pudo avisar a la nube que ya se trajo: la alerta puede seguir un rato.'}',
      );
      unawaited(_panel.currentState?.recargar());
    } catch (_) {
      if (mounted) {
        _decir(
          'No se guardó nada. Probá de nuevo; si sigue, cerrá esta ventana y '
          'volvé a abrirla.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _dato(String nombre, int valor, {Color? color}) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: Theme.of(context).textTheme.bodySmall),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _aviso(String texto, {required Color color, Key? key}) => Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(texto, style: const TextStyle(fontSize: 13)),
  );

  List<Widget> _inicio(BuildContext context) => [
    Row(
      children: [
        _dato('Con acompañantes', _conAcompanantes),
        const SizedBox(width: 10),
        _dato('Con música', _conMusica),
      ],
    ),
    const SizedBox(height: 14),
    Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          key: const Key('delegado_exportar'),
          onPressed: _ocupado ? null : _exportar,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('EXPORTAR EXCEL'),
        ),
        OutlinedButton.icon(
          key: const Key('delegado_importar'),
          onPressed: _ocupado ? null : _elegir,
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('IMPORTAR EXCEL'),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Text(
      'El Excel es solo de esta institución, con todos sus alumnos menos '
      'los dados de baja. El delegado completa hasta $kMaxAcompanantes '
      'acompañantes y la música de cada uno.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    if (widget.link != null)
      LinkDelDelegadoPanel(
        key: _panel,
        link: widget.link!,
        eventoId: widget.eventoId,
        fiesta: widget.institucion,
        urlDelLink: widget.urlDelLink ?? (clave) => clave,
        onTraer: _traerDelLink,
        elegirLimite: widget.elegirLimite ?? elegirLimiteConSelectores,
      ),
    if (_dicho != null)
      _aviso(
        _dicho!,
        key: const Key('delegado_dicho'),
        color: _dichoEsError ? Colors.redAccent : Colors.teal,
      ),
  ];

  List<Widget> _antesDeGuardar(BuildContext context, ResultadoPlanilla r) {
    final tema = Theme.of(context);
    if (r.rechazo != null) {
      return [
        _aviso(
          r.rechazo!,
          key: const Key('delegado_rechazo'),
          color: Colors.redAccent,
        ),
      ];
    }
    final pisan = r.cambios.where((c) => c.pisaAlgo).toList();
    final conComa = r.cambios.where((c) => c.conComa).length;
    final cargo = {
      for (final c in _cargas ?? const <CargaDelDelegado>[])
        c.alumnoId: c.cargo ?? 'alguien a quien se sacó',
    };
    final sinEnviar = _sinEnviar;
    return [
      Row(
        children: [
          _dato('Se cargan', r.cambios.length),
          const SizedBox(width: 8),
          _dato('Ya estaban', r.iguales),
          const SizedBox(width: 8),
          _dato('Vacíos', r.vacios),
          const SizedBox(width: 8),
          _dato(
            'Revisar',
            r.revisar.length,
            color: r.revisar.isEmpty ? null : Colors.orange.shade800,
          ),
        ],
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 250),
        child: Scrollbar(
          controller: _lista,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _lista,
            // A todo el ancho, y con lugar a la derecha: la barra de
            // desplazamiento se dibuja encima del borde y tapaba el final del
            // renglón más largo.
            padding: const EdgeInsets.only(right: 16, bottom: 6),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                key: const Key('delegado_detalle'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.revisar.isNotEmpty) ...[
                    Text(
                      'Revisar: no se cargan',
                      style: tema.textTheme.labelLarge,
                    ),
                    for (final x in r.revisar)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '$x',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  if (pisan.isNotEmpty) ...[
                    Text(
                      'Cambia lo que ya tenían',
                      style: tema.textTheme.labelLarge,
                    ),
                    for (final c in pisan)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${PlanillaDelegado.nombreLimpio(c.alumno)}: '
                          '${c.tenia} → ${c.leido}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  if (r.cambios.isNotEmpty) ...[
                    Text('Cómo se leyó', style: tema.textTheme.labelLarge),
                    for (final c in r.cambios)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${PlanillaDelegado.nombreLimpio(c.alumno)} · '
                          '${c.leido}'
                          '${c.conComa ? '  (con coma: una sola persona)' : ''}'
                          '${cargo[c.alumno.id] == null ? '' : '  · lo cargó ${cargo[c.alumno.id]}'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  if (r.cambios.isEmpty && r.revisar.isEmpty)
                    Text(
                      _delLink
                          ? 'No hay nada nuevo para cargar.'
                          : 'El Excel no trae nada nuevo para cargar.',
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (conComa > 0)
        _aviso(
          '$conComa casillero(s) traen una coma. La coma no separa: se tomó '
          'como una sola persona. Miralos arriba antes de importar.',
          color: Colors.orange,
        ),
      if (sinEnviar.isNotEmpty)
        CheckboxListTile(
          key: const Key('delegado_incluir_sin_enviar'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Incluir también lo que todavía no enviaron '
            '(${sinEnviar.length} alumno(s))',
          ),
          value: _incluirSinEnviar,
          onChanged: _ocupado
              ? null
              : (v) => setState(() {
                    _incluirSinEnviar = v == true;
                    _entendido = false;
                    _simulacro = _simulacroDelLink();
                  }),
        ),
      if (pisan.isNotEmpty)
        CheckboxListTile(
          key: const Key('delegado_entendido'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Entiendo que a ${pisan.length} alumno(s) se les reemplaza lo que '
            'ya tenían',
          ),
          value: _entendido,
          onChanged: (v) => setState(() => _entendido = v == true),
        ),
      if (_dicho != null)
        _aviso(
          _dicho!,
          key: const Key('delegado_dicho'),
          color: _dichoEsError ? Colors.redAccent : Colors.teal,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = _simulacro;
    final sePuede =
        r != null &&
        r.sePuedeImportar &&
        (_entendido || !r.cambios.any((c) => c.pisaAlgo));
    return AlertDialog(
      title: Text(r == null ? 'Acompañantes y música' : 'Antes de guardar'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.institucion} · ${_activos.length} alumno(s)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (r == null)
                ..._inicio(context)
              else
                ..._antesDeGuardar(context, r),
            ],
          ),
        ),
      ),
      actions: r == null
          ? [
              TextButton(
                key: const Key('delegado_cerrar'),
                onPressed: _ocupado
                    ? null
                    : () => Navigator.pop(context, _importo),
                child: const Text('CERRAR'),
              ),
            ]
          : [
              TextButton(
                key: const Key('delegado_volver'),
                onPressed: _ocupado
                    ? null
                    : () => setState(() {
                        _simulacro = null;
                        _cargas = null;
                        _dicho = null;
                      }),
                child: const Text('VOLVER'),
              ),
              if (r.rechazo == null)
                ElevatedButton(
                  key: const Key('delegado_confirmar'),
                  onPressed: _ocupado || !sePuede ? null : _importar,
                  child: Text(
                    r.cambios.isEmpty
                        ? (_delLink ? 'NADA PARA CARGAR' : 'NADA PARA IMPORTAR')
                        : _delLink
                            ? 'ACEPTAR Y CARGAR ${r.cambios.length} ALUMNO(S)'
                            : 'IMPORTAR ${r.cambios.length} ALUMNO(S)',
                  ),
                ),
            ],
    );
  }
}
