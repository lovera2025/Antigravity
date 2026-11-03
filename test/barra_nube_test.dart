import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/barra/datos/barra_nube.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// La barra del jefe en la web: lee y escribe directo en la nube. Con una nube
/// simulada (como `puesta_al_dia_nube_test.dart`): no sale nada de la PC.
const _evento = 'e0000000-0000-4000-8000-000000000001';

class _Pedido {
  final String metodo;
  final String tabla;
  final Map<String, List<String>> params;
  final Map<String, String> encabezados;
  final Object? cuerpo;
  _Pedido(this.metodo, this.tabla, this.params, this.encabezados, this.cuerpo);
}

class _Nube {
  final pedidos = <_Pedido>[];

  /// Qué devuelve un GET a cada tabla, según desde qué fila pide.
  List<Map<String, Object?>> Function(String tabla, int desde) filas = (_, _) => const [];
  bool falla = false;

  http.Client get cliente => MockClient((req) async {
        final tabla = req.url.pathSegments.last;
        pedidos.add(_Pedido(
          req.method,
          tabla,
          req.url.queryParametersAll,
          req.headers,
          req.body.isEmpty ? null : jsonDecode(req.body),
        ));
        if (falla) {
          return http.Response(jsonEncode({'message': 'sin red', 'code': '500'}), 500,
              headers: {'content-type': 'application/json'}, request: req);
        }
        final cuerpo = req.method == 'GET'
            ? filas(tabla, int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0)
            : const [];
        return http.Response(jsonEncode(cuerpo), req.method == 'GET' ? 200 : 201,
            headers: {'content-type': 'application/json'}, request: req);
      });
}

void main() {
  late _Nube nube;
  late BarraNube barra;
  final ahora = DateTime.utc(2026, 12, 4, 23, 41);

  setUp(() {
    nube = _Nube();
    final c = SupabaseClient('https://nube.test', 'anon-de-test', httpClient: nube.cliente);
    c.auth.stopAutoRefresh();
    addTearDown(c.dispose);
    barra = BarraNube(c, equipo: () async => 'web', reloj: () => ahora);
  });

  Map<String, Object?> filaProducto(int i, {int activo = 1}) => {
        'id': 'b0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        'nombre': 'Producto $i',
        'categoria': null,
        'activo': activo,
        'orden': 0,
        'imagen_url': null,
        'hecho_por': 'Jefe',
        'device_id': 'pc',
        'created_at': '2026-11-03T12:00:00+00:00',
        'updated_at': '2026-11-03T12:00:00+00:00',
      };

  test('los productos: solo los activos, ordenados, y lo que trae la nube se lee', () async {
    nube.filas = (tabla, _) => [filaProducto(1)];
    final lista = await barra.productos();
    expect(lista.single.nombre, 'Producto 1');
    expect(lista.single.categoria, '');
    final p = nube.pedidos.single;
    expect(p.metodo, 'GET');
    expect(p.tabla, 'barra_productos');
    expect(p.params['activo'], ['eq.1']);
    expect(p.params['order']!.single, startsWith('orden.asc'));

    nube.pedidos.clear();
    await barra.productos(conBajas: true);
    expect(nube.pedidos.single.params.containsKey('activo'), isFalse);
  });

  test('ninguna lista sale al revés: el paquete ordena de mayor a menor si no se le dice', () async {
    await barra.productos();
    await barra.precios(_evento);
    await barra.cajas(_evento);
    await barra.ventas(_evento);
    await barra.anulaciones(_evento);
    expect(nube.pedidos, hasLength(5));
    for (final p in nube.pedidos) {
      final orden = p.params['order']!.single;
      expect(orden, isNot(contains('desc')), reason: '${p.tabla}: $orden');
      expect(orden, contains('id.asc'), reason: '${p.tabla}: las páginas no se pisan');
    }
  });

  test('una fiesta con más de 1000 ventas trae todas, de a páginas', () async {
    nube.filas = (tabla, desde) => [
          for (var i = desde; i < (desde == 0 ? 1000 : 1003); i++)
            {
              'id': 'v$i',
              'caja_barra_id': 'c',
              'evento_id': _evento,
              'numero': i + 1,
              'renglones': '[]',
              'total': 1000,
              'medio': 'efectivo',
              'efectivo': 1000,
              'transferencia': 0,
              'recibe': null,
              'vuelto': 0,
              'recargo': 0,
              'recargo_pct': null,
              'created_at': '2026-12-04T23:00:00+00:00',
              'updated_at': '2026-12-04T23:00:00+00:00',
            },
        ];
    final ventas = await barra.ventas(_evento);
    expect(ventas, hasLength(1003));
    expect(nube.pedidos, hasLength(2));
    expect(nube.pedidos.first.params['evento_id'], ['eq.$_evento']);
    expect(nube.pedidos.last.params['offset'], ['1000']);
    expect(ventas.last.total, 1000);
  });

  test('guardar un producto lo sube entero, sellado por la web', () async {
    final p = await barra.guardarProducto(
      ProductoBarra.nuevo(nombre: 'Fernet', categoria: 'Tragos', ahora: ahora),
      quien: 'Jefe desde el iPhone',
    );
    expect(p.deviceId, 'web');
    final pedido = nube.pedidos.single;
    expect(pedido.metodo, 'POST');
    expect(pedido.tabla, 'barra_productos');
    expect(pedido.encabezados['Prefer'], contains('resolution=merge-duplicates'));
    expect((pedido.cuerpo as Map)['nombre'], 'Fernet');
    expect((pedido.cuerpo as Map)['hecho_por'], 'Jefe desde el iPhone');
  });

  test('guardar un precio va a su fila de id fijo', () async {
    final precio = PrecioBarra.para(
      eventoId: _evento,
      productoId: 'b0000000-0000-4000-8000-000000000001',
      precio: 3500,
      stockInicial: 240,
      ahora: ahora,
    );
    await barra.guardarPrecio(precio, quien: 'Jefe');
    final cuerpo = nube.pedidos.single.cuerpo as Map;
    expect(cuerpo['id'], precio.id);
    expect(cuerpo['stock_inicial'], 240);
  });

  group('anular desde la web', () {
    final venta = VentaBarra.nueva(
      cajaBarraId: 'c0000000-0000-4000-8000-000000000001',
      eventoId: _evento,
      numero: 17,
      renglones: const [RenglonVenta(productoId: 'p', nombre: 'Agua', precio: 1000, cantidad: 1)],
      medio: MedioBarra.efectivo,
      efectivo: 1000,
      ahora: DateTime.utc(2026, 12, 4, 23),
    );

    test('agrega la anulación sin tocar la venta, y si llega repetida no pisa la que hay', () async {
      final a = await barra.anular(venta, motivo: 'error de carga', quien: 'Jefe');
      expect(nube.pedidos.map((p) => '${p.metodo} ${p.tabla}'),
          ['GET barra_anulaciones', 'POST barra_anulaciones']);
      expect(nube.pedidos.any((p) => p.tabla == 'barra_ventas'), isFalse,
          reason: 'la venta no se toca');
      final post = nube.pedidos.last;
      expect(post.encabezados['Prefer'], contains('resolution=ignore-duplicates'));
      expect((post.cuerpo as Map)['id'], a.id);
      expect((post.cuerpo as Map)['motivo'], 'error de carga');
    });

    test('si ya estaba anulada, devuelve la que hay y no escribe', () async {
      final ya = AnulacionBarra.de(venta, motivo: 'la primera', hechoPor: 'Jefe en la PC', ahora: ahora);
      nube.filas = (tabla, _) => tabla == 'barra_anulaciones' ? [ya.toMap()] : const [];
      final a = await barra.anular(venta, motivo: 'otra', quien: 'Jefe');
      expect(a.motivo, 'la primera');
      expect(nube.pedidos.where((p) => p.metodo != 'GET'), isEmpty);
    });
  });

  test('en la web, un error de la nube se dice: no se esconde detrás de una lista vacía', () async {
    nube.falla = true;
    expect(barra.cajas(_evento), throwsA(isA<PostgrestException>()));
  });

  test('la web no vende ni abre cajas: no tiene cómo', () {
    expect(barra, isNot(isA<BarraDeLaCaja>()));
  });
}
