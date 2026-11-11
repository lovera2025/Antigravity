import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/pedido_de_cierre.dart';
import '../cuentas/pesos.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/papel_en_pantalla.dart';
import '../impresion/ticket_esc_pos.dart';
import '../providers/barra_providers.dart';
import 'ok_del_cierre.dart';
import 'pesos_enteros_formatter.dart';
import 'vales_de_la_venta_screen.dart' show quienEnLaBarra;
import 'ventas_de_la_caja_screen.dart' show pedirMotivo;

/// Cerrar la caja de barra de la cajera, al terminar la noche (etapa 6, decidido el 7-nov):
///
/// 1. **Contar, a ciegas.** Escribe el efectivo del cajón, con el cambio. La pantalla no
///    muestra ninguna plata antes: ni lo vendido ni lo esperado. Confirma viendo el número
///    grande.
/// 2. **Esperar el OK de la encargada** (11-nov-2026, pedido del usuario): la tablet anota
///    el pedido (`barra_cierres`), a la encargada le salta el aviso en su aparato, ve los
///    totales y acepta. Recién ahí **esta tablet cierra la caja**. Mientras espera la
///    cajera sigue sin ver ninguna plata. Para que ninguna caja quede trabada: LA
///    ENCARGADA ESTÁ ACÁ (su PIN en esta tablet, sin red), CERRAR SIN ESPERAR (a los 3
///    minutos, con motivo, y queda marcado) y VOLVER A VENDER (cancela el pedido).
///    Quien manda en la barra (la encargada con su propia caja, o el jefe) cierra sin pedir.
/// 3. **El cierre.** Recién ahí ve cuánto tenía que haber y la diferencia, y el cierre
///    entero como el papel: lo vendido por producto, las sillas, lo anulado, los totales y
///    el historial de sus ventas. Puede imprimirlo (por la térmica sale el corto),
///    guardarlo como PDF de 58 mm y agregar una nota.
///
/// Devuelve true si la caja quedó cerrada: VENDER se cierra sola y vuelve al inicio.
class CerrarCajaBarraScreen extends ConsumerStatefulWidget {
  final CajaBarra caja;
  final String fiesta;

  const CerrarCajaBarraScreen({super.key, required this.caja, required this.fiesta});

  @override
  ConsumerState<CerrarCajaBarraScreen> createState() => _CerrarCajaBarraScreenState();
}

class _CerrarCajaBarraScreenState extends ConsumerState<CerrarCajaBarraScreen> {
  final _contado = TextEditingController();
  final _nota = TextEditingController();

  /// La caja ya cerrada, como quedó guardada. Null: todavía se está contando.
  CajaBarra? _cerrada;
  List<VentaBarra> _ventas = const [];
  List<AnulacionBarra> _anulaciones = const [];
  bool _ocupado = false;
  ({String texto, bool error})? _aviso;

  /// El pedido de cierre que espera el OK de la encargada. Null: todavía no contó, o ya
  /// se contestó.
  PasoDelCierre? _pedido;

  /// Mientras espera, mira la base de este equipo cada pocos segundos: el OK llega por
  /// la red del salón o baja de la nube. No le pide nada a la nube.
  Timer? _vigia;
  bool _mirando = false;

  @override
  void initState() {
    super.initState();
    if (!widget.caja.abierta) {
      // Una caja que ya llegó cerrada (la cerró otra pantalla) va directo al cierre.
      unawaited(_mostrarCerrada(widget.caja));
    } else {
      // Si ya había pedido cerrar (cerró la app, o volvió a entrar), sigue esperando.
      unawaited(_retomarElPedido());
    }
  }

  @override
  void dispose() {
    _vigia?.cancel();
    _contado.dispose();
    _nota.dispose();
    super.dispose();
  }

  DateTime _ahora() => ref.read(ahoraEnLaBarraProvider)();

  int? get _contadoEscrito => PesosEnterosFormatter.leer(_contado.text);

  /// La categoría de cada bebida del catálogo: el papel corto va por categoría.
  Map<String, String> _categorias = const {};

  CierreDeBarra get _cuentas => CierreDeBarra.de(
        _cerrada ?? widget.caja,
        _ventas,
        _anulaciones,
        categorias: _categorias,
      );

  void _decir(String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (texto: texto, error: error));
  }

  Future<void> _leerVentas(CajaBarra caja) async {
    final barra = ref.read(barraDeLaCajaProvider);
    _ventas = await barra.ventasDeLaCaja(caja.id);
    _anulaciones = await barra.anulacionesDeLaCaja(caja.id);
    try {
      _categorias = {
        for (final p in await barra.productos(conBajas: true)) p.id: p.categoria,
      };
    } catch (_) {
      // Sin el catálogo el papel corto dice las unidades: el cierre no se frena por eso.
    }
  }

  Future<void> _mostrarCerrada(CajaBarra caja) async {
    await _leerVentas(caja);
    if (mounted) setState(() => _cerrada = caja);
  }

  // ── 1. Contar y cerrar ────────────────────────────────────────────────────

  Future<void> _cerrar() async {
    final contado = _contadoEscrito;
    if (contado == null || _ocupado) return;
    // Quien manda en la barra (la encargada con su propia caja, o el jefe) cierra sin
    // pedirle el OK a nadie.
    final cierraSola = ref.read(mandaEnLaBarraProvider);
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Contaste todo el efectivo, con el cambio?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contaste'),
            Text(
              pesos(contado.toDouble()),
              key: const Key('cierre_contado_grande'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              cierraSola
                  ? 'La caja se cierra con ese número. Después no se cambia: si algo no '
                      'cierra, lo explicás en la nota.'
                  : 'Con ese número se le pide el cierre a la encargada. Cuando ella '
                      'acepte, la caja se cierra y ya no se cambia.',
              key: const Key('cierre_que_pasa'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VOLVER A CONTAR')),
          FilledButton(
            key: const Key('cierre_confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(cierraSola ? 'SÍ, CERRAR' : 'SÍ, PEDIR EL CIERRE'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    if (cierraSola) {
      await _cerrarDeVerdad(contado.toDouble(), nota: _nota.text);
    } else {
      await _pedirElCierre(contado.toDouble());
    }
  }

  /// Cierra la caja en la base de este equipo, con lo contado. **Solo acá se toca
  /// `barra_cajas`:** la caja la cierra siempre su propio equipo.
  Future<void> _cerrarDeVerdad(double contado, {String? nota}) async {
    if (mounted) setState(() => _ocupado = true);
    final barra = ref.read(barraDeLaCajaProvider);
    final CajaBarra cerrada;
    try {
      // La caja como está guardada: el cambio pudo ponerse después de abrir.
      final enLaBase = widget.caja.operadorId == null
          ? null
          : await barra.cajaAbierta(eventoId: widget.caja.eventoId, operadorId: widget.caja.operadorId!);
      final caja = enLaBase ?? widget.caja;
      await _leerVentas(caja);
      final diferencia = CierreDeBarra.de(caja, _ventas, _anulaciones).diferenciaCon(contado);
      cerrada = await barra.cerrarCaja(
        caja,
        efectivoContado: contado,
        diferencia: diferencia,
        nota: nota,
        quien: quienEnLaBarra(ref, caja),
      );
    } catch (_) {
      if (mounted) setState(() => _ocupado = false);
      _decir('No se pudo cerrar la caja. Probá de nuevo.', error: true);
      return;
    }
    _vigia?.cancel();
    unawaited(ref.read(subirDeLaBarraProvider)('barra_cajas', cerrada.id));
    if (!mounted) return;
    setState(() {
      _cerrada = cerrada;
      _pedido = null;
      _ocupado = false;
    });
    await _imprimir(alCerrar: true);
  }

  // ── 2. Esperar el OK de la encargada ───────────────────────────────────────

  /// Anota el pedido de cierre, con lo contado, y se queda esperando.
  Future<void> _pedirElCierre(double contado) async {
    setState(() => _ocupado = true);
    try {
      final paso = await ref.read(barraDeLaCajaProvider).anotarPasoDelCierre(PasoDelCierre.pedir(
            caja: widget.caja,
            efectivoContado: contado,
            nota: _nota.text,
            hechoPor: quienEnLaBarra(ref, widget.caja),
            ahora: _ahora(),
          ));
      unawaited(ref.read(subirDeLaBarraProvider)('barra_cierres', paso.id));
      if (!mounted) return;
      setState(() {
        _pedido = paso;
        _ocupado = false;
        _aviso = null;
      });
      _arrancarElVigia();
    } catch (_) {
      if (mounted) setState(() => _ocupado = false);
      _decir('No se pudo pedir el cierre. Probá de nuevo.', error: true);
    }
  }

  void _arrancarElVigia() {
    _vigia?.cancel();
    _vigia = Timer.periodic(kMirarPedidosDeCierre, (_) => _mirarSiContestaron());
  }

  /// Al abrir: si la caja ya había pedido cerrar y nadie cerró, sigue desde ahí.
  Future<void> _retomarElPedido() async {
    try {
      final pasos = await ref.read(barraDeLaCajaProvider).pasosDelCierre(widget.caja.eventoId);
      final estado = PedidoDeCierre.de(widget.caja.id, pasos);
      if (!mounted || estado.pedido == null) return;
      if (estado.esperando || estado.aceptado) {
        setState(() => _pedido = estado.pedido);
        _arrancarElVigia();
        await _mirarSiContestaron();
      } else if (estado.hayQueRecontar) {
        _decir('La encargada pidió que cuentes de nuevo.', error: true);
      }
    } catch (_) {
      // Sin la tabla (una base que todavía no migró): se cuenta como siempre.
    }
  }

  /// Mira en la base de este equipo si a su pedido ya le contestaron.
  Future<void> _mirarSiContestaron() async {
    final pedido = _pedido;
    if (pedido == null || _ocupado || _mirando || !mounted) return;
    _mirando = true;
    try {
      final pasos = await ref.read(barraDeLaCajaProvider).pasosDelCierre(widget.caja.eventoId);
      if (!mounted || _pedido?.id != pedido.id) return;
      final estado = PedidoDeCierre.de(widget.caja.id, pasos);
      if (estado.pedido?.id != pedido.id) return;
      if (estado.aceptado) {
        await _cerrarConElOk(pedido, acepto: estado.respuesta!.hechoPor ?? '');
      } else if (estado.hayQueRecontar) {
        _volverAContar('La encargada pide que cuentes de nuevo.');
      } else {
        // El reloj de "cerrar sin esperar".
        setState(() {});
      }
    } catch (_) {
      // Se vuelve a mirar en la próxima vuelta.
    } finally {
      _mirando = false;
    }
  }

  /// Le llegó el OK: cierra con lo que había contado. Si en el medio hubo ventas (la
  /// app se cerró mientras esperaba y siguió vendiendo), ese conteo ya no sirve: el
  /// pedido se cancela y hay que contar de nuevo.
  Future<void> _cerrarConElOk(PasoDelCierre pedido, {required String acepto}) async {
    _vigia?.cancel();
    try {
      await _leerVentas(widget.caja);
    } catch (_) {}
    final pidio = DateTime.tryParse(pedido.createdAt);
    final vendioDespues = pidio != null &&
        _ventas.any((v) {
          final t = DateTime.tryParse(v.createdAt);
          return t != null && t.isAfter(pidio);
        });
    if (vendioDespues) {
      await _responder(pedido, TipoPasoDelCierre.cancelado);
      _volverAContar('Hubo ventas después de pedir el cierre: contá de nuevo.');
      return;
    }
    await _cerrarDeVerdad(
      pedido.efectivoContado ?? 0,
      nota: PedidoDeCierre.notaConElOk(notaDeLaCajera: pedido.nota, acepto: acepto),
    );
  }

  /// Agrega la respuesta a un pedido desde esta tablet. True si quedó anotada.
  Future<bool> _responder(
    PasoDelCierre pedido,
    TipoPasoDelCierre tipo, {
    String? nota,
    String? quien,
  }) async {
    try {
      final paso = await ref.read(barraDeLaCajaProvider).anotarPasoDelCierre(PasoDelCierre.responder(
            pedido: pedido,
            tipo: tipo,
            nota: nota,
            hechoPor: quien ?? quienEnLaBarra(ref, widget.caja),
            ahora: _ahora(),
          ));
      unawaited(ref.read(subirDeLaBarraProvider)('barra_cierres', paso.id));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _volverAContar(String aviso) {
    _vigia?.cancel();
    if (!mounted) return;
    setState(() {
      _pedido = null;
      _ocupado = false;
      _contado.clear();
      _aviso = (texto: aviso, error: true);
    });
  }

  /// VOLVER A VENDER: el pedido ya no vale, y la caja sigue abierta.
  Future<void> _volverAVender() async {
    final pedido = _pedido;
    if (pedido == null || _ocupado) return;
    setState(() => _ocupado = true);
    final anotado = await _responder(pedido, TipoPasoDelCierre.cancelado);
    if (!mounted) return;
    if (!anotado) {
      setState(() => _ocupado = false);
      _decir('No se pudo cancelar el pedido. Probá de nuevo.', error: true);
      return;
    }
    _vigia?.cancel();
    Navigator.of(context).pop(false);
  }

  /// CERRAR SIN ESPERAR: para una noche sin encargada, o si no contesta. Con motivo, y
  /// la caja queda marcada para que el jefe la mire.
  Future<void> _cerrarSinEsperar() async {
    final pedido = _pedido;
    if (pedido == null || _ocupado) return;
    if (!PedidoDeCierre.yaPuedeCerrarSinEsperar(pedido, _ahora())) return;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Cerrar sin el OK de la encargada',
      explicacion: 'La caja se cierra con lo que contaste. Queda anotado que cerró sin el '
          'OK, con tu nombre y el motivo, y el jefe lo ve en LAS CAJAS.',
      ayuda: 'Por qué: no hay encargada esta noche, se fue…',
      boton: 'CERRAR LA CAJA',
      claveBoton: 'sin_ok_cerrar',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    if (!await _responder(pedido, TipoPasoDelCierre.sinOk, nota: motivo)) {
      _decir('No se pudo cerrar la caja. Probá de nuevo.', error: true);
      return;
    }
    await _cerrarDeVerdad(
      pedido.efectivoContado ?? 0,
      nota: PedidoDeCierre.notaSinElOk(notaDeLaCajera: pedido.nota, motivo: motivo),
    );
  }

  /// LA ENCARGADA ESTÁ ACÁ: pone su PIN en esta tablet, ve los totales y acepta. No
  /// necesita red: sirve si la tablet se quedó sin wifi, o si la encargada vino a
  /// buscar la plata.
  Future<void> _laEncargadaEstaAca() async {
    final pedido = _pedido;
    if (pedido == null || _ocupado) return;
    final pin = await _pedirElPin();
    if (pin == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final encontrado = await ref.read(appRoleProvider.notifier).buscarOperador(pin);
      if (!mounted) return;
      if (encontrado == null) {
        _decir('Ese PIN no es de nadie.', error: true);
        return;
      }
      if (!encontrado.permisos.encargadaBarra) {
        _decir('Ese PIN no es de una encargada de barra.', error: true);
        return;
      }
      await _leerVentas(widget.caja);
      if (!mounted) return;
      final respuesta = await mostrarOkDelCierre(
        context,
        caja: widget.caja,
        pedido: pedido,
        cuentas: _cuentas,
      );
      if (respuesta == null || !mounted) return;
      final quien = encontrado.operador.nombre;
      if (respuesta == RespuestaAlCierre.recontar) {
        await _responder(pedido, TipoPasoDelCierre.recontar, quien: quien);
        _volverAContar('La encargada pide que cuentes de nuevo.');
        return;
      }
      if (!await _responder(pedido, TipoPasoDelCierre.ok, quien: quien)) {
        _decir('No se pudo guardar el OK. Probá de nuevo.', error: true);
        return;
      }
      await _cerrarConElOk(pedido, acepto: quien);
    } catch (_) {
      _decir('No se pudo comprobar el PIN. Probá de nuevo.', error: true);
    } finally {
      if (mounted && _cerrada == null && _pedido != null) setState(() => _ocupado = false);
    }
  }

  Future<String?> _pedirElPin() {
    final pin = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('El PIN de la encargada'),
        content: TextField(
          key: const Key('pin_encargada'),
          controller: pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          FilledButton(
            key: const Key('pin_seguir'),
            onPressed: () => Navigator.pop(ctx, pin.text.trim()),
            child: const Text('SEGUIR'),
          ),
        ],
      ),
    );
  }

  // ── 2. El cierre ──────────────────────────────────────────────────────────

  /// El papel de la térmica: **el corto** (por categoría y sin el historial), que mide lo
  /// mismo se venda lo que se venda. El detalle de cada bebida queda en la pantalla, en
  /// el PDF y en LAS CAJAS.
  Future<void> _imprimir({bool alCerrar = false}) async {
    final caja = _cerrada;
    if (caja == null || _ocupado) return;
    setState(() => _ocupado = true);
    bool salio;
    try {
      salio = await ref.read(papelDeLaBarraProvider).imprimir(
            ModeloTicket.deCierre(caja, _cuentas, fiesta: widget.fiesta, corto: true),
          );
    } catch (_) {
      salio = false;
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (salio) {
      _decir(alCerrar ? 'Caja cerrada. Salió el papel del cierre.' : 'Salió el papel del cierre.');
    } else {
      _decir(
        '${alCerrar ? 'Caja cerrada. ' : ''}No salió el papel. '
        '${ref.read(papelDeLaBarraProvider).sinPapel ? 'La impresora no tiene papel: cambiá el rollo y tocá' : '¿La impresora está prendida y cerca? Tocá'} IMPRIMIR.',
        error: true,
      );
    }
  }

  Future<void> _guardarPdf() async {
    final caja = _cerrada;
    if (caja == null || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(guardarPdfDeLaBarraProvider)(
        _lineasCompletas(caja),
        titulo: 'Cierre de caja ${caja.numeroCaja} - ${widget.fiesta}',
        nombre: _nombrePdf(caja),
        context: context,
      );
      _decir('PDF listo.');
    } catch (_) {
      _decir('No se pudo armar el PDF. Probá de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _anotar() async {
    final caja = _cerrada;
    if (caja == null || _ocupado) return;
    final nota = await pedirMotivo(
      context,
      titulo: 'Una nota para el cierre',
      explicacion: 'Sale en el papel y la ve el jefe. Lo contado no cambia.',
      ayuda: 'Por ejemplo: faltó un billete de 500',
      boton: 'GUARDAR',
      claveBoton: 'nota_guardar',
    );
    if (nota == null || !mounted) return;
    try {
      // Quién aceptó el cierre (o que cerró sin el OK) queda: la cajera cambia solo lo suyo.
      final anotada = await ref.read(barraDeLaCajaProvider).anotarCierre(
            caja,
            nota: PedidoDeCierre.notaNueva(escrita: nota, notaDeAntes: caja.notaCierre),
            quien: quienEnLaBarra(ref, caja),
          );
      unawaited(ref.read(subirDeLaBarraProvider)('barra_cajas', anotada.id));
      if (mounted) setState(() => _cerrada = anotada);
      _decir('Nota guardada. Tocá IMPRIMIR si la querés en papel.');
    } catch (_) {
      _decir('No se pudo guardar la nota. Probá de nuevo.', error: true);
    }
  }

  void _listo() => Navigator.of(context).pop(true);

  /// Lo que se lee en la pantalla y va al PDF: con el historial.
  List<LineaTicket> _lineasCompletas(CajaBarra caja) => ModeloTicket.deCierre(
        caja,
        _cuentas,
        fiesta: widget.fiesta,
        historial: _ventas,
        anulaciones: _anulaciones,
      );

  String _nombrePdf(CajaBarra caja) {
    final fecha = ModeloTicket.fechaYHora(caja.cerradaAt ?? caja.abiertaAt).split(' ').first.replaceAll('/', '-');
    final fiesta = widget.fiesta.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'cierre_barra_${fiesta}_caja${caja.numeroCaja}_$fecha.pdf';
  }

  // ── Dibujo ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cerrada = _cerrada;
    final pedido = _pedido;
    return PopScope(
      // Cerrada la caja, volver es lo mismo que LISTO: VENDER también se va. Esperando
      // el OK, volver es VOLVER A VENDER: no se sale dejando el pedido en pie.
      canPop: cerrada == null && pedido == null,
      onPopInvokedWithResult: (hecho, _) {
        if (hecho) return;
        if (cerrada != null) {
          _listo();
        } else if (pedido != null) {
          unawaited(_volverAVender());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Cerrar la caja ${widget.caja.numeroCaja}'
            '${widget.caja.operadorNombre == null ? '' : ' · ${widget.caja.operadorNombre}'}',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (cerrada != null)
              TextButton(key: const Key('cierre_listo'), onPressed: _listo, child: const Text('LISTO')),
          ],
        ),
        body: cerrada != null
            ? _elCierre(cerrada)
            : pedido != null
                ? _esperar(pedido)
                : _contar(),
      ),
    );
  }

  /// Esperando el OK de la encargada. **Sin ninguna plata de la caja a la vista**, como
  /// al contar (`test/modo_barra_cerrado_test.dart` lo vigila).
  Widget _esperar(PasoDelCierre pedido) {
    final tema = Theme.of(context);
    final falta = PedidoDeCierre.faltaParaCerrarSinEsperar(pedido, _ahora());
    final yaPuede = falta == Duration.zero;
    String reloj(Duration d) {
      final s = d.inSeconds + (d.inMilliseconds % 1000 == 0 ? 0 : 1);
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          key: const Key('cierre_esperando'),
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.hourglass_top, size: 48, color: tema.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Esperá a la encargada',
              key: const Key('cierre_esperando_titulo'),
              textAlign: TextAlign.center,
              style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Le llegó el aviso de que la Caja ${widget.caja.numeroCaja} pide cerrar. Cuando '
              'acepte, la caja se cierra sola y sale el papel. No hace falta tocar nada.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('cierre_encargada_aca'),
              onPressed: _ocupado ? null : _laEncargadaEstaAca,
              icon: const Icon(Icons.badge_outlined),
              label: const Text('LA ENCARGADA ESTÁ ACÁ'),
            ),
            const SizedBox(height: 4),
            Text(
              'Pone su PIN en esta tablet y acepta desde acá.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('cierre_volver_a_vender'),
              onPressed: _ocupado ? null : _volverAVender,
              icon: const Icon(Icons.arrow_back),
              label: const Text('VOLVER A VENDER'),
            ),
            const SizedBox(height: 4),
            Text(
              'Cancela el pedido: después se cuenta de nuevo.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              key: const Key('cierre_sin_esperar'),
              onPressed: _ocupado || !yaPuede ? null : _cerrarSinEsperar,
              icon: const Icon(Icons.lock_outline),
              label: const Text('CERRAR SIN ESPERAR'),
            ),
            Text(
              yaPuede
                  ? 'Si esta noche no hay encargada, o no contesta. Pide el motivo y queda anotado.'
                  : 'Se puede en ${reloj(falta)}, si la encargada no contesta.',
              key: const Key('cierre_sin_esperar_cuando'),
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
            if (_aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _aviso!.texto,
                  key: const Key('cierre_aviso'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _aviso!.error ? tema.colorScheme.error : null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contar() {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Contá todo el efectivo del cajón, con el cambio.', style: tema.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Después de cerrar vas a ver cuánto tenía que haber.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('cierre_contado'),
              controller: _contado,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [PesosEnterosFormatter()],
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: r'$ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('cierre_nota'),
              controller: _nota,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nota (si hace falta)'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('cierre_cerrar'),
              onPressed: _contadoEscrito == null || _ocupado ? null : _cerrar,
              icon: const Icon(Icons.lock_outline),
              label: const Text('CERRAR LA CAJA'),
            ),
            if (_aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _aviso!.texto,
                  key: const Key('cierre_aviso'),
                  style: TextStyle(color: _aviso!.error ? tema.colorScheme.error : null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _elCierre(CajaBarra caja) {
    final ancho = MediaQuery.sizeOf(context).width;
    final papel = PapelEnPantalla(_lineasCompletas(caja), key: const Key('cierre_papel'));
    final panel = _panel(caja);
    if (ancho >= 900) {
      // En la tablet acostada y en la PC: la diferencia y los botones a la izquierda, el
      // papel entero a la derecha.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 420,
            child: ListView(padding: const EdgeInsets.all(20), children: [panel]),
          ),
          Expanded(
            child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: papel),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [panel, const SizedBox(height: 16), papel],
    );
  }

  Widget _panel(CajaBarra caja) {
    final tema = Theme.of(context);
    final diferencia = caja.diferencia ?? 0;
    final c = centavos(diferencia);
    final color = c == 0
        ? Colors.green.shade400
        : c < 0
            ? tema.colorScheme.error
            : Colors.amber.shade600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const Key('cierre_resultado'),
          color: color.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tenía que haber ${pesos(_cuentas.efectivoEsperado)}',
                  key: const Key('cierre_esperado'),
                ),
                Text('Contaste ${pesos(caja.efectivoContado ?? 0)}'),
                const SizedBox(height: 6),
                Text(
                  diferenciaEnPalabras(diferencia),
                  key: const Key('cierre_diferencia'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('cierre_imprimir'),
              onPressed: _ocupado ? null : _imprimir,
              icon: const Icon(Icons.print),
              label: const Text('IMPRIMIR'),
            ),
            OutlinedButton.icon(
              key: const Key('cierre_pdf'),
              onPressed: _ocupado ? null : _guardarPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('GUARDAR PDF'),
            ),
            OutlinedButton.icon(
              key: const Key('cierre_anotar'),
              onPressed: _ocupado ? null : _anotar,
              icon: const Icon(Icons.edit_note),
              // "Aceptó: Romi" solo no es una nota de la cajera.
              label: Text(
                caja.notaCierre == null || caja.notaCierre == PedidoDeCierre.marcaDelOk(caja.notaCierre)
                    ? 'AGREGAR UNA NOTA'
                    : 'CAMBIAR LA NOTA',
              ),
            ),
          ],
        ),
        if (_aviso != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _aviso!.texto,
              key: const Key('cierre_aviso'),
              style: TextStyle(
                color: _aviso!.error ? tema.colorScheme.error : Colors.green.shade400,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
