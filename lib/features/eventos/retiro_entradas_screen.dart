import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_engine.dart';
import '../../core/utils/ar_time.dart';
import '../../models/contrato_alumno.dart';
import '../../models/entradas_retiro.dart';
import '../../models/entrega_entradas.dart';
import '../../models/evento.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../common/services/imprimir_planilla_de_entrega.dart';
import '../common/utils/cortes_pantalla.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/quien_opera.dart';
import '../common/utils/solo_jefe.dart';
import '../common/utils/texto_busqueda.dart';
import '../entradas/cuentas/lugares_de_la_familia.dart';
import '../entradas/datos/entradas_repositorio.dart';
import '../entradas/providers/entradas_providers.dart';
import '../entradas/services/en_caja.dart';
import '../entradas/services/nombre_de_la_fiesta.dart';
import '../entradas/widgets/para_rendir_screen.dart';
import '../entradas/widgets/precios_de_entradas_dialog.dart';
import '../entradas/widgets/vender_entradas_screen.dart';
import '../entradas/widgets/ventas_de_entradas_screen.dart';
import 'repositories/contratos_repository.dart';
import 'repositories/entradas_entregas_repository.dart';
import 'repositories/entradas_retiro_repository.dart';
import 'repositories/entregar_parte_de_la_app.dart';
import 'repositories/sorteos_mesas_repository.dart';
import 'services/entrega_por_partes.dart';
import 'services/entregar_parte.dart';
import 'services/lugares_al_sorteo.dart';
import 'services/lugares_pagos.dart';
import 'services/permisos_de_entrega.dart';
import 'services/planilla_sorteo.dart';
import 'services/retiro_entradas.dart';
import 'services/salon_mesas.dart';
import 'widgets/carteles_de_la_entrega.dart';
import 'widgets/entrega_entradas_dialog.dart';
import 'widgets/lugares_al_sorteo_dialog.dart';

/// La sección "Retiro de entradas" de una institución: quién ya retiró, quién
/// falta y quién no puede retirar todavía, y el diálogo del mostrador para
/// entregar.
///
/// **La entrega sin cargo va en dos partes** (20-nov-2026), cada una cuando
/// llega su material: las pulseras VIP con cena y las entradas generales. **No
/// escribe nada por su cuenta**: entregar y anular van por `EntregarParte`
/// (`entregarParteProvider`), el único camino para guardar una entrega
/// (`test/entregar_parte_test.dart`). La cuenta del alumno y los pagos se leen,
/// nunca se tocan: cobrar y editar al alumno abren las pantallas de siempre
/// ([onCobrar], [onEditarAlumno]).
class RetiroEntradasScreen extends ConsumerStatefulWidget {
  final Evento evento;

  /// En la oficina, el cobro y la edición de siempre. En el mostrador, null.
  final Future<void> Function(ContratoAlumno alumno)? onCobrar;
  final Future<void> Function(ContratoAlumno alumno)? onEditarAlumno;

  /// Se llegó desde PLANILLAS → "Planilla de entrega": apenas carga, pregunta
  /// si va en color o en blanco y negro.
  final bool imprimirAlAbrir;

  /// El mostrador de Entradas: el operador que entró solo a entregar. No cobra
  /// ni edita al alumno; la familia que debe va a la caja y queda en "En caja",
  /// y cuando el pago llega salta "pagó: ya podés entregar" (6.4.0).
  final bool enElMostrador;

  /// Desde la pantalla de la fiesta (la oficina).
  const RetiroEntradasScreen({
    super.key,
    required this.evento,
    required Future<void> Function(ContratoAlumno alumno) this.onCobrar,
    required Future<void> Function(ContratoAlumno alumno) this.onEditarAlumno,
    this.imprimirAlAbrir = false,
  }) : enElMostrador = false;

  /// Desde el mostrador de Entradas (`EntradasHomeScreen`).
  const RetiroEntradasScreen.mostrador({super.key, required this.evento})
      : onCobrar = null,
        onEditarAlumno = null,
        imprimirAlAbrir = false,
        enElMostrador = true;

  @override
  ConsumerState<RetiroEntradasScreen> createState() =>
      _RetiroEntradasScreenState();
}

class _RetiroEntradasScreenState extends ConsumerState<RetiroEntradasScreen> {
  bool _cargando = true;
  String? _errorCarga;
  List<ContratoAlumno> _alumnos = [];
  /// Todos los alumnos de la fiesta, **también los de baja temporal**: sus
  /// números entregados siguen teniendo dueño (revisión del 15-nov). La lista
  /// que se ve deja afuera las bajas; los números ocupados, no.
  List<ContratoAlumno> _todos = [];
  Map<String, DeudaAlumno> _deudas = {};
  Map<String, EntradasRetiro> _retiros = {};

  /// Los renglones de la entrega por partes (`entradas_entregas`) de **todos**
  /// los alumnos, también los de baja: sus números entregados siguen teniendo
  /// dueño.
  Map<String, List<EntregaEntradas>> _renglones = {};

  /// Los pagos de cada alumno: de ahí sale qué mesa adicional y qué silla
  /// extra están pagas enteras (lo único que se le vende, `APagarDeLaFamilia`).
  Map<String, List<Map<String, dynamic>>> _pagos = {};

  /// La venta de entradas de la fiesta (6.9.0): lo que compró cada familia.
  /// Los números vendidos no frenan la entrega: son el talonario de las
  /// anticipadas, otro que el de las generales (20-nov).
  /// [_ventaAndando]: la fiesta tiene precio y este equipo tiene la base (en la
  /// web, no).
  List<VentaEntradas> _ventas = const [];
  List<AnulacionEntradas> _anulaciones = const [];
  Map<String, int> _compradas = {};
  bool _ventaAndando = false;

  /// Las familias a las que ya se les intentó poner al día la fila de
  /// `entradas_retiro`, con cómo estaba lo suyo (`_firmaDeLaFila`): se intenta
  /// una vez por familia mientras lo suyo no cambie, **salvo que no se haya
  /// podido mirar la nube**: ahí se vuelve a intentar en la próxima lectura.
  final _completadas = <String, String>{};

  /// Lo que cada familia tenía al sorteo: el descuento es solo para eso
  /// (17-nov-2026). Y el descuento que el jefe puso en PRECIOS (viene en 50).
  FotoDeLosLugares _foto = FotoDeLosLugares.sinSorteo;
  double _descuentoPct = ConfigEntradas.kDescuentoDeLosLugares;
  bool _porDivision = false;
  bool _ocultarMontos = false;
  bool _ocupado = false;
  final _busqueda = TextEditingController();
  Timer? _refresco;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// El diálogo abierto de una familia bloqueada, y lo que debía al abrirlo: si
  /// la cuenta cambia (pagó en la caja), se cierra y se vuelve a abrir solo.
  String? _abiertoId;
  double? _abiertoDebia;
  final _cuentaCambio = _Aviso();

  PermisosDeEntrega get _permisos => PermisosDeEntrega.de(
        enElMostrador: widget.enElMostrador,
        tieneCobros: ref.read(appRoleProvider).permisos.cobros,
        esJefe: ref.read(esRolJefeProvider),
      );

  /// Lo que, si baja de la otra PC, cambia lo que se ve acá: una entrega, la
  /// cuenta del alumno o un cobro.
  static const _tablasQueMiro = {
    'entradas_retiro',
    'entradas_entregas',
    'contratos_alumnos',
    'pagos_contrato_alumno',
    'entradas_config',
    'entradas_ventas',
    'entradas_anulaciones',
    // El sorteo anota qué tenía cada familia: cambia qué va con descuento.
    'sorteos_mesas',
  };

  /// "al 50 %": lo que se paga con el descuento de PRECIOS.
  String get _alPorciento => alPorcientoQuePaga(_descuentoPct);

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
    _cargar().then((_) {
      if (mounted && widget.imprimirAlAbrir) _preguntarComoImprimir();
    });
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
    _cuentaCambio.dispose();
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
      final todos = await repo.getByEvento(widget.evento.id);
      final alumnos = todos.where((a) => !a.esBajaTemporal).toList()
        ..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
      final ids = [for (final a in alumnos) a.id];
      final pagos = <String, List<Map<String, dynamic>>>{};
      for (final p in await repo.getPagosForContratoIds(ids)) {
        final id = p['contrato_alumno_id'] as String?;
        if (id != null) pagos.putIfAbsent(id, () => []).add(p);
      }
      final mora = await repo.sumMoraCobradaHistorialPorContratos(ids);
      final idsDeTodos = [for (final a in todos) a.id];
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds(idsDeTodos);
      final renglones = await ref
          .read(entradasEntregasRepositoryProvider)
          .deContratos(idsDeTodos);
      final deudas = {
        for (final a in alumnos)
          a.id: RetiroEntradas.deudaDe(
            a,
            pagos: pagos[a.id] ?? const [],
            moraCobradaHistorial: mora[a.id] ?? 0,
          ),
      };
      final venta = await _leerLaVenta();
      final foto = await ref.read(fotoDeLosLugaresProvider)(widget.evento.id);
      if (!mounted) return;
      setState(() {
        _alumnos = alumnos;
        _todos = todos;
        _deudas = deudas;
        _retiros = retiros;
        _renglones = renglones;
        _pagos = pagos;
        _ventas = venta.ventas;
        _anulaciones = venta.anulaciones;
        _compradas = compradasPorFamilia(venta.ventas, venta.anulaciones);
        _ventaAndando = venta.andando;
        _descuentoPct = venta.descuentoPct;
        _foto = foto;
        _cargando = false;
        _errorCarga = null;
      });
      _despuesDeLeer(deudas);
      _completarLasFilas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (!silencioso) _errorCarga = '$e';
      });
    }
  }

  /// Lo vendido de la fiesta. **La entrega no depende de la venta**: si no se
  /// puede leer, sigue como antes de la 6.9.0 (sin lo vendido a la vista).
  Future<
      ({
        List<VentaEntradas> ventas,
        List<AnulacionEntradas> anulaciones,
        bool andando,
        double descuentoPct,
      })> _leerLaVenta() async {
    const nada = (
      ventas: <VentaEntradas>[],
      anulaciones: <AnulacionEntradas>[],
      andando: false,
      descuentoPct: ConfigEntradas.kDescuentoDeLosLugares,
    );
    if (!ref.read(entradasEnEsteEquipoProvider)) return nada;
    try {
      final entradas = ref.read(entradasDeLaFiestaProvider);
      final id = widget.evento.id;
      final config = await entradas.config(id);
      return (
        ventas: await entradas.ventas(id),
        anulaciones: await entradas.anulaciones(id),
        andando: config?.tienePrecio ?? false,
        descuentoPct: config?.descuentoLugaresPct ?? ConfigEntradas.kDescuentoDeLosLugares,
      );
    } catch (_) {
      return nada;
    }
  }

  /// Todos los renglones de la entrega por partes de la fiesta.
  List<EntregaEntradas> get _todosLosRenglones => [
        for (final l in _renglones.values) ...l,
      ];

  /// Cómo está la entrega de [a], por parte.
  EstadoDeLaEntrega _estadoDe(ContratoAlumno a) => EstadoDeLaEntrega.deAlumno(
        a,
        retiro: _retiros[a.id],
        renglones: _renglones[a.id] ?? const [],
      );

  /// Los números de las generales que ya se entregaron sin cargo a las otras
  /// familias (de una entrega de las 8 juntas y de los renglones de generales),
  /// salvo los de [alumnoId]. Es el `deOtros` de la entrega: **no mira lo
  /// vendido**, que es el talonario de las anticipadas (20-nov).
  Map<String, List<TramoTalonario>> _ocupadosPara(String alumnoId) =>
      EntregaPorPartes.numerosDeOtros(
        _todos,
        _retiros,
        _todosLosRenglones,
        salvo: alumnoId,
      );

  /// Lo de sus lugares adicionales: lo que compró y lo que le queda, **solo de
  /// lo que ya está pago entero** (la cuenta de VENDER, con los pagos que esta
  /// pantalla ya leyó), y con la misma regla para la cuenta que el jefe tiene
  /// que revisar (`APagarDeLaFamilia.porQueNoSeVendeCon`).
  LugaresDeLaFamilia _lugaresDe(ContratoAlumno a) {
    final deuda = _deudas[a.id];
    return LugaresDeLaFamilia.de(
      a,
      ventas: _ventas,
      anulaciones: _anulaciones,
      aPagar: APagarDeLaFamilia.de(a, pagos: _pagos[a.id] ?? const [], foto: _foto),
      // El de la venta: la deuda no tapa los otros frenos (sin mesa, las mesas
      // que no coinciden, no entran).
      bloqueo: RetiroEntradas.bloqueoDeLaVenta(a, deuda),
      todoEntregado: _estadoDe(a).todoEntregado,
    );
  }

  /// Una familia cuya fila de `entradas_retiro` no dice lo mismo que sus
  /// partes (`EntregaPorPartes.filaParaPonerAlDia`): tiene las dos partes y la
  /// fila no dice "entregado" (cada parte la dio un equipo distinto y uno estaba
  /// sin internet), o la fila dice "entregado" y el jefe anuló una parte. Con
  /// internet se pone al día ahora, para que una PC con la 6.9.x, el plano y la
  /// planilla vieja vean lo mismo. Lo decide `EntregarParte.completarLaFila`,
  /// que mira la nube antes. Se intenta una vez por familia mientras lo suyo no
  /// cambie, salvo que no haya podido mirar la nube.
  void _completarLasFilas() {
    if (ref.read(connectivityServiceProvider).currentStatus ==
        AppConnectivity.offline) {
      return;
    }
    for (final a in _alumnos) {
      final retiro = _retiros[a.id];
      if (!EntregaPorPartes.filaParaPonerAlDia(
        retiro: retiro,
        estado: _estadoDe(a),
      )) {
        continue;
      }
      final firma = _firmaDeLaFila(a);
      if (_completadas[a.id] == firma) continue;
      _completadas[a.id] = firma;
      unawaited(_completarLaFila(a));
    }
  }

  /// Cómo está lo suyo: cuántos renglones tiene y cómo está su fila. Si cambia,
  /// se vuelve a intentar.
  String _firmaDeLaFila(ContratoAlumno a) {
    final retiro = _retiros[a.id];
    return '${(_renglones[a.id] ?? const []).length}'
        '|${retiro?.estado.name}|${retiro?.updatedAt.toIso8601String()}';
  }

  Future<void> _completarLaFila(ContratoAlumno a) async {
    try {
      final r = await ref.read(entregarParteProvider).completarLaFila(
            eventoId: widget.evento.id,
            contratoAlumnoId: a.id,
          );
      switch (r) {
        case ResultadoDeLaFila.escrita:
          if (mounted && !_ocupado) await _cargar(silencioso: true);
        case ResultadoDeLaFila.sinNube:
          // No se pudo mirar la nube: se vuelve a intentar en la próxima
          // lectura (la tablet queda abierta toda la noche).
          _completadas.remove(a.id);
        case ResultadoDeLaFila.alDia:
          break;
      }
    } catch (e) {
      // Se vuelve a intentar en la próxima lectura.
      _completadas.remove(a.id);
      debugPrint('No se puso al día la fila de la entrega de ${a.nombreAlumno}: $e');
    }
  }

  /// Con las cuentas recién leídas (de esta PC, o bajadas cuando la otra cobró):
  /// en el mostrador, quién de "En caja" ya pagó, con un sonido corto la primera
  /// vez; y si el diálogo abierto es de una familia cuya cuenta cambió, se vuelve
  /// a abrir con los datos nuevos.
  void _despuesDeLeer(Map<String, DeudaAlumno> deudas) {
    if (widget.enElMostrador) {
      final recien =
          ref.read(enCajaProvider(widget.evento.id).notifier).conDeudas(deudas);
      if (recien.isNotEmpty) unawaited(SystemSound.play(SystemSoundType.alert));
    }
    final id = _abiertoId;
    final debia = _abiertoDebia;
    final d = id == null ? null : deudas[id];
    if (d != null && debia != null && (d.total - debia).abs() > RetiroEntradas.margen) {
      _cuentaCambio.avisar();
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

  /// El estado de [a], para el chip de su renglón. Lo entregado lleva el tilde
  /// en el texto y va sin ícono: con los dos se veían dos tildes (muestras del
  /// 20-nov-2026).
  ({String texto, Color color, IconData? icono}) _estado(ContratoAlumno a) {
    final e = _estadoDe(a);
    if (e.todoEntregado) {
      final cambio = e.pulseras.cambioLaCuenta || e.generales.cambioLaCuenta;
      return cambio
          ? (
              texto: '✓ Todo entregado · cambió la cuenta',
              color: Colors.orange.shade800,
              icono: Icons.warning_amber_rounded,
            )
          : (
              texto: '✓ Todo entregado',
              color: Colors.green.shade700,
              icono: null,
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
      BloqueoRetiro.ninguno => e.algoEntregado
          ? (
              texto: e.pulseras.entregada
                  ? '✓ Pulseras entregadas'
                  : '✓ Generales entregadas',
              color: Colors.green.shade700,
              icono: null,
            )
          : (
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
    final bloqueo = RetiroEntradas.bloqueo(a, deuda);
    final estado = _estadoDe(a);
    final bloqueado = !estado.todoEntregado && bloqueo != BloqueoRetiro.ninguno;
    _abiertoId = bloqueado ? a.id : null;
    _abiertoDebia = bloqueado ? deuda.total : null;
    final AccionEntrega? accion;
    try {
      accion = await mostrarEntregaEntradasDialog(
        context: context,
        alumno: a,
        entradas: RetiroEntradas.entradasDe(a, foto: _foto),
        estado: estado,
        deuda: deuda,
        bloqueo: bloqueo,
        permisos: _permisos,
        retiro: _retiros[a.id],
        renglones: _renglones[a.id] ?? const [],
        deOtros: _ocupadosPara(a.id),
        cuentaCambio: _cuentaCambio,
        venta: _ventaAndando
            ? VentaAlCincuenta(
                lugares: _lugaresDe(a),
                puedeVender: ref.read(puedeVenderEntradasProvider) &&
                    ref.read(entradasEnEsteEquipoProvider),
                descuentoPct: _descuentoPct,
              )
            : null,
      );
    } finally {
      _abiertoId = null;
      _abiertoDebia = null;
    }
    if (accion == null || !mounted) return;
    final enCaja = ref.read(enCajaProvider(widget.evento.id).notifier);
    switch (accion) {
      case IrACobrar():
        final cobrar = widget.onCobrar;
        if (cobrar == null) return;
        await cobrar(a);
        await _volverAAbrir(a.id);
      case EditarAlumno():
        final editar = widget.onEditarAlumno;
        if (editar == null) return;
        await editar(a);
        await _volverAAbrir(a.id);
      case MandarACaja():
        enCaja.mandar(a, deuda);
      case PasarACaja():
        enCaja.mandar(a, deuda);
        await _pasarACaja();
      case VolverAAbrir():
        await _volverAAbrir(a.id);
      case AnularEntrega(:final partes, :final motivo):
        await _anular(a, partes, motivo);
      case EntregarUnaParte(:final datos):
        await _entregar(a, datos);
      case VenderAlCincuenta():
        await _venderAlCincuenta(a);
    }
  }

  /// VENDERLE ESAS ENTRADAS: VENDER con esa familia ya elegida. Al volver se
  /// relee: lo que compró cambia lo que se ve.
  Future<void> _venderAlCincuenta(ContratoAlumno a) async {
    // Doble llave: el botón sale solo con el permiso.
    if (!ref.read(puedeVenderEntradasProvider)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenderEntradasScreen(evento: widget.evento, familiaId: a.id),
      ),
    );
    if (mounted) await _cargar(silencioso: true);
  }

  /// PASAR A CAJA desde una entrega: se cierra la entrega (está encima de
  /// Entradas, y la caja reemplaza a Entradas debajo) y se va a la caja sin el
  /// PIN. La familia quedó en "En caja": al volver con ENTRADAS, si pagó, salta.
  Future<void> _pasarACaja() async {
    if (!_permisos.pasarACaja) return;
    final rol = ref.read(appRoleProvider.notifier);
    Navigator.of(context).popUntil((r) => r.isFirst);
    await rol.pasarACaja();
  }

  /// Después de cobrar o de editar al alumno, el diálogo vuelve con los datos
  /// nuevos: el flujo del mostrador sigue donde estaba.
  Future<void> _volverAAbrir(String id) async {
    await _cargar();
    if (!mounted) return;
    final fresco = _alumnoPorId(id);
    if (fresco != null) await _abrir(fresco);
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

  /// Entrega una parte por `EntregarParte`, el único camino para guardar una
  /// entrega: mira la nube, pregunta si no hay internet, relee y frena si algo
  /// cambió. Acá solo se muestran los carteles.
  Future<void> _entregar(ContratoAlumno alumno, DatosDeLaParte datos) async {
    setState(() => _ocupado = true);
    try {
      final r = await ref.read(entregarParteProvider).entregar(
            eventoId: widget.evento.id,
            contratoAlumnoId: alumno.id,
            datos: datos,
            quien: quienOpera(ref),
            seguirSinInternet: () => seguirSinInternetEnLaEntrega(context, datos.parte),
          );
      await _cargar();
      if (!mounted) return;
      // Si estaba en "En caja", ya está: se le entregó.
      if (r is Entregada) {
        ref.read(enCajaProvider(widget.evento.id).notifier).sacar(alumno.id);
      }
      // Los mismos carteles que VENDER (`carteles_de_la_entrega.dart`).
      await mostrarComoTerminoLaEntrega(context, r, alumno: alumno, datos: datos);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se guardó la entrega: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Anula [partes] por `EntregarParte` (otro renglón: no se borra nada).
  Future<void> _anular(
    ContratoAlumno a,
    Set<ParteEntrega> partes,
    String motivo,
  ) async {
    // Doble llave: el botón está apagado sin modo jefe, y acá tampoco pasa.
    if (!_permisos.anular) return;
    setState(() => _ocupado = true);
    try {
      final r = await ref.read(entregarParteProvider).anularParte(
            eventoId: widget.evento.id,
            contratoAlumnoId: a.id,
            partes: partes,
            motivo: motivo,
            quien: quienOpera(ref),
            esJefe: _permisos.anular,
          );
      await _cargar();
      if (!mounted) return;
      switch (r) {
        case Anulada(:final subio, :final partes):
          final que = partes.length == ParteEntrega.values.length
              ? 'Entrega'
              : partes.single == ParteEntrega.pulseras
                  ? 'Entrega de las pulseras'
                  : 'Entrega de las generales';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                subio
                    ? '$que de ${a.nombreAlumno.trim()} anulada.'
                    : '$que de ${a.nombreAlumno.trim()} anulada en este equipo; sube '
                        'a la nube cuando vuelva la conexión.',
              ),
            ),
          );
        case NoSeAnulo(:final motivo):
          await _avisar('No se anuló', motivo);
        case CambioAlgo(:final motivo):
          await _avisar('Cambió algo', motivo);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se anuló: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// La misma elección del menú de la impresora, como pregunta: para cuando se
  /// llega desde PLANILLAS, donde todavía no se eligió.
  Future<void> _preguntarComoImprimir() async {
    if (_errorCarga != null) return;
    var material = ParteEntrega.pulseras;
    final blancoYNegro = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogo) => AlertDialog(
          title: const Text('Imprimir la planilla de entrega'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Una planilla por material: las pulseras VIP y las generales '
                  'llegan y se entregan en tandas distintas. Sale una hoja A4 '
                  'acostada por división, con lo que retira cada familia y el '
                  'lugar para anotar quién se lo lleva.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<ParteEntrega>(
                  segments: const [
                    ButtonSegment(
                      value: ParteEntrega.pulseras,
                      label: Text('Pulseras VIP', key: Key('entrega_material_pulseras')),
                    ),
                    ButtonSegment(
                      value: ParteEntrega.generales,
                      label: Text('Generales', key: Key('entrega_material_generales')),
                    ),
                  ],
                  selected: {material},
                  onSelectionChanged: (s) => setDialogo(() => material = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('entrega_cancelar'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCELAR'),
            ),
            OutlinedButton.icon(
              key: const Key('entrega_bn'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.contrast, size: 18),
              label: const Text('BLANCO Y NEGRO'),
            ),
            FilledButton.icon(
              key: const Key('entrega_color'),
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('EN COLOR'),
            ),
          ],
        ),
      ),
    );
    if (blancoYNegro == null || !mounted) return;
    await _imprimir(material: material, blancoYNegro: blancoYNegro);
  }

  /// La planilla de entrega de [material]: las pulseras VIP o las generales.
  Future<void> _imprimir({
    required ParteEntrega material,
    required bool blancoYNegro,
  }) async {
    try {
      await ref.read(imprimirPlanillaDeEntregaProvider)(
        widget.evento,
        _alumnos,
        material: material,
        retiros: _retiros,
        renglones: _todosLosRenglones,
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
          // La venta de entradas es de la oficina: en el mostrador se entra por
          // el inicio de Entradas.
          if (!widget.enElMostrador) ...[
            if (CortesPantalla.esCelular(MediaQuery.sizeOf(context).width))
              _menuDeLaVenta()
            else ...[
              _botonPrecios(),
              _botonVender(),
              _botonVentas(),
              _botonParaRendir(),
            ],
          ],
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _ocupado ? null : () => _cargar(),
            icon: const Icon(Icons.refresh),
          ),
          // Una planilla por material: cada uno llega y se entrega en su tanda.
          PopupMenuButton<(ParteEntrega, bool)>(
            key: const Key('entrega_imprimir'),
            tooltip: 'Planilla de entrega',
            icon: const Icon(Icons.print_rounded),
            onSelected: (e) => _imprimir(material: e.$1, blancoYNegro: e.$2),
            itemBuilder: (_) => [
              for (final material in ParteEntrega.values)
                for (final bn in const [true, false])
                  PopupMenuItem(
                    key: Key('entrega_imprimir_${material.clave}_${bn ? 'bn' : 'color'}'),
                    value: (material, bn),
                    child: Text(
                      'Planilla de ${material == ParteEntrega.pulseras ? 'pulseras VIP' : 'generales'}'
                      ' (${bn ? 'blanco y negro' : 'color'})',
                    ),
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

  /// En un celular PRECIOS, VENDER, VENTAS y PARA RENDIR no entran en la barra
  /// (21-nov-2026: con PARA RENDIR se desbordaba; ver el riesgo de la sección
  /// 10 de `docs/SPEC_entradas_para_rendir_2026-11-20.md`): van en un menú.
  ///
  /// **Cada opción es su botón**: se arma el botón y se toma de él si está
  /// prendido, qué abre y su motivo. Así el menú no tiene otra regla al lado,
  /// y lo apagado se ve apagado, con el motivo, como en la PC.
  Widget _menuDeLaVenta() {
    final opciones = [
      for (final b in [_botonPrecios(), _botonVender(), _botonVentas(), _botonParaRendir()])
        if (b case Tooltip(:final message?, child: final TextButton boton))
          (
            clave: (boton.key! as ValueKey<String>).value,
            texto: (boton.child! as Text).data!,
            abrir: boton.onPressed,
            motivo: message,
          ),
    ];
    return PopupMenuButton<String>(
      key: const Key('entradas_menu_venta'),
      tooltip: 'La venta de entradas',
      icon: const Icon(Icons.confirmation_number_outlined),
      onSelected: (clave) {
        for (final o in opciones) {
          if (o.clave == clave) o.abrir?.call();
        }
      },
      itemBuilder: (_) => [
        for (final o in opciones)
          PopupMenuItem<String>(
            key: Key('${o.clave}_menu'),
            value: o.clave,
            enabled: o.abrir != null,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              enabled: o.abrir != null,
              title: Text(o.texto),
              subtitle: o.abrir != null ? null : Text(o.motivo),
            ),
          ),
      ],
    );
  }

  /// PRECIOS: el precio de la entrada de esta fiesta (6.9.0). **Solo en modo
  /// jefe**: sin él se ve apagado, con el motivo.
  Widget _botonPrecios() {
    final esJefe = ref.watch(esRolJefeProvider);
    final enElEquipo = ref.watch(entradasEnEsteEquipoProvider);
    final motivo = !enElEquipo
        ? kEntradasDesdeLaPc
        : (esJefe ? 'El precio de la entrada de esta fiesta' : kSoloEnModoJefe);
    return Tooltip(
      message: motivo,
      child: TextButton(
        key: const Key('entradas_precios'),
        onPressed: esJefe && enElEquipo ? _abrirPrecios : null,
        child: const Text('PRECIOS'),
      ),
    );
  }

  Future<void> _abrirPrecios() async {
    // Doble llave: el botón ya está apagado sin modo jefe.
    if (!ref.read(esRolJefeProvider)) return;
    await mostrarPreciosDeEntradas(
      context,
      eventoId: widget.evento.id,
      fiesta: nombreDeLaFiesta(widget.evento),
      quien: quienOpera(ref),
      // Para proponer hasta cuándo vale la anticipada: el día anterior.
      fechaFiesta: widget.evento.fechaEvento,
      lugares: _foto,
      revisarLugares: _revisarLugares,
      // Guardado, ofrece los mismos precios en otras fiestas (22-nov-2026).
      otrasFiestas: ref.read(fiestasParaLosPreciosProvider),
    );
  }

  /// La lista de una fiesta sorteada antes de la regla del descuento: qué se
  /// agregó después del sorteo, para que el jefe la acepte. Devuelve lo que
  /// rige después, o null si no cambió nada.
  Future<FotoDeLosLugares?> _revisarLugares(BuildContext contexto) async {
    // Doble llave: a PRECIOS ya se entró en modo jefe.
    if (!ref.read(esRolJefeProvider)) return null;
    final cambio = await mostrarRevisionDeLugares(
      contexto,
      eventoId: widget.evento.id,
      fiesta: nombreDeLaFiesta(widget.evento),
    );
    if (!cambio) return null;
    final foto = await ref.read(fotoDeLosLugaresProvider)(widget.evento.id);
    if (mounted) setState(() => _foto = foto);
    return foto;
  }

  /// Mientras la fiesta esté sorteada sin la lista aceptada, el jefe lo ve acá:
  /// hasta entonces todo va con descuento. Solo en modo jefe y en la oficina.
  Widget? _recordatorioDeLosLugares() {
    if (widget.enElMostrador ||
        _foto.estado != EstadoDeLosLugares.sinAnotar ||
        !ref.watch(esRolJefeProvider) ||
        !ref.watch(entradasEnEsteEquipoProvider)) {
      return null;
    }
    final color = Colors.amber.shade900;
    return Container(
      key: const Key('entradas_falta_revisar_lugares'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Falta revisar qué lugares se agregaron después del sorteo. '
              'Hasta que aceptes la lista, todos van con descuento.',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const Key('entradas_revisar_lugares'),
            onPressed: _abrirPrecios,
            child: const Text('ABRIR PRECIOS'),
          ),
        ],
      ),
    );
  }

  /// VENTAS: el historial de todas las cajas de entradas de esta fiesta. Desde
  /// acá es del jefe; quien vende llega al de su caja por VENDER.
  Widget _botonVentas() {
    final esJefe = ref.watch(esRolJefeProvider);
    final enElEquipo = ref.watch(entradasEnEsteEquipoProvider);
    final motivo = !enElEquipo
        ? kEntradasDesdeLaPc
        : (esJefe ? 'Las ventas de entradas de esta fiesta' : kSoloEnModoJefe);
    return Tooltip(
      message: motivo,
      child: TextButton(
        key: const Key('entradas_ventas'),
        onPressed: esJefe && enElEquipo ? _abrirVentas : null,
        child: const Text('VENTAS'),
      ),
    );
  }

  Future<void> _abrirVentas() async {
    // Doble llave: el botón ya está apagado sin modo jefe.
    if (!ref.read(esRolJefeProvider)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VentasDeEntradasScreen(evento: widget.evento),
      ),
    );
    if (mounted) await _cargar(silencioso: true);
  }

  /// PARA RENDIR (21-nov-2026): quién se llevó entradas para venderlas por su
  /// cuenta, qué rindió y qué le queda; ahí el jefe las da. **Solo el jefe en
  /// modo jefe**, como VENTAS: sin él se ve apagado, con el motivo. En el
  /// mostrador no está (lo de quien vende es el aviso de VENDER).
  ({bool prendido, String motivo}) get _paraRendir {
    final esJefe = ref.watch(esRolJefeProvider);
    final enElEquipo = ref.watch(entradasEnEsteEquipoProvider);
    return (
      prendido: esJefe && enElEquipo,
      motivo: !enElEquipo
          ? kEntradasDesdeLaPc
          : (esJefe ? 'Las entradas que alguien se llevó para vender y rendir' : kSoloEnModoJefe),
    );
  }

  Widget _botonParaRendir() {
    final (:prendido, :motivo) = _paraRendir;
    return Tooltip(
      message: motivo,
      child: TextButton(
        key: const Key('entradas_para_rendir'),
        onPressed: prendido ? _abrirParaRendir : null,
        child: const Text('PARA RENDIR'),
      ),
    );
  }

  Future<void> _abrirParaRendir() async {
    // Doble llave: el botón ya está apagado sin modo jefe.
    if (!ref.read(esRolJefeProvider)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParaRendirScreen(evento: widget.evento),
      ),
    );
    if (mounted) await _cargar(silencioso: true);
  }

  /// VENDER: la caja de entradas de esta fiesta, para quien puede vender (el
  /// jefe en modo jefe, o un operador con "Vende entradas").
  Widget _botonVender() {
    final puede = ref.watch(puedeVenderEntradasProvider);
    final enElEquipo = ref.watch(entradasEnEsteEquipoProvider);
    final motivo = !enElEquipo
        ? kEntradasDesdeLaPc
        : (puede
            ? 'Vender entradas de esta fiesta'
            : 'Con el permiso "Vende entradas" o en modo jefe');
    return Tooltip(
      message: motivo,
      child: TextButton(
        key: const Key('entradas_vender'),
        onPressed: puede && enElEquipo ? _abrirVender : null,
        child: const Text('VENDER'),
      ),
    );
  }

  Future<void> _abrirVender() async {
    // Doble llave: el botón ya está apagado sin el permiso.
    if (!ref.read(puedeVenderEntradasProvider)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenderEntradasScreen(evento: widget.evento),
      ),
    );
    if (mounted) await _cargar(silencioso: true);
  }

  /// Arriba de todo en el mostrador: si se está en vivo con la caja, las
  /// familias que ya pagaron (con ENTREGAR) y las que siguen en la caja.
  Widget _arribaDelMostrador() {
    final enCaja = ref.watch(enCajaProvider(widget.evento.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LineaEnVivo(conexion: ref.watch(connectivityServiceProvider)),
          for (final f in enCaja.pagaron) ...[
            const SizedBox(height: 8),
            _avisoPago(f),
          ],
          if (enCaja.esperando.isNotEmpty) ...[
            const SizedBox(height: 8),
            _enCaja(enCaja.esperando),
          ],
        ],
      ),
    );
  }

  Widget _avisoPago(FamiliaEnCaja f) {
    final a = _alumnoPorId(f.alumnoId);
    final deuda = _deudas[f.alumnoId];
    final libre = a != null &&
        deuda != null &&
        RetiroEntradas.bloqueo(a, deuda) == BloqueoRetiro.ninguno;
    final verde = Colors.green.shade700;
    return Container(
      key: Key('entrega_pago_${f.alumnoId}'),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: verde.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: verde.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: verde),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              libre
                  ? '${f.nombre} pagó: ya podés entregar'
                  : '${f.nombre} pagó, pero todavía no se puede entregar: abrila '
                      'para ver por qué',
              style: TextStyle(fontWeight: FontWeight.w700, color: verde),
            ),
          ),
          if (a != null)
            FilledButton(
              key: Key('entrega_entregar_${f.alumnoId}'),
              style: FilledButton.styleFrom(backgroundColor: verde),
              onPressed: _ocupado ? null : () => _abrir(a),
              child: Text(libre ? 'ENTREGAR' : 'ABRIR'),
            ),
          IconButton(
            tooltip: 'Sacar el aviso',
            onPressed: () => ref
                .read(enCajaProvider(widget.evento.id).notifier)
                .sacar(f.alumnoId),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _enCaja(List<FamiliaEnCaja> familias) {
    final ambar = Colors.orange.shade800;
    return Container(
      key: const Key('entrega_en_caja'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ambar.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En caja: cuando paguen, avisa acá',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ambar),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in familias)
                InputChip(
                  key: Key('entrega_en_caja_${f.alumnoId}'),
                  label: Text(
                    f.pagoUnaParte
                        ? '${f.nombre} · pagó una parte · faltan${_plata(f.debe)}'
                        : '${f.nombre} · debe${_plata(f.debe)}',
                  ),
                  onPressed: () {
                    final a = _alumnoPorId(f.alumnoId);
                    if (a != null) _abrir(a);
                  },
                  onDeleted: () => ref
                      .read(enCajaProvider(widget.evento.id).notifier)
                      .sacar(f.alumnoId),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    // Lo sin cargo, por parte: cuántas pulseras y cuántas generales tienen que
    // llegar, y cuántas se entregaron.
    final partes = ResumenPorPartes.de(
      alumnos: _alumnos,
      retiros: _retiros,
      renglones: _todosLosRenglones,
      deudas: _deudas,
    );
    // Lo que se compra aparte no depende de la entrega.
    final resumen =
        RetiroEntradas.resumen(_alumnos, _retiros, _deudas, foto: _foto);
    final al = '${_alPorciento[0].toUpperCase()}${_alPorciento.substring(1)}';
    final sinDescuento = resumen.sinDescuento > 0
        ? ' · ${resumen.sinDescuento} sin descuento'
        : '';
    return Column(
      children: [
        if (widget.enElMostrador) _arribaDelMostrador(),
        ?_recordatorioDeLosLugares(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: LayoutBuilder(
            builder: (context, caja) {
              final retiraronTodo = _tarjeta(
                'Retiraron todo',
                '${partes.familiasConTodo} de ${partes.familias}',
              );
              final conDeuda = _tarjeta(
                'Con deuda',
                '${partes.conDeuda}',
                color: partes.conDeuda > 0 ? Colors.red.shade700 : null,
              );
              // Las de las mesas adicionales y las sillas extra: no se entregan
              // acá, se compran aparte con el descuento de PRECIOS (lo que la
              // familia agregó después del sorteo, sin descuento).
              // Con la venta de entradas andando, cuántas ya se vendieron.
              // Lo sin descuento va en el rótulo: en el número partía la
              // tarjeta en dos renglones, más alta que las demás (muestras del
              // 20-nov-2026).
              final aparte = _ventaAndando
                  ? _tarjeta(
                      '$al$sinDescuento',
                      '${_vendidasAlCincuenta()} vendidas de ${resumen.conDescuento}',
                    )
                  : _tarjeta('$al, aparte$sinDescuento', '${resumen.conDescuento}');
              // En un celular, cinco tarjetas en una fila partían los rótulos a
              // mitad de palabra (revisión del 20-nov-2026): van de a dos, y sin
              // las de pulseras y generales, que ya dice la línea de abajo.
              if (CortesPantalla.esCelular(caja.maxWidth)) {
                final mitad = (caja.maxWidth - 8) / 2;
                return Wrap(
                  key: const Key('entrega_tarjetas_celular'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in [retiraronTodo, conDeuda, aparte])
                      SizedBox(width: mitad, child: t),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: retiraronTodo),
                  Expanded(
                    child: _tarjeta(
                      'Pulseras VIP',
                      '${partes.pulserasEntregadas} de ${partes.pulserasTotales}',
                    ),
                  ),
                  Expanded(
                    child: _tarjeta(
                      'Generales',
                      '${partes.generalesEntregadas} de ${partes.generalesTotales}',
                    ),
                  ),
                  Expanded(child: conDeuda),
                  Expanded(child: aparte),
                ],
              );
            },
          ),
        ),
        // Para saber cuántas pulseras y cuántas generales tienen que llegar.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              partes.texto,
              key: const Key('entrega_total_partes'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // En un celular angosto se achica en vez de salirse de la
              // pantalla.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
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
                ),
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

  /// Las del 50 % vendidas a las familias de la lista: de cada una, como mucho
  /// las que le corresponden (si le sacaron una silla después, no suma de más).
  int _vendidasAlCincuenta() {
    var total = 0;
    for (final a in _alumnos) {
      final compradas = _compradas[a.id] ?? 0;
      if (compradas == 0) continue;
      final corresponden = RetiroEntradas.entradasDe(a, foto: _foto).conDescuento;
      total += compradas < corresponden ? compradas : corresponden;
    }
    return total;
  }

  Widget _tarjeta(String rotulo, String valor, {Color? color}) => Card(
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
      );

  Widget _vistaMostrador() {
    // Sin acentos y con las palabras en cualquier orden, como el resto de los
    // buscadores: con "gomez" no aparecía "GÓMEZ" (revisión del 13-nov).
    final q = _busqueda.text.trim();
    final visibles = q.isEmpty
        ? _alumnos
        : _alumnos.where((a) => coincideTextoBusqueda([a.nombreAlumno], q)).toList();
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
            // Retiró: las dos partes.
            final r = g.where((a) => _estadoDe(a).todoEntregado).length;
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
    final e = RetiroEntradas.entradasDe(a, foto: _foto);
    final partes = _estadoDe(a);
    final estado = _estado(a);
    final division = a.cursoDivision?.trim() ?? '';
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';
    // Lo que se llevó de cada parte: quién y cuándo, y los números si vinieron.
    final entregadas = [
      for (final p in ParteEntrega.values)
        if (partes.parte(p).entregada)
          () {
            final x = partes.parte(p);
            final cuando = x.entregadaAt == null
                ? ''
                : ' · ${ArTime.formatFechaHora(x.entregadaAt!)}';
            final numeros = p == ParteEntrega.generales && x.tramos.isNotEmpty
                ? ' · del ${TramoTalonario.legible(x.tramos)}'
                : '';
            return '${p == ParteEntrega.pulseras ? 'Pulseras' : 'Generales'} ✓ '
                '${x.parentesco?.etiqueta ?? ''} ${x.retiroNombre ?? ''}'
                '$cuando$numeros';
          }(),
    ];
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
                    'mesa $mesa · ${e.vip} VIP con cena + ${e.generales} generales'
                    '${e.conDescuento > 0 ? ' · ${e.conDescuento} $_alPorciento' : ''}'
                    '${e.conDescuento > 0 && _ventaAndando && (_compradas[a.id] ?? 0) > 0 ? ' (compró ${_compradas[a.id]})' : ''}'
                    '${e.sinDescuento > 0 ? ' · ${e.sinDescuento} sin descuento' : ''}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  if (entregadas.isNotEmpty && !compacta)
                    Text(
                      entregadas.join('\n'),
                      style: TextStyle(fontSize: 12.5, color: Colors.green.shade800),
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
                  if (estado.icono != null) ...[
                    Icon(estado.icono, size: 15, color: estado.color),
                    const SizedBox(width: 4),
                  ],
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

/// Le avisa al diálogo abierto que la cuenta de su familia cambió.
class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}

/// "En vivo con la caja" o "Sin internet": si lo que cobra la caja llega solo.
class _LineaEnVivo extends StatelessWidget {
  final ConnectivityService conexion;

  const _LineaEnVivo({required this.conexion});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConnectivity>(
      stream: conexion.stream,
      initialData: conexion.currentStatus,
      builder: (context, snap) {
        final enVivo = snap.data == AppConnectivity.online;
        final color = enVivo ? Colors.green.shade700 : Colors.orange.shade800;
        return Row(
          key: const Key('entrega_en_vivo'),
          children: [
            Icon(
              enVivo ? Icons.circle : Icons.warning_amber_rounded,
              size: enVivo ? 10 : 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                enVivo
                    ? 'En vivo con la caja'
                    : 'Sin internet: lo que se cobre en la caja no llega hasta que vuelva',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        );
      },
    );
  }
}
