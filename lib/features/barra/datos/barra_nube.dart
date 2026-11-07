import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/instalacion_id.dart';
import '../../../core/utils/uuid_utils.dart';
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
}
