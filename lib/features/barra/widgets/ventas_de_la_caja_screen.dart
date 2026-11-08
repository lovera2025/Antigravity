import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cuentas/pesos.dart';
import '../cuentas/reimpresion_de_barra.dart';
import '../cuentas/silla_de_la_puerta.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../providers/barra_providers.dart';
import '../services/papel_de_la_barra.dart';
import 'vales_de_la_venta_screen.dart';

/// VENTAS: las ventas de la caja de la cajera, la última arriba. Con cada una:
/// - **REIMPRIMIR** sus vales, con freno (`VentaDeLaCaja`): solo la última, una vez, con
///   motivo; cada copia sale con COPIA arriba y abajo y "Se entrega solo con el jefe".
/// - **IMPRIMIR LO QUE FALTA**, si quedaron bebidas sin vale (sin impresora, o se salió
///   antes): los vales originales que nunca salieron.
/// - **TICKET** con precios, si el cliente lo pide (sin logo: se ahorra papel).
/// - **ANULAR**, con motivo: la venta deja de contar en la caja y en el stock. La venta
///   no se toca: se agrega su anulación.
///
/// Lo que no se puede se ve apagado, con el motivo. Solo ventas de esta caja.
class VentasDeLaCajaScreen extends ConsumerStatefulWidget {
  final CajaBarra caja;
  final String fiesta;

  const VentasDeLaCajaScreen({super.key, required this.caja, required this.fiesta});

  @override
  ConsumerState<VentasDeLaCajaScreen> createState() => _VentasDeLaCajaScreenState();
}

class _VentasDeLaCajaScreenState extends ConsumerState<VentasDeLaCajaScreen> {
  List<VentaDeLaCaja> _ventas = const [];
  bool _cargando = true;
  bool _ocupado = false;

  /// Lo último que pasó, dicho en palabras, y de qué venta.
  ({String ventaId, String texto, bool error})? _aviso;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
  }

  Future<void> _cargar() async {
    final barra = ref.read(barraDeLaCajaProvider);
    final ventas = await barra.ventasDeLaCaja(widget.caja.id);
    final anulaciones = await barra.anulacionesDeLaCaja(widget.caja.id);
    final vales = await barra.valesDeLaCaja(widget.caja.id);
    if (!mounted) return;
    setState(() {
      _ventas = VentaDeLaCaja.armar(ventas: ventas, anulaciones: anulaciones, vales: vales);
      _cargando = false;
    });
  }

  void _decir(VentaBarra venta, String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (ventaId: venta.id, texto: texto, error: error));
  }

  Future<void> _conFreno(Future<void> Function() hacer) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await hacer();
    } finally {
      if (mounted) setState(() => _ocupado = false);
      await _cargar();
    }
  }

  // ── Reimprimir ────────────────────────────────────────────────────────────

  Future<void> _reimprimir(VentaDeLaCaja x) => _conFreno(() async {
        final cuantos = x.sinCopia.length;
        final motivo = await pedirMotivo(
          context,
          titulo: 'Reimprimir ${cuantos == 1 ? 'el vale' : 'los $cuantos vales'} de la N° ${_numero(x.venta)}',
          explicacion: 'Sale con COPIA arriba y abajo, con tu nombre, la hora y el motivo. '
              'El barman la entrega solo con el jefe. Se reimprime una sola vez.',
          ayuda: 'Por qué: se le mojó, se cortó el papel…',
          boton: 'REIMPRIMIR',
          claveBoton: 'motivo_reimprimir',
        );
        if (motivo == null || !mounted) return;
        final quien = quienEnLaBarra(ref, widget.caja);
        final copia = x.copia(motivo: motivo, hechoPor: quien, ahora: DateTime.now());
        final papel = ref.read(papelDeLaBarraProvider);
        var salieron = 0;
        for (final c in copia) {
          bool salio;
          try {
            salio = await papel.imprimir(ModeloTicket.deVale(
              c.vale,
              venta: x.venta,
              caja: widget.caja,
              fiesta: widget.fiesta,
              copia: c.copia,
            ));
          } catch (_) {
            salio = false;
          }
          if (!salio) break;
          salieron++;
          try {
            await anotarValeQueSalio(ref, venta: x.venta, caja: widget.caja, vale: c.vale, copia: c.copia);
          } catch (e) {
            debugPrint('⚠️ Barra: la copia salió pero no se pudo anotar: $e');
          }
        }
        if (salieron == copia.length) {
          _decir(x.venta, salieron == 1 ? 'Salió la copia.' : 'Salieron las $salieron copias.');
        } else {
          _decir(
            x.venta,
            '${salieron == 0 ? 'No salió la copia' : 'Salieron $salieron de ${copia.length}'}. '
            '${papel.sinPapel ? 'La impresora no tiene papel: cambiá el rollo y' : '¿La impresora está prendida y cerca?'}'
            '${papel.sinPapel ? ' tocá' : ' Tocá'} REIMPRIMIR para terminar.',
            error: true,
          );
        }
      });

  // ── Imprimir lo que falta ─────────────────────────────────────────────────

  Future<void> _imprimirLoQueFalta(VentaDeLaCaja x) => _conFreno(() async {
        final tema = Theme.of(context);
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Theme(
            data: tema,
            child: ValesDeLaVentaScreen(
              venta: x.venta,
              caja: widget.caja,
              fiesta: widget.fiesta,
              yaSalieron: x.originales,
              recienCobrada: false,
            ),
          ),
        ));
      });

  // ── El ticket con precios ─────────────────────────────────────────────────

  Future<void> _ticket(VentaDeLaCaja x) => _conFreno(() async {
        final salio = await imprimirTicketConPrecios(
          ref,
          venta: x.venta,
          caja: widget.caja,
          fiesta: widget.fiesta,
        );
        _decir(
          x.venta,
          salio
              ? 'Salió el ticket con precios.'
              : siNoSalio(ref.read(papelDeLaBarraProvider),
                  'No salió el ticket. ¿La impresora está prendida y cerca?'),
          error: !salio,
        );
      });

  // ── Anular ────────────────────────────────────────────────────────────────

  Future<void> _anular(VentaDeLaCaja x) => _conFreno(() async {
        final conSilla = x.venta.renglones.any((r) => esSillaDeLaPuerta(r.nombre));
        final motivo = await pedirMotivo(
          context,
          titulo: 'Anular la N° ${_numero(x.venta)} · ${pesos(x.venta.cobrado)}',
          explicacion: 'Deja de contar en la caja y en el stock. No se puede deshacer, y queda '
              'anotado con tu nombre y el motivo.'
              '${conSilla ? ' La silla de esta venta queda en rojo en la puerta.' : ''}',
          ayuda: 'Por qué: se cobró dos veces, se equivocó de bebida…',
          boton: 'ANULAR',
          claveBoton: 'motivo_anular',
          peligro: true,
        );
        if (motivo == null || !mounted) return;
        final AnulacionBarra anulacion;
        try {
          anulacion = await ref
              .read(barraDeLaCajaProvider)
              .anular(x.venta, motivo: motivo, quien: quienEnLaBarra(ref, widget.caja));
        } catch (_) {
          _decir(x.venta, 'No se pudo anular. Probá de nuevo.', error: true);
          return;
        }
        unawaited(ref.read(subirDeLaBarraProvider)('barra_anulaciones', anulacion.id));
        _decir(x.venta, 'Venta anulada.');
      });

  static String _numero(VentaBarra v) => v.numero.toString().padLeft(4, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ventas · Caja ${widget.caja.numeroCaja}', key: const Key('ventas_titulo')),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _ventas.isEmpty
              ? const Center(
                  child: Text('Todavía no hay ventas en esta caja.', key: Key('ventas_vacio')),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _ventas.length,
                      itemBuilder: (_, i) => _tarjeta(_ventas[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _tarjeta(VentaDeLaCaja x) {
    final tema = Theme.of(context);
    final v = x.venta;
    final id = v.id;
    final hora = _hora(v.createdAt);
    final medio = switch (v.medio) {
      MedioBarra.efectivo => 'Efectivo',
      MedioBarra.transferencia => 'Transferencia',
      MedioBarra.mixto => 'Mixto',
      MedioBarra.otro => 'Otro',
    };
    final bebidas = [for (final r in v.renglones) '${r.cantidad} ${r.nombre.toLowerCase()}'].join(', ');
    final tachado = x.anulada ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final aviso = _aviso?.ventaId == id ? _aviso : null;
    final motivoReimprimir = x.porQueNoSeReimprime;

    return Card(
      key: Key('venta_$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                Text(
                  'N° ${_numero(v)}${hora == null ? '' : ' · $hora'}',
                  style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text('${pesos(v.cobrado)} · $medio', style: tachado),
              ],
            ),
            const SizedBox(height: 4),
            Text(bebidas, style: tachado),
            if (x.anulada)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ANULADA · ${x.anulacion!.motivo}',
                  key: Key('anulada_$id'),
                  style: TextStyle(color: tema.colorScheme.error, fontWeight: FontWeight.bold),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_estadoDeLosVales(x), key: Key('vales_$id'), style: tema.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (x.faltanVales)
                  FilledButton.icon(
                    key: Key('faltan_$id'),
                    onPressed: _ocupado ? null : () => _imprimirLoQueFalta(x),
                    icon: const Icon(Icons.print),
                    label: const Text('IMPRIMIR LO QUE FALTA'),
                  ),
                if (!x.anulada)
                  Tooltip(
                    message: motivoReimprimir ?? 'Una copia de cada vale, con COPIA',
                    child: OutlinedButton.icon(
                      key: Key('reimprimir_$id'),
                      onPressed: _ocupado || motivoReimprimir != null ? null : () => _reimprimir(x),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('REIMPRIMIR'),
                    ),
                  ),
                if (x.porQueNoHayTicket == null)
                  OutlinedButton.icon(
                    key: Key('ticket_$id'),
                    onPressed: _ocupado ? null : () => _ticket(x),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('TICKET'),
                  ),
                if (x.porQueNoSeAnula == null)
                  TextButton.icon(
                    key: Key('anular_$id'),
                    style: TextButton.styleFrom(foregroundColor: tema.colorScheme.error),
                    onPressed: _ocupado ? null : () => _anular(x),
                    icon: const Icon(Icons.block),
                    label: const Text('ANULAR'),
                  ),
              ],
            ),
            // Lo que no se puede, apagado y con el motivo: si no, la cajera no sabe por qué.
            if (!x.anulada && motivoReimprimir != null && x.originales.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  motivoReimprimir,
                  key: Key('por_que_no_reimprime_$id'),
                  style: tema.textTheme.bodySmall,
                ),
              ),
            if (aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  aviso.texto,
                  key: Key('aviso_$id'),
                  style: TextStyle(
                    color: aviso.error ? tema.colorScheme.error : Colors.green.shade400,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Qué salió de esta venta, en palabras.
  static String _estadoDeLosVales(VentaDeLaCaja x) {
    final originales = x.originales.length;
    final copias = x.copias.length;
    final partes = [
      if (originales == 0)
        'No salió ningún vale'
      else
        originales == 1 ? 'Salió 1 vale' : 'Salieron $originales vales',
      if (x.unidadesSinVale > 0 && originales > 0) 'faltan ${x.unidadesSinVale} sin vale',
      if (copias > 0) copias == 1 ? '1 copia' : '$copias copias',
    ];
    return partes.join(' · ');
  }

  /// La hora de la venta en la hora de la PC: "23:41".
  static String? _hora(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

/// Pide un motivo, obligatorio. Null si se canceló.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  required String explicacion,
  required String ayuda,
  required String boton,
  required String claveBoton,
  bool peligro = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _MotivoDialog(
        titulo: titulo,
        explicacion: explicacion,
        ayuda: ayuda,
        boton: boton,
        claveBoton: claveBoton,
        peligro: peligro,
      ),
    );

class _MotivoDialog extends StatefulWidget {
  final String titulo;
  final String explicacion;
  final String ayuda;
  final String boton;
  final String claveBoton;
  final bool peligro;

  const _MotivoDialog({
    required this.titulo,
    required this.explicacion,
    required this.ayuda,
    required this.boton,
    required this.claveBoton,
    required this.peligro,
  });

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hayMotivo => _ctrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.explicacion),
            const SizedBox(height: 12),
            TextField(
              key: const Key('motivo_texto'),
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Motivo', helperText: widget.ayuda),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(
          key: Key(widget.claveBoton),
          style: widget.peligro
              ? FilledButton.styleFrom(backgroundColor: colores.error, foregroundColor: colores.onError)
              : null,
          onPressed: _hayMotivo ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: Text(widget.boton),
        ),
      ],
    );
  }
}
