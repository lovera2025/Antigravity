// Arnés manual: cuánto se desvía el camino del tótem en cada mesa, comparado
// con lo más corto que se puede caminar en escuadra sin pisar ninguna mesa
// (entre sillas sí). En el salón de la Normal y en dos playones a medida, con
// las mesas a 2 m y a 2,5 m: el camino sale de cómo está armado cada plano.
//
//   flutter test tool/caminos_rodeo_test.dart
//
// Imprime las medidas de cada salón (lo que queda libre entre columnas y entre
// filas, contando las sillas) y las mesas con más rodeo.

// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/totem/services/camino_a_la_mesa.dart';

double _largo(List<Offset> p) {
  var s = 0.0;
  for (var i = 1; i < p.length; i++) {
    s += (p[i] - p[i - 1]).distance;
  }
  return s;
}

const _tapan = {
  TipoSector.escenario,
  TipoSector.pasarela,
  TipoSector.barra,
  TipoSector.cajas,
  TipoSector.banos,
};

/// Lo más corto caminando a lo largo y a lo ancho por una grilla fina, sin
/// pisar ninguna mesa (entre sillas sí) ni lo que tapa, sin costos extra: la
/// referencia, en escuadra como el camino. Una sola búsqueda por hoja, desde
/// el ingreso a todas las celdas.
Map<int, double> _masCortoATodas(ArmadoSalon a, String hoja) {
  final h = a.hoja(hoja)!;
  final desde = CaminoALaMesa.ingresoEn(a, hoja)!;
  final paso = a.radio * 0.25;
  final cols = (h.caja.ancho / paso).ceil();
  final filas = (h.caja.alto / paso).ceil();
  Offset centro(int c) =>
      Offset(h.caja.x + (c % cols + 0.5) * paso, h.caja.y + (c ~/ cols + 0.5) * paso);
  int celda(Offset p) =>
      ((p.dy - h.caja.y) / paso).floor().clamp(0, filas - 1) * cols +
      ((p.dx - h.caja.x) / paso).floor().clamp(0, cols - 1);
  final tapada = List<bool>.filled(cols * filas, false);
  for (final o in a.mesasDeHoja(hoja)) {
    final r = a.radio * 1.15;
    for (var c = 0; c < tapada.length; c++) {
      if (!tapada[c] && (centro(c) - Offset(o.x, o.y)).distance < r) tapada[c] = true;
    }
  }
  for (final s in a.sectoresDeHoja(hoja)) {
    if (!_tapan.contains(s.tipo)) continue;
    for (var c = 0; c < tapada.length; c++) {
      final p = centro(c);
      if (p.dx >= s.caja.x && p.dx <= s.caja.derecha && p.dy >= s.caja.y && p.dy <= s.caja.abajo) {
        tapada[c] = true;
      }
    }
  }
  final dist = List<int>.filled(cols * filas, -1);
  final inicio = celda(desde);
  dist[inicio] = 0;
  final cola = Queue<int>()..add(inicio);
  while (cola.isNotEmpty) {
    final c = cola.removeFirst();
    final cx = c % cols, cy = c ~/ cols;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = cx + dx, ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= cols || ny >= filas) continue;
      final v = ny * cols + nx;
      if (dist[v] != -1 || tapada[v]) continue;
      dist[v] = dist[c] + 1;
      cola.add(v);
    }
  }
  // A cada mesa se llega hasta alguna celda de su borde.
  final r = <int, double>{};
  for (final m in a.mesasDeHoja(hoja)) {
    var mejor = -1;
    final borde = a.radio * 1.3;
    for (var c = 0; c < tapada.length; c++) {
      if (dist[c] < 0) continue;
      if ((centro(c) - Offset(m.x, m.y)).distance <= borde && (mejor < 0 || dist[c] < mejor)) {
        mejor = dist[c];
      }
    }
    if (mejor >= 0) r[m.numero] = mejor * paso;
  }
  return r;
}

void _medir(String nombre, ArmadoSalon a) {
  final mesas = a.mesas;
  List<double> valores(Iterable<double> v) =>
      v.map((x) => (x / 4).round() * 4.0).toSet().toList()..sort();
  String huecos(List<double> v) => [
        for (var i = 1; i < v.length && i < 10; i++)
          a.aMetros(v[i] - v[i - 1] - 2 * a.radio * CaminoALaMesa.conSillas).toStringAsFixed(2),
      ].join(' ');
  print('── $nombre: mesa de ${a.aMetros(2 * a.radio).toStringAsFixed(2)} m');
  print('   libre entre columnas (m): ${huecos(valores(mesas.map((m) => m.x)))}');
  print('   libre entre filas (m): ${huecos(valores(mesas.map((m) => m.y)))}');
  final filas = <(int, double, double)>[];
  for (final hoja in a.hojas) {
    if (CaminoALaMesa.ingresoEn(a, hoja.id) == null) continue;
    final cortos = _masCortoATodas(a, hoja.id);
    for (final m in a.mesasDeHoja(hoja.id)) {
      final ruta = CaminoALaMesa.trazar(a, m.numero);
      final corto = cortos[m.numero];
      if (ruta == null || corto == null || corto <= 0) continue;
      filas.add((m.numero, a.aMetros(_largo(ruta)), a.aMetros(corto)));
    }
  }
  filas.sort((x, y) => (y.$2 / y.$3).compareTo(x.$2 / x.$3));
  final rodeos = filas.where((f) => f.$2 > f.$3 * 1.25).length;
  print('   ${filas.length} mesas; con más de 25 % de rodeo: $rodeos');
  for (final (n, largo, corto) in filas.take(6)) {
    print('   mesa $n: ${largo.toStringAsFixed(1)} m (lo más corto '
        '${corto.toStringAsFixed(1)} m, +${((largo / corto - 1) * 100).round()} %)');
  }
}

/// Un playón a medida con el Ingreso donde lo pone el salón vacío: abajo al
/// medio, adentro del hormigón.
ArmadoSalon _aMedida(double lugarM) {
  final a = ArmarAMedida.armar(
    OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 150, lugarM: lugarM),
  ).armado;
  final h = a.hojas.first;
  final pts = h.contorno!.puntos;
  final abajo = pts.map((p) => p.y).reduce(math.max);
  final medio =
      (pts.map((p) => p.x).reduce(math.min) + pts.map((p) => p.x).reduce(math.max)) / 2;
  return a.copyWith(sectores: [
    ...a.sectores,
    SectorPlano(
      tipo: TipoSector.ingreso,
      texto: 'Ingreso',
      hoja: h.id,
      caja: RectPlano(
        medio - a.aUnidades(2),
        abajo - a.aUnidades(2.5),
        a.aUnidades(4),
        a.aUnidades(2),
      ),
    ),
  ]);
}

void main() {
  test('rodeos', () {
    _medir('Normal (Canva)', ArmadosPredefinidos.normal2aPagina3());
    _medir('Playón a medida, 2 m', _aMedida(2));
    _medir('Playón a medida, 2,5 m', _aMedida(2.5));
  });
}
