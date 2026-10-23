import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../../plano/modelo/armado_salon.dart';

/// El camino que dibuja el tótem desde el ingreso hasta la mesa de una
/// familia: **por los pasillos, sin pisar otras mesas** ni el escenario, la
/// pasarela, las barras, las cajas o los baños.
///
/// Busca el paso en una grilla de la hoja (búsqueda A*, de a medio radio de
/// mesa) y lo termina en el borde de la mesa. Si no encuentra paso, va en
/// línea recta: mejor una guía recta que ninguna.
///
/// **En escuadra** (6.2.1, a pedido del usuario: "queda como rayas, muy
/// desprolijo"; "línea recta y que doble, queda más simétrico"): antes iba por
/// el atajo más corto, rozando las mesas y doblando en cualquier ángulo. Ahora
/// va **solo derecho, a lo largo o a lo ancho, y dobla en ángulo recto**: por
/// el medio de los pasillos (cada celda cuesta más cuanto más cerca de algo
/// tapado está) y lo menos posible (cada vuelta cuesta). Sale alineado con el
/// ingreso y entra alineado con el centro de la mesa. La esquina apenas
/// suavizada y la flecha las pone el dibujo (`PintorResaltado`).
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
        : _enEscuadra(
            grilla.sinEscalones(
              grilla.esquinas(celdas),
              salida: celdas.first,
              llegada: celdas.last,
            ),
            desde,
            destino,
          );
    return _desdeElBorde(
      _hastaElBorde(puntos, destino, armado.radio * alBorde),
      _sectorIngreso(armado, m.hoja, desde),
    );
  }

  /// Las esquinas del camino (centros de celdas), con la punta de salida en el
  /// ingreso y la de llegada en el centro de la mesa. El primer tramo se corre
  /// para quedar alineado con el ingreso, y el último con la mesa: así todo
  /// sigue en escuadra (se corren menos de media celda). Con un solo tramo
  /// derecho, va del ingreso a la mesa.
  static List<Offset> _enEscuadra(
    List<Offset> esquinas,
    Offset desde,
    Offset destino,
  ) {
    if (esquinas.length <= 2) return [desde, destino];
    bool aLoAncho(Offset a, Offset b) => (a.dy - b.dy).abs() < (a.dx - b.dx).abs();
    final n = esquinas.length;
    final saleAlAncho = aLoAncho(esquinas[0], esquinas[1]);
    final llegaAlAncho = aLoAncho(esquinas[n - 2], esquinas[n - 1]);
    final r = [...esquinas];
    r[0] = desde;
    r[1] = saleAlAncho ? Offset(r[1].dx, desde.dy) : Offset(desde.dx, r[1].dy);
    r[n - 1] = destino;
    r[n - 2] = llegaAlAncho
        ? Offset(r[n - 2].dx, destino.dy)
        : Offset(destino.dx, r[n - 2].dy);
    return r;
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

/// La hoja partida en celdas, con lo que no se pisa marcado y, en cada celda,
/// lo lejos que está de algo tapado.
class _Grilla {
  final double x0;
  final double y0;
  final double paso;
  final int columnas;
  final int filas;
  final List<bool> tapada;

  /// Cuántas celdas hay hasta lo tapado más cercano (0: tapada). Se llena en
  /// [_medirHolgura], después de tapar todo.
  late final Float64List holgura;

  /// Las celdas del cartel del ingreso: se pueden pisar, pero cuestan, así el
  /// camino sale del cartel enseguida y no lo recorre por adentro.
  final Uint8List enIngreso;

  _Grilla._(this.x0, this.y0, this.paso, this.columnas, this.filas)
      : tapada = List.filled(columnas * filas, false),
        enIngreso = Uint8List(columnas * filas);

  /// Lo que cuesta cada paso adentro del cartel del ingreso.
  static const _porElCartel = 3.0;

  /// La holgura que se busca: con tanto lugar a los dos lados, el camino va
  /// por el medio del pasillo. En celdas de medio radio: un radio y medio.
  static const _holguraBuscada = 3.0;

  /// Lo que cuesta pasar pegado a algo tapado, además del paso: con holgura
  /// cero, el paso cuesta el triple.
  static const _pesoHolgura = 2.0;

  /// Lo que cuesta doblar en ángulo recto, en pasos: el camino dobla poco.
  static const _doblar = 4.0;

  /// Lo que cuesta volverse: casi nunca.
  static const _volverse = 30.0;

  /// Las cuatro direcciones, en orden alrededor: solo a lo largo y a lo ancho.
  static const _dx = [1, 0, -1, 0];
  static const _dy = [0, 1, 0, -1];

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
      } else if (s.tipo == TipoSector.ingreso) {
        for (var f = g._fila(s.caja.y); f <= g._fila(s.caja.abajo); f++) {
          for (var k = g._col(s.caja.x); k <= g._col(s.caja.derecha); k++) {
            g.enIngreso[f * g.columnas + k] = 1;
          }
        }
      }
    }
    g._medirHolgura();
    return g;
  }

  /// La distancia de cada celda a lo tapado más cercano, en dos pasadas
  /// (derecho cuesta 3, en diagonal 4: un tercio de celda de error a lo sumo).
  /// Sin nada tapado, todo queda con holgura de sobra.
  void _medirHolgura() {
    const lejos = 1 << 20;
    final d = Int32List(columnas * filas);
    for (var i = 0; i < d.length; i++) {
      d[i] = tapada[i] ? 0 : lejos;
    }
    void mirar(int i, int x, int y, int peso) {
      if (x < 0 || y < 0 || x >= columnas || y >= filas) return;
      final v = d[y * columnas + x] + peso;
      if (v < d[i]) d[i] = v;
    }

    for (var y = 0; y < filas; y++) {
      for (var x = 0; x < columnas; x++) {
        final i = y * columnas + x;
        mirar(i, x - 1, y, 3);
        mirar(i, x - 1, y - 1, 4);
        mirar(i, x, y - 1, 3);
        mirar(i, x + 1, y - 1, 4);
      }
    }
    for (var y = filas - 1; y >= 0; y--) {
      for (var x = columnas - 1; x >= 0; x--) {
        final i = y * columnas + x;
        mirar(i, x + 1, y, 3);
        mirar(i, x + 1, y + 1, 4);
        mirar(i, x, y + 1, 3);
        mirar(i, x - 1, y + 1, 4);
      }
    }
    holgura = Float64List(d.length);
    for (var i = 0; i < d.length; i++) {
      holgura[i] = d[i] / 3;
    }
  }

  /// Lo que se agrega al paso por pasar por [c]: nada con holgura de sobra.
  double _apretado(int c) =>
      _pesoHolgura *
      math.max(0.0, _holguraBuscada - holgura[c]) /
      _holguraBuscada;

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
  ///
  /// Solo a lo largo y a lo ancho. Cada paso cuesta uno, más lo apretado de la
  /// celda ([_apretado]), más lo que cuesta doblar ([_doblar]): la búsqueda va
  /// por celda y por dirección de llegada.
  List<int>? buscar(Offset desde, Offset hasta) {
    final inicio = celda(desde);
    final fin = celda(hasta);
    final estados = columnas * filas * 4;
    final g = Float64List(estados)..fillRange(0, estados, double.infinity);
    final de = Int32List(estados)..fillRange(0, estados, -1);
    final cerrado = Uint8List(estados);
    final cola = _Monticulo();
    final fc = fin % columnas;
    final ff = fin ~/ columnas;
    double h(int c) =>
        ((c % columnas - fc).abs() + (c ~/ columnas - ff).abs()).toDouble();

    bool libre(int c) => c == inicio || c == fin || !tapada[c];

    // Al salir, para cualquier lado sin doblar.
    for (var d = 0; d < 4; d++) {
      g[inicio * 4 + d] = 0;
      cola.poner(inicio * 4 + d, h(inicio));
    }
    while (cola.hayAlgo) {
      final s = cola.sacar();
      if (cerrado[s] == 1) continue;
      final c = s ~/ 4;
      if (c == fin) {
        final camino = <int>[c];
        var k = s;
        while (de[k] != -1) {
          k = de[k];
          if (k ~/ 4 != camino.last) camino.add(k ~/ 4);
        }
        return camino.reversed.toList();
      }
      cerrado[s] = 1;
      final dir = s % 4;
      final cx = c % columnas;
      final cy = c ~/ columnas;
      for (var nd = 0; nd < 4; nd++) {
        final nx = cx + _dx[nd];
        final ny = cy + _dy[nd];
        if (nx < 0 || ny < 0 || nx >= columnas || ny >= filas) continue;
        final v = ny * columnas + nx;
        if (!libre(v)) continue;
        final t = v * 4 + nd;
        if (cerrado[t] == 1) continue;
        final giro = (nd - dir).abs();
        final vuelta = giro == 0 ? 0.0 : (giro == 2 ? _volverse : _doblar);
        final cartel = enIngreso[v] == 1 ? _porElCartel : 0.0;
        final nuevo = g[s] + 1 + _apretado(v) + vuelta + cartel;
        if (nuevo < g[t]) {
          g[t] = nuevo;
          de[t] = s;
          cola.poner(t, nuevo + h(v));
        }
      }
    }
    return null;
  }

  /// Los centros de las celdas donde el camino dobla, con la primera y la
  /// última.
  List<Offset> esquinas(List<int> celdas) {
    final r = <Offset>[centro(celdas.first)];
    for (var i = 1; i < celdas.length - 1; i++) {
      if (celdas[i] - celdas[i - 1] != celdas[i + 1] - celdas[i]) {
        r.add(centro(celdas[i]));
      }
    }
    r.add(centro(celdas.last));
    return r;
  }

  /// Si se puede ir derecho de [a] a [b] (a lo largo o a lo ancho) sin pisar
  /// nada ni pasar pegado: con una celda libre alrededor, salvo en las de
  /// [salida] y [llegada].
  bool _libreEntre(Offset a, Offset b, int salida, int llegada) {
    final largo = (b - a).distance;
    final pasos = math.max(1, (largo / (paso * 0.4)).ceil());
    for (var i = 0; i <= pasos; i++) {
      final c = celda(Offset.lerp(a, b, i / pasos)!);
      if (c == salida || c == llegada) continue;
      if (tapada[c] || holgura[c] < 1) return false;
    }
    return true;
  }

  /// Saca los escalones: donde el camino va, se corre un poco y sigue para el
  /// mismo lado (una Z), prueba de hacer la corrida al principio o al final de
  /// ese tramo, sin pisar nada. Cada escalón que se va son dos vueltas menos.
  /// La salida y la llegada no se mueven.
  List<Offset> sinEscalones(
    List<Offset> esquinas, {
    required int salida,
    required int llegada,
  }) {
    var r = [...esquinas];
    bool aLoAncho(Offset a, Offset b) => (a.dy - b.dy).abs() < (a.dx - b.dx).abs();
    // Saca las esquinas que quedaron en el medio de un tramo derecho.
    List<Offset> derecho(List<Offset> p) {
      final s = <Offset>[p.first];
      for (var i = 1; i < p.length - 1; i++) {
        final a = s.last, b = p[i], c = p[i + 1];
        final mismoLado = (a.dx - b.dx).abs() < 1e-6 && (b.dx - c.dx).abs() < 1e-6 ||
            (a.dy - b.dy).abs() < 1e-6 && (b.dy - c.dy).abs() < 1e-6;
        if (!mismoLado && b != a) s.add(b);
      }
      s.add(p.last);
      return s;
    }

    var cambio = true;
    while (cambio) {
      cambio = false;
      for (var i = 0; i + 3 < r.length; i++) {
        final a = r[i], b = r[i + 1], c = r[i + 2], d = r[i + 3];
        final ancho = aLoAncho(a, b);
        // Una Z: dos tramos para el mismo lado unidos por una corrida.
        if (ancho != aLoAncho(c, d) || ancho == aLoAncho(b, c)) continue;
        final mismoSentido = ancho
            ? (b.dx - a.dx).sign == (d.dx - c.dx).sign
            : (b.dy - a.dy).sign == (d.dy - c.dy).sign;
        if (!mismoSentido) continue;
        // La corrida al principio: de a se corre a la línea de c y d.
        final alPrincipio = ancho ? Offset(a.dx, c.dy) : Offset(c.dx, a.dy);
        // O al final: de a derecho hasta la altura de d, y ahí la corrida.
        final alFinal = ancho ? Offset(d.dx, a.dy) : Offset(a.dx, d.dy);
        List<Offset>? nuevo;
        if (_libreEntre(a, alPrincipio, salida, llegada) &&
            _libreEntre(alPrincipio, d, salida, llegada)) {
          nuevo = [a, alPrincipio, d];
        } else if (_libreEntre(a, alFinal, salida, llegada) &&
            _libreEntre(alFinal, d, salida, llegada)) {
          nuevo = [a, alFinal, d];
        }
        if (nuevo != null) {
          r = derecho([...r.sublist(0, i), ...nuevo, ...r.sublist(i + 4)]);
          cambio = true;
          break;
        }
      }
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
