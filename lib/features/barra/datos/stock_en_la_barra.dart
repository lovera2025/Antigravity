import '../../../core/utils/uuid_utils.dart';
import '../cuentas/nombre_de_barra.dart';
import 'lectura_de_filas.dart';

/// Con cuánto arranca un producto en una barra de una fiesta, y desde cuánto se avisa
/// (`barra_stock_barras`, v83; decidido por el usuario el 25-nov-2026).
///
/// El jefe carga el stock general en PRECIOS (`barra_precios.stock_inicial`) y lo
/// **reparte**: la Barra 1 arranca con tanto y la Barra 2 con tanto. Lo que no reparte
/// es el depósito. El aviso ("Está quedando poco") lo pone **para cada barra**.
///
/// Una fila por fiesta, producto y barra, con id fijo
/// ([UuidUtils.barraStockBarraId]): si el jefe lo cambia desde dos equipos, escriben la
/// misma fila (gana la última), como `barra_precios`. Sacarla es [activo] en false: **no
/// se borra**.
class StockEnLaBarra {
  final String id;
  final String eventoId;
  final String productoId;

  /// El nombre de la barra, como lo elige la caja al abrirse ("Barra 1").
  final String barra;
  final int arranque;

  /// Desde cuántas que quedan se le avisa al repositor. Null: no avisa.
  final int? aviso;
  final bool activo;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const StockEnLaBarra({
    required this.id,
    required this.eventoId,
    required this.productoId,
    required this.barra,
    required this.arranque,
    this.aviso,
    this.activo = true,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Con cuánto arranca [productoId] en [barra]. Un arranque o un aviso negativos, o
  /// una barra sin nombre, no se guardan.
  factory StockEnLaBarra.para({
    required String eventoId,
    required String productoId,
    required String barra,
    required int arranque,
    int? aviso,
    bool activo = true,
    required DateTime ahora,
  }) {
    final nombre = barra.trim().replaceAll(RegExp(r'\s+'), ' ');
    _validar(nombre, arranque, aviso);
    final iso = isoDe(ahora);
    return StockEnLaBarra(
      id: UuidUtils.barraStockBarraId(eventoId, productoId, claveDeBarra(nombre)),
      eventoId: eventoId,
      productoId: productoId,
      barra: nombre,
      arranque: arranque,
      aviso: aviso,
      activo: activo,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  static void _validar(String barra, int arranque, int? aviso) {
    if (barra.isEmpty || esElDeposito(barra)) {
      throw ArgumentError.value(barra, 'barra', 'hace falta el nombre de la barra');
    }
    if (arranque < 0) {
      throw ArgumentError.value(arranque, 'arranque', 'no puede ser negativo');
    }
    if (aviso != null && aviso < 0) {
      throw ArgumentError.value(aviso, 'aviso', 'no puede ser negativo');
    }
  }

  /// Lo mismo con otro arranque, aviso o estado. [sinAviso] saca el aviso.
  StockEnLaBarra conCambios({int? arranque, int? aviso, bool sinAviso = false, bool? activo}) {
    final a = arranque ?? this.arranque;
    final v = sinAviso ? null : (aviso ?? this.aviso);
    _validar(barra, a, v);
    return StockEnLaBarra(
      id: id,
      eventoId: eventoId,
      productoId: productoId,
      barra: barra,
      arranque: a,
      aviso: v,
      activo: activo ?? this.activo,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  StockEnLaBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      StockEnLaBarra(
        id: id,
        eventoId: eventoId,
        productoId: productoId,
        barra: barra,
        arranque: arranque,
        aviso: aviso,
        activo: activo,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'producto_id': productoId,
        'barra': barra,
        'arranque': arranque,
        'aviso': aviso,
        'activo': activo ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory StockEnLaBarra.fromMap(Map<String, dynamic> m) => StockEnLaBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        productoId: comoTexto(m['producto_id']),
        barra: comoTexto(m['barra']).trim(),
        arranque: comoInt(m['arranque']),
        aviso: comoIntONull(m['aviso']),
        activo: comoBool(m['activo']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
