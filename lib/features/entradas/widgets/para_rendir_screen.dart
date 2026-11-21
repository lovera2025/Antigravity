import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_engine.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../../models/evento.dart';
import '../../barra/cuentas/pesos.dart';
import '../../barra/widgets/ventas_de_la_caja_screen.dart' show pedirMotivo;
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/quien_opera.dart';
import '../../common/utils/solo_jefe.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../cuentas/para_rendir.dart';
import '../datos/entradas_repositorio.dart';
import '../pdf/comprobante_entradas_pdf.dart' show ComprobanteEntradasPdf;
import '../providers/entradas_providers.dart';
import '../services/nombre_de_la_fiesta.dart';
import 'dar_para_rendir_dialog.dart';
import 'para_rendir_comun.dart';
import 'vender_a_pagar.dart' show ChipDeVender;

/// Lo que dice el botón de la constancia mientras no se imprime (21-nov-2026:
/// el papel para firmar llega en la etapa siguiente).
const kConstanciaTodaviaNo = 'La constancia para firmar todavía no se imprime desde acá';

/// PARA RENDIR (21-nov-2026, `docs/SPEC_entradas_para_rendir_2026-11-20.md`,
/// sección 5): **quién se llevó entradas para venderlas por su cuenta**, qué
/// rindió, qué devolvió, qué no volvió y cuánto le queda. Se abre desde
/// ENTRADAS de la fiesta, **solo el jefe en modo jefe**.
///
/// - Arriba, los totales (sin rendir, "faltan hasta" y lo que no volvió) y los
///   avisos de las cuentas (rindió de más, números cruzados…), que **solo
///   avisan**: nada se corrige solo.
/// - Una persona por renglón, primero quien tiene más sin rendir; tocándola se
///   ven sus bloques con todo lo que pasó.
/// - **DAR ENTRADAS PARA RENDIR** ([_dar]); por bloque, **NO VOLVIERON**
///   ([_noVolvieron]) y **ANULAR** ([_anularMovimiento]: el bloque sin nada
///   rendido, o un "devolvió" o un "no volvieron"). **La plata de una rendición
///   se anula en VENTAS**, como cualquier venta.
///
/// **Doble llave**: el botón de ENTRADAS ya llega apagado sin modo jefe, y cada
/// guardado empieza con `_frenaSinModoJefe()` y la repite después de su ventana,
/// antes de escribir: el modo jefe pudo cerrarse con la ventana abierta
/// (`test/solo_modo_jefe_test.dart`).
/// Las cuentas son de `ParaRendir` (por `paraRendirDeLaFiestaProvider`); acá no
/// hay ninguna otra. **Lo que alguien debe de entradas para rendir no es deuda
/// de su contrato y no frena nada.**
class ParaRendirScreen extends ConsumerStatefulWidget {
  final Evento evento;

  const ParaRendirScreen({super.key, required this.evento});

  @override
  ConsumerState<ParaRendirScreen> createState() => _ParaRendirScreenState();
}

class _ParaRendirScreenState extends ConsumerState<ParaRendirScreen> {
  /// Los alumnos de la fiesta, para la división del chip y para DAR.
  List<ContratoAlumno> _alumnos = const [];
  bool _ocupado = false;

  /// La persona desplegada (por su clave), o null.
  String? _abierta;

  /// Lo último que pasó, arriba: "Se le dieron 20 entradas a …".
  String? _hecho;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// Lo que, si baja de otro equipo, cambia lo que se ve: los bloques y lo
  /// rendido, las ventas (la plata de lo rendido) y sus anulaciones.
  static const _tablasQueMiro = {
    'entradas_para_rendir',
    'entradas_ventas',
    'entradas_anulaciones',
  };

  String get _id => widget.evento.id;

  @override
  void initState() {
    super.initState();
    _leerAlumnos();
    _cambiosSub =
        ref.read(syncEngineProvider).cambiosBajadosStream.listen((tablas) {
      if (!mounted) return;
      if (tablas.any(_tablasQueMiro.contains)) {
        ref.invalidate(paraRendirDeLaFiestaProvider(_id));
      }
      if (tablas.contains('contratos_alumnos')) _leerAlumnos();
    });
  }

  @override
  void dispose() {
    _cambiosSub?.cancel();
    super.dispose();
  }

  Future<List<ContratoAlumno>> _alumnosDeLaFiesta() =>
      ref.read(contratosRepositoryProvider).getByEvento(_id);

  Future<void> _leerAlumnos() async {
    try {
      final alumnos = await _alumnosDeLaFiesta();
      if (mounted) setState(() => _alumnos = alumnos);
    } catch (_) {
      // Sin la división en el chip se ve igual: dice "alumno de la fiesta".
    }
  }

  Map<String, String> get _divisiones => {
        for (final a in _alumnos)
          if ((a.cursoDivision ?? '').trim().isNotEmpty) a.id: a.cursoDivision!.trim(),
      };

  void _decir(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ── Las llaves ───────────────────────────────────────────────────────────

  /// La segunda llave: dar, NO VOLVIERON y anular son solo del jefe.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    _decir('$kSoloEnModoJefe: dar, marcar lo que no volvió y anular es del jefe.');
    return true;
  }

  /// Lo que se le dice cuando el repositorio frena porque otro equipo cambió
  /// algo en el medio (rindió, devolvió o anuló).
  static const _cambioAlgo =
      'Cambió algo mientras lo cargabas (otro equipo rindió, devolvió o anuló): '
      'revisá y probá de nuevo.';

  // ── Lo que guarda ────────────────────────────────────────────────────────

  /// DAR ENTRADAS PARA RENDIR: la ventana no escribe; acá se guarda, con el
  /// precio de hoy y **después de volver a leer** lo de la fiesta (otro equipo
  /// pudo vender o dar esos números con la ventana abierta).
  ///
  /// **El precio también se vuelve a sacar** (21-nov-2026): si con la ventana
  /// abierta otro equipo apretó GENERAL en PRECIOS, o pasó la medianoche del
  /// último día de la anticipada, el bloque quedaría fijo con un precio que ya
  /// no es el de hoy. Si no es el que se mostró, no se da y se dice cuál es.
  Future<void> _dar() async {
    if (_frenaSinModoJefe()) return;
    if (_ocupado) return;
    final entradas = ref.read(entradasDelJefeProvider);
    final hoy = ref.read(hoyEnArgentinaProvider);
    final ParaRendir cuenta;
    final ConfigEntradas? config;
    final List<ContratoAlumno> alumnos;
    try {
      cuenta = await ref.refresh(paraRendirDeLaFiestaProvider(_id).future);
      config = await entradas.config(_id);
      alumnos = [
        for (final a in await _alumnosDeLaFiesta())
          if (!a.esBajaTemporal) a,
      ]..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
    } catch (_) {
      _decir('No se pudo leer la fiesta. Probá de nuevo.');
      return;
    }
    if (!mounted) return;
    final pedido = await mostrarDarParaRendir(
      context,
      cuenta: cuenta,
      alumnos: alumnos,
      config: config,
      hoyAr: hoy(),
    );
    if (pedido == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      // Lo de la fiesta otra vez, recién leído: si en el medio alguien vendió
      // o dio alguno de esos números, no se da.
      final ahora = await ref.refresh(paraRendirDeLaFiestaProvider(_id).future);
      final configAhora = await entradas.config(_id);
      final hoyAhora = hoy();
      // Y el precio, con la misma cuenta que la ventana: si cambió, no se da
      // (sin precio, lo dice `errorAlDar`).
      final precioAhora = ParaRendir.precioParaDar(configAhora, hoyAhora);
      if (precioAhora != null &&
          (centavos(precioAhora.precio) != centavos(pedido.precio) ||
              precioAhora.nombre != pedido.nombrePrecio)) {
        _decir('No se dieron: el precio cambió mientras cargabas. Ahora es '
            '${pesos(precioAhora.precio)} cada una '
            '(${nombreDelPrecioParaRendir(precioAhora.nombre).toLowerCase()}). '
            'Volvé a abrir DAR.');
        return;
      }
      final error = ParaRendir.errorAlDar(
        config: configAhora,
        hoyAr: hoyAhora,
        deAfuera: pedido.contratoAlumnoId == null,
        contratoAlumnoId: pedido.contratoAlumnoId,
        personaNombre: pedido.personaNombre,
        cantidad: pedido.cantidad,
        tramos: pedido.numeros,
        ocupados: ahora.ocupados,
      );
      if (error != null) {
        // Las razones de `errorAlDar` son oraciones sueltas: después de los dos
        // puntos van con minúscula, como "el precio cambió" (21-nov-2026).
        final razon =
            error.isEmpty ? error : error[0].toLowerCase() + error.substring(1);
        _decir('No se dieron: $razon');
        return;
      }
      // Otra vez la llave, justo antes de escribir: el modo jefe pudo cerrarse
      // con la ventana abierta (21-nov-2026, como RENDIR en VENDER).
      if (_frenaSinModoJefe()) return;
      final dio = await entradas.darParaRendir(
        eventoId: _id,
        personaNombre: pedido.personaNombre,
        personaContacto: pedido.personaContacto,
        contratoAlumnoId: pedido.contratoAlumnoId,
        cantidad: pedido.cantidad,
        numeros: pedido.numeros,
        precio: pedido.precio,
        nombrePrecio: pedido.nombrePrecio,
        nota: pedido.nota,
        quien: quienOpera(ref),
      );
      avisarQueCambioLaVenta(ref, _id);
      if (!mounted) return;
      setState(() {
        _hecho = 'Se le ${dio.cantidad == 1 ? 'dio 1 entrada' : 'dieron ${dio.cantidad} entradas'} '
            'a ${dio.personaNombre} (del ${TramoTalonario.legible(dio.tramos)}) para rendir.';
        _abierta = null;
      });
    } catch (_) {
      _decir('No se pudieron dar. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// NO VOLVIERON: las que no vuelven ni se pagan, con el motivo. No entra
  /// plata y quedan anuladas, pero no para siempre: si después aparecen, el
  /// jefe anula este "no volvieron" y se rinden como cualquier otra.
  Future<void> _noVolvieron(BloqueParaRendir bloque) async {
    if (_frenaSinModoJefe()) return;
    if (_ocupado || bloque.sinRendir < 1) return;
    final r = await showDialog<({int cantidad, List<TramoTalonario> numeros, String motivo})>(
      context: context,
      builder: (_) => _NoVolvieronDialog(bloque: bloque),
    );
    if (r == null || !mounted) return;
    // Otra vez la llave: el modo jefe pudo cerrarse con la ventana abierta.
    if (_frenaSinModoJefe()) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(entradasDelJefeProvider).noVolvieron(
            bloque.dio,
            cantidad: r.cantidad,
            numeros: r.numeros,
            motivo: r.motivo,
            quien: quienOpera(ref),
          );
      avisarQueCambioLaVenta(ref, _id);
      if (mounted) {
        setState(() => _hecho = '${bloque.persona}: '
            '${r.cantidad == 1 ? '1 no volvió' : '${r.cantidad} no volvieron'}.');
      }
    } on StateError {
      ref.invalidate(paraRendirDeLaFiestaProvider(_id));
      _decir(_cambioAlgo);
    } catch (_) {
      _decir('No se pudo guardar. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// ANULAR, con motivo: un bloque sin nada rendido, un "devolvió" o un "no
  /// volvieron". Es otra fila: lo anulado queda en la lista, tachado. [que]:
  /// qué se anula, en palabras ("lo que devolvió PÉREZ, JUAN").
  Future<void> _anularMovimiento(
    MovimientoParaRendir movimiento, {
    required String que,
    required String explicacion,
  }) async {
    if (_frenaSinModoJefe()) return;
    if (_ocupado) return;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Anular $que',
      explicacion: explicacion,
      ayuda: 'Por qué: se cargó mal, eran de otro…',
      boton: 'ANULAR',
      claveBoton: 'para_rendir_anular_confirmar',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    // Otra vez la llave: el modo jefe pudo cerrarse con la ventana abierta.
    if (_frenaSinModoJefe()) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(entradasDelJefeProvider).anularDeParaRendir(
            movimiento,
            motivo: motivo,
            quien: quienOpera(ref),
          );
      avisarQueCambioLaVenta(ref, _id);
      if (mounted) setState(() => _hecho = 'Anulado: $que.');
    } on StateError {
      ref.invalidate(paraRendirDeLaFiestaProvider(_id));
      _decir(_cambioAlgo);
    } catch (_) {
      _decir('No se pudo anular. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final enElEquipo = ref.watch(entradasEnEsteEquipoProvider);
    final celular = CortesPantalla.esCelular(MediaQuery.sizeOf(context).width);
    final puede = esJefe && enElEquipo;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para rendir'),
            Text(
              nombreDeLaFiesta(widget.evento),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (puede && !celular)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _botonDar(),
            ),
        ],
      ),
      body: !esJefe
          ? const _Aviso(
              clave: 'para_rendir_sin_modo_jefe',
              texto: 'PARA RENDIR es solo del jefe: $kSoloEnModoJefe.',
            )
          : !enElEquipo
              ? const _Aviso(clave: 'para_rendir_en_la_web', texto: kEntradasDesdeLaPc)
              : ref.watch(paraRendirDeLaFiestaProvider(_id)).when(
                    // Al releer se queda lo que había: no parpadea.
                    skipLoadingOnRefresh: true,
                    skipLoadingOnReload: true,
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const _Aviso(
                      clave: 'para_rendir_error',
                      texto: 'No se pudo leer lo de la fiesta. Volvé a entrar.',
                    ),
                    data: (cuenta) => _cuerpo(cuenta, celular: celular),
                  ),
    );
  }

  Widget _botonDar() => FilledButton.icon(
        key: const Key('para_rendir_dar'),
        onPressed: _ocupado ? null : _dar,
        icon: const Icon(Icons.outbox_outlined, size: 18),
        label: const Text('DAR ENTRADAS PARA RENDIR'),
      );

  Widget _cuerpo(ParaRendir cuenta, {required bool celular}) {
    final naranja = Colors.orange.shade800;
    final verde = Colors.green.shade700;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            if (celular) ...[_botonDar(), const SizedBox(height: 10)],
            _Totales(cuenta: cuenta),
            for (final (i, a) in cuenta.avisos.indexed)
              _Banda(
                clave: 'para_rendir_aviso_$i',
                color: naranja,
                icono: Icons.warning_amber_rounded,
                texto: a.texto,
              ),
            if (_hecho != null)
              _Banda(
                clave: 'para_rendir_hecho',
                color: verde,
                icono: Icons.check_circle,
                texto: _hecho!,
                alCerrar: () => setState(() => _hecho = null),
              ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: cuenta.porPersona.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Text(
                          'Nadie tiene entradas para rendir.',
                          key: Key('para_rendir_vacio'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: [
                          for (final (i, p) in cuenta.porPersona.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _persona(p, celular: celular),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El renglón de una persona: quién es, qué se llevó, qué rindió, cómo está
  /// y "faltan hasta $X". Tocándolo se despliegan sus bloques.
  Widget _persona(PersonaParaRendir p, {required bool celular}) {
    final abierta = _abierta == p.clave;
    final gris = Colors.grey.shade700;
    final enPie = p.bloques.where((b) => !b.anulado).toList();
    final linea1 = switch (enPie.length) {
      0 => 'se llevó ${p.bloques.length == 1 ? 'unas entradas' : 'entradas'}, y se anularon',
      1 => '${seLlevoParaRendir(enPie.single)} · ${pesos(enPie.single.precioDeCadaUna)} c/u '
          '(${nombreDelPrecioParaRendir(enPie.single.nombrePrecio).toLowerCase()}, fijo)',
      _ => 'se llevó ${p.seLlevo} en ${enPie.length} veces'
          '${p.desde == null ? '' : ' · desde el ${diaParaRendir(p.desde!)}'}',
    };
    final estado = _estado(p);
    final falta = p.sinRendir > 0
        ? Text(
            'faltan hasta ${pesos(p.plataQueFalta)}',
            key: Key('para_rendir_falta_${p.clave}'),
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9A7B12)),
          )
        : null;
    final derecha = Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [estado, ?falta],
    );
    final izquierda = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
            ChipDeQuienLleva(
              esAlumno: p.esDeUnAlumno,
              division: _divisiones[p.contratoAlumnoId],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          linea1,
          key: Key('para_rendir_linea_${p.clave}'),
          style: TextStyle(fontSize: 12.5, color: gris),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'vendió ${p.vendidas} · devolvió ${p.devueltas}'),
              if (p.noVolvieron > 0)
                TextSpan(
                  text: ' · no volvieron ${p.noVolvieron}',
                  style: TextStyle(color: Colors.red.shade700),
                ),
            ],
          ),
          key: Key('para_rendir_cuenta_${p.clave}'),
          style: TextStyle(fontSize: 12.5, color: gris),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('para_rendir_persona_${p.clave}'),
          onTap: () => setState(() => _abierta = abierta ? null : p.clave),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: celular
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [izquierda, const SizedBox(height: 6), derecha],
                        ),
                      ),
                      Icon(abierta ? Icons.expand_less : Icons.expand_more, color: gris),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: izquierda),
                      const SizedBox(width: 12),
                      Flexible(child: derecha),
                      const SizedBox(width: 6),
                      Icon(abierta ? Icons.expand_less : Icons.expand_more, color: gris),
                    ],
                  ),
          ),
        ),
        if (abierta)
          for (final b in p.bloques)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _detalle(b),
            ),
      ],
    );
  }

  /// "rindió de más: revisar", "✓ rindió todo" o "sin rendir 12".
  Widget _estado(PersonaParaRendir p) {
    final clave = Key('para_rendir_estado_${p.clave}');
    if (p.rindioDeMas > 0) {
      return ChipDeVender('rindió de más: revisar', key: clave, color: Colors.red.shade700);
    }
    if (p.sinRendir > 0) {
      return ChipDeVender('sin rendir ${p.sinRendir}', key: clave, color: const Color(0xFF7A610E));
    }
    if (p.rindioTodo) {
      return ChipDeVender('✓ rindió todo', key: clave, color: Colors.green.shade700);
    }
    return ChipDeVender('anuladas', key: clave, color: Colors.blueGrey.shade600);
  }

  /// Un bloque desplegado: lo que se llevó, cada cosa que pasó después y sus
  /// botones.
  Widget _detalle(BloqueParaRendir b) {
    final gris = Colors.grey.shade700;
    final nota = (b.dio.nota ?? '').trim();
    final contacto = (b.contacto ?? '').trim();
    final hijos = <Widget>[
      _Movimiento(
        clave: 'para_rendir_dio_${b.id}',
        cuando: diaParaRendir(b.dadoAt),
        texto: [
          'Se llevó ${b.cantidad}',
          'del ${TramoTalonario.legible(b.tramos)}',
          'sin pulseras',
          if (contacto.isNotEmpty) contacto,
        ].join(' · '),
        quien: b.dio.hechoPor ?? '',
        tachado: b.anulado,
      ),
      if (nota.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Nota: $nota', style: TextStyle(fontSize: 12.5, color: gris)),
        ),
      if (b.anulado)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Anuladas el ${momentoParaRendir(b.anulacion!.createdAt)}'
            '${(b.anulacion!.hechoPor ?? '').isEmpty ? '' : ' por ${b.anulacion!.hechoPor}'}'
            ' · ${b.anulacion!.motivo ?? ''}',
            key: Key('para_rendir_anulado_${b.id}'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
        ),
      if (b.movimientos.isEmpty && !b.anulado)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('Todavía no rindió nada.', style: TextStyle(color: gris)),
        ),
      for (final m in _paraMirar(b.movimientos)) _movimiento(b, m),
    ];
    if (!b.anulado) {
      final conMovimientos = b.tieneMovimientos;
      hijos.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Tooltip(
              message: kConstanciaTodaviaNo,
              child: OutlinedButton(onPressed: null, child: Text('CONSTANCIA')),
            ),
            OutlinedButton(
              key: Key('para_rendir_no_volvieron_${b.id}'),
              onPressed: _ocupado || b.sinRendir < 1 ? null : () => _noVolvieron(b),
              child: const Text('NO VOLVIERON'),
            ),
            Tooltip(
              message: conMovimientos
                  ? 'Ya rindió algo: anulá cada movimiento (la plata, en VENTAS)'
                  : 'Anular las que se le dieron, con motivo',
              child: FilledButton(
                key: Key('para_rendir_anular_${b.id}'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                onPressed: _ocupado || conMovimientos
                    ? null
                    : () => _anularMovimiento(
                          b.dio,
                          que: 'las entradas de ${b.persona}',
                          explicacion: 'Las ${b.cantidad} que se le dieron a ${b.persona} '
                              '(del ${TramoTalonario.legible(b.tramos)}) quedan anuladas: '
                              'no tiene nada para rendir y esos números quedan libres. No '
                              'se borra: queda en la lista, tachado, con el motivo.',
                        ),
                child: const Text('ANULAR'),
              ),
            ),
            if (conMovimientos)
              Text(
                'Ya rindió algo: anulá cada movimiento (la plata, en VENTAS)',
                key: Key('para_rendir_anular_motivo_${b.id}'),
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: gris),
              ),
          ],
        ),
      ));
    }
    return Container(
      key: Key('para_rendir_bloque_${b.id}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
    );
  }

  /// Lo que pasó, en el orden en que se lee: por el minuto y, en el mismo
  /// minuto (una rendición deja lo vendido y lo devuelto juntos), primero lo
  /// vendido, después lo devuelto y al final lo que no volvió. Solo cambia
  /// cómo se ve: las cuentas no miran el orden.
  static List<MovimientoDelBloque> _paraMirar(List<MovimientoDelBloque> movs) {
    int porQue(MovimientoDelBloque m) =>
        m.movimiento.esVendio ? 0 : (m.movimiento.esDevolvio ? 1 : 2);
    String minuto(MovimientoDelBloque m) {
      final iso = m.movimiento.createdAt;
      final t = DateTime.tryParse(iso);
      return t == null ? iso : t.toUtc().toIso8601String().substring(0, 16);
    }

    final enOrden = movs.indexed.toList()
      ..sort((a, b) {
        final porMinuto = minuto(a.$2).compareTo(minuto(b.$2));
        if (porMinuto != 0) return porMinuto;
        final porLoQueEs = porQue(a.$2).compareTo(porQue(b.$2));
        return porLoQueEs != 0 ? porLoQueEs : a.$1.compareTo(b.$1);
      });
    return [for (final (_, m) in enOrden) m];
  }

  /// Una cosa que pasó con un bloque: lo rendido (la plata se anula en VENTAS),
  /// lo devuelto o lo que no volvió (estos dos, con su ANULAR).
  Widget _movimiento(BloqueParaRendir b, MovimientoDelBloque m) {
    final mov = m.movimiento;
    final numeros = m.tramos.isEmpty ? '' : ' · del ${TramoTalonario.legible(m.tramos)}';
    final String texto;
    String? porQueNoCuenta;
    if (mov.esVendio) {
      final venta = m.venta;
      final plata = venta?.total ?? mov.cantidad * b.precioDeCadaUna;
      texto = [
        'Vendió ${mov.cantidad}',
        pesos(plata),
        if (venta != null) 'venta ${ComprobanteEntradasPdf.numero(venta)}',
        if (m.plataEnCamino) 'la plata está en camino desde otro equipo',
      ].join(' · ');
      if (m.anulacionDeLaVenta != null) porQueNoCuenta = 'anulada en VENTAS';
    } else if (mov.esDevolvio) {
      texto = 'Devolvió ${mov.cantidad}$numeros';
      if (m.anulacion != null) porQueNoCuenta = 'anulado: ${m.anulacion!.motivo ?? ''}';
    } else {
      texto = 'No volvieron ${mov.cantidad}$numeros · "${mov.motivo ?? ''}"';
      if (m.anulacion != null) porQueNoCuenta = 'anulado: ${m.anulacion!.motivo ?? ''}';
    }
    final anulable = !mov.esVendio && m.cuenta;
    return _Movimiento(
      clave: 'para_rendir_mov_${mov.id}',
      cuando: momentoParaRendir(mov.createdAt),
      texto: porQueNoCuenta == null ? texto : '$texto ($porQueNoCuenta)',
      quien: mov.hechoPor ?? '',
      tachado: !m.cuenta,
      accion: anulable
          ? TextButton(
              key: Key('para_rendir_anular_${mov.id}'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _ocupado
                  ? null
                  : () => _anularMovimiento(
                        mov,
                        que: mov.esDevolvio
                            ? 'lo que devolvió ${b.persona}'
                            : 'lo que no volvió de ${b.persona}',
                        explicacion: _queHaceAnular(mov, m.tramos),
                      ),
              child: const Text('ANULAR'),
            )
          : null,
    );
  }

  /// Lo que explica la ventana de ANULAR un "devolvió" o un "no volvieron":
  /// "Las 5 que devolvió (del 1239 al 1243) vuelven a quedar a su cargo para
  /// rendir." Los números van entre paréntesis, no con el " · " de la lista,
  /// que en medio de una oración se leía cortado (21-nov-2026).
  static String _queHaceAnular(
    MovimientoParaRendir mov,
    List<TramoTalonario> tramos,
  ) {
    final numeros = tramos.isEmpty ? '' : ' (del ${TramoTalonario.legible(tramos)})';
    final una = mov.cantidad == 1;
    if (mov.esDevolvio) {
      return una
          ? 'La que devolvió$numeros vuelve a quedar a su cargo para rendir.'
          : 'Las ${mov.cantidad} que devolvió$numeros vuelven a quedar a su cargo '
              'para rendir.';
    }
    return una
        ? 'La que no volvió$numeros vuelve a quedar a su cargo para rendir (si la '
            'vendió o la trajo).'
        : 'Las ${mov.cantidad} que no volvieron$numeros vuelven a quedar a su cargo '
            'para rendir (si las vendió o las trajo).';
  }
}

/// Los tres números de arriba: sin rendir, "faltan hasta" y lo que no volvió.
class _Totales extends StatelessWidget {
  const _Totales({required this.cuenta});

  final ParaRendir cuenta;

  @override
  Widget build(BuildContext context) {
    final personas = cuenta.personas;
    final tarjetas = [
      (
        'para_rendir_total_sin_rendir',
        'Sin rendir',
        '${cuenta.sinRendir}',
        'entradas · ${personas == 1 ? '1 persona' : '$personas personas'}',
      ),
      (
        'para_rendir_total_falta',
        'Faltan hasta',
        pesos(cuenta.plataQueFalta),
        'si no devuelven ninguna',
      ),
      (
        'para_rendir_total_no_volvieron',
        'No volvieron',
        '${cuenta.noVolvieron}',
        pesos(cuenta.plataNoVolvio),
      ),
    ];
    return LayoutBuilder(
      builder: (context, caja) {
        final columnas = caja.maxWidth >= 560 ? 3 : 2;
        final ancho = (caja.maxWidth - 8 * (columnas - 1)) / columnas;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (clave, titulo, valor, abajo) in tarjetas)
              SizedBox(
                width: ancho,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          valor,
                          key: Key(clave),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(abajo,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Un aviso en una banda de color, con su ícono (y una cruz, si se saca).
class _Banda extends StatelessWidget {
  const _Banda({
    required this.clave,
    required this.color,
    required this.icono,
    required this.texto,
    this.alCerrar,
  });

  final String clave;
  final Color color;
  final IconData icono;
  final String texto;
  final VoidCallback? alCerrar;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: EdgeInsets.fromLTRB(12, 8, alCerrar == null ? 12 : 4, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                key: Key(clave),
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ),
            if (alCerrar != null)
              IconButton(
                tooltip: 'Sacar el aviso',
                icon: const Icon(Icons.close),
                onPressed: alCerrar,
              ),
          ],
        ),
      );
}

/// Un renglón de lo que pasó: cuándo, qué y quién (y su botón, si tiene).
class _Movimiento extends StatelessWidget {
  const _Movimiento({
    required this.clave,
    required this.cuando,
    required this.texto,
    required this.quien,
    this.tachado = false,
    this.accion,
  });

  final String clave;
  final String cuando;
  final String texto;
  final String quien;
  final bool tachado;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final gris = Colors.grey.shade700;
    final estilo = TextStyle(
      fontSize: 13,
      decoration: tachado ? TextDecoration.lineThrough : null,
      color: tachado ? Colors.grey.shade500 : null,
    );
    final elTexto = Text(texto, key: Key(clave), style: estilo);
    return LayoutBuilder(
      builder: (context, caja) {
        // En un celular, cuándo y quién arriba y lo que pasó debajo: en una
        // fila se partían en pedazos (muestras del 21-nov-2026).
        if (caja.maxWidth < 520) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quien.isEmpty ? cuando : '$cuando · $quien',
                        style: TextStyle(fontSize: 12, color: gris),
                      ),
                      elTexto,
                    ],
                  ),
                ),
                ?accion,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(cuando, style: estilo.copyWith(color: gris)),
              ),
              Expanded(child: elTexto),
              if (quien.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(quien, style: TextStyle(fontSize: 12.5, color: gris)),
              ],
              if (accion != null) ...[const SizedBox(width: 6), accion!],
            ],
          ),
        );
      },
    );
  }
}

/// Un aviso a pantalla entera: sin modo jefe, en la web o si no se pudo leer.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.clave, required this.texto});

  final String clave;
  final String texto;

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

/// NO VOLVIERON de un bloque: cuántas, sus números si se saben y el motivo,
/// obligatorio. **No escribe nada**: devuelve lo elegido y guarda PARA RENDIR,
/// con su llave. Qué se puede, lo dice `ParaRendir.errorAlMarcarNoVolvieron`.
class _NoVolvieronDialog extends StatefulWidget {
  const _NoVolvieronDialog({required this.bloque});

  final BloqueParaRendir bloque;

  @override
  State<_NoVolvieronDialog> createState() => _NoVolvieronDialogState();
}

class _NoVolvieronDialogState extends State<_NoVolvieronDialog> {
  int _cantidad = 1;
  final _del = TextEditingController();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _del.dispose();
    _motivo.dispose();
    super.dispose();
  }

  List<TramoTalonario> get _numeros {
    final del = int.tryParse(_del.text.trim());
    return del == null ? const [] : [TramoTalonario(del, del + _cantidad - 1)];
  }

  String? get _error => ParaRendir.errorAlMarcarNoVolvieron(
        widget.bloque,
        cantidad: _cantidad,
        numeros: _numeros,
        motivo: _motivo.text,
      );

  @override
  Widget build(BuildContext context) {
    final b = widget.bloque;
    final error = _error;
    final naranja = Colors.orange.shade800;
    final nada = _motivo.text.trim().isEmpty && _del.text.trim().isEmpty;
    return AlertDialog(
      title: const Text('No volvieron'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${b.persona} · le quedan ${b.sinRendir} de ${b.cantidad} '
                '(${TramoTalonario.legible(b.tramos)}) · ${pesos(b.precioDeCadaUna)} c/u',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text('Cuántas no volvieron',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              Row(
                children: [
                  IconButton(
                    key: const Key('no_volvieron_menos'),
                    tooltip: 'Una menos',
                    onPressed: _cantidad <= 1 ? null : () => setState(() => _cantidad--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$_cantidad',
                      key: const Key('no_volvieron_cantidad'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const Key('no_volvieron_mas'),
                    tooltip: 'Una más',
                    onPressed: _cantidad >= b.sinRendir
                        ? null
                        : () => setState(() => _cantidad++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      key: const Key('no_volvieron_del'),
                      controller: _del,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Del (opcional)',
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Text(
                    _numeros.isEmpty ? 'al …' : 'al ${_numeros.last.hasta}',
                    key: const Key('no_volvieron_al'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('no_volvieron_motivo'),
                controller: _motivo,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obligatorio)',
                  hintText: 'Por ejemplo: dice que las perdió',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: naranja.withValues(alpha: 0.08),
                  border: Border.all(color: naranja.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                // No "para siempre" (21-nov-2026): si aparecen, el jefe anula
                // este "no volvieron" y se rinden como cualquier otra.
                child: Text(
                  'No entra plata y quedan anuladas: la lista dice que valían '
                  '${pesos(_cantidad * b.precioDeCadaUna)}. Si después aparecen, '
                  'anulá este "no volvieron" y se rinden.',
                  style: TextStyle(fontWeight: FontWeight.w600, color: naranja),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    key: const Key('no_volvieron_error'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: nada
                          ? Colors.grey.shade700
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('no_volvieron_cancelar'),
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('no_volvieron_confirmar'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: error != null
              ? null
              : () => Navigator.pop(context, (
                    cantidad: _cantidad,
                    numeros: _numeros,
                    motivo: _motivo.text.trim(),
                  )),
          child: Text(
            _cantidad == 1 ? 'MARCAR 1 QUE NO VOLVIÓ' : 'MARCAR $_cantidad QUE NO VOLVIERON',
          ),
        ),
      ],
    );
  }
}
