import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../../models/evento.dart';
import '../../barra/cuentas/cobro_barra.dart';
import '../../barra/cuentas/pesos.dart';
import '../../barra/widgets/cobrar_hoja.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/services/pdf_service.dart';
import '../../common/utils/quien_opera.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/entradas_entregas_repository.dart';
import '../../eventos/repositories/entradas_retiro_repository.dart';
import '../../eventos/repositories/entregar_parte_de_la_app.dart';
import '../../eventos/repositories/sorteos_mesas_repository.dart';
import '../../eventos/services/entrega_por_partes.dart';
import '../../eventos/services/entregar_parte.dart';
import '../../eventos/services/lugares_pagos.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../../eventos/widgets/carteles_de_la_entrega.dart';
import '../cuentas/linea_de_subida.dart';
import '../cuentas/lugares_de_la_familia.dart';
import '../cuentas/numeros_de_entradas.dart';
import '../cuentas/pedido_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import '../pdf/comprobante_entradas_pdf.dart';
import '../pdf/papeles_de_entradas.dart';
import '../providers/entradas_providers.dart';
import '../services/en_caja.dart';
import '../services/nombre_de_la_fiesta.dart';
import 'abrir_caja_entradas_dialog.dart';
import 'cerrar_caja_entradas_screen.dart';
import 'vender_a_pagar.dart';
import 'vender_gratis.dart';
import 'vender_lista.dart';
import 'ventas_de_entradas_screen.dart';

/// VENDER: la pantalla de quien vende entradas en una fiesta (6.9.0; rehecha
/// el 20-nov-2026 con las maquetas que aprobó el usuario). **Quien tiene "Vende
/// entradas" entra solo por acá**: es la única puerta de la fiesta.
///
/// - Arriba, la línea de la caja y **el total de la fiesta**: cuántas pulseras
///   VIP y cuántas generales tienen que llegar, y cuántas se entregaron.
/// - **Un alumno de la fiesta**: la lista a la vista, con el buscador y el
///   filtro (abre en "Pagó todo: puede retirar"). Elegido, su tarjeta tiene:
///   - **GRATIS · SE ENTREGA** ([BloqueGratis]): las 8 de la mesa del contrato,
///     en dos partes (pulseras y generales), cada una cuando llega su material.
///     **Solo a quien pagó todo su contrato** (cuotas, extras y mora, de los
///     pagos: `RetiroEntradas.bloqueo`); quien debe va a la caja ("En caja", y
///     "pagó todo: ya podés entregar" cuando el pago baja). Se guarda por
///     `EntregarParte` ([_entregar]), sin caja ni precio.
///   - **A PAGAR** ([LineasAPagar]): cada mesa adicional y las sillas extra,
///     **solo lo que ya está pago entero**, con descuento lo que tenía al
///     sorteo y al precio del día lo agregado después. Se cobra en esta caja.
/// - **Alguien de afuera**: entradas al precio del día, como siempre.
///
/// **No cobra cuotas ni toca la cuenta de ningún alumno**: del alumno solo lee.
/// Lo que escribe es la venta (`PedidoDeEntradas.guardarEn`) y la entrega
/// (`EntregarParte`) (`test/venta_entradas_no_toca_test.dart`). **VENDER no
/// anula entregas**: eso es del jefe, desde ENTRADAS de la fiesta.
///
/// Las cuentas no están acá: el precio, lo que le queda a la familia, los
/// números y por qué todavía no se puede confirmar los decide
/// [PedidoDeEntradas]; qué está pago, [APagarDeLaFamilia]; quién puede
/// retirar, `RetiroEntradas` y `EntregaPorPartes`.
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

  /// Los alumnos de la fiesta, sin las bajas: los de la lista.
  List<ContratoAlumno> _alumnos = [];

  /// Todos, **también los de baja temporal**: sus números entregados siguen
  /// teniendo dueño.
  List<ContratoAlumno> _todos = [];
  Map<String, DeudaAlumno> _deudas = {};
  Map<String, EntradasRetiro> _retiros = {};
  Map<String, List<EntregaEntradas>> _renglones = {};
  List<VentaEntradas> _ventas = [];
  List<AnulacionEntradas> _anulaciones = [];
  int _sinSubir = 0;

  /// Cada alumno de la lista, con lo que se ve de él ya contado.
  Map<String, AlumnoDeVender> _info = {};

  /// Pulseras y generales de toda la fiesta.
  ResumenPorPartes? _resumen;

  // Lo que se está por vender.
  bool _aUnaFamilia = true;
  late String? _familiaId = widget.familiaId;
  FiltroDeVender _filtro = FiltroDeVender.puede;

  /// Cuántas lleva de cada línea de A PAGAR (por `claveDeLinea`). Sin la
  /// clave: todas las que le quedan de esa línea.
  final _cantidades = <String, int>{};

  /// Cuántas lleva alguien de afuera.
  int? _sueltas;

  /// La parte de GRATIS cuyo formulario está abierto, o null.
  ParteEntrega? _parteAbierta;

  bool _dosTramos = false;

  /// Quien vende escribió el número del talonario: ya no se le propone otro.
  bool _delTocado = false;

  /// En "Del" vino propuesto el número que sigue al último que vendió esta
  /// caja. Sin ventas con número (la primera de la caja), no hay propuesta y el
  /// casillero viene vacío: el texto de abajo no dice que trae uno.
  bool _hayPropuesta = false;
  final _busqueda = TextEditingController();
  final _comprador = TextEditingController();
  final _dni = TextEditingController();
  final _descuento = TextEditingController(text: '0');
  final _del = TextEditingController();
  final _al = TextEditingController();
  final _del2 = TextEditingController();

  bool _guardando = false;
  bool _entregando = false;
  bool _pidiendoCaja = false;

  /// La caja se pide **una vez**, al entrar. Si se vuelve sin abrirla, VENDER
  /// se queda (lo sin cargo se entrega sin caja) y no vuelve a preguntar.
  bool _cajaPreguntada = false;

  /// La pantalla de cerrar la caja está abierta encima: no se pide caja.
  bool _cerrandoCaja = false;

  /// La última venta guardada: su aviso queda arriba hasta la siguiente.
  VentaEntradas? _ultima;
  StreamSubscription<Set<String>>? _cambiosSub;
  StreamSubscription<int>? _pendienteSub;

  /// Las familias a las que ya se les intentó poner al día la fila de
  /// `entradas_retiro`, con cómo estaba lo suyo (`_firmaDeLaFila`). Si no se
  /// pudo mirar la nube, se saca y se vuelve a intentar en la próxima lectura.
  final _completadas = <String, String>{};

  /// Lo que, si baja de otro equipo, cambia lo que se ve acá: el precio, lo
  /// vendido, lo entregado, el sorteo y **lo que pagó cada familia** (con eso
  /// se habilita lo de A PAGAR y se destraba lo sin cargo). La tabla de los
  /// pagos no se nombra acá: viene en [tablasQueCambianLoPagado].
  static const _tablasQueMiro = {
    'entradas_config',
    'entradas_ventas',
    'entradas_anulaciones',
    'entradas_retiro',
    'entradas_entregas',
    // El sorteo (o el jefe, al aceptar la lista de PRECIOS) anota qué tenía
    // cada familia: cambia a quién le va el descuento.
    'sorteos_mesas',
    ...tablasQueCambianLoPagado,
  };

  bool get _ocupado => _guardando || _entregando;

  /// Algo bajó mientras se guardaba o se entregaba: se relee apenas termina
  /// ([_releerSiQuedoPendiente]). Si no, un pago que bajaba con el cartel de la
  /// entrega abierto se perdía hasta la próxima bajada, y "pagó todo: ya podés
  /// entregar" no salía (revisión del 20-nov-2026).
  bool _hayQueReleer = false;

  void _releerSiQuedoPendiente() {
    if (_hayQueReleer && mounted && !_ocupado) _cargar(silencioso: true);
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _cambiosSub =
        ref.read(syncEngineProvider).cambiosBajadosStream.listen((tablas) {
      if (!tablas.any(_tablasQueMiro.contains)) return;
      if (_ocupado) {
        _hayQueReleer = true;
      } else {
        _cargar(silencioso: true);
      }
    });
    // El aviso de arriba sale al bajar, no al subir: cuando el motor termina de
    // subir, la línea vuelve a contar lo que falta (etapa 7: quedaba en "1 venta
    // subiendo" con la venta ya en la nube, hasta la próxima venta o bajada).
    _pendienteSub =
        ref.read(syncEngineProvider).pendingStream.listen((_) => _contarSinSubir());
  }

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
    // Esta lectura ya trae lo que haya bajado.
    _hayQueReleer = false;
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
      final deudas = {
        for (final a in alumnos)
          a.id: RetiroEntradas.deudaDe(
            a,
            pagos: pagos[a.id] ?? const [],
            moraCobradaHistorial: mora[a.id] ?? 0,
          ),
      };
      // La entrega de todos, también de las bajas: sus números tienen dueño.
      final idsDeTodos = [for (final a in todos) a.id];
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds(idsDeTodos);
      final renglones = await ref
          .read(entradasEntregasRepositoryProvider)
          .deContratos(idsDeTodos);
      final ventas = await entradas.ventas(id);
      final anulaciones = await entradas.anulaciones(id);
      final caja = await entradas.cajaAbierta(
        eventoId: id,
        operadorId: _quienVende.id,
      );
      final sinSubir = await entradas.ventasSinSubir();
      // Lo que cada familia tenía al sorteo: el descuento es solo para eso.
      // Solo se lee: la venta no escribe el registro.
      final foto = await ref.read(fotoDeLosLugaresProvider)(id);
      final info = <String, AlumnoDeVender>{};
      for (final a in alumnos) {
        final deuda = deudas[a.id]!;
        final estado = EstadoDeLaEntrega.deAlumno(
          a,
          retiro: retiros[a.id],
          renglones: renglones[a.id] ?? const [],
        );
        final aPagar = APagarDeLaFamilia.de(
          a,
          pagos: pagos[a.id] ?? const [],
          foto: foto,
        );
        final bloqueo = RetiroEntradas.bloqueo(a, deuda);
        info[a.id] = AlumnoDeVender(
          alumno: a,
          deuda: deuda,
          bloqueo: bloqueo,
          grupo: EntregaPorPartes.grupoDe(a, deuda: deuda, estado: estado),
          estado: estado,
          aPagar: aPagar,
          // Con la cuenta para revisar no se le vende nada: la misma regla que
          // el diálogo de la entrega (`APagarDeLaFamilia.porQueNoSeVendeCon`),
          // con el bloqueo de la venta: la deuda no tapa los otros frenos.
          lugares: LugaresDeLaFamilia.de(
            a,
            ventas: ventas,
            anulaciones: anulaciones,
            aPagar: aPagar,
            bloqueo: RetiroEntradas.bloqueoDeLaVenta(a, deuda),
            todoEntregado: estado.todoEntregado,
          ),
        );
      }
      final resumen = ResumenPorPartes.de(
        alumnos: alumnos,
        retiros: retiros,
        renglones: [for (final l in renglones.values) ...l],
        deudas: deudas,
      );
      if (!mounted) return;
      setState(() {
        // La última venta anulada ya no es "guardada": se va su aviso verde.
        if (_ultima != null && anulaciones.any((a) => a.ventaId == _ultima!.id)) {
          _ultima = null;
        }
        _config = config;
        _alumnos = alumnos;
        _todos = todos;
        _deudas = deudas;
        _retiros = retiros;
        _renglones = renglones;
        _ventas = ventas;
        _anulaciones = anulaciones;
        _caja = caja;
        _sinSubir = sinSubir;
        _info = info;
        _resumen = resumen;
        _cargando = false;
        _errorCarga = null;
        _proponerNumero();
      });
      _despuesDeLeer(deudas);
      _completarLasFilas();
      // Sin caja abierta, VENDER la pide **una vez**. Sin precio no: no hay
      // nada que cobrar (lo sin cargo se entrega igual).
      if (caja == null &&
          (config?.tienePrecio ?? false) &&
          ref.read(puedeVenderEntradasProvider) &&
          !_cajaPreguntada &&
          !_pidiendoCaja &&
          !_cerrandoCaja) {
        _cajaPreguntada = true;
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

  /// Con las cuentas recién leídas: quién de "En caja" ya pagó todo, con un
  /// sonido corto la primera vez (como el mostrador).
  void _despuesDeLeer(Map<String, DeudaAlumno> deudas) {
    final recien =
        ref.read(enCajaProvider(widget.evento.id).notifier).conDeudas(deudas);
    if (recien.isNotEmpty) unawaited(SystemSound.play(SystemSoundType.alert));
  }

  /// Una familia cuya fila de `entradas_retiro` no dice lo mismo que sus
  /// partes (`EntregaPorPartes.filaParaPonerAlDia`): tiene las dos partes y la
  /// fila no dice "entregado" (cada parte la dio un equipo distinto y uno estaba
  /// sin internet), o la fila dice "entregado" y el jefe anuló una parte. Con
  /// internet se pone al día ahora, para que el plano, Recepción y una PC con
  /// la 6.9.x vean lo mismo. Lo decide `EntregarParte.completarLaFila`, que
  /// mira la nube antes. Una vez por familia mientras lo suyo no cambie, salvo
  /// que no haya podido mirar la nube.
  void _completarLasFilas() {
    if (!ref.read(puedeVenderEntradasProvider)) return;
    if (ref.read(connectivityServiceProvider).currentStatus ==
        AppConnectivity.offline) {
      return;
    }
    for (final a in _alumnos) {
      final estado = _info[a.id]?.estado;
      if (estado == null ||
          !EntregaPorPartes.filaParaPonerAlDia(
            retiro: _retiros[a.id],
            estado: estado,
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
    return '${(_renglones[a.id] ?? const <EntregaEntradas>[]).length}'
        '|${retiro?.estado.name}|${retiro?.updatedAt.toIso8601String()}';
  }

  /// Pone al día la fila de [a]. Es automático (lo llama la lectura), así que
  /// la llave va callada: sin el permiso de vender no se guarda nada, sin
  /// cartel.
  Future<void> _completarLaFila(ContratoAlumno a) async {
    if (!ref.read(puedeVenderEntradasProvider)) return;
    try {
      final r = await ref.read(entregarParteProvider).completarLaFila(
            eventoId: widget.evento.id,
            contratoAlumnoId: a.id,
          );
      switch (r) {
        case ResultadoDeLaFila.escrita:
          if (mounted && !_ocupado) {
            await _cargar(silencioso: true);
          } else {
            _hayQueReleer = true;
          }
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

  // ── Las llaves ───────────────────────────────────────────────────────────

  /// Sin el permiso de vender (o el modo jefe) no se abre una caja, ni se
  /// guarda una venta o una entrega, aunque alguien llegue hasta acá.
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
    _cajaPreguntada = true;
    final quien = _quienVende;
    final caja = await abrirCajaDeEntradas(
      context,
      eventoId: widget.evento.id,
      fiesta: _fiesta,
      operadorId: quien.id,
      operadorNombre: quien.nombre,
    );
    _pidiendoCaja = false;
    // Volvió sin abrirla: VENDER se queda (lo sin cargo se entrega sin caja) y
    // A PAGAR ofrece ABRIR LA CAJA.
    if (!mounted || caja == null) return;
    avisarQueCambioLaVenta(ref, widget.evento.id);
    setState(() {
      _caja = caja;
      _proponerNumero();
    });
  }

  // ── Lo que se está por vender ────────────────────────────────────────────

  ContratoAlumno? get _familia {
    if (!_aUnaFamilia) return null;
    for (final a in _alumnos) {
      if (a.id == _familiaId) return a;
    }
    return null;
  }

  /// El descuento de PRECIOS para lo que tenía al sorteo (viene en 50).
  double get _descuentoPct =>
      _config?.descuentoLugaresPct ?? ConfigEntradas.kDescuentoDeLosLugares;

  /// Los números de las anticipadas que ya tienen dueño: solo lo vendido. Lo
  /// entregado sin cargo es otro talonario (el de las generales de los
  /// alumnos) y no frena una venta (20-nov).
  Map<String, List<TramoTalonario>> get _ocupados =>
      NumerosDeEntradas.ocupadosDeLaVenta(_ventas, _anulaciones);

  /// Cuántas le quedan de cada línea de A PAGAR de [info], cuántas siguen "a
  /// confirmar" y cuántas lleva.
  ({List<int> quedan, List<int> aConfirmar, List<int> lleva}) _lineasDe(
    AlumnoDeVender info,
  ) {
    final lineas = info.aPagar.lineas;
    final (:quedan, :aConfirmar) = info.lugares.porLinea(lineas);
    return (
      quedan: quedan,
      aConfirmar: aConfirmar,
      lleva: [
        for (var i = 0; i < lineas.length; i++)
          (_cantidades[claveDeLinea(lineas[i])] ?? quedan[i]).clamp(0, quedan[i]),
      ],
    );
  }

  /// El pedido sin los números: de acá sale cuántas entradas son.
  ///
  /// A una familia: lo de cada línea con descuento va a sus lugares adicionales
  /// y lo sin descuento a las sueltas; **los topes y el porqué los pone
  /// [PedidoDeEntradas]**. A una familia no se le pone descuento a mano.
  PedidoDeEntradas get _sinNumeros {
    var p = PedidoDeEntradas.nuevo(
      config: _config,
      hoyAr: ref.read(hoyEnArgentinaProvider)(),
      esJefe: ref.read(esRolJefeProvider),
      ocupados: _ocupados,
    );
    final familia = _familia;
    final info = familia == null ? null : _info[familia.id];
    if (familia != null && info != null) {
      final lineas = info.aPagar.lineas;
      final cuantas = _lineasDe(info).lleva;
      var conDescuento = 0;
      var sinDescuento = 0;
      for (var i = 0; i < lineas.length; i++) {
        if (lineas[i].conDescuento) {
          conDescuento += cuantas[i];
        } else {
          sinDescuento += cuantas[i];
        }
      }
      p = p
          .paraLaFamilia(familia.id, info.lugares)
          .conDeLugar(conDescuento)
          .conSueltas(sinDescuento);
    } else if (!_aUnaFamilia) {
      p = p
          .conSueltas(_sueltas ?? 0)
          .conDescuento(double.tryParse(_descuento.text.replaceAll(',', '.')) ?? 0);
    }
    return p.conComprador(_comprador.text).conDni(_dni.text);
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

  /// Propone en "del" el número que sigue al último que vendió esta caja
  /// (20-nov-2026), salvo que quien vende ya haya escrito o borrado algo.
  void _proponerNumero() {
    if (_delTocado || _dosTramos) return;
    final caja = _caja;
    final n = caja == null
        ? null
        : NumerosDeEntradas.siguienteDeLaCaja(caja.id, _ventas, _anulaciones);
    _del.text = n?.toString() ?? '';
    _hayPropuesta = n != null;
  }

  void _elegirFamilia(String? id) => setState(() {
        _familiaId = id;
        _cantidades.clear();
        _parteAbierta = null;
        _busqueda.clear();
      });

  /// Desde "En caja": abre la tarjeta de esa familia.
  void _abrirLaFamilia(String id) {
    _aUnaFamilia = true;
    _elegirFamilia(id);
  }

  /// Después de una venta: la pantalla queda lista para la siguiente. La
  /// familia elegida se queda (puede faltarle retirar lo sin cargo).
  void _limpiar() {
    _cantidades.clear();
    _sueltas = null;
    _dosTramos = false;
    _delTocado = false;
    _comprador.clear();
    _dni.clear();
    _descuento.text = '0';
    _del.clear();
    _al.clear();
    _del2.clear();
  }

  // ── Entregar lo sin cargo ────────────────────────────────────────────────

  /// Entrega una parte por `EntregarParte`, el único camino para guardar una
  /// entrega: mira la nube, pregunta si no hay internet, relee y frena si algo
  /// cambió. Acá solo se muestran los carteles, los mismos que la entrega de
  /// ENTRADAS (`carteles_de_la_entrega.dart`).
  Future<void> _entregar(ContratoAlumno alumno, DatosDeLaParte datos) async {
    if (_frenaSinPermiso()) return;
    if (_ocupado) return;
    setState(() => _entregando = true);
    try {
      final r = await ref.read(entregarParteProvider).entregar(
            eventoId: widget.evento.id,
            contratoAlumnoId: alumno.id,
            datos: datos,
            quien: quienOpera(ref),
            seguirSinInternet: () => seguirSinInternetEnLaEntrega(context, datos.parte),
          );
      if (!mounted) return;
      // Si estaba en "En caja", ya está: se le entregó.
      if (r is Entregada) {
        ref.read(enCajaProvider(widget.evento.id).notifier).sacar(alumno.id);
      }
      // Sin internet y sin SEGUIR, el formulario queda con lo escrito.
      if (r is! Cancelada) setState(() => _parteAbierta = null);
      await _cargar(silencioso: true);
      if (!mounted) return;
      // Ya se guardó: mientras se lee el cartel, lo que baje se muestra.
      setState(() => _entregando = false);
      await mostrarComoTerminoLaEntrega(context, r, alumno: alumno, datos: datos);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se guardó la entrega. Probá de nuevo.')),
        );
      }
    } finally {
      if (mounted && _entregando) setState(() => _entregando = false);
      _releerSiQuedoPendiente();
    }
  }

  /// MANDAR A CAJA: la familia que debe va a pagar y queda en "En caja"; cuando
  /// el pago baja, salta "pagó todo: ya podés entregar". Se vuelve a la lista.
  void _mandarACaja(ContratoAlumno a) {
    final deuda = _deudas[a.id];
    if (deuda == null) return;
    ref.read(enCajaProvider(widget.evento.id).notifier).mandar(a, deuda);
    _elegirFamilia(null);
  }

  /// PASAR A CAJA: quien vende también tiene Cobros. La familia queda en "En
  /// caja" y se va a la caja de cuotas sin volver a poner el PIN.
  Future<void> _pasarACaja(ContratoAlumno a) async {
    final app = ref.read(appRoleProvider);
    if (!app.esEntradas || !app.permisos.cobros) return;
    final deuda = _deudas[a.id];
    if (deuda != null) {
      ref.read(enCajaProvider(widget.evento.id).notifier).mandar(a, deuda);
    }
    final rol = ref.read(appRoleProvider.notifier);
    Navigator.of(context).popUntil((r) => r.isFirst);
    await rol.pasarACaja();
  }

  bool get _puedePasarACaja {
    final app = ref.watch(appRoleProvider);
    return app.esEntradas && app.permisos.cobros;
  }

  // ── Cobrar y guardar ─────────────────────────────────────────────────────

  Future<void> _cobrar(MedioBarra medio) async {
    if (_frenaSinPermiso()) return;
    final caja = _caja;
    final pedido = _pedido;
    if (caja == null || _ocupado || pedido.falta != null) return;

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
      _releerSiQuedoPendiente();
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

  /// La planilla de entrega en papel, **una por material** (las pulseras VIP y
  /// las generales llegan y se entregan en tandas distintas).
  Future<void> _imprimirPlanilla(ParteEntrega material, bool blancoYNegro) async {
    try {
      await PdfService.generarPlanillaEntrega(
        widget.evento,
        _alumnos,
        material: material,
        retiros: _retiros,
        renglones: [for (final l in _renglones.values) ...l],
        deudas: _deudas,
        blancoYNegro: blancoYNegro,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo armar la planilla. Probá de nuevo.')),
      );
    }
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
            // En un celular, corto: al lado van VENTAS y CERRAR CAJA.
            Text(
              MediaQuery.sizeOf(context).width < kVenderAngosto
                  ? 'Vender'
                  : 'Vender entradas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _fiesta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (puede && _caja != null) ...[
            TextButton(
              key: const Key('vender_ventas'),
              onPressed: _ocupado ? null : _abrirVentas,
              child: const Text('VENTAS'),
            ),
            TextButton(
              key: const Key('vender_cerrar'),
              onPressed: _ocupado ? null : _cerrarCaja,
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

  /// PLANILLA, al lado del total de la fiesta: la de entrega en papel, una por
  /// material.
  Widget _menuDeLaPlanilla() => PopupMenuButton<(ParteEntrega, bool)>(
        key: const Key('vender_planilla'),
        tooltip: 'Planilla de entrega',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.print_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                'PLANILLA',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        onSelected: (e) => _imprimirPlanilla(e.$1, e.$2),
        itemBuilder: (_) => [
          for (final material in ParteEntrega.values)
            for (final bn in const [true, false])
              PopupMenuItem(
                key: Key('vender_planilla_${material.clave}_${bn ? 'bn' : 'color'}'),
                value: (material, bn),
                child: Text(
                  'Planilla de ${material == ParteEntrega.pulseras ? 'pulseras VIP' : 'generales'}'
                  ' (${bn ? 'blanco y negro' : 'color'})',
                ),
              ),
        ],
      );

  bool get _tienePrecio => _config?.tienePrecio ?? false;

  Widget _cuerpo() {
    final familia = _familia;
    final info = familia == null ? null : _info[familia.id];
    final lista = <Widget>[];
    if (_aUnaFamilia && info == null) {
      final todos = [
        for (final a in _alumnos)
          if (_info[a.id] != null) _info[a.id]!,
      ];
      lista
        ..add(FiltrosDeVender(
          todos: todos,
          filtro: _filtro,
          busqueda: _busqueda,
          alBuscar: () => setState(() {}),
          alFiltrar: (f) => setState(() => _filtro = f),
        ))
        ..add(const SizedBox(height: 4));
      final visibles = alumnosQueSeVen(todos, filtro: _filtro, busqueda: _busqueda.text);
      for (var i = 0; i < visibles.length; i++) {
        if (i > 0) lista.add(const Divider(height: 1));
        final a = visibles[i];
        lista.add(RenglonDeVender(
          info: a,
          descuentoPct: _descuentoPct,
          alElegir: () => _elegirFamilia(a.id),
        ));
      }
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _linea(),
            _totalDeLaFiesta(),
            if (!_tienePrecio)
              const _AvisoEnLinea(
                clave: 'vender_sin_precio',
                texto: kLaFiestaNoTienePrecio,
                detalle: 'Hasta que lo ponga (ENTRADAS → PRECIOS, en modo jefe) no '
                    'se vende. Lo sin cargo se entrega igual.',
              ),
            ..._enCajaArriba(),
            if (_ultima != null) _avisoDeGuardada(_ultima!),
            const SizedBox(height: 10),
            _aQuien(),
            const SizedBox(height: 10),
            if (_aUnaFamilia && info != null) _tarjeta(info),
            ...lista,
            if (!_aUnaFamilia) ..._afuera(),
          ],
        ),
      ),
    );
  }

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
        final sinCaja = _caja == null;
        final color = linea.atencion || sinCaja
            ? Colors.orange.shade800
            : Colors.green.shade700;
        return Row(
          key: const Key('vender_linea'),
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sinCaja
                    ? 'Sin caja abierta · ${_quienVende.nombre} · ${linea.texto}'
                    : 'Caja abierta · ${_caja?.operadorNombre ?? _quienVende.nombre} · '
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

  /// "Pulseras VIP: 24 (entregadas 3) · Generales: 40 (entregadas 0)": cuántas
  /// tienen que llegar de cada material, y cuántas ya se dieron.
  Widget _totalDeLaFiesta() {
    final r = _resumen;
    if (r == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.confirmation_number_outlined, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Total de la fiesta · ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: r.texto),
                ],
              ),
              key: const Key('vender_total_fiesta'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
          ),
          _menuDeLaPlanilla(),
        ],
      ),
    );
  }

  /// Las familias que se mandaron a la caja: las que ya pagaron todo (con
  /// ENTREGAR) y las que todavía deben.
  List<Widget> _enCajaArriba() {
    final enCaja = ref.watch(enCajaProvider(widget.evento.id));
    if (enCaja.vacia) return const [];
    final verde = Colors.green.shade700;
    final ambar = Colors.orange.shade800;
    final notifier = ref.read(enCajaProvider(widget.evento.id).notifier);
    return [
      for (final f in enCaja.pagaron)
        Builder(builder: (context) {
          final info = _info[f.alumnoId];
          final libre = info != null && info.bloqueo == BloqueoRetiro.ninguno;
          return Container(
            key: Key('vender_pago_${f.alumnoId}'),
            margin: const EdgeInsets.only(top: 8),
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
                        ? '${f.nombre} pagó todo: ya podés entregar'
                        : '${f.nombre} pagó, pero todavía no se puede entregar: '
                            'abrila para ver por qué',
                    key: Key('vender_pago_texto_${f.alumnoId}'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: verde),
                  ),
                ),
                // En el celular el texto llegaba pegado al botón (muestras del
                // 20-nov-2026).
                const SizedBox(width: 8),
                if (info != null)
                  FilledButton(
                    key: Key('vender_pago_abrir_${f.alumnoId}'),
                    style: FilledButton.styleFrom(backgroundColor: verde),
                    onPressed: _ocupado ? null : () => _abrirLaFamilia(f.alumnoId),
                    child: Text(libre ? 'ENTREGAR' : 'ABRIR'),
                  ),
                IconButton(
                  tooltip: 'Sacar el aviso',
                  onPressed: () => notifier.sacar(f.alumnoId),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
        }),
      if (enCaja.esperando.isNotEmpty)
        Container(
          key: const Key('vender_en_caja'),
          margin: const EdgeInsets.only(top: 8),
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
                  for (final f in enCaja.esperando)
                    InputChip(
                      key: Key('vender_en_caja_${f.alumnoId}'),
                      label: Text(
                        f.pagoUnaParte
                            ? '${f.nombre} · pagó una parte · faltan ${pesos(f.debe)}'
                            : '${f.nombre} · debe ${pesos(f.debe)}',
                      ),
                      onPressed: () => _abrirLaFamilia(f.alumnoId),
                      onDeleted: () => notifier.sacar(f.alumnoId),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
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
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: verde),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Venta ${ComprobanteEntradasPdf.numero(v)} guardada · '
                  '${v.cantidad == 1 ? '1 entrada' : '${v.cantidad} entradas'} · '
                  '${pesos(v.cobrado)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: verde),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
        ],
      ),
    );
  }

  Widget _aQuien() => SegmentedButton<bool>(
        key: const Key('vender_a_quien'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Un alumno de la fiesta')),
          ButtonSegment(value: false, label: Text('Alguien de afuera')),
        ],
        selected: {_aUnaFamilia},
        onSelectionChanged: (s) => setState(() {
          _aUnaFamilia = s.first;
          _cantidades.clear();
          _sueltas = null;
          _parteAbierta = null;
        }),
      );

  // ── La tarjeta del alumno ────────────────────────────────────────────────

  Widget _tarjeta(AlumnoDeVender info) {
    final a = info.alumno;
    final chip = info.chip;
    final enCaja = ref.watch(enCajaProvider(widget.evento.id)).contiene(a.id);
    return Card(
      key: const Key('vender_familia_elegida'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: a.nombreAlumno.trim(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' · ${info.divisionYMesa}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                        key: const Key('vender_familia_nombre'),
                      ),
                      ChipDeVender(
                        chip.texto,
                        key: const Key('vender_familia_estado'),
                        color: chip.color,
                        icono: chip.icono,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('vender_cambiar_familia'),
                  onPressed: _ocupado ? null : () => _elegirFamilia(null),
                  child: const Text('CAMBIAR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BloqueGratis(
              alumno: a,
              estado: info.estado,
              deuda: info.deuda,
              bloqueo: info.bloqueo,
              abierta: _parteAbierta,
              ocupado: _ocupado,
              deOtros: EntregaPorPartes.numerosDeOtros(
                _todos,
                _retiros,
                [for (final l in _renglones.values) ...l],
                salvo: a.id,
              ),
              retiro: _retiros[a.id],
              renglones: _renglones[a.id] ?? const [],
              enCaja: enCaja,
              puedePasarACaja: _puedePasarACaja,
              alAbrir: (p) => setState(() => _parteAbierta = p),
              alCancelar: () => setState(() => _parteAbierta = null),
              alConfirmar: (datos) => _entregar(a, datos),
              alMandarACaja: () => _mandarACaja(a),
              alPasarACaja: () => _pasarACaja(a),
            ),
            const SizedBox(height: 12),
            _aPagar(info),
          ],
        ),
      ),
    );
  }

  /// A PAGAR: lo de su mesa adicional y sus sillas extra que ya pagó entero,
  /// con su precio, y el cobro.
  Widget _aPagar(AlumnoDeVender info) {
    final gris = Colors.grey.shade700;
    final lineas = info.aPagar.lineas;
    final hijos = <Widget>[
      Row(
        children: [
          const Expanded(
            child: Text(
              'A PAGAR',
              key: Key('vender_a_pagar_titulo'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Text('Se cobra en esta caja', style: TextStyle(fontSize: 12.5, color: gris)),
        ],
      ),
    ];
    if (lineas.isEmpty) {
      hijos.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Nada: no tiene mesa adicional ni sillas extra.',
          key: const Key('vender_nada_a_pagar'),
          style: TextStyle(color: gris),
        ),
      ));
    } else if (!_tienePrecio) {
      hijos.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('$kLaFiestaNoTienePrecio.', style: TextStyle(color: gris)),
      ));
    } else {
      final p = _pedido;
      final cuentas = _lineasDe(info);
      // Con la cuenta para revisar (la misma regla que el diálogo de la
      // entrega), las líneas se ven apagadas y no se vende nada: el porqué va
      // abajo, sin quién compra ni cobro.
      final frenadas = info.lugares.frenada != null;
      hijos.add(LineasAPagar(
        aPagar: info.aPagar,
        quedan: cuentas.quedan,
        aConfirmar: cuentas.aConfirmar,
        cantidades: cuentas.lleva,
        alCambiar: (i, n) =>
            setState(() => _cantidades[claveDeLinea(lineas[i])] = n),
        precioConDescuento: p.precioDeLugar ?? 0,
        precioEntero: _config?.valorEntrada ?? 0,
        precioDelDia: p.precioDeHoy ?? 0,
        rigeLaAnticipada: p.rigeLaAnticipada,
        descuentoPct: _descuentoPct,
        frenadas: frenadas,
      ));
      // Cada línea ya dice "Ya compró las de esta línea": abajo no se repite
      // (revisión del 20-nov-2026).
      final todasDicenYaCompro = !frenadas &&
          lineas.any((l) => l.entradas > 0) &&
          [
            for (var i = 0; i < lineas.length; i++)
              lineas[i].entradas <= 0 ||
                  (cuentas.quedan[i] <= 0 && cuentas.aConfirmar[i] <= 0),
          ].every((b) => b);
      final porQueNo = info.lugares.porQueNoSeVende;
      if (porQueNo != null) {
        // Sin nada para comprar hoy no se pide quién compra ni se cobra. Lo que
        // espera el pago ya lo dice cada línea ("A confirmar: falta pagarla en
        // caja"): no se repite abajo.
        if (porQueNo != info.lugares.textoAConfirmar && !todasDicenYaCompro) {
          hijos.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              porQueNo,
              key: const Key('vender_a_pagar_motivo'),
              style: TextStyle(fontWeight: FontWeight.w600, color: gris),
            ),
          ));
        }
      } else {
        hijos.addAll([
          const Divider(height: 20),
          _quienCompra(),
          const SizedBox(height: 12),
          _talonario(p),
          const SizedBox(height: 12),
          _total(p),
        ]);
      }
    }
    return Container(
      key: const Key('vender_a_pagar'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x80D4AF37)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: hijos,
      ),
    );
  }

  // ── Alguien de afuera ────────────────────────────────────────────────────

  List<Widget> _afuera() {
    if (!_tienePrecio) return const [];
    final p = _pedido;
    return [
      _quienCompra(),
      const SizedBox(height: 8),
      const Divider(height: 1),
      _renglonDeAfuera(p),
      if (!p.puedeDescontar)
        Text(
          'El descuento a mano: $kSoloEnModoJefe, o si el jefe lo permite en '
          'PRECIOS.',
          key: const Key('vender_descuento_motivo'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      const SizedBox(height: 12),
      _talonario(p),
      const SizedBox(height: 12),
      _total(p),
    ];
  }

  Widget _quienCompra() => LayoutBuilder(
        builder: (context, caja) {
          final angosto = caja.maxWidth < kVenderAngosto;
          final comprador = TextField(
            key: const Key('vender_comprador'),
            controller: _comprador,
            textCapitalization: TextCapitalization.characters,
            // En un celular el rótulo largo se cortaba ("…de quien co…", muestras
            // del 20-nov): va corto, y lo que se pide abajo, como ayuda.
            decoration: InputDecoration(
              labelText: angosto ? 'Quien compra' : 'Nombre y apellido de quien compra',
              hintText: angosto ? 'Nombre y apellido' : null,
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
          // En un celular, uno debajo del otro: lado a lado los rótulos no
          // entran.
          if (angosto) {
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
      );

  /// Las entradas de alguien de afuera: al precio del día, con el descuento a
  /// mano si se puede.
  Widget _renglonDeAfuera(PedidoDeEntradas p) {
    final titulo = p.rigeLaAnticipada ? 'Entradas (anticipada)' : 'Entradas';
    final detalle = p.descuentoQueVa > 0
        ? '${pesos(p.precioDeHoy ?? 0)} c/u · con el descuento, '
            '${pesos(RenglonEntradas.precioCon(p.precioDeHoy ?? 0, p.descuentoQueVa))}'
        : '${pesos(p.precioDeHoy ?? 0)} c/u';
    final descuento = SizedBox(
        width: 120,
        child: Tooltip(
          message: p.puedeDescontar
              ? 'Descuento a mano sobre estas entradas'
              : kSoloEnModoJefe,
          child: TextField(
            key: const Key('vender_descuento'),
            controller: _descuento,
            enabled: p.puedeDescontar,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      );
    // En un celular el descuento va en su propio renglón: al lado de la
    // cantidad y el subtotal, en 360 px se salía del ancho (revisión del
    // 20-nov-2026).
    ControlDeCantidad controles({required bool conDescuento}) => ControlDeCantidad(
          clave: 'vender_sueltas',
          cantidad: p.sueltasQueVan,
          subtotal: p.sueltasQueVan *
              RenglonEntradas.precioCon(p.precioDeHoy ?? 0, p.descuentoQueVa),
          alCambiar: (n) => setState(() => _sueltas = n < 0 ? 0 : n),
          antes: conDescuento ? descuento : null,
        );
    return Padding(
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
          // En la PC, el nombre a la izquierda y la cantidad y el subtotal
          // contra el borde derecho. En un celular, los controles debajo.
          if (caja.maxWidth < kVenderAngosto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                nombre,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: descuento),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: controles(conDescuento: false),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: nombre),
              const SizedBox(width: 12),
              controles(conDescuento: true),
            ],
          );
        },
      ),
    );
  }

  // ── El talonario y el total ──────────────────────────────────────────────

  /// El talonario de las anticipadas: todo lo que se vende sale de ahí. Viene
  /// propuesto el número que sigue al último que vendió esta caja; se puede
  /// cambiar o borrar (sin número se vende igual).
  Widget _talonario(PedidoDeEntradas p) {
    Widget campo(String clave, TextEditingController c, String rotulo) =>
        SizedBox(
          width: 120,
          child: TextField(
            key: Key(clave),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: rotulo, isDense: true),
            onChanged: (_) => setState(() => _delTocado = true),
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
    final n = p.cantidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n > 0
              ? 'Talonario de las anticipadas · ${n == 1 ? 'la que paga' : 'las $n que paga'}'
              : 'Talonario de las anticipadas',
          key: const Key('vender_talonario_titulo'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          _hayPropuesta
              ? 'Opcional. Viene el número que sigue al último que vendió esta '
                  'caja: se puede cambiar o borrar.'
              : 'Opcional: escribí el primer número de las anticipadas que '
                  'entregás.',
          key: const Key('vender_talonario_ayuda'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
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
                _delTocado = true;
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
    final apagado = falta != null || _ocupado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(thickness: 2, color: Color(0x80D4AF37)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Total a pagar · ${p.cantidad == 1 ? '1 entrada' : '${p.cantidad} entradas'}',
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
        if (falta != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              falta,
              key: const Key('vender_falta'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                // Mientras falta quién compra es una guía, no un error: en rojo,
                // apenas se elige una familia (que viene con sus entradas
                // cargadas) o justo después de una venta, asusta.
                color: _comprador.text.trim().isEmpty
                    ? Colors.grey.shade700
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          )
        else
          const SizedBox(height: 8),
        if (_caja == null)
          FilledButton.icon(
            key: const Key('vender_abrir_caja'),
            onPressed: _ocupado ? null : _pedirCaja,
            icon: const Icon(Icons.point_of_sale),
            label: const Text('ABRIR LA CAJA'),
          )
        else if (p.esSinCargo)
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
              Widget boton(String clave, String texto, MedioBarra medio) => FilledButton(
                    key: Key(clave),
                    onPressed: apagado ? null : () => _cobrar(medio),
                    child: Text(texto),
                  );
              // En un celular, uno debajo del otro: lado a lado
              // "TRANSFERENCIA" no entra y se parte en dos renglones.
              if (caja.maxWidth < kVenderAngosto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (clave, texto, medio) in medios)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: boton(clave, texto, medio),
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (final (clave, texto, medio) in medios)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: boton(clave, texto, medio),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Un aviso a pantalla entera: sin permiso, o si no se pudo leer.
class _Aviso extends StatelessWidget {
  final String clave;
  final String texto;

  const _Aviso({required this.clave, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            texto,
            key: Key(clave),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      );
}

/// Un aviso en la pantalla, arriba: la fiesta sin precio.
class _AvisoEnLinea extends StatelessWidget {
  final String clave;
  final String texto;
  final String detalle;

  const _AvisoEnLinea({required this.clave, required this.texto, required this.detalle});

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade900;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            key: Key(clave),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          Text(detalle, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
