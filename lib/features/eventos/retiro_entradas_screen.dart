import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_engine.dart';
import '../../core/utils/ar_time.dart';
import '../../models/contrato_alumno.dart';
import '../../models/entradas_retiro.dart';
import '../../models/evento.dart';
import '../common/services/pdf_service.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/quien_opera.dart';
import '../common/utils/subir_ya.dart';
import 'repositories/contratos_repository.dart';
import 'repositories/entradas_retiro_repository.dart';
import 'services/planilla_sorteo.dart';
import 'services/retiro_entradas.dart';
import 'services/salon_mesas.dart';
import 'widgets/entrega_entradas_dialog.dart';

/// La sección "Retiro de entradas" de una institución: quién ya retiró, quién
/// falta y quién no puede retirar todavía, y el diálogo del mostrador para
/// entregar.
///
/// Solo escribe `entradas_retiro`. La cuenta del alumno y los pagos se leen,
/// nunca se tocan: cobrar y editar al alumno abren las pantallas de siempre
/// ([onCobrar], [onEditarAlumno]).
class RetiroEntradasScreen extends ConsumerStatefulWidget {
  final Evento evento;
  final Future<void> Function(ContratoAlumno alumno) onCobrar;
  final Future<void> Function(ContratoAlumno alumno) onEditarAlumno;

  const RetiroEntradasScreen({
    super.key,
    required this.evento,
    required this.onCobrar,
    required this.onEditarAlumno,
  });

  @override
  ConsumerState<RetiroEntradasScreen> createState() =>
      _RetiroEntradasScreenState();
}

class _RetiroEntradasScreenState extends ConsumerState<RetiroEntradasScreen> {
  bool _cargando = true;
  String? _errorCarga;
  List<ContratoAlumno> _alumnos = [];
  Map<String, DeudaAlumno> _deudas = {};
  Map<String, EntradasRetiro> _retiros = {};
  bool _porDivision = false;
  bool _ocultarMontos = false;
  bool _ocupado = false;
  final _busqueda = TextEditingController();
  Timer? _refresco;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// Lo que, si baja de la otra PC, cambia lo que se ve acá: una entrega, la
  /// cuenta del alumno o un cobro.
  static const _tablasQueMiro = {
    'entradas_retiro',
    'contratos_alumnos',
    'pagos_contrato_alumno',
  };

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
    _cargar();
    // En tiempo real: cuando la otra PC entrega, sube al instante y avisa por el
    // pulso; esta PC lo baja en menos de un segundo, y acá se relee apenas llega.
    _cambiosSub = ref.read(syncEngineProvider).cambiosBajadosStream.listen((
      tablas,
    ) {
      if (!_ocupado && tablas.any(_tablasQueMiro.contains)) {
        _cargar(silencioso: true);
      }
    });
    // Red de seguridad por si el aviso no llega: releer lo local cada 15 s.
    _refresco = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_ocupado) _cargar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _cambiosSub?.cancel();
    _refresco?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargarPreferencias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ocultar = prefs.getBool('ocultarMontos_${widget.evento.id}') ?? false;
      if (mounted) setState(() => _ocultarMontos = ocultar);
    } catch (_) {
      // Sin la preferencia se muestran los montos, como en la grilla.
    }
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final repo = ref.read(contratosRepositoryProvider);
      final alumnos = (await repo.getByEvento(widget.evento.id))
          .where((a) => !a.esBajaTemporal)
          .toList()
        ..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
      final ids = [for (final a in alumnos) a.id];
      final pagos = <String, List<Map<String, dynamic>>>{};
      for (final p in await repo.getPagosForContratoIds(ids)) {
        final id = p['contrato_alumno_id'] as String?;
        if (id != null) pagos.putIfAbsent(id, () => []).add(p);
      }
      final mora = await repo.sumMoraCobradaHistorialPorContratos(ids);
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds(ids);
      final deudas = {
        for (final a in alumnos)
          a.id: RetiroEntradas.deudaDe(
            a,
            pagos: pagos[a.id] ?? const [],
            moraCobradaHistorial: mora[a.id] ?? 0,
          ),
      };
      if (!mounted) return;
      setState(() {
        _alumnos = alumnos;
        _deudas = deudas;
        _retiros = retiros;
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

  ContratoAlumno? _alumnoPorId(String id) {
    for (final a in _alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _plata(double monto) => _ocultarMontos ? '' : ' ${monto.toCurrency()}';

  // ── Estado de cada egresado ──────────────────────────────────────────────

  ({String texto, Color color, IconData icono}) _estado(ContratoAlumno a) {
    final r = _retiros[a.id];
    if (r != null && r.entregado) {
      final cambio =
          RetiroEntradas.cambioLaCuenta(r, RetiroEntradas.entradasDe(a));
      return cambio
          ? (
              texto: 'Retiró · cambió la cuenta',
              color: Colors.orange.shade800,
              icono: Icons.warning_amber_rounded,
            )
          : (
              texto: 'Retiró',
              color: Colors.green.shade700,
              icono: Icons.check_circle,
            );
    }
    final deuda = _deudas[a.id];
    final b = deuda == null
        ? BloqueoRetiro.ninguno
        : RetiroEntradas.bloqueo(a, deuda);
    return switch (b) {
      BloqueoRetiro.debe => (
          texto: 'Debe${_plata(deuda!.total)}',
          color: Colors.red.shade700,
          icono: Icons.block,
        ),
      BloqueoRetiro.cuentaNoCoincide => (
          texto: 'Revisar la cuenta',
          color: Colors.red.shade700,
          icono: Icons.report_problem_outlined,
        ),
      BloqueoRetiro.sinMesa => (
          texto: 'Sin mesa',
          color: Colors.orange.shade800,
          icono: Icons.table_restaurant_outlined,
        ),
      BloqueoRetiro.mesasNoCoinciden => (
          texto: 'Revisar sus mesas',
          color: Colors.orange.shade800,
          icono: Icons.table_restaurant_outlined,
        ),
      BloqueoRetiro.noEntran => (
          texto: 'No entran',
          color: Colors.orange.shade800,
          icono: Icons.groups_outlined,
        ),
      BloqueoRetiro.ninguno => (
          texto: 'Pendiente',
          color: Colors.blueGrey.shade600,
          icono: Icons.schedule,
        ),
    };
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _abrir(ContratoAlumno a) async {
    final deuda = _deudas[a.id];
    if (deuda == null || _ocupado) return;
    final accion = await mostrarEntregaEntradasDialog(
      context: context,
      alumno: a,
      entradas: RetiroEntradas.entradasDe(a),
      deuda: deuda,
      bloqueo: RetiroEntradas.bloqueo(a, deuda),
      retiro: _retiros[a.id],
      deOtros: RetiroEntradas.tramosDeOtros(_alumnos, _retiros, salvo: a.id),
    );
    if (accion == null || !mounted) return;
    switch (accion) {
      case IrACobrar():
        await widget.onCobrar(a);
        await _volverAAbrir(a.id);
      case EditarAlumno():
        await widget.onEditarAlumno(a);
        await _volverAAbrir(a.id);
      case AnularEntrega(:final motivo):
        await _anular(a, motivo);
      case final EntregarEntradas datos:
        await _entregar(a, datos);
    }
  }

  /// Después de cobrar o de editar al alumno, el diálogo vuelve con los datos
  /// nuevos: el flujo del mostrador sigue donde estaba.
  Future<void> _volverAAbrir(String id) async {
    await _cargar();
    if (!mounted) return;
    final fresco = _alumnoPorId(id);
    if (fresco != null) await _abrir(fresco);
  }

  Future<bool> _confirmar(String titulo, String texto, String boton) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(boton),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _avisar(String titulo, String texto) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ENTENDIDO'),
            ),
          ],
        ),
      );

  String _textoRetiro(EntradasRetiro r) =>
      '${r.parentesco?.etiqueta ?? ''} ${r.retiroNombre ?? ''}'
      '${r.entregadoAt == null ? '' : ', el ${ArTime.formatFechaHora(r.entregadoAt!)}'}'
      '${r.entregadoPor == null ? '' : ' (lo registró ${r.entregadoPor})'}';

  Future<void> _entregar(ContratoAlumno alumno, EntregarEntradas datos) async {
    setState(() => _ocupado = true);
    try {
      final repo = ref.read(entradasRetiroRepositoryProvider);

      // La otra PC puede haber entregado hace un minuto y todavía no bajó.
      var online = ref.read(connectivityServiceProvider).currentStatus !=
          AppConnectivity.offline;
      if (online) {
        try {
          final nube = await repo.traerDeLaNube(alumno.id);
          final local = _retiros[alumno.id];
          if (nube != null &&
              nube.entregado &&
              (local == null || nube.updatedAt.isAfter(local.updatedAt))) {
            await _cargar();
            if (mounted) {
              await _avisar(
                'Ya retiró',
                'La otra PC ya le entregó las entradas: ${_textoRetiro(nube)}. '
                    'No se guardó nada.',
              );
            }
            return;
          }
        } catch (_) {
          online = false;
        }
      }
      if (!online && mounted) {
        final seguir = await _confirmar(
          'Sin conexión',
          'No se puede ver si la otra PC ya le entregó las entradas. Seguí '
              'solo si hoy se entregan únicamente desde esta PC.',
          'SEGUIR',
        );
        if (!seguir) return;
      }

      // Con todo recién leído: si mientras el diálogo estaba abierto cambió la
      // cuenta, se anuló un cobro o la otra PC usó esos números, no se guarda.
      await _cargar();
      if (!mounted) return;
      final a = _alumnoPorId(alumno.id);
      final deuda = _deudas[alumno.id];
      final actual = _retiros[alumno.id];
      if (a == null || deuda == null) return;
      if (actual != null && actual.entregado) {
        await _avisar(
          'Ya retiró',
          'Ya figura entregado: ${_textoRetiro(actual)}. No se guardó nada.',
        );
        return;
      }
      final entradas = RetiroEntradas.entradasDe(a);
      final bloqueo = RetiroEntradas.bloqueo(a, deuda);
      final errorTramos = RetiroEntradas.errorTramos(
        tramos: datos.tramos,
        generales: entradas.generales,
        deOtros: RetiroEntradas.tramosDeOtros(_alumnos, _retiros, salvo: a.id),
      );
      if (bloqueo != BloqueoRetiro.ninguno || errorTramos != null) {
        await _avisar(
          'Cambió algo',
          '${errorTramos ?? 'La cuenta de este alumno cambió mientras el '
              'diálogo estaba abierto.'} No se guardó nada: volvé a abrirlo '
              'con los datos nuevos.',
        );
        return;
      }

      final checkpoint = DateTime.now().toUtc();
      final retiro = RetiroEntradas.nuevaEntrega(
        alumno: a,
        entradas: entradas,
        tramos: datos.tramos,
        menores10: datos.menores10,
        parentesco: datos.parentesco,
        nombre: datos.nombre,
        motivo: datos.motivo,
        autorizacionFirmada: datos.autorizacionFirmada,
        quien: quienOpera(ref),
        ahora: ArTime.nowUtc(),
        anterior: actual,
      );
      await repo.guardar(retiro);
      await _cargar();
      // Arriba ya, no en el próximo ciclo: mientras no sube, la otra PC no la ve
      // y podría entregarle de nuevo a la misma familia.
      final subio = await subirYa(
        ref.read(syncEngineProvider),
        tabla: 'entradas_retiro',
        registroId: retiro.id,
        desde: checkpoint,
      );
      if (!mounted) return;
      if (!subio) {
        await _avisar(
          'Entregado, pero todavía no subió',
          'La entrega quedó guardada en esta PC, pero no llegó a la nube (¿sin '
              'internet?). Hasta que suba, la otra PC no la ve: no le entreguen '
              'a esta familia desde la otra PC. Sube sola cuando vuelva la '
              'conexión.',
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            'Entregadas ${retiro.entradas} entradas a ${retiro.retiroNombre} '
            '(${retiro.parentesco?.etiqueta.toLowerCase() ?? ''}).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se guardó la entrega: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _anular(ContratoAlumno a, String motivo) async {
    final r = _retiros[a.id];
    if (r == null || !r.entregado) return;
    setState(() => _ocupado = true);
    try {
      final checkpoint = DateTime.now().toUtc();
      await ref.read(entradasRetiroRepositoryProvider).guardar(
            RetiroEntradas.anular(
              r,
              motivo: motivo,
              quien: quienOpera(ref),
              ahora: ArTime.nowUtc(),
            ),
          );
      await _cargar();
      final subio = await subirYa(
        ref.read(syncEngineProvider),
        tabla: 'entradas_retiro',
        registroId: r.id,
        desde: checkpoint,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            subio
                ? 'Entrega de ${a.nombreAlumno} anulada.'
                : 'Entrega de ${a.nombreAlumno} anulada en esta PC; sube a la '
                    'nube cuando vuelva la conexión.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se anuló: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _imprimir({required bool blancoYNegro}) async {
    try {
      await PdfService.generarPlanillaEntrega(
        widget.evento,
        _alumnos,
        retiros: _retiros,
        deudas: _deudas,
        blancoYNegro: blancoYNegro,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la planilla: $e')),
      );
    }
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final institucion = widget.evento.cliente?.nombreCompleto ?? 'Evento';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Retiro de entradas'),
            Text(
              institucion,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _ocupado ? null : () => _cargar(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<bool>(
            tooltip: 'Planilla de entrega',
            icon: const Icon(Icons.print_rounded),
            onSelected: (bn) => _imprimir(blancoYNegro: bn),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: true,
                child: Text('Planilla de entrega (blanco y negro)'),
              ),
              PopupMenuItem(
                value: false,
                child: Text('Planilla de entrega (color)'),
              ),
            ],
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
    final resumen = RetiroEntradas.resumen(_alumnos, _retiros, _deudas);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _tarjeta('Retiraron', '${resumen.retiraron} de ${resumen.alumnos}'),
              _tarjeta('Faltan', '${resumen.faltan}'),
              _tarjeta(
                'Con deuda',
                '${resumen.conDeuda}',
                color: resumen.conDeuda > 0 ? Colors.red.shade700 : null,
              ),
              _tarjeta(
                'Entradas entregadas',
                '${resumen.entradasEntregadas} de ${resumen.entradasTotales}',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.search),
                    label: Text('Mostrador'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_list),
                    label: Text('Por división'),
                  ),
                ],
                selected: {_porDivision},
                onSelectionChanged: (s) =>
                    setState(() => _porDivision = s.first),
              ),
              if (_ocupado) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _porDivision ? _vistaPorDivision() : _vistaMostrador()),
      ],
    );
  }

  Widget _tarjeta(String rotulo, String valor, {Color? color}) => Expanded(
        child: Card(
          elevation: 0,
          color: Colors.grey.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _vistaMostrador() {
    final q = _busqueda.text.trim().toLowerCase();
    final visibles = q.isEmpty
        ? _alumnos
        : _alumnos.where((a) => a.nombreAlumno.toLowerCase().contains(q)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _busqueda,
            autofocus: true,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: 'Apellido o nombre del egresado',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_busqueda.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visibles.isEmpty
              ? const Center(child: Text('Nadie con ese nombre.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: visibles.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (_, i) => _fila(visibles[i]),
                ),
        ),
      ],
    );
  }

  Widget _vistaPorDivision() {
    final grupos = <String, List<ContratoAlumno>>{};
    for (final a in _alumnos) {
      grupos.putIfAbsent(PlanillaSorteo.division(a), () => []).add(a);
    }
    final claves = grupos.keys.toList()
      ..sort((x, y) {
        if (x == PlanillaSorteo.sinDivision) return 1;
        if (y == PlanillaSorteo.sinDivision) return -1;
        return x.compareTo(y);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final d in claves) ...[
          () {
            final g = grupos[d]!;
            final r = g.where((a) => _retiros[a.id]?.entregado ?? false).length;
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Text(
                    d,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'retiraron $r de ${g.length}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: g.isEmpty ? 0 : r / g.length,
                      minHeight: 5,
                      color: Colors.green.shade600,
                      backgroundColor: Colors.grey.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            );
          }(),
          for (final a in grupos[d]!) _fila(a, compacta: true),
          const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _fila(ContratoAlumno a, {bool compacta = false}) {
    final e = RetiroEntradas.entradasDe(a);
    final r = _retiros[a.id];
    final estado = _estado(a);
    final division = a.cursoDivision?.trim() ?? '';
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';
    return InkWell(
      onTap: _ocupado ? null : () => _abrir(a),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compacta ? 6 : 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.nombreAlumno.trim(),
                    style: TextStyle(
                      fontSize: compacta ? 14 : 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${!compacta && division.isNotEmpty ? '$division · ' : ''}'
                    'mesa $mesa · ${e.lugares} entradas '
                    '(${e.vip} VIP + ${e.generales} generales)',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  if (r != null && r.entregado && !compacta)
                    Text(
                      '${r.parentesco?.etiqueta ?? ''}: ${r.retiroNombre ?? ''}'
                      '${r.entregadoAt == null ? '' : ' · ${ArTime.formatFechaHora(r.entregadoAt!)}'}'
                      '${r.tramos.isEmpty ? '' : ' · talonario ${TramoTalonario.legible(r.tramos)}'}',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: estado.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(estado.icono, size: 15, color: estado.color),
                  const SizedBox(width: 4),
                  Text(
                    estado.texto,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: estado.color,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
