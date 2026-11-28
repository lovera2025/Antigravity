import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/aviso_al_anotar.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/evento.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/dia_de_operacion.dart';
import '../cuentas/pesos.dart';
import '../cuentas/reimpresion_de_barra.dart';
import '../cuentas/silla_de_la_puerta.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/disenio_barra.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/papel_en_pantalla.dart';
import '../impresion/ticket_esc_pos.dart' show LineaTicket;
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';
import '../services/pantalla_despierta.dart';
import '../services/papel_de_la_barra.dart';
import '../widgets/anular_venta_dialog.dart';
import '../widgets/elegir_papel.dart';
import '../widgets/pesos_enteros_formatter.dart';
import '../widgets/ok_del_cierre.dart';
import '../widgets/vales_de_la_venta_screen.dart';
import '../central/central_barra_provider.dart';
import '../central/panel_central_barra.dart';
import '../widgets/ventas_de_la_caja_screen.dart' show pedirMotivo;
import 'barra_jefe_providers.dart';

/// CAJAS de una fiesta: arriba los totales, **una tarjeta por caja** (elegido el 7-nov:
/// se ve bien también en el iPhone), y al costado el stock de toda la fiesta, con lo
/// agotado y lo que está en aviso arriba. Tocar una caja muestra sus ventas: el jefe
/// **anula cualquiera** con motivo y **reimprime cualquiera** (sin el freno de la cajera),
/// y ve el cierre como el papel.
///
/// **La Encargada de barra ve lo mismo** (6.4.0, LAS CAJAS desde su inicio): la llave es
/// [mandaEnLaBarraProvider] (el jefe en modo jefe o la encargada). El catálogo y los
/// precios siguen siendo solo del jefe.
///
/// Se pone al día solo: cuando una caja sube sus ventas, el aviso entre equipos hace que
/// esto se vuelva a leer. Sin internet, cada tablet guarda lo suyo y lo sube al volver.
///
/// **Una noche por vez** (25-nov-2026, `cuentas/dia_de_operacion.dart`): viene en la de
/// esta noche (o la última con cajas), y los otros días van arriba para tocar. Los
/// totales, la diferencia, LO VENDIDO, el papel y el stock son de esa noche: las cajas de
/// prueba de otro día no se suman, como un cierre de caja en su fecha. Una tarjeta de
/// otra noche dice su fecha.
///
/// **No deja apagar la pantalla de la tablet** mientras está abierta, como VENDER: de
/// madrugada, si no, el pedido de cierre de una cajera no se ve ni suena.
class CajasDeLaFiestaVista extends ConsumerStatefulWidget {
  final Evento fiesta;

  const CajasDeLaFiestaVista({super.key, required this.fiesta});

  @override
  ConsumerState<CajasDeLaFiestaVista> createState() => _CajasDeLaFiestaVistaState();
}

/// Qué ventas de la caja se miran (11-nov-2026). "Transferencia" trae también las
/// mixtas: es la lista para comparar con Mercado Pago.
enum _FiltroDeVentas {
  todas('Todas'),
  efectivo('Efectivo'),
  transferencia('Transferencia'),
  mixto('Mixto'),
  anuladas('Anuladas');

  final String rotulo;
  const _FiltroDeVentas(this.rotulo);

  bool deja(VentaDeLaCaja x) {
    final v = x.venta;
    return switch (this) {
      _FiltroDeVentas.todas => true,
      _FiltroDeVentas.anuladas => x.anulada,
      _FiltroDeVentas.efectivo => !x.anulada && v.medio == MedioBarra.efectivo,
      _FiltroDeVentas.transferencia => !x.anulada && centavos(v.transferencia) > 0,
      _FiltroDeVentas.mixto => !x.anulada && v.medio == MedioBarra.mixto,
    };
  }
}

class _CajasDeLaFiestaVistaState extends ConsumerState<CajasDeLaFiestaVista> {
  String? _cajaElegida;
  bool _ocupado = false;

  /// La noche que se mira. Null: la de esta noche, o la última con cajas
  /// ([CajasPorDia.inicial]).
  DiaDeOperacion? _noche;

  /// En una caja: la lista de ventas, o LO VENDIDO (cada bebida, por categoría).
  bool _verLoVendido = false;
  _FiltroDeVentas _filtro = _FiltroDeVentas.todas;

  /// Lo último que pasó con una venta, en palabras.
  ({String ventaId, String texto, bool error})? _aviso;

  /// En la web: la relectura cada [kRelecturaDeCajasEnLaWeb] mientras CAJAS está abierta.
  Timer? _relectura;

  String get _titulo => EventoPresentacion.tituloPrincipal(widget.fiesta);

  @override
  void initState() {
    super.initState();
    // En la tablet de la encargada la pantalla no se apaga mientras mira las cajas.
    unawaited(PantallaDespierta.mantener(true));
    if (ref.read(enLaWebProvider)) {
      _relectura = Timer.periodic(kRelecturaDeCajasEnLaWeb, (_) => _releer());
    }
  }

  @override
  void dispose() {
    unawaited(PantallaDespierta.mantener(false));
    _relectura?.cancel();
    super.dispose();
  }

  void _releer() => ref.invalidate(cajasDelJefeProvider(widget.fiesta.id));

  /// Deslizar hacia abajo: se relee ya, y la ruedita se va cuando llegó.
  Future<void> _releerAhora() async {
    _releer();
    try {
      await ref.read(cajasDelJefeProvider(widget.fiesta.id).future);
    } catch (_) {}
  }

  /// La segunda llave: el jefe en modo jefe o la Encargada de barra.
  bool _frenaSinModoJefe() {
    if (ref.read(mandaEnLaBarraProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('$kSoloEnModoJefe: anular y reimprimir es del jefe o de la encargada de barra.')),
      );
    }
    return true;
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
      // Desde el iPhone la respuesta puede llegar con la pantalla ya cerrada (SALIR):
      // ahí no se toca `ref` (28-nov-2026, lo encontró la prueba de pantalla).
      if (mounted) {
        ref.invalidate(cajasDelJefeProvider(widget.fiesta.id));
        setState(() => _ocupado = false);
      }
    }
  }

  /// Lo último que pasó con la plata de la caja que se está mirando.
  ({String texto, bool error})? _avisoPlata;

  /// **SACAR EFECTIVO, DAR CAMBIO o Corregir** (maqueta aprobada el 27-nov): la encargada
  /// desde su sesión (también en su caja) o el jefe, siempre con motivo. Solo se agrega
  /// una fila; sale a la red del salón y la tablet de esa caja lo cuenta al cerrar.
  Future<void> _anotarPlata(CajaBarra caja, TipoMovimientoDeCaja tipo) => _conFreno(() async {
        final pedido = await showDialog<({double monto, String motivo})>(
          context: context,
          builder: (_) => _PedirMovimiento(caja: caja, tipo: tipo),
        );
        if (pedido == null || !mounted) return;
        if (_frenaSinModoJefe()) return;
        final MovimientoDeCaja hecho;
        final subir = ref.read(subirDeLaBarraProvider);
        try {
          hecho = await ref.read(barraDelJefeProvider).anotarMovimientoDeCaja(
                MovimientoDeCaja.nuevo(
                  eventoId: caja.eventoId,
                  cajaBarraId: caja.id,
                  tipo: tipo,
                  monto: pedido.monto,
                  motivo: pedido.motivo,
                  ahora: DateTime.now(),
                ),
                quien: quienEsElJefe(ref),
              );
        } on CajaYaCerrada {
          if (mounted) setState(() => _avisoPlata = (texto: 'La Caja ${caja.numeroCaja} ya cerró: no se anota.', error: true));
          return;
        } catch (e) {
          // Desde el iPhone, "probá de nuevo" podía anotarlo dos veces: se dice el aviso.
          if (mounted) {
            setState(() => _avisoPlata = (texto: textoDelError(e, 'No se pudo anotar. Probá de nuevo.'), error: true));
          }
          return;
        }
        unawaited(subir('barra_caja_movimientos', hecho.id));
        if (mounted) {
          setState(() => _avisoPlata = (
                texto: switch (tipo) {
                  TipoMovimientoDeCaja.retiro => 'Anotado: sacaste ${pesos(pedido.monto)} de la Caja ${caja.numeroCaja}.',
                  TipoMovimientoDeCaja.cambio => 'Anotado: le diste ${pesos(pedido.monto)} de cambio a la Caja ${caja.numeroCaja}.',
                  TipoMovimientoDeCaja.ajusteCambio => 'Anotada la corrección de ${masOMenos(pedido.monto)}.',
                },
                error: false,
              ));
        }
      });

  /// La plata de la caja: lo que tiene que haber, de dónde sale, lo que se hizo con la
  /// plata y los botones (con la caja abierta).
  Widget _plataDeLaCaja(ResumenDeCaja r, List<MovimientoDeCaja> movimientos) {
    final caja = r.caja;
    final cuentas = r.cuentas;
    final aviso = _avisoPlata;
    Widget renglon(String a, String b, {Key? key, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(a, style: const TextStyle(color: Color(0xFFC9C4BA)))),
              Text(b, key: key, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );
    final orden = [...movimientos]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DecoratedBox(
        key: Key('jefe_caja_plata_${caja.id}'),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1913),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4A3F1C)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('TIENE QUE HABER',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFFC9C4BA))),
                  ),
                  Text(
                    pesos(cuentas.efectivoEsperado),
                    key: const Key('jefe_caja_tiene_que_haber'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              renglon('Cambio con que abrió', pesos(cuentas.cambioInicial)),
              renglon('Efectivo vendido', pesos(cuentas.efectivo)),
              if (centavos(cuentas.cambioAgregado) != 0)
                renglon(cuentas.rotuloDelCambio, masOMenos(cuentas.cambioAgregado), color: const Color(0xFF59D38A)),
              if (centavos(cuentas.retirado) != 0)
                renglon(cuentas.rotuloDeLoSacado, masOMenos(-cuentas.retirado), color: const Color(0xFFFF8F82)),
              if (orden.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('LO QUE SE HIZO CON LA PLATA',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8, color: Color(0xFFA7A29A))),
                for (final m in orden)
                  Padding(
                    key: Key('jefe_caja_movimiento_${m.id}'),
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${ArTime.formatHora(DateTime.parse(m.createdAt))} · ${switch (m.tipo) {
                              TipoMovimientoDeCaja.retiro => 'Sacó efectivo',
                              TipoMovimientoDeCaja.cambio => 'Dio cambio',
                              TipoMovimientoDeCaja.ajusteCambio => 'Corrigió',
                              null => 'Otro',
                            }}${m.hechoPor == null ? '' : ' · ${m.hechoPor}'}\n${m.motivo}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(masOMenos(deCentavos(m.efectoEnCentavos)), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
              if (aviso != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    aviso.texto,
                    key: const Key('jefe_caja_plata_aviso'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: aviso.error ? const Color(0xFFFF8F82) : const Color(0xFF59D38A),
                    ),
                  ),
                ),
              if (caja.abierta) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('jefe_caja_sacar_efectivo'),
                      onPressed: _ocupado ? null : () => _anotarPlata(caja, TipoMovimientoDeCaja.retiro),
                      icon: const Icon(Icons.south_west),
                      label: const Text('SACAR EFECTIVO'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                    OutlinedButton.icon(
                      key: const Key('jefe_caja_dar_cambio'),
                      onPressed: _ocupado ? null : () => _anotarPlata(caja, TipoMovimientoDeCaja.cambio),
                      icon: const Icon(Icons.north_east),
                      label: const Text('DAR CAMBIO'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                    TextButton(
                      key: const Key('jefe_caja_corregir'),
                      onPressed: _ocupado ? null : () => _anotarPlata(caja, TipoMovimientoDeCaja.ajusteCambio),
                      child: const Text('Corregir (se anotó mal algo)'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Si lo que se hace acá le llega a la tablet al momento: desde la página del iPhone,
  /// o desde la notebook con la central prendida para esta fiesta.
  bool _seEnteraAlMomento() {
    if (ref.read(enLaPaginaDeLaBarraProvider)) return true;
    if (ref.read(enLaWebProvider)) return false;
    final central = ref.read(centralDeLaBarraProvider);
    return central.prendida && central.eventoId == widget.fiesta.id;
  }

  Future<void> _anular(VentaDeLaCaja x) => _conFreno(() async {
        final conSilla = x.venta.renglones.any((r) => esSillaDeLaPuerta(r.nombre));
        // "¿Volvió el vale?" (28-nov-2026): con el vale en la mano el stock vuelve; si ya
        // se entregó, la plata se anula igual y el stock no vuelve.
        final pedido = await pedirAnulacion(
          context,
          titulo: 'Anular la N° ${_numero(x.venta)} · ${pesos(x.venta.cobrado)}',
          explicacion: 'La venta no se borra: queda ANULADA con tu nombre y el motivo, y deja de '
              'contar en la caja. No se puede deshacer. '
              '${_seEnteraAlMomento() ? 'La tablet se entera al momento por el wifi.' : 'La tablet se entera con internet.'}'
              '${conSilla ? ' La silla de esta venta queda en rojo en la puerta.' : ''}',
          preguntaPorElVale: AnulacionBarra.preguntaPorElVale(x.venta),
        );
        if (pedido == null || !mounted) return;
        if (_frenaSinModoJefe()) return;
        final (:motivo, :valeVolvio) = pedido;
        final AnulacionBarra anulacion;
        final subir = ref.read(subirDeLaBarraProvider);
        try {
          anulacion = await ref
              .read(barraDelJefeProvider)
              .anular(x.venta, motivo: motivo, quien: quienEsElJefe(ref), valeVolvio: valeVolvio);
        } catch (e) {
          _decir(x.venta, textoDelError(e, 'No se pudo anular. Probá de nuevo.'), error: true);
          return;
        }
        unawaited(subir('barra_anulaciones', anulacion.id));
        _decir(
          x.venta,
          anulacion.valeVolvio
              ? 'Venta anulada. Ya no cuenta en la caja ni en el stock.'
              : 'Venta anulada. Ya no cuenta en la caja; el stock no vuelve (el vale ya se entregó).',
        );
      });

  Future<void> _reimprimir(VentaDeLaCaja x, CajaBarra caja) => _conFreno(() async {
        // Antes del motivo: que no lo escriba para nada.
        final falta = await faltaLaImpresora(ref);
        if (falta != null) {
          _decir(x.venta, falta, error: true);
          return;
        }
        if (!mounted) return;
        final cuantos = x.originales.length;
        final motivo = await pedirMotivo(
          context,
          titulo: 'Reimprimir ${cuantos == 1 ? 'el vale' : 'los $cuantos vales'} de la N° ${_numero(x.venta)}',
          explicacion: 'Sale por la impresora de este equipo, con COPIA arriba y abajo, tu nombre, '
              'la hora y el motivo.',
          ayuda: 'Por qué: se le mojó, se cortó el papel…',
          boton: 'REIMPRIMIR',
          claveBoton: 'motivo_reimprimir',
        );
        if (motivo == null || !mounted) return;
        if (_frenaSinModoJefe()) return;
        final quien = quienEsElJefe(ref);
        final copia = x.copiaDelJefe(motivo: motivo, hechoPor: quien, ahora: DateTime.now());
        final papel = ref.read(papelDeLaBarraProvider);
        var salieron = 0;
        for (final c in copia) {
          bool salio;
          try {
            salio = await papel.imprimir(ModeloTicket.deVale(
              c.vale,
              venta: x.venta,
              caja: caja,
              fiesta: _titulo,
              copia: c.copia,
            ));
          } catch (_) {
            salio = false;
          }
          if (!salio) break;
          salieron++;
          try {
            await anotarValeQueSalio(ref, venta: x.venta, caja: caja, vale: c.vale, copia: c.copia, quien: quien);
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
            '${siNoSalio(papel, '¿La impresora está prendida y cerca de esta PC?')}',
            error: true,
          );
        }
      });

  Future<void> _verCierre(ResumenDeCaja r, CajasDeLaFiesta datos) async {
    final caja = r.caja;
    final ventas = [for (final v in datos.ventas) if (v.cajaBarraId == caja.id) v];
    final anulaciones = [for (final a in datos.anulaciones) if (a.cajaBarraId == caja.id) a];
    final conHistorial = ModeloTicket.deCierre(
      caja,
      r.cuentas,
      fiesta: _titulo,
      historial: ventas,
      anulaciones: anulaciones,
    );
    // Por la impresora: el corto (por categoría, de largo fijo) o con cada bebida.
    final corto = ModeloTicket.deCierre(caja, r.cuentas, fiesta: _titulo, corto: true);
    final sinHistorial = ModeloTicket.deCierre(caja, r.cuentas, fiesta: _titulo);
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Cierre · Caja ${caja.numeroCaja}${caja.operadorNombre == null ? '' : ' · ${caja.operadorNombre}'}'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(child: PapelEnPantalla(conHistorial, key: const Key('jefe_cierre_papel'))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('CERRAR')),
          // En la web no hay impresora: queda el PDF.
          if (!ref.read(enLaWebProvider))
          OutlinedButton(
            key: const Key('jefe_cierre_imprimir'),
            onPressed: () async {
              final elegido = await elegirPapelDeLaBarra(dialogo);
              if (elegido == null || !dialogo.mounted) return;
              final falta = await faltaLaImpresora(ref);
              bool salio = false;
              if (falta == null) {
                try {
                  salio = await ref
                      .read(papelDeLaBarraProvider)
                      .imprimir(elegido == PapelDeLaBarraElegido.corto ? corto : sinHistorial);
                } catch (_) {
                  salio = false;
                }
              }
              if (!dialogo.mounted) return;
              ScaffoldMessenger.of(dialogo).showSnackBar(SnackBar(
                content: Text(falta ??
                    (salio
                        ? (elegido == PapelDeLaBarraElegido.corto
                            ? 'Salió el cierre corto. El detalle de cada bebida está en LO VENDIDO.'
                            : 'Salió el cierre con cada bebida (sin el historial, para ahorrar papel).')
                        : siNoSalio(ref.read(papelDeLaBarraProvider),
                            'No salió. ¿La impresora está prendida y cerca de esta PC?'))),
              ));
            },
            child: const Text('IMPRIMIR'),
          ),
          FilledButton(
            key: const Key('jefe_cierre_pdf'),
            onPressed: () => ref.read(guardarPdfDeLaBarraProvider)(
              conHistorial,
              titulo: 'Cierre de caja',
              nombre: 'Cierre barra - Caja ${caja.numeroCaja} - $_titulo',
              context: dialogo,
            ),
            child: const Text('PDF 58 mm'),
          ),
        ],
      ),
    );
  }

  /// LO VENDIDO DE LA FIESTA: todas las cajas **de la noche que se mira** juntas, cada
  /// bebida por categoría. En la pantalla y en el PDF va entero; por la impresora, se
  /// elige corto o con cada bebida.
  Future<void> _verLoVendidoDeLaFiesta(NocheDeLaBarra noche) async {
    final cuentas = noche.resumen.deLaFiesta;
    if (cuentas == null) return;
    final ahora = DateTime.now();
    final cajas = noche.resumen.cajas.length;
    List<LineaTicket> papel({required bool corto}) => ModeloTicket.deLoVendido(
          cuentas,
          fiesta: _titulo,
          cajas: cajas,
          ahora: ahora,
          corto: corto,
          dia: noche.dia,
        );
    final entero = papel(corto: false);
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Lo vendido de la fiesta'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: PapelEnPantalla(entero, key: const Key('jefe_vendido_fiesta_papel')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('CERRAR')),
          if (!ref.read(enLaWebProvider))
            OutlinedButton(
              key: const Key('jefe_vendido_fiesta_imprimir'),
              onPressed: () async {
                final elegido = await elegirPapelDeLaBarra(dialogo);
                if (elegido == null || !dialogo.mounted) return;
                final falta = await faltaLaImpresora(ref);
                bool salio = false;
                if (falta == null) {
                  try {
                    salio = await ref.read(papelDeLaBarraProvider).imprimir(
                          elegido == PapelDeLaBarraElegido.corto ? papel(corto: true) : entero,
                        );
                  } catch (_) {
                    salio = false;
                  }
                }
                if (!dialogo.mounted) return;
                ScaffoldMessenger.of(dialogo).showSnackBar(SnackBar(
                  content: Text(falta ??
                      (salio
                          ? 'Salió lo vendido de la fiesta.'
                          : siNoSalio(ref.read(papelDeLaBarraProvider),
                              'No salió. ¿La impresora está prendida y cerca de esta PC?'))),
                ));
              },
              child: const Text('IMPRIMIR'),
            ),
          FilledButton(
            key: const Key('jefe_vendido_fiesta_pdf'),
            onPressed: () => ref.read(guardarPdfDeLaBarraProvider)(
              entero,
              titulo: 'Lo vendido de la fiesta',
              nombre: 'Lo vendido barra - $_titulo - ${noche.dia.diaYMes.replaceAll('/', '-')}',
              context: dialogo,
            ),
            child: const Text('PDF 58 mm'),
          ),
        ],
      ),
    );
  }

  /// Cada bebida de una caja, con sus unidades y su plata, junta por categoría: el
  /// detalle que el papel corto no trae.
  Widget _loVendido(CierreDeBarra cuentas) {
    if (cuentas.porProducto.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Todavía no hay ventas en esta caja.', key: Key('jefe_vendido_vacio')),
      );
    }
    Widget renglon(String a, String b, {bool fuerte = false, Key? key}) => Padding(
          key: key,
          padding: EdgeInsets.fromLTRB(fuerte ? 16 : 28, fuerte ? 10 : 3, 16, 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  a,
                  style: TextStyle(
                    fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500,
                    color: fuerte ? TemaBarra.dorado : null,
                  ),
                ),
              ),
              Text(b, style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );
    return Column(
      key: const Key('jefe_vendido_lista'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in cuentas.porCategoria) ...[
          renglon(
            '${g.unidades} · ${g.nombre.toUpperCase()}',
            pesos(g.plata),
            fuerte: true,
            key: Key('jefe_vendido_cat_${g.nombre}'),
          ),
          for (final p in g.productos)
            renglon('${p.unidades} x ${p.nombre}', pesos(p.plata), key: Key('jefe_vendido_${p.productoId}')),
        ],
        const Divider(height: 20, color: Color(0xFF2A2830)),
        renglon(
          cuentas.unidades == 1 ? '1 unidad' : '${cuentas.unidades} unidades',
          pesos(deCentavos(cuentas.porProducto.fold(0, (s, p) => s + centavos(p.plata)))),
          fuerte: true,
          key: const Key('jefe_vendido_total'),
        ),
        if (centavos(cuentas.recargos) > 0)
          renglon('Recargos por transferencia (aparte)', pesos(cuentas.recargos)),
        const SizedBox(height: 12),
      ],
    );
  }

  /// La lista de CAJAS; en la web, con "deslizar hacia abajo para releer".
  Widget _lista(List<Widget> hijos, {required bool enLaWeb}) {
    final lista = ListView(
      physics: enLaWeb ? const AlwaysScrollableScrollPhysics() : null,
      children: hijos,
    );
    if (!enLaWeb) return lista;
    return RefreshIndicator(
      key: const Key('jefe_cajas_releer'),
      onRefresh: _releerAhora,
      color: TemaBarra.dorado,
      child: lista,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(mandaEnLaBarraProvider);
    // **LAS CAJAS, con la plata de todas, solo la encargada o el jefe** (26-nov-2026), se
    // llegue por donde se llegue: no alcanza con esconder el botón.
    if (!esJefe) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Las cajas, con la plata, las ve la encargada o el jefe en modo jefe.',
            key: Key('cajas_sin_permiso'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final cajas = ref.watch(cajasDelJefeProvider(widget.fiesta.id));
    final enLaWeb = ref.watch(enLaWebProvider);
    final ahora = ref.watch(relojDelJefeProvider)();
    final estaNoche = DiaDeOperacion.de(ahora);
    // La central se prende en la notebook, no en la web ni en una tablet.
    final conPanel = !enLaWeb && ref.watch(centralSePrendeAcaProvider);
    final panel = [
      if (conPanel) ...[
        PanelCentralDeLaBarra(eventoId: widget.fiesta.id, fechaDeLaFiesta: widget.fiesta.fechaEvento),
        const SizedBox(height: 12),
      ],
      _EnVivo(enLaWeb: enLaWeb, eventoId: widget.fiesta.id),
    ];
    return cajas.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('No se pudieron leer las cajas.')),
      skipLoadingOnRefresh: true,
      data: (datos) {
        if (datos.sinCajas) {
          return _lista(enLaWeb: enLaWeb, [
            // La central de la barra, en la notebook (no en la web ni en una tablet).
            ...panel,
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Todavía no se abrió ninguna caja en esta fiesta.',
                key: Key('jefe_sin_cajas'),
              ),
            ),
          ]);
        }
        // La noche elegida, si sigue teniendo cajas (o es esta noche); si no, la de esta
        // noche o la última con cajas.
        final elegidaAntes = _noche;
        final dia = elegidaAntes != null && (datos.porDia.tiene(elegidaAntes) || elegidaAntes == estaNoche)
            ? elegidaAntes
            : datos.porDia.inicial(ahora: ahora, fechaDeLaFiesta: widget.fiesta.fechaEvento);
        final noche = datos.delDia(dia);
        final noches = _Noches(
          porDia: datos.porDia,
          elegida: dia,
          estaNoche: estaNoche,
          onElegir: (d) => setState(() {
            _noche = d;
            _cajaElegida = null;
            _aviso = null;
          }),
        );
        if (noche.sinCajas) {
          // Esta noche todavía sin cajas, pero hubo en otros días: arriba, para tocar.
          return _lista(enLaWeb: enLaWeb, [
            ...panel,
            AvisoDePedidosDeCierre(eventoId: widget.fiesta.id),
            const SizedBox(height: 12),
            noches,
            const SizedBox(height: 24),
            Center(
              child: Text(
                dia == estaNoche
                    ? 'Todavía no se abrió ninguna caja esta noche.'
                    : 'Esa noche no se abrió ninguna caja.',
                key: const Key('jefe_sin_cajas_esta_noche'),
              ),
            ),
          ]);
        }
        final elegida = noche.resumen.cajas.where((r) => r.caja.id == _cajaElegida).firstOrNull;
        return LayoutBuilder(builder: (context, caja) {
          final conCostado = caja.maxWidth >= 1000;
          final principal = <Widget>[
            ...panel,
            // "La Caja 2 pide cerrar": a la encargada y al jefe en modo jefe.
            AvisoDePedidosDeCierre(eventoId: widget.fiesta.id),
            const SizedBox(height: 12),
            noches,
            const SizedBox(height: 12),
            _Totales(resumen: noche.resumen),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('jefe_vendido_fiesta'),
                onPressed: () => _verLoVendidoDeLaFiesta(noche),
                icon: const Icon(Icons.local_bar_outlined),
                label: const Text('LO VENDIDO DE LA FIESTA'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
            const SizedBox(height: 16),
            if (elegida == null)
              _Tarjetas(
                resumen: noche.resumen,
                estaNoche: estaNoche,
                sinOk: datos.sinOk,
                onElegir: (r) => setState(() {
                  _cajaElegida = r.caja.id;
                  _aviso = null;
                  _verLoVendido = false;
                  _filtro = _FiltroDeVentas.todas;
                }),
              )
            else
              _ventasDeLaCaja(elegida, datos, esJefe, enLaWeb: enLaWeb, estaNoche: estaNoche),
          ];
          final stock = _Stock(stock: noche.stock, dia: dia, estaNoche: estaNoche);
          if (!conCostado) {
            return _lista(
              enLaWeb: enLaWeb,
              [...principal, const SizedBox(height: 16), stock, const SizedBox(height: 24)],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _lista(enLaWeb: enLaWeb, [...principal, const SizedBox(height: 24)])),
              const SizedBox(width: 20),
              SizedBox(width: 360, child: SingleChildScrollView(child: stock)),
            ],
          );
        });
      },
    );
  }

  Widget _ventasDeLaCaja(
    ResumenDeCaja r,
    CajasDeLaFiesta datos,
    bool esJefe, {
    required bool enLaWeb,
    required DiaDeOperacion estaNoche,
  }) {
    final caja = r.caja;
    final ventas = VentaDeLaCaja.armar(
      ventas: [for (final v in datos.ventas) if (v.cajaBarraId == caja.id) v],
      anulaciones: [for (final a in datos.anulaciones) if (a.cajaBarraId == caja.id) a],
      vales: [for (final v in datos.vales) if (v.cajaBarraId == caja.id) v],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF17161A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2830)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('jefe_cajas_volver'),
                  onPressed: () => setState(() {
                    _cajaElegida = null;
                    _aviso = null;
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('TODAS LAS CAJAS'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
                Text(
                  'Caja ${caja.numeroCaja}${caja.operadorNombre == null ? '' : ' · ${caja.operadorNombre}'}',
                  key: const Key('jefe_caja_titulo'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(_horario(caja, estaNoche), style: const TextStyle(color: Color(0xFFA7A29A))),
                OutlinedButton.icon(
                  key: const Key('jefe_ver_cierre'),
                  onPressed: () => _verCierre(r, datos),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(caja.abierta ? 'VER CÓMO VA' : 'VER CIERRE'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ],
            ),
          ),
          if (esJefe) _plataDeLaCaja(r, [for (final m in datos.movimientos) if (m.cajaBarraId == caja.id) m]),
          // VENTAS (una por una) o LO VENDIDO (cada bebida, por categoría).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                key: const Key('jefe_caja_pestanas'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('VENTAS', key: Key('jefe_pestana_ventas'))),
                  ButtonSegment(value: true, label: Text('LO VENDIDO', key: Key('jefe_pestana_vendido'))),
                ],
                selected: {_verLoVendido},
                onSelectionChanged: (s) => setState(() => _verLoVendido = s.first),
              ),
            ),
          ),
          if (_verLoVendido)
            _loVendido(r.cuentas)
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Anular no borra la venta: queda marcada, con el motivo, y deja de contar.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
              ),
            ),
            if (ventas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Todavía no hay ventas en esta caja.', key: Key('jefe_caja_sin_ventas')),
              )
            else
              ..._ventasFiltradas(ventas, r.cuentas, caja, esJefe, enLaWeb: enLaWeb),
          ],
        ],
      ),
    );
  }

  /// Las ventas de la caja con el filtro de arriba. Con "Transferencia" dice cuántas
  /// son y cuánto suman: es lo que se compara con Mercado Pago.
  List<Widget> _ventasFiltradas(
    List<VentaDeLaCaja> ventas,
    CierreDeBarra cuentas,
    CajaBarra caja,
    bool esJefe, {
    required bool enLaWeb,
  }) {
    final vistas = [for (final x in ventas) if (_filtro.deja(x)) x];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in _FiltroDeVentas.values)
              ChoiceChip(
                key: Key('jefe_filtro_${f.name}'),
                label: Text(f.rotulo),
                selected: _filtro == f,
                onSelected: (_) => setState(() => _filtro = f),
              ),
          ],
        ),
      ),
      if (_filtro == _FiltroDeVentas.transferencia)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            cuentas.conTransferencia == 0
                ? 'Ninguna venta por transferencia.'
                : 'Por transferencia: '
                    '${cuentas.conTransferencia == 1 ? '1 venta' : '${cuentas.conTransferencia} ventas'}'
                    ' · ${pesos(cuentas.transferencia)}. Comparalo con Mercado Pago.',
            key: const Key('jefe_filtro_resumen'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (vistas.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Ninguna venta así en esta caja.', key: Key('jefe_filtro_vacio')),
        ),
      for (final x in vistas) _venta(x, caja, esJefe, enLaWeb: enLaWeb),
    ];
  }

  Widget _venta(VentaDeLaCaja x, CajaBarra caja, bool esJefe, {required bool enLaWeb}) {
    final v = x.venta;
    final id = v.id;
    final error = Theme.of(context).colorScheme.error;
    final medio = switch (v.medio) {
      MedioBarra.efectivo => 'Efectivo',
      MedioBarra.transferencia => 'Transferencia',
      // Cuánto fue de cada cosa: lo transferido es lo que se busca en Mercado Pago.
      MedioBarra.mixto => 'Mixto · E ${pesos(v.efectivo)} · T ${pesos(v.transferencia)}',
      MedioBarra.otro => 'Otro',
    };
    final bebidas = [for (final r in v.renglones) '${r.cantidad} ${r.nombre}'].join(' · ');
    final tachado = x.anulada
        ? const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFFA7A29A))
        : null;
    final aviso = _aviso?.ventaId == id ? _aviso : null;
    final porQueNo = x.porQueNoReimprimeElJefe;
    return DecoratedBox(
      key: Key('jefe_venta_$id'),
      decoration: BoxDecoration(
        color: x.anulada ? const Color(0x0DFF7A6B) : null,
        border: const Border(top: BorderSide(color: Color(0xFF2A2830))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                Text(
                  'N° ${_numero(v)} · ${_hora(v.createdAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('${pesos(v.cobrado)} · $medio', style: tachado ?? const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(bebidas, style: tachado),
            if (x.anulada)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ANULADA · ${x.anulacion!.motivoParaMostrar}'
                  '${x.anulacion!.valeVolvio ? '' : ' · el vale no volvió'}'
                  '${x.anulacion!.hechoPor == null ? '' : ' · ${x.anulacion!.hechoPor}'}',
                  key: Key('jefe_anulada_$id'),
                  style: TextStyle(color: error, fontWeight: FontWeight.w800),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // En la web no hay impresora: reimprimir es de la PC.
                  if (!enLaWeb)
                  Tooltip(
                    message: !esJefe ? kSoloEnModoJefe : (porQueNo ?? 'Una copia de cada vale, con COPIA'),
                    child: OutlinedButton.icon(
                      key: Key('jefe_reimprimir_$id'),
                      onPressed: _ocupado || !esJefe || porQueNo != null ? null : () => _reimprimir(x, caja),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('REIMPRIMIR'),
                    ),
                  ),
                  Tooltip(
                    message: esJefe ? 'Anular, con motivo' : kSoloEnModoJefe,
                    child: TextButton.icon(
                      key: Key('jefe_anular_$id'),
                      style: TextButton.styleFrom(foregroundColor: error),
                      onPressed: _ocupado || !esJefe ? null : () => _anular(x),
                      icon: const Icon(Icons.block),
                      label: const Text('ANULAR'),
                    ),
                  ),
                ],
              ),
              if (porQueNo != null && !enLaWeb)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(porQueNo, style: const TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A))),
                ),
            ],
            if (aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  aviso.texto,
                  key: Key('jefe_aviso_$id'),
                  style: TextStyle(
                    color: aviso.error ? error : const Color(0xFF59D38A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _numero(VentaBarra v) => v.numero.toString().padLeft(4, '0');
}

/// "23:41", en hora de Argentina.
String _hora(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final ar = ArTime.toAr(t);
  return '${ar.hour.toString().padLeft(2, '0')}:${ar.minute.toString().padLeft(2, '0')}';
}

/// "abierta desde las 22:05" o "de 22:15 a 02:40". **Una caja de otra noche que
/// [estaNoche] dice su fecha** ("Vie 20/11 · de 22:15 a 02:40"): una caja de prueba no
/// se confunde con una de la fiesta.
String _horario(CajaBarra c, DiaDeOperacion estaNoche) {
  final horas = c.abierta
      ? 'abierta desde las ${_hora(c.abiertaAt)}'
      : 'de ${_hora(c.abiertaAt)} a ${_hora(c.cerradaAt!)}';
  final dia = DiaDeOperacion.deLaCaja(c);
  return dia == estaNoche ? horas : '${dia.corto} · $horas';
}

class _EnVivo extends ConsumerWidget {
  final bool enLaWeb;
  final String eventoId;

  const _EnVivo({required this.enLaWeb, required this.eventoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Con la central de esta fiesta prendida, lo de las cajas llega por la red del salón al
    // momento, haya internet o no.
    final conCentral = !enLaWeb &&
        ref.watch(centralDeLaBarraProvider.select((e) => e.prendida && e.eventoId == eventoId));
    final enLaPagina = ref.watch(enLaPaginaDeLaBarraProvider);
    return Row(
      children: [
        const Icon(Icons.circle, size: 10, color: Color(0xFF59D38A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            enLaPagina
                ? 'Al día con la notebook de la barra: cada venta llega al momento por el wifi, sin internet.'
                : enLaWeb
                ? 'Se pone al día cada 30 segundos con lo que las cajas subieron; deslizá hacia '
                    'abajo para ponerla al día ahora. Sin internet, cada tablet guarda lo suyo y lo '
                    'sube al volver.'
                : conCentral
                    ? 'Se pone al día con cada venta que llega por la red del salón, haya internet o '
                        'no. Cada tablet sube lo suyo a la nube cuando hay internet.'
                    : 'Se pone al día solo cuando las cajas suben sus ventas. Sin internet, cada tablet '
                        'guarda lo suyo y lo sube al volver.',
            key: const Key('jefe_en_vivo'),
            style: const TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
          ),
        ),
      ],
    );
  }
}

class _Totales extends StatelessWidget {
  final ResumenDeCajas resumen;

  const _Totales({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final cerradas = r.cajas.length - r.abiertas;
    final kpis = [
      ('total', 'TOTAL VENDIDO', pesos(r.total), 'sin las anuladas', TemaBarra.dorado),
      ('efectivo', 'EFECTIVO', pesos(r.efectivo), 'lo cobrado en efectivo', null),
      (
        'transferencia',
        'TRANSFERENCIA',
        pesos(r.transferencia),
        centavos(r.recargos) > 0 ? 'con ${pesos(r.recargos)} de recargo' : 'sin recargos',
        null,
      ),
      ('ventas', 'VENTAS', '${r.ventas}', r.anuladas == 1 ? '1 anulada' : '${r.anuladas} anuladas', null),
      (
        'cajas',
        'CAJAS',
        r.abiertas == 1 ? '1 abierta' : '${r.abiertas} abiertas',
        cerradas == 1 ? '1 cerrada' : '$cerradas cerradas',
        null,
      ),
      if (cerradas > 0)
        (
          'diferencia',
          'DIFERENCIA',
          diferenciaEnPalabras(r.diferencia).replaceFirst('Justo, sin diferencia', 'Justo'),
          'de las cajas cerradas',
          centavos(r.diferencia) == 0
              ? const Color(0xFF59D38A)
              : (centavos(r.diferencia) < 0 ? const Color(0xFFFF8F82) : const Color(0xFFF2B84B)),
        ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (clave, titulo, valor, sub, color) in kpis)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160),
            child: DecoratedBox(
              key: Key('jefe_kpi_$clave'),
              decoration: BoxDecoration(
                color: const Color(0xFF17161A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2830)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA7A29A),
                      ),
                    ),
                    Text(
                      valor,
                      key: Key('jefe_kpi_${clave}_valor'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                    ),
                    Text(sub, style: const TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Las noches de la fiesta con cajas, arriba, para tocar: la que se mira marcada, **esta
/// noche primero** y las demás de la más nueva a la más vieja. Con una sola noche (la de
/// hoy) no aparece. Si la que se mira no es esta noche, lo dice en ámbar: una caja de
/// prueba no se lee como de la fiesta.
class _Noches extends StatelessWidget {
  final CajasPorDia porDia;
  final DiaDeOperacion elegida;
  final DiaDeOperacion estaNoche;
  final ValueChanged<DiaDeOperacion> onElegir;

  const _Noches({
    required this.porDia,
    required this.elegida,
    required this.estaNoche,
    required this.onElegir,
  });

  static String clave(DiaDeOperacion d) => 'jefe_noche_${d.anio}-${d.mes}-${d.dia}';

  @override
  Widget build(BuildContext context) {
    final dias = porDia.dias.reversed.where((d) => d != estaNoche).toList();
    final todas = [estaNoche, ...dias];
    // Solo esta noche y ninguna otra: no hay nada que elegir.
    if (dias.isEmpty) return const SizedBox.shrink();
    String rotulo(DiaDeOperacion d) {
      final n = porDia.delDia(d).length;
      final cajas = n == 0 ? 'sin cajas' : (n == 1 ? '1 caja' : '$n cajas');
      return d == estaNoche ? 'Esta noche · ${d.corto} · $cajas' : '${d.corto} · $cajas';
    }

    return Column(
      key: const Key('jefe_noches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in todas)
              ChoiceChip(
                key: Key(clave(d)),
                label: Text(rotulo(d)),
                selected: d == elegida,
                onSelected: (_) => onElegir(d),
              ),
          ],
        ),
        if (elegida != estaNoche)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Estás mirando las cajas del ${elegida.largo}: no son las de esta noche.',
              key: const Key('jefe_noche_otra'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFF2B84B)),
            ),
          ),
      ],
    );
  }
}

class _Tarjetas extends StatelessWidget {
  final ResumenDeCajas resumen;
  final ValueChanged<ResumenDeCaja> onElegir;

  /// La noche de hoy: una caja de otra dice su fecha.
  final DiaDeOperacion estaNoche;

  /// Las cajas que cerraron sin el OK de la encargada.
  final Set<String> sinOk;

  const _Tarjetas({
    required this.resumen,
    required this.onElegir,
    required this.estaNoche,
    this.sinOk = const {},
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      // En el celular, una tarjeta por renglón, a todo el ancho.
      final ancho = caja.maxWidth < 600 ? caja.maxWidth : 270.0;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final r in resumen.cajas)
            _TarjetaDeCaja(
              r: r,
              ancho: ancho,
              onTap: () => onElegir(r),
              estaNoche: estaNoche,
              sinOk: sinOk.contains(r.caja.id),
            ),
        ],
      );
    });
  }
}

class _TarjetaDeCaja extends StatelessWidget {
  final ResumenDeCaja r;
  final double ancho;
  final VoidCallback onTap;
  final DiaDeOperacion estaNoche;

  /// Cerró sin esperar el OK de la encargada.
  final bool sinOk;

  const _TarjetaDeCaja({
    required this.r,
    required this.ancho,
    required this.onTap,
    required this.estaNoche,
    this.sinOk = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = r.caja;
    final cuentas = r.cuentas;
    final dif = r.diferencia ?? 0;
    final colorDif = centavos(dif) == 0
        ? const Color(0xFF59D38A)
        : (centavos(dif) < 0 ? const Color(0xFFFF8F82) : const Color(0xFFF2B84B));
    Widget renglon(String a, String b) => Row(
          children: [
            Expanded(child: Text(a, style: const TextStyle(color: Color(0xFFA7A29A)))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        );
    return SizedBox(
      width: ancho,
      child: Material(
        color: const Color(0xFF17161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF2A2830)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('jefe_caja_${c.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Caja ${c.numeroCaja}',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.abierta ? const Color(0x2659D38A) : const Color(0xFF2A2830),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        child: Text(
                          c.abierta ? 'ABIERTA' : 'CERRADA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: c.abierta ? const Color(0xFF59D38A) : const Color(0xFFC9C4BA),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (c.operadorNombre != null) c.operadorNombre!,
                    if (c.sede != null) c.sede!,
                    _horario(c, estaNoche),
                  ].join(' · '),
                  key: Key('jefe_caja_horario_${c.id}'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
                ),
                const SizedBox(height: 10),
                // Con cuánto arrancó: lo pidió el jefe para la encargada (5-nov).
                KeyedSubtree(
                  key: Key('jefe_caja_cambio_${c.id}'),
                  child: renglon('Cambio', pesos(c.cambioInicial)),
                ),
                renglon(
                  'Ventas',
                  '${cuentas.ventas}${cuentas.anuladas > 0 ? ' · ${cuentas.anuladas} anul.' : ''}',
                ),
                renglon('Efectivo', pesos(cuentas.efectivo)),
                renglon('Transferencia', pesos(cuentas.transferencia)),
                if (centavos(cuentas.cambioAgregado) != 0)
                  KeyedSubtree(
                    key: Key('jefe_caja_cambio_dado_${c.id}'),
                    child: renglon(cuentas.rotuloDelCambio, masOMenos(cuentas.cambioAgregado)),
                  ),
                if (centavos(cuentas.retirado) != 0)
                  KeyedSubtree(
                    key: Key('jefe_caja_retirado_${c.id}'),
                    child: renglon(cuentas.rotuloDeLoSacado, masOMenos(-cuentas.retirado)),
                  ),
                if (cuentas.sillas > 0)
                  KeyedSubtree(
                    key: Key('jefe_caja_sillas_${c.id}'),
                    child: renglon('Sillas extra', '${cuentas.sillas}'),
                  ),
                if (cuentas.sillasSueltas > 0)
                  KeyedSubtree(
                    key: Key('jefe_caja_sueltas_${c.id}'),
                    child: renglon('Sillas sueltas', '${cuentas.sillasSueltas}'),
                  ),
                const SizedBox(height: 10),
                if (!c.abierta && c.efectivoContado != null)
                  DecoratedBox(
                    key: Key('jefe_caja_diferencia_${c.id}'),
                    decoration: BoxDecoration(
                      color: colorDif.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        'Contó ${pesos(c.efectivoContado!)} · ${diferenciaEnPalabras(dif)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: colorDif),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Lo contado y la diferencia aparecen cuando la cajera cierra.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
                  ),
                // Un retiro (o una anulación) que llegó después de cerrar: lo anotado no se
                // toca; esto lo dice, con la cuenta de ahora (27-nov).
                if (r.cambioDespuesDelCierre)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Algo llegó después del cierre (un retiro o una anulación): con todo, '
                      '${diferenciaEnPalabras(r.diferenciaConTodo!).toLowerCase()}.',
                      key: Key('jefe_caja_cambio_despues_${c.id}'),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFF2B84B)),
                    ),
                  ),
                // Cerró sin esperar el OK de la encargada (11-nov): para que el jefe la mire.
                if (sinOk)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Cerró sin el OK de la encargada',
                      key: Key('jefe_caja_sin_ok_${c.id}'),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFF2B84B)),
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'VER SUS VENTAS →',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: TemaBarra.dorado),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stock extends StatelessWidget {
  final List<StockConNombre> stock;

  /// La noche de este stock, y la de hoy.
  final DiaDeOperacion dia;
  final DiaDeOperacion estaNoche;

  const _Stock({required this.stock, required this.dia, required this.estaNoche});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('jefe_stock'),
      decoration: BoxDecoration(
        color: const Color(0xFF17161A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2830)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'STOCK DE LA FIESTA',
              style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A)),
            ),
            const SizedBox(height: 2),
            Text(
              '${dia == estaNoche ? 'Esta noche' : 'La noche del ${dia.corto}'}: todas las cajas '
              'descuentan del mismo; las de otros días, no. Arriba, lo agotado y lo que está en aviso.',
              key: const Key('jefe_stock_noche'),
              style: const TextStyle(fontSize: 13, color: Color(0xFFA7A29A)),
            ),
            const SizedBox(height: 12),
            if (stock.isEmpty)
              const Text(
                'Ningún producto lleva stock en esta fiesta. Se carga en PRECIOS.',
                key: Key('jefe_stock_vacio'),
              ),
            for (final s in stock) _fila(s),
          ],
        ),
      ),
    );
  }

  Widget _fila(StockConNombre s) {
    final st = s.stock;
    final inicial = st.inicial!;
    final queda = st.queda!;
    final color = st.agotado
        ? const Color(0xFFFF7A6B)
        : (st.enAviso ? const Color(0xFFF2B84B) : const Color(0xFF59D38A));
    final texto = st.agotado
        ? 'Agotado · ${st.vendido} de $inicial'
        : 'Quedan $queda de $inicial';
    final fraccion = inicial <= 0 ? 0.0 : (queda / inicial).clamp(0.0, 1.0);
    return Padding(
      key: Key('jefe_stock_${st.productoId}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(
                texto,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: st.enAviso ? color : const Color(0xFFC9C4BA),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraccion,
              minHeight: 6,
              backgroundColor: const Color(0xFF2A2830),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// SACAR EFECTIVO, DAR CAMBIO o Corregir: cuánto y por qué. **El motivo es obligatorio.**
/// Corregir pregunta si suma o resta (se anotó de menos o de más).
class _PedirMovimiento extends StatefulWidget {
  final CajaBarra caja;
  final TipoMovimientoDeCaja tipo;

  const _PedirMovimiento({required this.caja, required this.tipo});

  @override
  State<_PedirMovimiento> createState() => _PedirMovimientoState();
}

class _PedirMovimientoState extends State<_PedirMovimiento> {
  final _monto = TextEditingController();
  final _motivo = TextEditingController();
  bool _suma = true;

  static const _rapidos = {
    TipoMovimientoDeCaja.retiro: ['Mucho efectivo en la caja', 'Para pagar algo', 'Lo pidió el jefe'],
    TipoMovimientoDeCaja.cambio: ['Se quedó sin billetes chicos', 'Pidió más cambio'],
    TipoMovimientoDeCaja.ajusteCambio: ['El cambio se anotó mal al abrir', 'Un retiro se anotó mal'],
  };

  @override
  void dispose() {
    _monto.dispose();
    _motivo.dispose();
    super.dispose();
  }

  int? get _numero => PesosEnterosFormatter.leer(_monto.text);

  @override
  Widget build(BuildContext context) {
    final n = _numero;
    final listo = n != null && n > 0 && _motivo.text.trim().isNotEmpty;
    final caja = 'Caja ${widget.caja.numeroCaja}${widget.caja.operadorNombre == null ? '' : ' · ${widget.caja.operadorNombre}'}';
    final (titulo, boton) = switch (widget.tipo) {
      TipoMovimientoDeCaja.retiro => ('Sacar efectivo · $caja', n == null ? 'SACAR' : 'SACAR ${pesos(n.toDouble())}'),
      TipoMovimientoDeCaja.cambio => ('Dar cambio · $caja', n == null ? 'DAR' : 'DAR ${pesos(n.toDouble())}'),
      TipoMovimientoDeCaja.ajusteCambio => ('Corregir · $caja', 'CORREGIR'),
    };
    return AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.tipo == TipoMovimientoDeCaja.ajusteCambio) ...[
                SegmentedButton<bool>(
                  key: const Key('mov_suma'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Hay más (suma)', key: Key('mov_mas'))),
                    ButtonSegment(value: false, label: Text('Hay menos (resta)', key: Key('mov_menos'))),
                  ],
                  selected: {_suma},
                  onSelectionChanged: (v) => setState(() => _suma = v.first),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                key: const Key('mov_monto'),
                controller: _monto,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: const [PesosEnterosFormatter()],
                decoration: const InputDecoration(labelText: 'Cuánto', prefixText: '\$ '),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('mov_motivo'),
                controller: _motivo,
                decoration: const InputDecoration(labelText: 'Por qué (obligatorio)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (i, t) in (_rapidos[widget.tipo] ?? const <String>[]).indexed)
                    ActionChip(
                      key: Key('mov_rapido_$i'),
                      label: Text(t),
                      onPressed: () => setState(() => _motivo.text = t),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Queda anotado con tu nombre y la hora. No se borra: si te equivocás, "Corregir".',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(
          key: const Key('mov_confirmar'),
          onPressed: listo
              ? () => Navigator.pop(context, (
                    monto: (widget.tipo == TipoMovimientoDeCaja.ajusteCambio && !_suma ? -n : n).toDouble(),
                    motivo: _motivo.text.trim(),
                  ))
              : null,
          child: Text(boton),
        ),
      ],
    );
  }
}
