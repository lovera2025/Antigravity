import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_engine.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/evento.dart';
import '../../barra/cuentas/pesos.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/quien_opera.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/entradas_retiro_repository.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../cuentas/historial_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import '../pdf/comprobante_entradas_pdf.dart';
import '../pdf/historial_entradas_pdf.dart';
import '../pdf/papeles_de_entradas.dart';
import '../providers/entradas_providers.dart';
import '../services/nombre_de_la_fiesta.dart';
import 'imprimir_por_hojas.dart';

/// VENTAS: el historial de la venta de entradas de una fiesta (6.9.0, sección 8
/// del spec del 13-nov).
///
/// **Quien vende ve las de su caja; el jefe, todas las de la fiesta.**
/// Reimprimir puede cualquiera; **"Pago verificado" y ANULAR, solo el jefe**:
/// sin modo jefe se ven apagados, con el motivo, y las dos funciones frenan
/// igual (`_frenaSinModoJefe`, `test/solo_modo_jefe_test.dart`).
///
/// Una venta nunca se borra ni se edita: anulada sigue en la lista, tachada,
/// con quién la anuló, el motivo y si devolvieron las entradas.
class VentasDeEntradasScreen extends ConsumerStatefulWidget {
  final Evento evento;

  /// La caja de quien vende: ve solo las suyas. El jefe en modo jefe ve todas,
  /// venga con caja o sin ella.
  final CajaEntradas? caja;

  const VentasDeEntradasScreen({super.key, required this.evento, this.caja});

  @override
  ConsumerState<VentasDeEntradasScreen> createState() =>
      _VentasDeEntradasScreenState();
}

class _VentasDeEntradasScreenState
    extends ConsumerState<VentasDeEntradasScreen> {
  bool _cargando = true;
  String? _errorCarga;
  HistorialDeEntradas? _historial;
  List<ContratoAlumno> _alumnos = [];
  FiltroDeVentas _filtro = FiltroDeVentas.todas;
  bool _ocupado = false;

  /// Las tandas del historial que ya se imprimieron en esta pantalla (por su
  /// primera hoja), con lo que decían esas hojas al imprimirlas
  /// ([HistorialEntradasPdf.firmaDeLasHojas]). **Una tanda está "impresa" solo
  /// si sus hojas siguen diciendo lo mismo** (revisión del 15-nov): una venta
  /// anulada o verificada después, otro filtro, o las hojas corridas, y la pila
  /// de papeles ya no es la de ahora.
  final _tandasImpresas = <int, String>{};
  StreamSubscription<Set<String>>? _cambiosSub;

  static const _tablasQueMiro = {
    'entradas_cajas',
    'entradas_ventas',
    'entradas_anulaciones',
    'entradas_verificaciones',
    'entradas_retiro',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
    _cambiosSub =
        ref.read(syncEngineProvider).cambiosBajadosStream.listen((tablas) {
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

  String get _fiesta => nombreDeLaFiesta(widget.evento);

  /// El jefe ve toda la fiesta; quien vende, su caja (y sin caja, ninguna).
  String? get _soloDeLaCaja =>
      ref.read(esRolJefeProvider) ? null : (widget.caja?.id ?? '');

  /// Las sumas de plata, solo para el jefe: **quien vende cuenta su caja a
  /// ciegas**, y con el total de su caja abierta sabría cuánto efectivo tiene
  /// que haber (revisión del 14-nov). El monto de cada venta sí lo ve.
  bool get _conPlata => ref.read(esRolJefeProvider);

  String get _alcance {
    if (_soloDeLaCaja == null) return 'Todas las cajas';
    final nombre = widget.caja?.operadorNombre ?? '';
    return nombre.isEmpty ? 'Tu caja' : 'La caja de $nombre';
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final id = widget.evento.id;
      final entradas = ref.read(entradasDeLaFiestaProvider);
      final alumnos = await ref.read(contratosRepositoryProvider).getByEvento(id);
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds([for (final a in alumnos) a.id]);
      final historial = HistorialDeEntradas.de(
        cajas: await entradas.cajas(id),
        ventas: await entradas.ventas(id),
        anulaciones: await entradas.anulaciones(id),
        verificaciones: await entradas.verificaciones(id),
        entregados: RetiroEntradas.tramosDeOtros(alumnos, retiros, salvo: ''),
        soloDeLaCaja: _soloDeLaCaja,
      );
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _alumnos = alumnos;
        _cargando = false;
        _errorCarga = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (!silencioso) {
          _errorCarga = 'No se pudieron leer las ventas. Volvé a entrar.';
        }
      });
    }
  }

  void _decir(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// La segunda llave: anular y "Pago verificado" son solo del jefe.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    _decir('$kSoloEnModoJefe: anular y verificar un pago es del jefe.');
    return true;
  }

  Future<void> _verificar(VentaDelHistorial v, bool verificado) async {
    if (_frenaSinModoJefe()) return;
    if (v.anulada || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(entradasDelJefeProvider).verificar(
            v.venta,
            verificado: verificado,
            quien: quienOpera(ref),
          );
    } catch (_) {
      _decir('No se pudo guardar. Probá de nuevo.');
    }
    await _cargar(silencioso: true);
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _anular(VentaDelHistorial v) async {
    if (_frenaSinModoJefe()) return;
    if (v.anulada || _ocupado) return;
    final respuesta = await showDialog<({String motivo, bool devueltas})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnularVentaDialog(venta: v.venta),
    );
    if (respuesta == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(entradasDelJefeProvider).anular(
            v.venta,
            motivo: respuesta.motivo,
            devueltas: respuesta.devueltas,
            quien: quienOpera(ref),
          );
      avisarQueCambioLaVenta(ref, widget.evento.id);
      _decir('Venta ${ComprobanteEntradasPdf.numero(v.venta)} anulada.');
    } catch (_) {
      _decir('No se pudo anular. Probá de nuevo.');
    }
    await _cargar(silencioso: true);
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _reimprimir(VentaDelHistorial v) async {
    ContratoAlumno? alumno;
    for (final a in _alumnos) {
      if (a.id == v.venta.contratoAlumnoId) alumno = a;
    }
    try {
      await ref.read(abrirComprobanteDeEntradasProvider)(
        DatosDelComprobante(
          venta: v.venta,
          fiesta: _fiesta,
          fechaFiesta: widget.evento.fechaEvento,
          alumno: alumno?.nombreAlumno.trim(),
          mesa: alumno == null ? null : SalonMesas.textoMesasPuerta(alumno),
          copia: true,
          anulacion: v.anulacion,
        ),
        context: context,
      );
    } catch (_) {
      _decir('No se pudo abrir el comprobante. Probá de nuevo.');
    }
  }

  /// La familia de cada alumno, para el historial: "PÉREZ, JUAN m.12-13".
  Map<String, String> _familias() => {
        for (final a in _alumnos)
          a.id: () {
            final mesa = SalonMesas.textoMesasPuerta(a);
            return '${a.nombreAlumno.trim()}${mesa == null ? '' : ' m.$mesa'}';
          }(),
      };

  /// IMPRIMIR HISTORIAL. **Si son muchas hojas, pregunta antes** (pedido del
  /// usuario, 15-nov): todo junto, o por hojas (de a tandas, o un tramo).
  Future<void> _imprimirHistorial() async {
    final h = _historial;
    if (h == null) return;
    var datos = DatosDelHistorial(
      historial: h,
      fiesta: _fiesta,
      fechaFiesta: widget.evento.fechaEvento,
      alcance: _alcance,
      emitido: DateTime.now(),
      conPlata: _conPlata,
      familias: _familias(),
    );
    final hojas = HistorialEntradasPdf.hojas(datos);
    if (hojas > kHojasParaPreguntar) {
      final elegidas = await elegirHojasParaImprimir(
        context,
        hojas: hojas,
        ventas: h.ventas.length,
        impresas: {
          for (final t in _tandasImpresas.entries)
            if (HistorialEntradasPdf.firmaDeLasHojas(
                  datos,
                  t.key,
                  (t.key + kHojasPorTanda - 1).clamp(1, hojas),
                ) ==
                t.value)
              t.key,
        },
      );
      if (elegidas == null || !mounted) return;
      if (elegidas.desde != 1 || elegidas.hasta != hojas) {
        datos = datos.soloLasHojas(elegidas.desde, elegidas.hasta);
      }
      if (elegidas.tanda) {
        _tandasImpresas[elegidas.desde] =
            HistorialEntradasPdf.firmaDeLasHojas(datos, elegidas.desde, elegidas.hasta);
      }
    }
    if (!mounted) return;
    try {
      await ref.read(abrirHistorialDeEntradasProvider)(datos, context: context);
    } catch (_) {
      _decir('No se pudo armar el historial. Probá de nuevo.');
    }
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final h = _historial;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ventas de entradas'),
            Text(
              '$_fiesta · $_alcance',
              key: const Key('ventas_alcance'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          // En un celular, el ícono: con el texto, el título se cortaba.
          if (CortesPantalla.esCelular(MediaQuery.sizeOf(context).width))
            IconButton(
              key: const Key('ventas_imprimir'),
              tooltip: 'Imprimir el historial',
              icon: const Icon(Icons.print_outlined),
              onPressed: h == null ? null : _imprimirHistorial,
            )
          else
            TextButton(
              key: const Key('ventas_imprimir'),
              onPressed: h == null ? null : _imprimirHistorial,
              child: const Text('IMPRIMIR HISTORIAL'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Center(child: Text(_errorCarga!))
              : _cuerpo(h!, esJefe),
    );
  }

  Widget _cuerpo(HistorialDeEntradas h, bool esJefe) {
    final visibles = h.con(_filtro);
    final t = h.totales;
    final gris = Colors.grey.shade700;
    final naranja = Colors.orange.shade800;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final (i, r) in h.repetidos.indexed)
              Container(
                key: Key('ventas_repetido_$i'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: naranja.withValues(alpha: 0.08),
                  border: Border.all(color: naranja.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: naranja),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.texto,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: naranja,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<FiltroDeVentas>(
                  key: const Key('ventas_filtro'),
                  showSelectedIcon: false,
                  segments: [
                    for (final f in FiltroDeVentas.values)
                      ButtonSegment(value: f, label: Text(f.rotulo)),
                  ],
                  selected: {_filtro},
                  onSelectionChanged: (s) => setState(() => _filtro = s.first),
                ),
                if (!esJefe)
                  Text(
                    '"Pago verificado" y ANULAR: $kSoloEnModoJefe',
                    key: const Key('ventas_motivo'),
                    style: TextStyle(fontSize: 12.5, color: gris),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${t.ventas == 1 ? '1 venta' : '${t.ventas} ventas'} · '
              '${t.entradas == 1 ? '1 entrada' : '${t.entradas} entradas'}'
              '${_conPlata ? ' · ${pesos(t.total)}' : ''}'
              '${t.anuladas > 0 ? ' · ${t.anuladas == 1 ? '1 anulada' : '${t.anuladas} anuladas'}' : ''}'
              ' · pago verificado: ${h.verificadas} de ${h.verificadas + h.sinVerificar}',
              key: const Key('ventas_totales'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (visibles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    h.ventas.isEmpty
                        ? 'Todavía no hay ventas.'
                        : 'Ninguna venta con ese filtro.',
                    key: const Key('ventas_vacio'),
                  ),
                ),
              ),
            for (final v in visibles) _fila(v, esJefe),
          ],
        ),
      ),
    );
  }

  Widget _fila(VentaDelHistorial v, bool esJefe) {
    final venta = v.venta;
    final gris = Colors.grey.shade700;
    final tachado = v.anulada
        ? TextStyle(decoration: TextDecoration.lineThrough, color: gris)
        : const TextStyle();
    final numeros = TramoTalonario.deTexto(venta.numeros);
    final puedeTocar = esJefe && !v.anulada && !_ocupado;
    return Card(
      key: Key('venta_${venta.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ComprobanteEntradasPdf.numero(venta)} · '
                    '${venta.compradorNombre}',
                    style: tachado.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    [
                      ComprobanteEntradasPdf.cuando(venta.createdAt),
                      venta.cantidad == 1 ? '1 entrada' : '${venta.cantidad} entradas',
                      pesos(venta.cobrado),
                      ComprobanteEntradasPdf.comoPago(venta),
                      if (v.vendio.isNotEmpty) 'vendió ${v.vendio}',
                      // El "$" no se separa de su número al cortar el renglón.
                    ].join(' · ').replaceAll(r'$ ', '\$ '),
                    style: tachado.copyWith(fontSize: 12.5, color: gris),
                  ),
                  if (numeros.isNotEmpty)
                    Text(
                      'Talonario ${TramoTalonario.legible(numeros)}',
                      style: TextStyle(fontSize: 12.5, color: gris),
                    ),
                  if (v.anulada)
                    Text(
                      [
                        'Anulada'
                            '${(v.anulacion!.hechoPor ?? '').isEmpty ? '' : ' por ${v.anulacion!.hechoPor}'}'
                            ' el ${ComprobanteEntradasPdf.cuando(v.anulacion!.createdAt)}',
                        v.anulacion!.motivo,
                        v.anulacion!.devueltas
                            ? 'devolvieron las entradas y pulseras'
                            : 'NO devolvieron las entradas: esos números quedan anulados',
                      ].join(' · '),
                      key: Key('anulada_${venta.id}'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                ],
              ),
            ),
            // Un Wrap y no un Row: en un celular, con letra grande, los botones
            // bajan de renglón en vez de salirse de la tarjeta.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!v.anulada)
                  Tooltip(
                    message: esJefe
                        ? (v.verificada
                            ? 'Verificado por ${v.verificacion?.hechoPor ?? ''}'
                            : 'Tildar cuando la plata entró')
                        : kSoloEnModoJefe,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          key: Key('verificar_${venta.id}'),
                          value: v.verificada,
                          onChanged: puedeTocar
                              ? (x) => _verificar(v, x ?? false)
                              : null,
                        ),
                        Text(
                          'Pago verificado',
                          style: TextStyle(fontSize: 12.5, color: gris),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 6),
                TextButton(
                  key: Key('reimprimir_${venta.id}'),
                  onPressed: () => _reimprimir(v),
                  child: const Text('REIMPRIMIR'),
                ),
                if (!v.anulada)
                  Tooltip(
                    message: esJefe ? 'Anular, con motivo' : kSoloEnModoJefe,
                    child: TextButton(
                      key: Key('anular_${venta.id}'),
                      onPressed: puedeTocar ? () => _anular(v) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      child: const Text('ANULAR'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Anular una venta: el motivo, obligatorio, y si devolvieron las entradas y
/// las pulseras (también hay que contestarlo). No guarda: devuelve la
/// respuesta, y guarda quien lo abrió, con su llave.
class _AnularVentaDialog extends StatefulWidget {
  final VentaEntradas venta;

  const _AnularVentaDialog({required this.venta});

  @override
  State<_AnularVentaDialog> createState() => _AnularVentaDialogState();
}

class _AnularVentaDialogState extends State<_AnularVentaDialog> {
  final _motivo = TextEditingController();
  bool? _devueltas;
  String? _problema;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final motivo = _motivo.text.trim();
    if (motivo.isEmpty) {
      setState(() => _problema = 'Escribí por qué se anula.');
      return;
    }
    final devueltas = _devueltas;
    if (devueltas == null) {
      setState(
        () => _problema = 'Decí si devolvieron las entradas y las pulseras.',
      );
      return;
    }
    Navigator.pop(context, (motivo: motivo, devueltas: devueltas));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final numeros = TramoTalonario.deTexto(v.numeros);
    final gris = Theme.of(context).hintColor;
    return AlertDialog(
      title: Text('Anular la venta ${ComprobanteEntradasPdf.numero(v)}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${v.compradorNombre} · '
                '${v.cantidad == 1 ? '1 entrada' : '${v.cantidad} entradas'} · '
                '${pesos(v.cobrado)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'La venta no se borra: queda en la lista, tachada, con el motivo. '
                'Se supone que la plata se devolvió.',
                style: TextStyle(fontSize: 12.5, color: gris),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('anular_motivo'),
                controller: _motivo,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Por qué se anula'),
                onChanged: (_) => setState(() => _problema = null),
              ),
              const SizedBox(height: 14),
              Text(
                numeros.isEmpty
                    ? '¿Devolvieron las entradas y las pulseras?'
                    : '¿Devolvieron las entradas y las pulseras? '
                        '(${TramoTalonario.legible(numeros)})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('anular_devolvieron_si'),
                    label: const Text('Sí, las devolvieron'),
                    selected: _devueltas == true,
                    onSelected: (_) => setState(() {
                      _devueltas = true;
                      _problema = null;
                    }),
                  ),
                  ChoiceChip(
                    key: const Key('anular_devolvieron_no'),
                    label: const Text('No las devolvieron'),
                    selected: _devueltas == false,
                    onSelected: (_) => setState(() {
                      _devueltas = false;
                      _problema = null;
                    }),
                  ),
                ],
              ),
              if (_devueltas == false)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    numeros.isEmpty
                        ? 'Esas entradas quedan anuladas.'
                        : 'Esos números quedan anulados para siempre: no se '
                            'vuelven a vender ni a entregar.',
                    style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800),
                  ),
                ),
              if (_problema != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _problema!,
                    key: const Key('anular_problema'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('anular_volver'),
          onPressed: () => Navigator.pop(context),
          child: const Text('VOLVER'),
        ),
        FilledButton(
          key: const Key('anular_confirmar'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: _confirmar,
          child: const Text('ANULAR LA VENTA'),
        ),
      ],
    );
  }
}
