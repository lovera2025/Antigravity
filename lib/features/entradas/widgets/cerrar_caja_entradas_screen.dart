import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../barra/cuentas/cierre_de_barra.dart' show diferenciaEnPalabras;
import '../../barra/cuentas/pesos.dart';
import '../../barra/widgets/pesos_enteros_formatter.dart';
import '../../barra/widgets/ventas_de_la_caja_screen.dart' show pedirMotivo;
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/quien_opera.dart';
import '../cuentas/cierre_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import '../pdf/cierre_caja_entradas_pdf.dart';
import '../pdf/papeles_de_entradas.dart';
import '../providers/entradas_providers.dart';
import '../services/nombre_de_la_fiesta.dart';
import 'abrir_caja_entradas_dialog.dart' show kSinPermisoParaVender;

/// Cerrar la caja de entradas (sección 9.1 del spec del 13-nov), desde CERRAR
/// CAJA en VENDER:
///
/// 1. **Contar, a ciegas.** Se escribe el efectivo de la caja, con el cambio.
///    La pantalla no muestra ninguna plata de la caja antes: ni lo vendido ni
///    lo que tenía que haber (`test/cerrar_caja_entradas_test.dart` lo vigila).
///    Se confirma viendo el número grande.
/// 2. **El cierre.** Recién cerrada se ve cuánto tenía que haber, lo contado y
///    la diferencia ("Justo", "Sobran $ 500", "Faltan $ 1.500"), y las cuentas
///    de la caja. Su papel (media A4) **no sale solo** (22-nov-2026): IMPRIMIR
///    EL CIERRE, o después Cierre de caja → ENTRADAS → PAPEL DEL CIERRE.
///
/// **Una caja cerrada no se vuelve a cerrar ni se corrige:** solo se le puede
/// agregar la nota. Sin el OK de una encargada: eso es de la barra.
///
/// Devuelve true si la caja quedó cerrada: VENDER se va y vuelve atrás.
class CerrarCajaEntradasScreen extends ConsumerStatefulWidget {
  final CajaEntradas caja;
  final Evento evento;

  const CerrarCajaEntradasScreen({
    super.key,
    required this.caja,
    required this.evento,
  });

  @override
  ConsumerState<CerrarCajaEntradasScreen> createState() =>
      _CerrarCajaEntradasScreenState();
}

class _CerrarCajaEntradasScreenState
    extends ConsumerState<CerrarCajaEntradasScreen> {
  final _contado = TextEditingController();
  final _nota = TextEditingController();

  /// La caja ya cerrada, como quedó guardada. Null: todavía se está contando.
  CajaEntradas? _cerrada;
  List<VentaEntradas> _ventas = const [];
  List<AnulacionEntradas> _anulaciones = const [];
  bool _ocupado = false;
  ({String texto, bool error})? _aviso;

  @override
  void initState() {
    super.initState();
    // Una caja que ya llegó cerrada va directo al cierre.
    if (!widget.caja.abierta) unawaited(_mostrarCerrada(widget.caja));
  }

  @override
  void dispose() {
    _contado.dispose();
    _nota.dispose();
    super.dispose();
  }

  String get _fiesta => nombreDeLaFiesta(widget.evento);

  int? get _contadoEscrito => PesosEnterosFormatter.leer(_contado.text);

  CierreDeEntradas get _cuentas =>
      CierreDeEntradas.de(_cerrada ?? widget.caja, _ventas, _anulaciones);

  void _decir(String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (texto: texto, error: error));
  }

  /// A nombre de quién, como en VENDER: el operador, o quien opera (el jefe).
  String get _quien {
    final operador = ref.read(appRoleProvider).operador;
    if (ref.read(esRolJefeProvider) || operador == null) return quienOpera(ref);
    return operador.nombre;
  }

  Future<void> _leerVentas(CajaEntradas caja) async {
    final entradas = ref.read(entradasDeLaCajaProvider);
    _ventas = await entradas.ventasDeLaCaja(caja.id);
    _anulaciones = await entradas.anulacionesDeLaCaja(caja.id);
  }

  Future<void> _mostrarCerrada(CajaEntradas caja) async {
    try {
      await _leerVentas(caja);
    } catch (_) {
      // Sin las ventas se ve lo contado y la diferencia, que están en la caja.
    }
    if (mounted) setState(() => _cerrada = caja);
  }

  // ── La llave ─────────────────────────────────────────────────────────────

  /// Sin el permiso de vender (o el modo jefe) no se cierra la caja, aunque
  /// alguien llegue hasta acá.
  bool _frenaSinPermiso() {
    if (ref.read(puedeVenderEntradasProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kSinPermisoParaVender)),
      );
    }
    return true;
  }

  // ── 1. Contar y cerrar ───────────────────────────────────────────────────

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
            const Text(
              'La caja se cierra con ese número. Después no se cambia: si algo no '
              'cierra, lo explicás en la nota.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('VOLVER A CONTAR'),
          ),
          FilledButton(
            key: const Key('cierre_confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, CERRAR'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    await _cerrarDeVerdad(contado.toDouble(), nota: _nota.text);
  }

  /// Cierra la caja en la base de este equipo, con lo contado. La diferencia
  /// se anota en ese momento: después no se vuelve a calcular.
  Future<void> _cerrarDeVerdad(double contado, {String? nota}) async {
    if (_frenaSinPermiso()) return;
    setState(() => _ocupado = true);
    final CajaEntradas cerrada;
    try {
      await _leerVentas(widget.caja);
      final diferencia = CierreDeEntradas.de(widget.caja, _ventas, _anulaciones)
          .diferenciaCon(contado);
      final laNota = (nota ?? '').trim();
      cerrada = await ref.read(entradasDeLaCajaProvider).cerrarCaja(
            widget.caja,
            efectivoContado: contado,
            diferencia: diferencia,
            nota: laNota.isEmpty ? null : laNota,
            quien: _quien,
          );
    } catch (_) {
      if (mounted) setState(() => _ocupado = false);
      _decir('No se pudo cerrar la caja. Probá de nuevo.', error: true);
      return;
    }
    avisarQueCambioLaVenta(ref, widget.evento.id);
    if (!mounted) return;
    // El papel no sale solo (pedido del usuario, 22-nov-2026): queda IMPRIMIR
    // EL CIERRE, y después, en Cierre de caja → ENTRADAS, PAPEL DEL CIERRE.
    setState(() {
      _cerrada = cerrada;
      _ocupado = false;
    });
    _decir('Caja cerrada.');
  }

  // ── 2. El cierre ─────────────────────────────────────────────────────────

  Future<void> _imprimir() async {
    final caja = _cerrada;
    if (caja == null || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(abrirCierreDeEntradasProvider)(
        DatosDelCierreDeEntradas(
          caja: caja,
          cuentas: _cuentas,
          fiesta: _fiesta,
          fechaFiesta: widget.evento.fechaEvento,
        ),
        context: context,
      );
    } catch (_) {
      // La caja ya quedó cerrada: lo único que falló es el papel.
      _decir('No se pudo abrir el papel del cierre. Probá de nuevo.', error: true);
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
      final anotada = await ref.read(entradasDeLaCajaProvider).anotarCierre(
            caja,
            nota: nota.trim().isEmpty ? null : nota.trim(),
            quien: _quien,
          );
      avisarQueCambioLaVenta(ref, widget.evento.id);
      if (mounted) setState(() => _cerrada = anotada);
      _decir('Nota guardada. Tocá IMPRIMIR EL CIERRE si la querés en papel.');
    } catch (_) {
      _decir('No se pudo guardar la nota. Probá de nuevo.', error: true);
    }
  }

  /// LISTO: se va el cierre, y VENDER también. No pregunta por el papel
  /// (22-nov-2026): si hace falta, se saca después en Cierre de caja →
  /// ENTRADAS → PAPEL DEL CIERRE.
  Future<void> _listo() async {
    if (_ocupado) return;
    Navigator.of(context).pop(true);
  }

  // ── Dibujo ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cerrada = _cerrada;
    return PopScope(
      // Cerrada la caja, volver es lo mismo que LISTO: VENDER también se va.
      // Mientras se cierra o sale el papel no se sale (revisión del 15-nov): la
      // caja se cerraría igual sin que se vea el resultado ni salga el papel.
      canPop: cerrada == null && !_ocupado,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho && cerrada != null && !_ocupado) _listo();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cerrada == null ? 'Cerrar la caja de entradas' : 'Caja de entradas cerrada',
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$_fiesta · ${widget.caja.operadorNombre ?? 'Jefe'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: [
            if (cerrada != null)
              TextButton(
                key: const Key('cierre_listo'),
                onPressed: _ocupado ? null : _listo,
                child: const Text('LISTO'),
              ),
          ],
        ),
        body: cerrada != null ? _elCierre(cerrada) : _contar(),
      ),
    );
  }

  /// Contar, **a ciegas**: acá no va ninguna plata de la caja
  /// (`test/cerrar_caja_entradas_test.dart` lee esta función).
  Widget _contar() {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Contá el efectivo que tenés en la caja, con el cambio, y escribilo.',
              style: tema.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Todavía no se muestra cuánto tenía que haber: lo vas a ver al cerrar.',
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
              decoration: const InputDecoration(
                labelText: 'Efectivo contado',
                prefixText: r'$ ',
              ),
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
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('cierre_volver'),
                  onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
                  child: const Text('VOLVER A VENDER'),
                ),
                FilledButton.icon(
                  key: const Key('cierre_cerrar'),
                  onPressed: _contadoEscrito == null || _ocupado ? null : _cerrar,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('CERRAR LA CAJA'),
                ),
              ],
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

  Widget _elCierre(CajaEntradas caja) {
    final tema = Theme.of(context);
    final c = _cuentas;
    final diferencia = caja.diferencia ?? 0;
    final centavosDif = centavos(diferencia);
    final color = centavosDif == 0
        ? Colors.green.shade700
        : centavosDif < 0
            ? tema.colorScheme.error
            : Colors.orange.shade800;
    final gris = Colors.grey.shade700;
    Widget fila(String a, String b, {Color? colorB, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(a)),
              const SizedBox(width: 12),
              Text(
                b,
                key: key,
                style: TextStyle(fontWeight: FontWeight.w700, color: colorB),
              ),
            ],
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              key: const Key('cierre_resultado'),
              color: color.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fila(
                      'Contaste',
                      caja.efectivoContado == null ? '—' : pesos(caja.efectivoContado!),
                      key: const Key('cierre_contaste'),
                    ),
                    fila(
                      'Tenía que haber',
                      // Lo que se anotó al cerrar: si después se anula algo, el
                      // cierre no cambia (va en "Anulado después del cierre").
                      pesos(CierreDeEntradas.esperadoAlCerrar(caja) ?? c.efectivoEsperado),
                      key: const Key('cierre_esperado'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      diferenciaEnPalabras(diferencia),
                      key: const Key('cierre_diferencia'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            fila('Cambio inicial', pesos(c.cambioInicial)),
            fila('Efectivo', pesos(c.efectivo), colorB: const Color(0xFF00896E)),
            fila('Transferencia (con los recargos)', pesos(c.transferencia),
                colorB: const Color(0xFF5A52D5)),
            fila('Ventas mixtas', '${c.mixtos}'),
            fila(
              'Entradas vendidas',
              '${c.entradas} (${c.sueltas} sueltas y ${c.deLugar} de lugares'
                  '${c.otras > 0 ? ', ${c.otras} otras' : ''})',
              key: const Key('cierre_vendidas'),
            ),
            fila('Descuentos a mano', pesos(c.descuentos)),
            fila('Anuladas (no cuentan)', '${c.anuladas}'),
            if (c.hayAnuladoDespues)
              fila(
                'Anulado después del cierre',
                pesos(c.anuladoDespues),
                colorB: tema.colorScheme.error,
              ),
            if ((caja.notaCierre ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Nota: ${caja.notaCierre!.trim()}',
                key: const Key('cierre_nota_guardada'),
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Una caja cerrada no se vuelve a cerrar ni se corrige: solo se le puede '
              'agregar la nota.',
              style: TextStyle(fontSize: 12.5, color: gris),
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
                  label: const Text('IMPRIMIR EL CIERRE'),
                ),
                OutlinedButton.icon(
                  key: const Key('cierre_anotar'),
                  onPressed: _ocupado ? null : _anotar,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    (caja.notaCierre ?? '').trim().isEmpty
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
                    color: _aviso!.error ? tema.colorScheme.error : Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
