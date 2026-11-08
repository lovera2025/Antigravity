import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cuentas/cierre_de_barra.dart';
import '../cuentas/pesos.dart';
import '../datos/barra_repositorio.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/papel_en_pantalla.dart';
import '../impresion/ticket_esc_pos.dart';
import '../providers/barra_providers.dart';
import 'pesos_enteros_formatter.dart';
import 'vales_de_la_venta_screen.dart' show quienEnLaBarra;
import 'ventas_de_la_caja_screen.dart' show pedirMotivo;

/// Cerrar la caja de barra de la cajera, al terminar la noche (etapa 6, decidido el 7-nov):
///
/// 1. **Contar, a ciegas.** Escribe el efectivo del cajón, con el cambio. La pantalla no
///    muestra ninguna plata antes: ni lo vendido ni lo esperado. Confirma viendo el número
///    grande, y **la caja se cierra en ese momento**: lo contado ya no se cambia.
/// 2. **El cierre.** Recién ahí ve cuánto tenía que haber y la diferencia, y el cierre
///    entero como el papel: lo vendido por producto, las sillas, lo anulado, los totales y
///    el historial de sus ventas. Puede imprimirlo (por la térmica sale sin el historial),
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

  @override
  void initState() {
    super.initState();
    // Una caja que ya llegó cerrada (la cerró otra pantalla) va directo al cierre.
    if (!widget.caja.abierta) unawaited(_mostrarCerrada(widget.caja));
  }

  @override
  void dispose() {
    _contado.dispose();
    _nota.dispose();
    super.dispose();
  }

  int? get _contadoEscrito => PesosEnterosFormatter.leer(_contado.text);

  CierreDeBarra get _cuentas => CierreDeBarra.de(_cerrada ?? widget.caja, _ventas, _anulaciones);

  void _decir(String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (texto: texto, error: error));
  }

  Future<void> _leerVentas(CajaBarra caja) async {
    final barra = ref.read(barraDeLaCajaProvider);
    _ventas = await barra.ventasDeLaCaja(caja.id);
    _anulaciones = await barra.anulacionesDeLaCaja(caja.id);
  }

  Future<void> _mostrarCerrada(CajaBarra caja) async {
    await _leerVentas(caja);
    if (mounted) setState(() => _cerrada = caja);
  }

  // ── 1. Contar y cerrar ────────────────────────────────────────────────────

  Future<void> _cerrar() async {
    final contado = _contadoEscrito;
    if (contado == null || _ocupado) return;
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
            const Text('La caja se cierra con ese número. Después no se cambia: si algo no '
                'cierra, lo explicás en la nota.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VOLVER A CONTAR')),
          FilledButton(
            key: const Key('cierre_confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, CERRAR'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() => _ocupado = true);
    final barra = ref.read(barraDeLaCajaProvider);
    final CajaBarra cerrada;
    try {
      // La caja como está guardada: el cambio pudo ponerse después de abrir.
      final enLaBase = widget.caja.operadorId == null
          ? null
          : await barra.cajaAbierta(eventoId: widget.caja.eventoId, operadorId: widget.caja.operadorId!);
      final caja = enLaBase ?? widget.caja;
      await _leerVentas(caja);
      final diferencia = CierreDeBarra.de(caja, _ventas, _anulaciones).diferenciaCon(contado.toDouble());
      cerrada = await barra.cerrarCaja(
        caja,
        efectivoContado: contado.toDouble(),
        diferencia: diferencia,
        nota: _nota.text,
        quien: quienEnLaBarra(ref, caja),
      );
    } catch (_) {
      if (mounted) setState(() => _ocupado = false);
      _decir('No se pudo cerrar la caja. Probá de nuevo.', error: true);
      return;
    }
    unawaited(ref.read(subirDeLaBarraProvider)('barra_cajas', cerrada.id));
    if (!mounted) return;
    setState(() {
      _cerrada = cerrada;
      _ocupado = false;
    });
    await _imprimir(alCerrar: true);
  }

  // ── 2. El cierre ──────────────────────────────────────────────────────────

  /// El papel de la térmica: sin el historial, para ahorrar papel.
  Future<void> _imprimir({bool alCerrar = false}) async {
    final caja = _cerrada;
    if (caja == null || _ocupado) return;
    setState(() => _ocupado = true);
    bool salio;
    try {
      salio = await ref.read(papelDeLaBarraProvider).imprimir(
            ModeloTicket.deCierre(caja, _cuentas, fiesta: widget.fiesta),
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
      final anotada = await ref
          .read(barraDeLaCajaProvider)
          .anotarCierre(caja, nota: nota, quien: quienEnLaBarra(ref, caja));
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
    return PopScope(
      // Cerrada la caja, volver es lo mismo que LISTO: VENDER también se va.
      canPop: cerrada == null,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho && cerrada != null) _listo();
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
        body: cerrada == null ? _contar() : _elCierre(cerrada),
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
              label: Text(caja.notaCierre == null ? 'AGREGAR UNA NOTA' : 'CAMBIAR LA NOTA'),
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
