import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_engine.dart';
import '../../models/contrato_alumno.dart';
import '../../models/evento.dart';
import '../../models/plano_evento.dart';
import '../../models/sillas_reparto.dart';
import '../common/utils/quien_opera.dart';
import '../common/utils/subir_ya.dart';
import '../eventos/repositories/contratos_repository.dart';
import '../eventos/repositories/sillas_reparto_repository.dart';
import '../eventos/services/salon_mesas.dart';
import 'estilos/estilo_plano.dart';
import 'modelo/medidas_salon.dart';
import 'repositories/planos_evento_repository.dart';
import 'services/aplicar_eleccion.dart';
import 'services/plano_de_la_fiesta.dart';
import 'widgets/elegir_plano_dialog.dart';
import 'widgets/plano_evento_cuerpo.dart';

/// El plano del salón de una fiesta: el armado con sus medidas, las familias
/// en sus mesas y lo que hay que revisar.
///
/// Lee siempre los datos del momento (las fichas, el reparto de sillas y el
/// plano), y se refresca sola cuando baja un cambio de la otra PC. Lo único que
/// escribe es `planos_evento`, y antes de escribir relee el plano de la nube.
class PlanoEventoScreen extends ConsumerStatefulWidget {
  final Evento evento;

  /// La familia que se abre resaltada, cuando se llega desde su renglón.
  final String? resaltarAlumnoId;

  const PlanoEventoScreen({
    super.key,
    required this.evento,
    this.resaltarAlumnoId,
  });

  @override
  ConsumerState<PlanoEventoScreen> createState() => _PlanoEventoScreenState();
}

class _PlanoEventoScreenState extends ConsumerState<PlanoEventoScreen> {
  bool _cargando = true;
  bool _ocupado = false;
  String? _errorCarga;
  List<ContratoAlumno> _alumnos = [];
  Map<String, SillasReparto> _repartos = {};
  PlanoEvento? _plano;

  /// Lo que se muestra, ya calculado. Null si la fiesta no tiene plano o si su
  /// armado no se puede leer.
  PlanoDeLaFiesta? _vista;
  bool _yaOfrecioArmar = false;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// Lo que, si baja de la otra PC, cambia lo que se ve acá.
  static const _tablasQueMiro = {
    'planos_evento',
    'contratos_alumnos',
    'sillas_reparto',
  };

  @override
  void initState() {
    super.initState();
    _cargar(nube: true).then((_) => _ofrecerArmar());
    _cambiosSub = ref.read(syncEngineProvider).cambiosBajadosStream.listen((
      tablas,
    ) {
      // Lo que bajó ya está en la base de esta PC: alcanza con releerla.
      if (!_ocupado && tablas.any(_tablasQueMiro.contains)) {
        _cargar(silencioso: true);
      }
    });
  }

  @override
  void dispose() {
    _cambiosSub?.cancel();
    super.dispose();
  }

  bool get _hayConexion =>
      ref.read(connectivityServiceProvider).currentStatus ==
      AppConnectivity.online;

  /// El plano de la fiesta: con [nube], primero el de la nube (por si la otra
  /// PC lo tocó hace un momento) y, si no hay red, el de esta PC.
  Future<PlanoEvento?> _leerPlano({required bool nube}) async {
    final planos = ref.read(planosEventoRepositoryProvider);
    final id = widget.evento.id;
    if (nube && _hayConexion) {
      try {
        return await planos.traerDeLaNube(id);
      } catch (_) {
        // Sin red, o la tabla todavía no existe en la nube: manda esta PC.
      }
    }
    return planos.obtener(id);
  }

  Future<void> _cargar({bool nube = false, bool silencioso = false}) async {
    try {
      final alumnos = await ref
          .read(contratosRepositoryProvider)
          .getByEvento(widget.evento.id);
      final repartos = await ref
          .read(sillasRepartoRepositoryProvider)
          .obtenerPorContratoIds([for (final a in alumnos) a.id]);
      final plano = await _leerPlano(nube: nube);
      final armado = plano?.armadoONull;
      final vista = plano == null || armado == null
          ? null
          : PlanoDeLaFiesta.desde(
              armado: armado,
              config: plano.config,
              alumnos: alumnos,
              repartos: repartos,
            );
      if (!mounted) return;
      setState(() {
        _alumnos = alumnos;
        _repartos = repartos;
        _plano = plano;
        _vista = vista;
        _cargando = false;
        _errorCarga = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (!silencioso) _errorCarga = '$e';
      });
    }
  }

  /// La primera vez que se entra, la fiesta no tiene plano: se abren los tres
  /// pasos sin que haya que buscar el botón.
  void _ofrecerArmar() {
    if (!mounted || _yaOfrecioArmar || _errorCarga != null) return;
    _yaOfrecioArmar = true;
    if (_plano == null) _elegir();
  }

  bool get _hayFamiliasConMesa =>
      _alumnos.any((a) => !a.esBajaTemporal && SalonMesas.tieneNumeros(a));

  Future<void> _elegir() async {
    if (_ocupado) return;
    final actual = _plano;
    final tieneArmado = actual?.armadoONull != null;
    final eleccion = await mostrarElegirPlano(
      context: context,
      mesasNecesarias: PlanoDeLaFiesta.mesasQueNecesita(_alumnos),
      medidas: actual?.config.medidas ?? const MedidasPlano(),
      actual: actual,
      ocupantes: PlanoDeLaFiesta.ocupantes(_alumnos, _repartos),
      armadoTrabado: tieneArmado && _hayFamiliasConMesa
          ? 'Ya hay familias con mesa: para cambiar el armado hay que deshacer '
              'el sorteo. El estilo se cambia siempre.'
          : null,
    );
    if (eleccion == null || !mounted) return;
    await _guardar(eleccion);
  }

  Future<void> _guardar(EleccionPlano eleccion) async {
    setState(() => _ocupado = true);
    try {
      final desde = DateTime.now().toUtc();
      // Antes de escribir, lo que diga la nube: sube la fila entera, y con la
      // de esta PC se pisaría lo que la otra acaba de cambiar.
      final fresco = await _leerPlano(nube: true);
      final resultado = aplicarEleccionAlPlano(
        eventoId: widget.evento.id,
        fresco: fresco,
        armado: eleccion.armado,
        estilo: eleccion.estilo,
        modo: eleccion.modo,
        hayFamiliasConMesa: _hayFamiliasConMesa,
        hechoPor: quienOpera(ref),
        ahora: DateTime.now().toUtc(),
      );
      final nuevo = resultado.plano;
      // El diálogo ya no dejaba cambiar el armado si acá se veía el plano. Si
      // se conservó sin que se viera, es que lo armó la otra PC.
      final aviso = resultado.conservoArmado && _plano?.armadoONull == null
          ? 'La otra PC ya había armado el plano: se conservó su armado.'
          : null;
      await ref.read(planosEventoRepositoryProvider).guardar(nuevo);
      await _cargar();
      final subio = await subirYa(
        ref.read(syncEngineProvider),
        tabla: 'planos_evento',
        registroId: nuevo.id,
        desde: desde,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${aviso ?? 'Plano guardado.'}'
            '${subio ? '' : ' Quedó en esta PC; sube cuando vuelva la conexión.'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se guardó el plano: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final institucion = widget.evento.cliente?.nombreCompleto ?? 'Evento';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plano del salón'),
            Text(
              institucion,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _ocupado ? null : () => _cargar(nube: true),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Center(child: Text('No se pudo cargar: $_errorCarga'))
              : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    final plano = _plano;
    final vista = _vista;
    if (plano == null || vista == null) {
      return _SinPlano(
        ilegible: plano != null,
        onArmar: _ocupado ? null : _elegir,
      );
    }
    return PlanoEventoCuerpo(
      // Con otro armado se arranca de cero: hoja, zoom y selección.
      key: ValueKey(plano.armadoJson.hashCode),
      plano: vista,
      estilo: plano.estiloPlano ?? EstiloPlano.arquitecto,
      alumnos: _alumnos,
      repartos: _repartos,
      resaltarAlumnoId: widget.resaltarAlumnoId,
      onEstiloYArmado: _ocupado ? null : _elegir,
    );
  }
}

/// La fiesta todavía no tiene plano (o el que tiene no se puede leer).
class _SinPlano extends StatelessWidget {
  final bool ilegible;
  final VoidCallback? onArmar;

  const _SinPlano({required this.ilegible, required this.onArmar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant_outlined,
                size: 56, color: tema.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              ilegible
                  ? 'El armado de esta fiesta no se puede leer'
                  : 'Esta fiesta todavía no tiene plano',
              style: tema.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              ilegible
                  ? 'Elegí el armado de nuevo. Lo demás del plano se conserva.'
                  : 'Se arma en tres pasos y ya viene todo elegido: el armado '
                      'del salón, el estilo y cómo se sortea.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('armar_plano'),
              onPressed: onArmar,
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: Text(ilegible ? 'ELEGIR EL ARMADO' : 'ARMAR EL PLANO'),
            ),
          ],
        ),
      ),
    );
  }
}
