import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/evento.dart';
import '../../barra/cuentas/cobro_barra.dart';
import '../../barra/cuentas/pesos.dart';
import '../../barra/widgets/cobrar_hoja.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/quien_opera.dart';
import '../../common/utils/solo_jefe.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/entradas_retiro_repository.dart';
import '../../eventos/repositories/sorteos_mesas_repository.dart';
import '../../eventos/services/lugares_al_sorteo.dart';
import '../../eventos/services/lugares_pagos.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../cuentas/linea_de_subida.dart';
import '../cuentas/lugares_de_la_familia.dart';
import '../cuentas/numeros_de_entradas.dart';
import '../cuentas/pedido_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import '../pdf/comprobante_entradas_pdf.dart';
import '../pdf/papeles_de_entradas.dart';
import '../providers/entradas_providers.dart';
import '../services/nombre_de_la_fiesta.dart';
import 'abrir_caja_entradas_dialog.dart';
import 'cerrar_caja_entradas_screen.dart';
import 'ventas_de_entradas_screen.dart';

/// VENDER: la pantalla de la caja de entradas de una fiesta (6.9.0, sección 7.3
/// del spec del 13-nov). A una familia de la fiesta o a alguien de afuera.
///
/// **No cobra cuotas ni toca la cuenta de ningún alumno**: del alumno solo lee
/// (su mesa, cuántas entradas de sus lugares adicionales le quedan y si debe,
/// para decirlo). Lo único que escribe es la venta, por
/// `PedidoDeEntradas.guardarEn` (`test/venta_entradas_no_toca_test.dart`).
///
/// Las cuentas no están acá: el precio, lo que le queda a la familia, los
/// números y por qué todavía no se puede confirmar los decide
/// [PedidoDeEntradas].
///
/// La llave es `puedeVenderEntradasProvider` (`test/solo_modo_jefe_test.dart`).
class VenderEntradasScreen extends ConsumerStatefulWidget {
  final Evento evento;

  /// La familia ya elegida, cuando se llega desde la entrega.
  final String? familiaId;

  const VenderEntradasScreen({super.key, required this.evento, this.familiaId});

  @override
  ConsumerState<VenderEntradasScreen> createState() =>
      _VenderEntradasScreenState();
}

class _VenderEntradasScreenState extends ConsumerState<VenderEntradasScreen> {
  bool _cargando = true;
  String? _errorCarga;
  ConfigEntradas? _config;
  CajaEntradas? _caja;
  List<ContratoAlumno> _alumnos = [];
  /// Todos los alumnos de la fiesta, **también los de baja temporal**: sus
  /// números entregados siguen teniendo dueño (revisión del 15-nov). La lista
  /// que se ve deja afuera las bajas; los números ocupados, no.
  List<ContratoAlumno> _todos = [];
  Map<String, DeudaAlumno> _deudas = {};
  Map<String, EntradasRetiro> _retiros = {};
  List<VentaEntradas> _ventas = [];
  List<AnulacionEntradas> _anulaciones = [];
  int _sinSubir = 0;

  /// Lo que cada familia tenía al sorteo: el descuento es solo para eso. Solo
  /// se lee (`fotoDeLosLugaresProvider`): la venta no escribe el registro.
  FotoDeLosLugares _foto = FotoDeLosLugares.sinSorteo;

  /// Lo de cada familia que se compra aparte, cosa por cosa y con qué está
  /// pago entero (20-nov-2026): se le vende solo eso. Sale de los pagos, que
  /// se leen para la deuda; la cuenta está en `APagarDeLaFamilia`.
  Map<String, APagarDeLaFamilia> _aPagar = {};

  // Lo que se está por vender.
  late bool _aUnaFamilia = true;
  late String? _familiaId = widget.familiaId;

  /// Cuántas de sus lugares adicionales lleva. Null: todas las que le quedan.
  int? _deLugar;

  /// Cuántas sueltas lleva. Null: las que vienen (a una familia, todas las
  /// que le quedan sin descuento; a alguien de afuera, ninguna).
  int? _sueltas;
  bool _dosTramos = false;
  final _busqueda = TextEditingController();
  final _comprador = TextEditingController();
  final _dni = TextEditingController();
  final _descuento = TextEditingController(text: '0');
  final _del = TextEditingController();
  final _al = TextEditingController();
  final _del2 = TextEditingController();

  bool _guardando = false;
  bool _pidiendoCaja = false;

  /// La pantalla de cerrar la caja está abierta encima: no se pide caja.
  bool _cerrandoCaja = false;

  /// La última venta guardada: su aviso queda arriba hasta la siguiente.
  VentaEntradas? _ultima;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// Lo que, si baja de otro equipo, cambia lo que se ve acá. Un cobro en la
  /// caja cambia la cuenta del alumno, y con eso alcanza para volver a leer lo
  /// que debe: acá no se nombra la tabla de los pagos.
  static const _tablasQueMiro = {
    'entradas_config',
    'entradas_ventas',
    'entradas_anulaciones',
    'entradas_retiro',
    'contratos_alumnos',
    // El sorteo (o el jefe, al aceptar la lista de PRECIOS) anota qué tenía
    // cada familia: cambia a quién le va el descuento.
    'sorteos_mesas',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
    _cambiosSub =
        ref.read(syncEngineProvider).cambiosBajadosStream.listen((tablas) {
      if (!_guardando && tablas.any(_tablasQueMiro.contains)) {
        _cargar(silencioso: true);
      }
    });
    // El aviso de arriba sale al bajar, no al subir: cuando el motor termina de
    // subir, la línea vuelve a contar lo que falta (etapa 7: quedaba en "1 venta
    // subiendo" con la venta ya en la nube, hasta la próxima venta o bajada).
    _pendienteSub =
        ref.read(syncEngineProvider).pendingStream.listen((_) => _contarSinSubir());
  }

  StreamSubscription<int>? _pendienteSub;

  /// Solo lo que espera subir, para la línea de arriba: no relee nada más.
  Future<void> _contarSinSubir() async {
    try {
      final n = await ref.read(entradasDeLaCajaProvider).ventasSinSubir();
      if (mounted && n != _sinSubir) setState(() => _sinSubir = n);
    } catch (_) {
      // Si no se puede contar, queda lo último que se contó.
    }
  }

  @override
  void dispose() {
    _cambiosSub?.cancel();
    _pendienteSub?.cancel();
    for (final c in [
      _busqueda,
      _comprador,
      _dni,
      _descuento,
      _del,
      _al,
      _del2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _fiesta => nombreDeLaFiesta(widget.evento);

  /// A nombre de quién va la caja: el operador, o el jefe (sin operador).
  ({String? id, String nombre}) get _quienVende {
    final operador = ref.read(appRoleProvider).operador;
    if (ref.read(esRolJefeProvider) || operador == null) {
      return (id: null, nombre: quienOpera(ref));
    }
    return (id: operador.id, nombre: operador.nombre);
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final id = widget.evento.id;
      final entradas = ref.read(entradasDeLaCajaProvider);
      final repo = ref.read(contratosRepositoryProvider);
      final config = await entradas.config(id);
      final todos = await repo.getByEvento(id);
      final alumnos = todos.where((a) => !a.esBajaTemporal).toList()
        ..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
      final ids = [for (final a in alumnos) a.id];
      final pagos = <String, List<Map<String, dynamic>>>{};
      for (final p in await repo.getPagosForContratoIds(ids)) {
        final alumno = p['contrato_alumno_id'] as String?;
        if (alumno != null) pagos.putIfAbsent(alumno, () => []).add(p);
      }
      final mora = await repo.sumMoraCobradaHistorialPorContratos(ids);
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds([for (final a in todos) a.id]);
      final deudas = {
        for (final a in alumnos)
          a.id: RetiroEntradas.deudaDe(
            a,
            pagos: pagos[a.id] ?? const [],
            moraCobradaHistorial: mora[a.id] ?? 0,
          ),
      };
      final ventas = await entradas.ventas(id);
      final anulaciones = await entradas.anulaciones(id);
      final caja = await entradas.cajaAbierta(
        eventoId: id,
        operadorId: _quienVende.id,
      );
      final sinSubir = await entradas.ventasSinSubir();
      final foto = await ref.read(fotoDeLosLugaresProvider)(id);
      final aPagar = {
        for (final a in alumnos)
          a.id: APagarDeLaFamilia.de(
            a,
            pagos: pagos[a.id] ?? const [],
            foto: foto,
          ),
      };
      if (!mounted) return;
      setState(() {
        // La última venta anulada ya no es "guardada": se va su aviso verde.
        if (_ultima != null && anulaciones.any((a) => a.ventaId == _ultima!.id)) {
          _ultima = null;
        }
        _foto = foto;
        _aPagar = aPagar;
        _config = config;
        _alumnos = alumnos;
        _todos = todos;
        _deudas = deudas;
        _retiros = retiros;
        _ventas = ventas;
        _anulaciones = anulaciones;
        _caja = caja;
        _sinSubir = sinSubir;
        _cargando = false;
        _errorCarga = null;
      });
      // Sin caja abierta, VENDER la pide. Sin precio no: lo dice la pantalla.
      if (caja == null &&
          (config?.tienePrecio ?? false) &&
          !_pidiendoCaja &&
          !_cerrandoCaja) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _pedirCaja());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (!silencioso) {
          _errorCarga = 'No se pudo leer la fiesta. Volvé a entrar.';
        }
      });
    }
  }

  // ── Las llaves ───────────────────────────────────────────────────────────

  /// Sin el permiso de vender (o el modo jefe) no se abre una caja ni se
  /// guarda una venta, aunque alguien llegue hasta acá.
  bool _frenaSinPermiso() {
    if (ref.read(puedeVenderEntradasProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kSinPermisoParaVender)),
      );
    }
    return true;
  }

  Future<void> _pedirCaja() async {
    if (!mounted || _pidiendoCaja || _caja != null) return;
    if (_frenaSinPermiso()) return;
    _pidiendoCaja = true;
    final quien = _quienVende;
    final caja = await abrirCajaDeEntradas(
      context,
      eventoId: widget.evento.id,
      fiesta: _fiesta,
      operadorId: quien.id,
      operadorNombre: quien.nombre,
    );
    _pidiendoCaja = false;
    if (!mounted) return;
    if (caja != null) avisarQueCambioLaVenta(ref, widget.evento.id);
    if (caja == null) {
      // Volvió sin abrir: no hay nada que hacer en VENDER.
      await Navigator.of(context).maybePop();
      return;
    }
    setState(() => _caja = caja);
  }

  // ── Lo que se está por vender ────────────────────────────────────────────

  ContratoAlumno? get _familia {
    if (!_aUnaFamilia) return null;
    for (final a in _alumnos) {
      if (a.id == _familiaId) return a;
    }
    return null;
  }

  /// Sin lo de A PAGAR leído todavía, nada está pago: no se le vende nada.
  LugaresDeLaFamilia _lugaresDe(ContratoAlumno a) => LugaresDeLaFamilia.de(
        a,
        ventas: _ventas,
        anulaciones: _anulaciones,
        aPagar: _aPagar[a.id] ?? APagarDeLaFamilia.de(a, pagos: null, foto: _foto),
      );

  /// "al 50 %": lo que se paga con el descuento que el jefe puso en PRECIOS.
  String get _alPorciento =>
      alPorcientoQuePaga(_config?.descuentoLugaresPct ?? ConfigEntradas.kDescuentoDeLosLugares);

  /// Los números que ya tienen dueño: lo entregado sin cargo y lo vendido.
  Map<String, List<TramoTalonario>> get _ocupados => NumerosDeEntradas.ocupados(
        entregados: RetiroEntradas.tramosDeOtros(_todos, _retiros, salvo: ''),
        ventas: _ventas,
        anulaciones: _anulaciones,
      );

  /// El pedido sin los números: de acá sale cuántas entradas son.
  PedidoDeEntradas get _sinNumeros {
    var p = PedidoDeEntradas.nuevo(
      config: _config,
      hoyAr: ref.read(hoyEnArgentinaProvider)(),
      esJefe: ref.read(esRolJefeProvider),
      ocupados: _ocupados,
    );
    final familia = _familia;
    if (familia != null) {
      final lugares = _lugaresDe(familia);
      p = p.paraLaFamilia(familia.id, lugares);
      final n = _deLugar;
      if (n != null) p = p.conDeLugar(n);
    }
    final sueltas = _sueltas;
    if (sueltas != null) p = p.conSueltas(sueltas);
    return p
        .conDescuento(double.tryParse(_descuento.text.replaceAll(',', '.')) ?? 0)
        .conComprador(_comprador.text)
        .conDni(_dni.text);
  }

  /// Los números escritos. Con un solo tramo, el "al" se calcula solo, como en
  /// la entrega.
  List<TramoTalonario> _tramos(int cantidad) {
    final del = int.tryParse(_del.text.trim());
    if (del == null) return const [];
    if (!_dosTramos) return [TramoTalonario(del, del + cantidad - 1)];
    final al = int.tryParse(_al.text.trim());
    if (al == null) return [TramoTalonario(del, del)];
    final primero = TramoTalonario(del, al);
    final resto = cantidad - primero.cantidad;
    final del2 = int.tryParse(_del2.text.trim());
    if (del2 == null || resto < 1) return [primero];
    return [primero, TramoTalonario(del2, del2 + resto - 1)];
  }

  PedidoDeEntradas get _pedido {
    final p = _sinNumeros;
    return p.conTramos(_tramos(p.cantidad));
  }

  void _elegirFamilia(String? id) => setState(() {
        _familiaId = id;
        _deLugar = null;
        _sueltas = null;
        _busqueda.clear();
      });

  void _limpiar() {
    _familiaId = null;
    _deLugar = null;
    _sueltas = null;
    _dosTramos = false;
    _busqueda.clear();
    _comprador.clear();
    _dni.clear();
    _descuento.text = '0';
    _del.clear();
    _al.clear();
    _del2.clear();
  }

  // ── Cobrar y guardar ─────────────────────────────────────────────────────

  Future<void> _cobrar(MedioBarra medio) async {
    if (_frenaSinPermiso()) return;
    final caja = _caja;
    final pedido = _pedido;
    if (caja == null || _guardando || pedido.falta != null) return;

    final CobroBarra? cobro;
    if (pedido.esSinCargo) {
      // Con el 100 % de descuento no hay nada que cobrar: se pregunta y queda
      // anotada, con el descuento.
      final si = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Venta sin cargo'),
          content: Text(
            '${pedido.cantidad == 1 ? 'Es 1 entrada' : 'Son ${pedido.cantidad} entradas'} '
            'con el 100 % de descuento: no se cobra nada. Queda anotada, con '
            'el descuento.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('VOLVER'),
            ),
            FilledButton(
              key: const Key('vender_sin_cargo_confirmar'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      );
      cobro = si == true ? pedido.cobroPor(MedioBarra.efectivo) : null;
    } else {
      cobro = await pedirCobro(
        context,
        total: pedido.total,
        medio: medio,
        recargoPrendido: pedido.recargoPrendido,
        recargoPct: pedido.recargoPct,
      );
    }
    if (cobro == null || !mounted) return;

    setState(() => _guardando = true);
    VentaEntradas? venta;
    try {
      // La venta se guarda antes de abrir el comprobante: sin impresora,
      // igual queda.
      venta = await pedido.guardarEn(
        ref.read(entradasDeLaCajaProvider),
        caja: caja,
        cobro: cobro,
        quien: _quienVende.nombre,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se guardó la venta. Probá de nuevo.')),
        );
      }
    }
    if (!mounted) return;
    if (venta == null) {
      setState(() => _guardando = false);
      return;
    }
    final guardada = venta;
    avisarQueCambioLaVenta(ref, widget.evento.id);
    final datos = _datosDelComprobante(guardada);
    setState(() {
      _ultima = guardada;
      _limpiar();
      _guardando = false;
    });
    await _cargar(silencioso: true);
    await _abrirComprobante(datos);
  }

  DatosDelComprobante _datosDelComprobante(VentaEntradas v, {bool copia = false}) {
    ContratoAlumno? alumno;
    for (final a in _alumnos) {
      if (a.id == v.contratoAlumnoId) alumno = a;
    }
    // Si la anularon (desde VENTAS, o el jefe desde otro equipo), la copia
    // sale con ANULADA, como la de VENTAS.
    AnulacionEntradas? anulacion;
    for (final a in _anulaciones) {
      if (a.ventaId == v.id) anulacion = a;
    }
    return DatosDelComprobante(
      venta: v,
      fiesta: _fiesta,
      fechaFiesta: widget.evento.fechaEvento,
      alumno: alumno?.nombreAlumno.trim(),
      mesa: alumno == null ? null : SalonMesas.textoMesasPuerta(alumno),
      copia: copia,
      anulacion: anulacion,
    );
  }

  Future<void> _abrirComprobante(DatosDelComprobante datos) async {
    try {
      await ref.read(abrirComprobanteDeEntradasProvider)(datos, context: context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La venta quedó guardada. No se pudo abrir el comprobante: '
            'probá de nuevo con VER EL COMPROBANTE.',
          ),
        ),
      );
    }
  }

  /// VENTAS: las de esta caja (el jefe ve todas las de la fiesta). Al volver se
  /// relee todo: una venta anulada cambia lo que le queda a esa familia y los
  /// números que están libres.
  Future<void> _abrirVentas() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VentasDeEntradasScreen(evento: widget.evento, caja: _caja),
      ),
    );
    if (mounted) await _cargar(silencioso: true);
  }

  /// CERRAR CAJA: se cuenta a ciegas y se cierra. Cerrada, VENDER también se
  /// va (si se quedara, pediría abrir otra caja). Mientras tanto VENDER no pide
  /// caja aunque relea: el cartel de abrir saldría encima del cierre.
  Future<void> _cerrarCaja() async {
    final caja = _caja;
    if (caja == null) return;
    _cerrandoCaja = true;
    bool? cerrada;
    try {
      cerrada = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CerrarCajaEntradasScreen(caja: caja, evento: widget.evento),
        ),
      );
    } finally {
      // Cerrada, VENDER se va: hasta desaparecer no vuelve a pedir caja.
      if (cerrada != true) _cerrandoCaja = false;
    }
    if (!mounted) return;
    if (cerrada == true) {
      await Navigator.of(context).maybePop();
      return;
    }
    await _cargar(silencioso: true);
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final puede = ref.watch(puedeVenderEntradasProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vender entradas'),
            Text(
              _fiesta,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (puede && _caja != null) ...[
            TextButton(
              key: const Key('vender_ventas'),
              onPressed: _guardando ? null : _abrirVentas,
              child: const Text('VENTAS'),
            ),
            TextButton(
              key: const Key('vender_cerrar'),
              onPressed: _guardando ? null : _cerrarCaja,
              child: const Text('CERRAR CAJA'),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: !puede
          ? const _Aviso(
              clave: 'vender_sin_permiso',
              texto: kSinPermisoParaVender,
            )
          : _cargando
              ? const Center(child: CircularProgressIndicator())
              : _errorCarga != null
                  ? _Aviso(clave: 'vender_error', texto: _errorCarga!)
                  : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (!(_config?.tienePrecio ?? false)) {
      return const _Aviso(
        clave: 'vender_sin_precio',
        texto: kLaFiestaNoTienePrecio,
        detalle: 'Sin precio no se abre la caja ni se vende. Se pone en '
            'ENTRADAS → PRECIOS, en modo jefe.',
      );
    }
    if (_caja == null) {
      return Center(
        child: FilledButton(
          key: const Key('vender_abrir_caja'),
          onPressed: _pedirCaja,
          child: const Text('ABRIR LA CAJA'),
        ),
      );
    }
    final p = _pedido;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _linea(),
            if (_ultima != null) _avisoDeGuardada(_ultima!),
            _titulo('1 · ¿A quién?'),
            _aQuien(),
            _titulo('2 · Las entradas'),
            _renglones(p),
            _titulo('3 · Números del talonario (opcional)'),
            _numeros(p),
            const SizedBox(height: 12),
            _total(p),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      );

  /// "Caja abierta · Romi · Todo subido".
  Widget _linea() {
    final conexion = ref.watch(connectivityServiceProvider);
    return StreamBuilder<AppConnectivity>(
      stream: conexion.stream,
      initialData: conexion.currentStatus,
      builder: (context, snap) {
        final linea = lineaDeSubidaDeEntradas(
          hayInternet: snap.data == AppConnectivity.online,
          sinSubir: _sinSubir,
        );
        final color =
            linea.atencion ? Colors.orange.shade800 : Colors.green.shade700;
        return Row(
          key: const Key('vender_linea'),
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Caja abierta · ${_caja?.operadorNombre ?? _quienVende.nombre} · '
                '${linea.texto}',
                key: const Key('vender_linea_texto'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _avisoDeGuardada(VentaEntradas v) {
    final verde = Colors.green.shade700;
    return Container(
      key: const Key('vender_guardada'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: verde.withValues(alpha: 0.1),
        border: Border.all(color: verde.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: verde),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Venta ${ComprobanteEntradasPdf.numero(v)} guardada · '
              '${v.cantidad == 1 ? '1 entrada' : '${v.cantidad} entradas'} · '
              '${pesos(v.cobrado)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: verde),
            ),
          ),
          TextButton(
            key: const Key('vender_ver_comprobante'),
            onPressed: () =>
                _abrirComprobante(_datosDelComprobante(v, copia: true)),
            child: const Text('VER EL COMPROBANTE'),
          ),
          IconButton(
            tooltip: 'Sacar el aviso',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _ultima = null),
          ),
        ],
      ),
    );
  }

  Widget _aQuien() {
    final familia = _familia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          key: const Key('vender_a_quien'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Una familia de la fiesta')),
            ButtonSegment(value: false, label: Text('Alguien de afuera')),
          ],
          selected: {_aUnaFamilia},
          onSelectionChanged: (s) => setState(() {
            _aUnaFamilia = s.first;
            _deLugar = null;
            _sueltas = null;
          }),
        ),
        const SizedBox(height: 8),
        if (_aUnaFamilia && familia == null) _buscador(),
        if (familia != null) _tarjetaDeLaFamilia(familia),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, caja) {
            final comprador = TextField(
              key: const Key('vender_comprador'),
              controller: _comprador,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nombre y apellido de quien compra',
              ),
              onChanged: (_) => setState(() {}),
            );
            final dni = TextField(
              key: const Key('vender_dni'),
              controller: _dni,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'DNI (opcional)'),
            );
            // En un celular, uno debajo del otro: lado a lado los rótulos
            // no entran.
            if (caja.maxWidth < _angosto) {
              return Column(
                children: [comprador, const SizedBox(height: 8), dni],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: comprador),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: dni),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Por debajo de este ancho, la pantalla se acomoda como en un celular.
  static const _angosto = 560.0;

  Widget _buscador() {
    final q = _busqueda.text.trim();
    final visibles = q.isEmpty
        ? const <ContratoAlumno>[]
        : _alumnos
            .where((a) => coincideTextoBusqueda([a.nombreAlumno], q))
            .take(6)
            .toList();
    final compradas = compradasPorFamilia(_ventas, _anulaciones);
    return Column(
      children: [
        TextField(
          key: const Key('vender_buscar'),
          controller: _busqueda,
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
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (q.isNotEmpty && visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Nadie con ese nombre.'),
          ),
        for (final a in visibles)
          ListTile(
            key: Key('vender_familia_${a.id}'),
            dense: true,
            title: Text(
              a.nombreAlumno.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_resumenDe(a, compradas[a.id] ?? 0)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _elegirFamilia(a.id),
          ),
      ],
    );
  }

  /// "6° A · mesa 14 y 15 · 14 al 50 % (compró 3)".
  String _resumenDe(ContratoAlumno a, int compro) {
    final division = (a.cursoDivision ?? '').trim();
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';
    final e = RetiroEntradas.entradasDe(a, foto: _foto);
    return [
      if (division.isNotEmpty) division,
      'mesa $mesa',
      if (e.conDescuento > 0) '${e.conDescuento} $_alPorciento (compró $compro)',
      if (e.sinDescuento > 0) '${e.sinDescuento} sin descuento',
    ].join(' · ');
  }

  Widget _tarjetaDeLaFamilia(ContratoAlumno a) {
    final lugares = _lugaresDe(a);
    final deuda = _deudas[a.id];
    final division = (a.cursoDivision ?? '').trim();
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';
    final cadaUna = _sinNumeros.precioDeLugar;
    final gris = Colors.grey.shade700;
    return Card(
      key: const Key('vender_familia_elegida'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: a.nombreAlumno.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: ' · ${division.isEmpty ? '' : '$division · '}mesa $mesa',
                          style: TextStyle(color: gris),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lugares.leCorresponden == 0
                        ? lugares.sinDescuento > 0
                            ? 'Sus lugares adicionales los agregó después del '
                                'sorteo: no llevan el descuento.'
                            : 'No tiene mesa adicional ni sillas extra: no '
                                'tiene entradas para comprar.'
                        : lugares.quedan == 0
                            ? lugares.compradas >= lugares.leCorresponden
                                ? 'Ya compró todas las de sus lugares adicionales '
                                    '(${lugares.compradas}).'
                                : 'De sus lugares adicionales no le queda nada '
                                    'pago para comprar (le corresponden '
                                    '${lugares.leCorresponden}, compró '
                                    '${lugares.compradas}).'
                            : 'Le quedan ${lugares.quedan} '
                                '${lugares.quedan == 1 ? 'entrada' : 'entradas'} de sus '
                                'lugares adicionales, a ${pesos(cadaUna ?? 0)} cada una '
                                '(le corresponden ${lugares.leCorresponden}, compró '
                                '${lugares.compradas}).',
                    key: const Key('vender_le_quedan'),
                  ),
                  if (lugares.sinDescuento > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Agregó ${lugares.sinDescuento} '
                        '${lugares.sinDescuento == 1 ? 'lugar' : 'lugares'} después '
                        'del sorteo: ${lugares.sinDescuento == 1 ? 'esa entrada va' : 'esas entradas van'} '
                        'al precio de hoy, sin el descuento. Le '
                        '${lugares.quedanSinDescuento == 1 ? 'queda 1' : 'quedan ${lugares.quedanSinDescuento}'}.',
                        key: const Key('vender_sin_descuento'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  // Lo que no está pago entero no se vende (20-nov-2026).
                  if (lugares.textoAConfirmar != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        lugares.textoAConfirmar!,
                        key: const Key('vender_a_confirmar'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  if (deuda != null && !deuda.pagoTodo)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Debe ${pesos(deuda.total)} del contrato: se salda en '
                        'caja. Se le vende solo lo que ya está pago entero.',
                        key: const Key('vender_debe'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              key: const Key('vender_cambiar_familia'),
              onPressed: () => _elegirFamilia(null),
              child: const Text('CAMBIAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renglones(PedidoDeEntradas p) {
    final familia = _familia;
    final lugares = familia == null ? null : _lugaresDe(familia);
    final gris = Colors.grey.shade700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lugares != null && lugares.quedan > 0) ...[
          const Divider(height: 1),
          _renglon(
            titulo: 'Entradas de sus lugares adicionales',
            detalle: '${pesos(p.precioDeLugar ?? 0)} c/u · tope ${lugares.quedan}',
            cantidad: p.deLugarQueVan,
            clave: 'vender_lugar',
            alCambiar: (n) => setState(
              () => _deLugar = n.clamp(0, lugares.quedan),
            ),
            subtotal: p.deLugarQueVan * (p.precioDeLugar ?? 0),
          ),
        ],
        // A una familia, las sueltas son lo que agregó después del sorteo, con
        // su tope: sin nada de eso pago, el renglón no está.
        if (lugares == null || lugares.quedanSinDescuento > 0) ...[
          const Divider(height: 1),
          _renglon(
            titulo: lugares != null
                ? 'Sin descuento: lo agregado después del sorteo'
                : p.rigeLaAnticipada
                    ? 'Entradas (anticipada)'
                    : 'Entradas',
            detalle: (p.descuentoQueVa > 0
                    ? '${pesos(p.precioDeHoy ?? 0)} c/u · con el descuento, '
                        '${pesos(RenglonEntradas.precioCon(p.precioDeHoy ?? 0, p.descuentoQueVa))}'
                    : '${pesos(p.precioDeHoy ?? 0)} c/u') +
                (lugares != null ? ' · tope ${lugares.quedanSinDescuento}' : ''),
            cantidad: p.sueltasQueVan,
            clave: 'vender_sueltas',
            alCambiar: (n) => setState(() => _sueltas = n < 0 ? 0 : n),
            subtotal: p.sueltasQueVan *
                RenglonEntradas.precioCon(p.precioDeHoy ?? 0, p.descuentoQueVa),
            antes: SizedBox(
              width: 120,
              child: Tooltip(
                message: p.puedeDescontar
                    ? 'Descuento a mano sobre estas entradas'
                    : kSoloEnModoJefe,
                child: TextField(
                  key: const Key('vender_descuento'),
                  controller: _descuento,
                  enabled: p.puedeDescontar,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Descuento',
                    suffixText: '%',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
          if (!p.puedeDescontar)
            Text(
              'El descuento a mano: $kSoloEnModoJefe, o si el jefe lo permite en '
              'PRECIOS.',
              key: const Key('vender_descuento_motivo'),
              style: TextStyle(fontSize: 12, color: gris),
            ),
        ],
      ],
    );
  }

  Widget _renglon({
    required String titulo,
    required String detalle,
    required int cantidad,
    required String clave,
    required ValueChanged<int> alCambiar,
    required double subtotal,
    Widget? antes,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, caja) {
            final nombre = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(detalle, style: TextStyle(color: Colors.grey.shade700)),
              ],
            );
            final controles = _controlesDelRenglon(
              cantidad: cantidad,
              clave: clave,
              alCambiar: alCambiar,
              subtotal: subtotal,
              antes: antes,
            );
            // En la PC, el nombre a la izquierda y la cantidad y el subtotal
            // contra el borde derecho, uno debajo del otro. En un celular, los
            // controles debajo del nombre.
            if (caja.maxWidth < _angosto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [nombre, const SizedBox(height: 6), controles],
              );
            }
            return Row(
              children: [
                Expanded(child: nombre),
                const SizedBox(width: 12),
                controles,
              ],
            );
          },
        ),
      );

  Widget _controlesDelRenglon({
    required int cantidad,
    required String clave,
    required ValueChanged<int> alCambiar,
    required double subtotal,
    Widget? antes,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (antes != null) ...[antes, const SizedBox(width: 12)],
          IconButton(
            key: Key('${clave}_menos'),
            tooltip: 'Una menos',
            onPressed: cantidad <= 0 ? null : () => alCambiar(cantidad - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$cantidad',
              key: Key('${clave}_cantidad'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            key: Key('${clave}_mas'),
            tooltip: 'Una más',
            onPressed: () => alCambiar(cantidad + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          SizedBox(
            width: 96,
            child: Text(
              pesos(subtotal),
              key: Key('${clave}_subtotal'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );

  Widget _numeros(PedidoDeEntradas p) {
    Widget campo(String clave, TextEditingController c, String rotulo) =>
        SizedBox(
          width: 120,
          child: TextField(
            key: Key(clave),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: rotulo, isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        );
    final tramos = p.tramos;
    final ultimo = tramos.isEmpty ? null : tramos.last;
    final alCalculado = Text(
      // Como en la entrega: el "al" del último tramo sale solo.
      ultimo == null ||
              ultimo.hasta < ultimo.desde ||
              (_dosTramos && tramos.length < 2)
          ? 'al …'
          : 'al ${ultimo.hasta}',
      key: const Key('vender_al_calculado'),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            campo('vender_del', _del, 'Del'),
            if (!_dosTramos) alCalculado,
            if (_dosTramos) ...[
              campo('vender_al', _al, 'Al'),
              campo('vender_del_2', _del2, 'Del'),
              alCalculado,
            ],
            TextButton(
              key: const Key('vender_dos_tramos'),
              onPressed: () => setState(() {
                _dosTramos = !_dosTramos;
                _al.clear();
                _del2.clear();
              }),
              child: Text(
                _dosTramos ? 'Un solo tramo' : 'El talonario salta: dos tramos',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _total(PedidoDeEntradas p) {
    final falta = p.falta;
    final apagado = falta != null || _guardando;
    Widget boton(String clave, String texto, MedioBarra medio) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton(
              key: Key(clave),
              onPressed: apagado ? null : () => _cobrar(medio),
              child: Text(texto),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(thickness: 2, color: Color(0x80D4AF37)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Total · ${p.cantidad == 1 ? '1 entrada' : '${p.cantidad} entradas'}',
                key: const Key('vender_cantidad'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              pesos(p.total),
              key: const Key('vender_total'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        SizedBox(
          height: 26,
          child: falta == null
              ? null
              : Text(
                  falta,
                  key: const Key('vender_falta'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    // Con la pantalla recién limpia es una guía, no un error:
                    // en rojo, justo después de una venta, asusta.
                    color: p.cantidad == 0 && _comprador.text.trim().isEmpty
                        ? Colors.grey.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
        ),
        if (p.esSinCargo)
          FilledButton(
            key: const Key('vender_sin_cargo'),
            onPressed: apagado ? null : () => _cobrar(MedioBarra.efectivo),
            child: const Text('GUARDAR SIN CARGO'),
          )
        else
          LayoutBuilder(
            builder: (context, caja) {
              final medios = [
                ('vender_efectivo', 'EFECTIVO', MedioBarra.efectivo),
                ('vender_transferencia', 'TRANSFERENCIA', MedioBarra.transferencia),
                ('vender_mixto', 'MIXTO', MedioBarra.mixto),
              ];
              // En un celular, uno debajo del otro: lado a lado
              // "TRANSFERENCIA" no entra y se parte en dos renglones.
              if (caja.maxWidth < _angosto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (clave, texto, medio) in medios)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton(
                          key: Key(clave),
                          onPressed: apagado ? null : () => _cobrar(medio),
                          child: Text(texto),
                        ),
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (final (clave, texto, medio) in medios)
                    boton(clave, texto, medio),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  final String clave;
  final String texto;
  final String? detalle;

  const _Aviso({required this.clave, required this.texto, this.detalle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                texto,
                key: Key(clave),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              if (detalle != null) ...[
                const SizedBox(height: 8),
                Text(detalle!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );
}
