import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/instalacion_id.dart';
import '../../../core/services/pulso_entre_equipos.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/evento.dart';
import 'barra_repositorio.dart';

/// La barra del jefe en la web del iPhone: lee y escribe **directo en la nube**, sin
/// base ni cola. Las PCs y las tablets lo bajan con el sync de siempre.
///
/// A diferencia de [BarraLocal], un error **sí sube**: en la web sin internet no hay
/// nada guardado que mostrar, y la pantalla tiene que decirlo.
///
/// La web no vende ni abre cajas: eso es [BarraDeLaCaja], que solo existe en el equipo.
class BarraNube implements BarraDelJefe {
  BarraNube(
    this._supabase, {
    Future<String?> Function()? equipo,
    DateTime Function()? reloj,
  })  : _equipo = equipo ?? InstalacionId.inicializar,
        _reloj = reloj ?? DateTime.now;

  final SupabaseClient _supabase;
  final Future<String?> Function() _equipo;
  final DateTime Function() _reloj;

  /// La nube devuelve de a 1000 filas: una fiesta puede tener más ventas que eso.
  /// Cada consulta va ordenada hasta el id, para que las páginas no se pisen.
  /// **`order` sin `ascending: true` ordena de mayor a menor** en este paquete.
  static const _pagina = 1000;

  Future<List<Map<String, dynamic>>> _todas(
    PostgrestTransformBuilder<PostgrestList> Function() armar,
  ) async {
    final todas = <Map<String, dynamic>>[];
    for (var desde = 0;; desde += _pagina) {
      final filas = await armar().range(desde, desde + _pagina - 1);
      todas.addAll(filas);
      if (filas.length < _pagina) return todas;
    }
  }

  /// Las fiestas, para elegir cuál mirar: en la web no hay base de dónde leerlas
  /// (etapa 8). Vienen todas, también las canceladas: `FiestasDelJefe.de` las saca.
  Future<List<Evento>> eventos() async {
    final filas = await _todas(() => _supabase
        .from('eventos')
        .select()
        .order('fecha_evento', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) Evento.fromJson(f)];
  }

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) async {
    final filas = await _todas(() {
      final q = _supabase.from('barra_productos').select();
      return (conBajas ? q : q.eq('activo', 1))
          .order('orden', ascending: true)
          .order('nombre', ascending: true)
          .order('id', ascending: true);
    });
    return [for (final f in filas) ProductoBarra.fromMap(f)];
  }

  @override
  Future<ProductoBarra> guardarProducto(
    ProductoBarra producto, {
    required String quien,
  }) async {
    final sellado = producto.sellado(
      hechoPor: quien,
      deviceId: await _equipo(),
      ahora: _reloj(),
    );
    await _supabase.from('barra_productos').upsert(sellado.toMap());
    return sellado;
  }

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) async {
    final filas = await _todas(() {
      final q = _supabase.from('barra_precios').select().eq('evento_id', eventoId);
      return (conBajas ? q : q.eq('activo', 1))
          .order('orden', ascending: true)
          .order('id', ascending: true);
    });
    return [for (final f in filas) PrecioBarra.fromMap(f)];
  }

  /// Sin la tabla en la nube (su SQL todavía no se corrió), ninguna receta: el stock
  /// sigue como antes, sin el Speed de los vodkas.
  @override
  Future<List<RecetaBarra>> recetas(String eventoId) async {
    try {
      final filas = await _todas(() => _supabase
          .from('barra_recetas')
          .select()
          .eq('evento_id', eventoId)
          .eq('activo', true)
          .order('id', ascending: true));
      return [for (final f in filas) RecetaBarra.fromMap(f)];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  @override
  Future<RecetaBarra> guardarReceta(RecetaBarra receta, {required String quien}) async {
    final sellado = receta.sellado(hechoPor: quien, deviceId: await _equipo(), ahora: _reloj());
    await _supabase.from('barra_recetas').upsert(sellado.toMap());
    return sellado;
  }

  /// Sin la tabla en la nube (su SQL todavía no se corrió), ninguno: GANANCIA dice que
  /// falta el precio de lista.
  @override
  Future<List<CostoBarra>> costos(String eventoId) async {
    try {
      final filas = await _todas(() => _supabase
          .from('barra_costos')
          .select()
          .eq('evento_id', eventoId)
          .order('producto_id', ascending: true)
          .order('id', ascending: true));
      return [for (final f in filas) CostoBarra.fromMap(f)];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  @override
  Future<CostoBarra> guardarCosto(CostoBarra costo, {required String quien}) async {
    final sellado = costo.sellado(hechoPor: quien, deviceId: await _equipo(), ahora: _reloj());
    await _supabase.from('barra_costos').upsert(sellado.toMap());
    return sellado;
  }

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) async {
    final sellado = precio.sellado(
      hechoPor: quien,
      deviceId: await _equipo(),
      ahora: _reloj(),
    );
    await _supabase.from('barra_precios').upsert(sellado.toMap());
    return sellado;
  }

  @override
  Future<RecargoBarra?> recargo(String eventoId) async {
    final fila = await _supabase
        .from('barra_recargos')
        .select()
        .eq('id', UuidUtils.barraRecargoId(eventoId))
        .maybeSingle();
    return fila == null ? null : RecargoBarra.fromMap(fila);
  }

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) async {
    final sellado = recargo.sellado(
      hechoPor: quien,
      deviceId: await _equipo(),
      ahora: _reloj(),
    );
    await _supabase.from('barra_recargos').upsert(sellado.toMap());
    return sellado;
  }

  @override
  Future<List<CajaBarra>> cajas(String eventoId) async {
    final filas = await _todas(() => _supabase
        .from('barra_cajas')
        .select()
        .eq('evento_id', eventoId)
        .order('numero_caja', ascending: true)
        .order('abierta_at', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) CajaBarra.fromMap(f)];
  }

  @override
  Future<List<VentaBarra>> ventas(String eventoId) async {
    final filas = await _todas(() => _supabase
        .from('barra_ventas')
        .select()
        .eq('evento_id', eventoId)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) VentaBarra.fromMap(f)];
  }

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) async {
    final filas = await _todas(() => _supabase
        .from('barra_anulaciones')
        .select()
        .eq('evento_id', eventoId)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) AnulacionBarra.fromMap(f)];
  }

  @override
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
  }) async {
    final nueva = AnulacionBarra.de(
      venta,
      motivo: motivo,
      hechoPor: quien,
      deviceId: await _equipo(),
      ahora: _reloj(),
    );
    final ya = await _supabase
        .from('barra_anulaciones')
        .select()
        .eq('id', nueva.id)
        .maybeSingle();
    if (ya != null) return AnulacionBarra.fromMap(ya);
    // Si la PC la anuló en el medio, la que ya está queda como está.
    await _supabase
        .from('barra_anulaciones')
        .upsert(nueva.toMap(), ignoreDuplicates: true);
    return nueva;
  }

  @override
  Future<List<ValeBarra>> vales(String eventoId) async {
    final filas = await _todas(() => _supabase
        .from('barra_vales')
        .select()
        .eq('evento_id', eventoId)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) ValeBarra.fromMap(f)];
  }

  // ── El cierre con el OK de la encargada (v79) ──────────────────────────────

  @override
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId) async {
    final filas = await _todas(() => _supabase
        .from('barra_cierres')
        .select()
        .eq('evento_id', eventoId)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    return [for (final f in filas) PasoDelCierre.fromMap(f)];
  }

  /// La respuesta de la encargada desde la web: va derecho a la nube, y la tablet de
  /// la cajera la baja. Solo se agrega: si la fila ya está, queda como está.
  ///
  /// **Y les avisa a los equipos** ([_avisar]). Hasta la 6.8.0 no avisaba: la tablet
  /// de la cajera bajaba el OK recién con la red de seguridad de 5 minutos, y a los
  /// 3 ya le ofrecía CERRAR SIN ESPERAR (revisión del 13-nov).
  @override
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso) async {
    final equipo = await _equipo();
    final conEquipo = paso.conEquipo(equipo);
    await _supabase.from('barra_cierres').upsert(conEquipo.toMap(), ignoreDuplicates: true);
    await _avisar(const ['barra_cierres'], origen: equipo);
    return conEquipo;
  }

  // ── Los retiros y el cambio de la encargada (v84) ──────────────────────────

  /// Sin la tabla en la nube (su SQL todavía no se corrió), ninguno: el efectivo que
  /// tiene que haber sigue como antes.
  @override
  Future<List<MovimientoDeCaja>> movimientosDeCaja(String eventoId) async {
    try {
      final filas = await _todas(() => _supabase
          .from('barra_caja_movimientos')
          .select()
          .eq('evento_id', eventoId)
          .order('created_at', ascending: true)
          .order('id', ascending: true));
      return [for (final f in filas) MovimientoDeCaja.fromMap(f)];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  /// La encargada desde la web del iPhone: va derecho a la nube y **les avisa a los
  /// equipos**, así la tablet de esa caja lo baja antes de cerrar. Sobre una caja que
  /// ya cerró no se anota. Solo se agrega: si la fila ya está, queda como está.
  @override
  Future<MovimientoDeCaja> anotarMovimientoDeCaja(MovimientoDeCaja movimiento, {required String quien}) async {
    final fila = await _supabase
        .from('barra_cajas')
        .select()
        .eq('id', movimiento.cajaBarraId)
        .maybeSingle();
    if (fila == null) throw StateError('la caja del movimiento no está en la nube');
    final caja = CajaBarra.fromMap(fila);
    if (!caja.abierta) throw CajaYaCerrada(caja.numeroCaja);
    final equipo = await _equipo();
    final sellado = movimiento.sellado(hechoPor: quien, deviceId: equipo, ahora: _reloj());
    await _supabase.from('barra_caja_movimientos').upsert(sellado.toMap(), ignoreDuplicates: true);
    await _avisar(const ['barra_caja_movimientos'], origen: equipo);
    return sellado;
  }

  RealtimeChannel? _canalDelAviso;

  /// Les avisa a las PCs y a las tablets que cambiaron [tablas], para que las bajen
  /// ya: el mismo aviso que manda el motor de un equipo cuando sube algo
  /// (`pulso_entre_equipos.dart`). Sin suscribirse, va por REST.
  ///
  /// Que no salga no rompe nada: la fila ya quedó en la nube, y el equipo que espera
  /// la baja igual un rato después.
  Future<void> _avisar(List<String> tablas, {String? origen}) async {
    try {
      final canal = _canalDelAviso ??= _supabase.channel(kCanalDelPulso);
      await canal
          .sendBroadcastMessage(
            event: kEventoDelPulso,
            payload: avisoDeTablas(origen: origen ?? 'web', tablas: tablas),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('BarraNube: el aviso a los equipos no salió: $e');
    }
  }
}
