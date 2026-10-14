import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../plano/modelo/armado_salon.dart';

/// El camino que dibuja el tótem desde el ingreso hasta la mesa de una
/// familia: **por los pasillos, sin pisar otras mesas** ni el escenario, la
/// pasarela, las barras, las cajas o los baños.
///
/// Busca el paso en una grilla de la hoja (búsqueda A*, de a medio radio de
/// mesa), lo endereza en pocos tramos y lo termina en el borde de la mesa. Si
/// no encuentra paso, va en línea recta: mejor una guía recta que ninguna.
///
/// Sin pantalla ni base, en coordenadas del plano.
abstract final class CaminoALaMesa {
  /// Lo que ocupa una mesa con sus sillas, en radios de mesa.
  static const double conSillas = 1.35;

  /// Dónde termina el camino: apenas afuera del borde de la mesa.
  static const double alBorde = 1.05;

  /// Lo que no se pisa, además de las mesas.
  static const _sectoresQueTapan = {
    TipoSector.escenario,
    TipoSector.pasarela,
    TipoSector.barra,
    TipoSector.cajas,
    TipoSector.banos,
  };

  /// La grilla más grande que se arma: de sobra para un playón de 284 mesas.
  static const _maxCeldas = 120000;

  /// De dónde sale el camino en [hoja]: el ingreso del armado si está en esa
  /// hoja; si no, el centro del sector "Ingreso" de la hoja. Null: no hay.
  static Offset? ingresoEn(ArmadoSalon armado, String hoja) {
    final i = armado.ingreso;
    if (i != null && i.hoja == hoja) return Offset(i.x, i.y);
    for (final s in armado.sectoresDeHoja(hoja)) {
      if (s.tipo == TipoSector.ingreso) {
        return Offset(s.caja.centroX, s.caja.centroY);
      }
    }
    return null;
  }

  /// El camino hasta el borde de la mesa [mesa], desde el ingreso de su hoja.
  /// Null si la mesa no está o su hoja no tiene ingreso.
  static List<Offset>? trazar(ArmadoSalon armado, int mesa) {
    final m = armado.mesa(mesa);
    if (m == null) return null;
    final h = armado.hoja(m.hoja);
    final desde = ingresoEn(armado, m.hoja);
    if (h == null || desde == null) return null;
    final destino = Offset(m.x, m.y);
    final grilla = _Grilla.de(armado, h, mesa);
    final celdas = grilla.buscar(desde, destino);
    final puntos = celdas == null
        ? [desde, destino]
        : grilla.enderezar([
            desde,
            for (final c in celdas.skip(1).take(math.max(0, celdas.length - 2)))
              grilla.centro(c),
            destino,
          ]);
    return _desdeElBorde(
      _hastaElBorde(puntos, destino, armado.radio * alBorde),
      _sectorIngreso(armado, m.hoja, desde),
    );
  }

  /// El sector "Ingreso" de la hoja que tiene adentro el punto de salida.
  static RectPlano? _sectorIngreso(ArmadoSalon armado, String hoja, Offset p) {
    for (final s in armado.sectoresDeHoja(hoja)) {
      final c = s.caja;
      if (s.tipo == TipoSector.ingreso &&
          p.dx >= c.x &&
          p.dx <= c.derecha &&
          p.dy >= c.y &&
          p.dy <= c.abajo) {
        return c;
      }
    }
    return null;
  }

  /// Si sale de adentro del cartel del ingreso, arranca en su borde: así no
  /// tacha lo que dice.
  static List<Offset> _desdeElBorde(List<Offset> puntos, RectPlano? sector) {
    if (sector == null || puntos.length < 2) return puntos;
    final a = puntos[0];
    final b = puntos[1];
    final d = b - a;
    double salida(double desde, double paso, double menor, double mayor) =>
        paso > 0
            ? (mayor - desde) / paso
            : paso < 0
                ? (menor - desde) / paso
                : double.infinity;
    final t = math.min(
      salida(a.dx, d.dx, sector.x, sector.derecha),
      salida(a.dy, d.dy, sector.y, sector.abajo),
    );
    if (t >= 1) return puntos.length > 2 ? puntos.sublist(1) : puntos;
    return [Offset.lerp(a, b, t)!, ...puntos.skip(1)];
  }

  /// Corta el camino donde entra en la mesa: termina en su borde.
  static List<Offset> _hastaElBorde(
    List<Offset> puntos,
    Offset mesa,
    double borde,
  ) {
    final r = [
      for (final p in puntos)
        if ((p - mesa).distance > borde) p,
    ];
    if (r.isEmpty) return puntos;
    final ultimo = r.last;
    final hacia = mesa - ultimo;
    final largo = hacia.distance;
    if (largo > borde) r.add(mesa - hacia / largo * borde);
    return r;
  }
}

/// La hoja partida en celdas, con lo que no se pisa marcado.
class _Grilla {
  final double x0;
  final double y0;
  final double paso;
  final int columnas;
  final int filas;
  final List<bool> tapada;

  _Grilla._(this.x0, this.y0, this.paso, this.columnas, this.filas)
      : tapada = List.filled(columnas * filas, false);

  factory _Grilla.de(ArmadoSalon armado, HojaPlano h, int destino) {
    var paso = armado.radio * 0.5;
    while ((h.caja.ancho / paso).ceil() * (h.caja.alto / paso).ceil() >
        CaminoALaMesa._maxCeldas) {
      paso *= 1.25;
    }
    final g = _Grilla._(
      h.caja.x,
      h.caja.y,
      paso,
      math.max(1, (h.caja.ancho / paso).ceil()),
      math.max(1, (h.caja.alto / paso).ceil()),
    );
    final r = armado.radio * CaminoALaMesa.conSillas;
    for (final m in armado.mesasDeHoja(h.id)) {
      if (m.numero == destino) continue;
      g._taparCirculo(Offset(m.x, m.y), r);
    }
    for (final s in armado.sectoresDeHoja(h.id)) {
      if (CaminoALaMesa._sectoresQueTapan.contains(s.tipo)) {
        g._taparRect(s.caja.x, s.caja.y, s.caja.derecha, s.caja.abajo);
      }
    }
    return g;
  }

  int _col(double x) => ((x - x0) / paso).floor().clamp(0, columnas - 1);
  int _fila(double y) => ((y - y0) / paso).floor().clamp(0, filas - 1);
  int celda(Offset p) => _fila(p.dy) * columnas + _col(p.dx);

  Offset centro(int c) => Offset(
        x0 + (c % columnas + 0.5) * paso,
        y0 + (c ~/ columnas + 0.5) * paso,
      );

  void _taparCirculo(Offset c, double r) {
    for (var f = _fila(c.dy - r); f <= _fila(c.dy + r); f++) {
      for (var k = _col(c.dx - r); k <= _col(c.dx + r); k++) {
        if ((centro(f * columnas + k) - c).distance < r) {
          tapada[f * columnas + k] = true;
        }
      }
    }
  }

  void _taparRect(double x1, double y1, double x2, double y2) {
    for (var f = _fila(y1); f <= _fila(y2); f++) {
      for (var k = _col(x1); k <= _col(x2); k++) {
        tapada[f * columnas + k] = true;
      }
    }
  }

  /// Las celdas de [desde] a [hasta], o null si no hay paso. La de salida y la
  /// de llegada nunca cuentan como tapadas: el ingreso puede caer junto a una
  /// mesa, y la mesa de destino no se tapa.
  List<int>? buscar(Offset desde, Offset hasta) {
    final inicio = celda(desde);
    final fin = celda(hasta);
    final n = columnas * filas;
    final g = List<double>.filled(n, double.infinity);
    final de = List<int>.filled(n, -1);
    final cerrada = List<bool>.filled(n, false);
    final cola = _Monticulo();
    final fc = fin % columnas;
    final ff = fin ~/ columnas;
    double h(int c) {
      final dx = (c % columnas - fc).abs();
      final dy = (c ~/ columnas - ff).abs();
      return math.max(dx, dy) + (math.sqrt2 - 1) * math.min(dx, dy);
    }

    bool libre(int c) => c == inicio || c == fin || !tapada[c];

    g[inicio] = 0;
    cola.poner(inicio, h(inicio));
    while (cola.hayAlgo) {
      final c = cola.sacar();
      if (cerrada[c]) continue;
      if (c == fin) {
        final camino = <int>[c];
        var k = c;
        while (de[k] != -1) {
          k = de[k];
          camino.add(k);
        }
        return camino.reversed.toList();
      }
      cerrada[c] = true;
      final cx = c % columnas;
      final cy = c ~/ columnas;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= columnas || ny >= filas) continue;
          final v = ny * columnas + nx;
          if (cerrada[v] || !libre(v)) continue;
          // En diagonal, sin cortar la esquina de algo tapado.
          if (dx != 0 &&
              dy != 0 &&
              (!libre(cy * columnas + nx) || !libre(ny * columnas + cx))) {
            continue;
          }
          final nuevo = g[c] + (dx != 0 && dy != 0 ? math.sqrt2 : 1);
          if (nuevo < g[v]) {
            g[v] = nuevo;
            de[v] = c;
            cola.poner(v, nuevo + h(v));
          }
        }
      }
    }
    return null;
  }

  /// Si se puede ir derecho de [a] a [b] sin pasar por nada tapado.
  bool _derecho(Offset a, Offset b, {required int salvoA, required int salvoB}) {
    final largo = (b - a).distance;
    final pasos = math.max(1, (largo / (paso * 0.4)).ceil());
    for (var i = 0; i <= pasos; i++) {
      final c = celda(Offset.lerp(a, b, i / pasos)!);
      if (c == salvoA || c == salvoB) continue;
      if (tapada[c]) return false;
    }
    return true;
  }

  /// Saca los puntos de más: desde cada punto, salta al más lejano al que se
  /// llega derecho.
  List<Offset> enderezar(List<Offset> puntos) {
    if (puntos.length <= 2) return puntos;
    final salida = celda(puntos.first);
    final llegada = celda(puntos.last);
    final r = <Offset>[puntos.first];
    var i = 0;
    while (i < puntos.length - 1) {
      var j = puntos.length - 1;
      while (j > i + 1 &&
          !_derecho(puntos[i], puntos[j], salvoA: salida, salvoB: llegada)) {
        j--;
      }
      r.add(puntos[j]);
      i = j;
    }
    return r;
  }
}

/// Una cola de prioridad mínima: la celda con menor costo estimado primero.
class _Monticulo {
  final _celdas = <int>[];
  final _costos = <double>[];

  bool get hayAlgo => _celdas.isNotEmpty;

  void poner(int celda, double costo) {
    _celdas.add(celda);
    _costos.add(costo);
    var i = _celdas.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_costos[p] <= _costos[i]) break;
      _cambiar(i, p);
      i = p;
    }
  }

  int sacar() {
    final primera = _celdas.first;
    final ultimaCelda = _celdas.removeLast();
    final ultimoCosto = _costos.removeLast();
    if (_celdas.isNotEmpty) {
      _celdas[0] = ultimaCelda;
      _costos[0] = ultimoCosto;
      var i = 0;
      while (true) {
        final a = 2 * i + 1;
        final b = a + 1;
        var menor = i;
        if (a < _celdas.length && _costos[a] < _costos[menor]) menor = a;
        if (b < _celdas.length && _costos[b] < _costos[menor]) menor = b;
        if (menor == i) break;
        _cambiar(i, menor);
        i = menor;
      }
    }
    return primera;
  }

  void _cambiar(int a, int b) {
    final c = _celdas[a];
    _celdas[a] = _celdas[b];
    _celdas[b] = c;
    final k = _costos[a];
    _costos[a] = _costos[b];
    _costos[b] = k;
  }
}
