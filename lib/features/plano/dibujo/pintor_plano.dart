import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';

/// Cómo se acomoda una hoja del plano en un rectángulo de pantalla: se escala
/// para que entre entera y se centra.
@immutable
class EncuadrePlano {
  final double escala;
  final Offset desplazamiento;

  const EncuadrePlano(this.escala, this.desplazamiento);

  factory EncuadrePlano.de(RectPlano caja, Size size) {
    final s = math.min(size.width / caja.ancho, size.height / caja.alto);
    return EncuadrePlano(
      s,
      Offset(
        (size.width - caja.ancho * s) / 2 - caja.x * s,
        (size.height - caja.alto * s) / 2 - caja.y * s,
      ),
    );
  }

  Offset aPlano(Offset pantalla) => (pantalla - desplazamiento) / escala;
  Offset aPantalla(Offset plano) => plano * escala + desplazamiento;

  void aplicar(Canvas canvas) {
    canvas.translate(desplazamiento.dx, desplazamiento.dy);
    canvas.scale(escala);
  }
}

/// La mesa de [armado] (en [hoja]) bajo un punto de la pantalla, o null.
int? mesaEnPunto(ArmadoSalon armado, String hoja, Size size, Offset punto) {
  final h = armado.hoja(hoja);
  if (h == null) return null;
  final p = EncuadrePlano.de(h.caja, size).aPlano(punto);
  int? mejor;
  var mejorD = double.infinity;
  for (final m in armado.mesasDeHoja(hoja)) {
    final d = (Offset(m.x, m.y) - p).distance;
    if (d <= armado.radio * 1.1 && d < mejorD) {
      mejor = m.numero;
      mejorD = d;
    }
  }
  return mejor;
}

/// Radio con que se dibuja una mesa en este estilo (Arquitecto la achica para
/// que entren las sillas sin tocar a la de al lado).
double radioDibujo(ArmadoSalon armado, TemaPlano tema) =>
    armado.radio * tema.escalaMesa;

/// Las mesas de [numeros] que están en [hoja]. Lo que está resaltado en la
/// otra hoja no cuenta acá: ni apaga el resto ni lleva pulso.
Set<int> mesasEnHoja(ArmadoSalon armado, String hoja, Iterable<int> numeros) =>
    {
      for (final n in numeros)
        if (armado.mesa(n)?.hoja == hoja) n,
    };

/// Cuánto mide como mucho el apellido debajo de una mesa, en radios de
/// dibujo. Con mesas en columnas vecinas, más ancho se pisa con el de al lado.
const double anchoApellidoEnRadios = 2.15;

/// Alto de la letra del apellido, en radios de dibujo.
const double altoApellidoEnRadios = 0.42;

/// Dónde va el apellido de la mesa con centro [c]: debajo de ella (y de sus
/// sillas, si se dibujan), sin salirse de la [caja] de la hoja.
///
/// La usan los dos pintores: [PintorPlano] escribe el apellido adentro y
/// [PintorResaltado] recorta esa franja para que el anillo del pulso no lo
/// cruce.
Rect franjaApellido(
  Offset c,
  double r,
  RectPlano caja, {
  required bool conSillas,
}) {
  final ancho = math.min(r * anchoApellidoEnRadios, caja.ancho);
  final abajo = conSillas ? r + 17 : r + 6;
  final izquierda = (c.dx - ancho / 2).clamp(caja.x, caja.derecha - ancho);
  return Rect.fromLTWH(
    izquierda.toDouble(),
    c.dy + abajo,
    ancho,
    r * altoApellidoEnRadios,
  );
}

/// La familia cuyo apellido lleva esta mesa: la que la ocupa o, antes del
/// sorteo, la que la tiene fijada. Null si no lleva apellido.
OcupantePlano? familiaConApellido(InfoMesa info, NivelDetalle nivel) {
  if (!nivel.apellidos || !info.principal) return null;
  return info.ocupante ?? info.fijadaPara;
}

/// Las líneas de la grilla que cubren el rectángulo [visible] (en coordenadas
/// del plano): arrancan en el múltiplo de [paso] anterior, así la grilla llega
/// a todos los bordes sin terminar en dientes.
({List<double> xs, List<double> ys}) lineasGrilla(
  Rect visible, {
  double paso = 50,
}) {
  List<double> eje(double desde, double hasta) => [
        for (var v = (desde / paso).floor() * paso; v <= hasta; v += paso) v,
      ];
  return (
    xs: eje(visible.left, visible.right),
    ys: eje(visible.top, visible.bottom),
  );
}

/// Dibuja una hoja del plano en un estilo: fondo, sectores y mesas.
///
/// No anima nada: el pulso de lo resaltado y el camino van en
/// [PintorResaltado], encima, para no redibujar el salón entero en cada
/// cuadro.
class PintorPlano extends CustomPainter {
  PintorPlano({
    required this.armado,
    required this.hoja,
    required this.tema,
    required this.estado,
    this.resaltadas = const {},
    this.seleccionada,
  });

  final ArmadoSalon armado;
  final String hoja;
  final TemaPlano tema;
  final EstadoPlano estado;
  final Set<int> resaltadas;
  final int? seleccionada;

  final Map<String, TextPainter> _textos = {};

  /// Lo que está en foco en esta hoja. Una familia resaltada en la otra hoja
  /// no apaga esta.
  late final Set<int> _foco = mesasEnHoja(armado, hoja, {
    ...resaltadas,
    ?seleccionada,
  });

  bool _enFoco(int n) => _foco.contains(n);

  @override
  void paint(Canvas canvas, Size size) {
    final h = armado.hoja(hoja);
    canvas.drawRect(Offset.zero & size, Paint()..color = tema.fondo);
    if (h == null) return;
    final encuadre = EncuadrePlano.de(h.caja, size);
    final nivel = NivelDetalle.para(armado.radio * encuadre.escala);

    canvas.save();
    encuadre.aplicar(canvas);
    _grilla(
      canvas,
      Rect.fromPoints(
        encuadre.aPlano(Offset.zero),
        encuadre.aPlano(Offset(size.width, size.height)),
      ),
      encuadre.escala,
    );

    final sectores = armado.sectoresDeHoja(hoja);
    final escena = [for (final s in sectores) if (_esEscena(s)) s];
    for (final s in sectores) {
      if (!_esEscena(s)) _sector(canvas, s);
    }
    if (escena.isNotEmpty) _escenario(canvas, escena);
    if (nivel.etiquetas) {
      for (final s in sectores) {
        _rotulo(canvas, s);
      }
    }

    final mesas = armado.mesasDeHoja(hoja);
    if (_foco.isEmpty) {
      for (final m in mesas) {
        _mesa(canvas, m, nivel, h.caja);
      }
    } else {
      // Las que no están en foco van apagadas, todas en una sola capa. Debajo
      // de cada una va un disco del color del fondo: sin él, la grilla se ve
      // a través de la mesa.
      final r = radioDibujo(armado, tema);
      final fondo = Paint()..color = tema.fondo;
      for (final m in mesas) {
        if (!_enFoco(m.numero)) canvas.drawCircle(Offset(m.x, m.y), r, fondo);
      }
      canvas.saveLayer(
        Rect.fromLTWH(h.caja.x, h.caja.y, h.caja.ancho, h.caja.alto)
            .inflate(r * 2),
        Paint()..color = const Color(0x99000000),
      );
      for (final m in mesas) {
        if (!_enFoco(m.numero)) _mesa(canvas, m, nivel, h.caja);
      }
      canvas.restore();
      // Las resaltadas, encima.
      for (final m in mesas) {
        if (_enFoco(m.numero)) _mesa(canvas, m, nivel, h.caja);
      }
    }
    canvas.restore();
  }

  // ── Fondo y sectores ────────────────────────────────────────────────────

  void _grilla(Canvas canvas, Rect visible, double escala) {
    final c = tema.grilla;
    if (c == null) return;
    final lineas = lineasGrilla(visible);
    // Una miniatura muy chica tendría cientos de líneas que no se distinguen.
    if (lineas.xs.length + lineas.ys.length > 600) return;
    final p = Paint()
      ..color = c
      ..strokeWidth = 1.2 / escala;
    for (final x in lineas.xs) {
      canvas.drawLine(Offset(x, visible.top), Offset(x, visible.bottom), p);
    }
    for (final y in lineas.ys) {
      canvas.drawLine(Offset(visible.left, y), Offset(visible.right, y), p);
    }
  }

  bool _esEscena(SectorPlano s) =>
      s.tipo == TipoSector.escenario || s.tipo == TipoSector.pasarela;

  Rect _rect(SectorPlano s) =>
      Rect.fromLTWH(s.caja.x, s.caja.y, s.caja.ancho, s.caja.alto);

  void _sector(Canvas canvas, SectorPlano s) {
    final rrect = RRect.fromRectAndRadius(_rect(s), const Radius.circular(14));

    if (tema.estilo == EstiloPlano.neon) {
      canvas.drawRRect(rrect, Paint()..color = tema.sectorRelleno);
      _conBrillo(canvas, (p) => canvas.drawRRect(rrect, p),
          color: tema.sectorBorde, ancho: 3);
      // El halo solo no alcanza: sin una línea nítida el sector no tiene borde.
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = Color.lerp(tema.sectorBorde, Colors.white, 0.25)!,
      );
      return;
    }
    canvas.drawRRect(rrect, Paint()..color = tema.sectorRelleno);
    if (tema.estilo == EstiloPlano.arquitecto) {
      _rayado(canvas, rrect, tema.sectorBorde.withValues(alpha: 0.35));
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tema.estilo == EstiloPlano.gala ? 1.6 : 2
        ..color = tema.sectorBorde,
    );
  }

  /// El escenario y la pasarela, en una sola figura: así la T queda unida, sin
  /// la línea ni la muesca de las esquinas donde se tocan.
  void _escenario(Canvas canvas, List<SectorPlano> escena) {
    var figura = Path();
    for (final s in escena) {
      final parte = Path()
        ..addRRect(RRect.fromRectAndRadius(_rect(s), const Radius.circular(6)));
      figura = Path.combine(PathOperation.union, figura, parte);
    }

    if (tema.estilo == EstiloPlano.neon) {
      canvas.drawPath(
        figura,
        Paint()..color = tema.escenario.withValues(alpha: 0.32),
      );
      _conBrillo(canvas, (p) => canvas.drawPath(figura, p),
          color: tema.escenario, ancho: 3);
      canvas.drawPath(
        figura,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(tema.escenario, Colors.white, 0.35)!,
      );
      return;
    }
    canvas.drawPath(figura, Paint()..color = tema.escenario);
    canvas.drawPath(
      figura,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tema.estilo == EstiloPlano.gala ? 1.6 : 2
        ..strokeJoin = StrokeJoin.round
        ..color = tema.escenario,
    );
  }

  void _rotulo(Canvas canvas, SectorPlano s) {
    if (s.texto.isEmpty) return;
    final rect = _rect(s);
    final neon = tema.estilo == EstiloPlano.neon;
    final texto = neon ? s.texto : s.texto.toUpperCase();
    final alto = s.vertical ? rect.width : rect.height;
    final largo = s.vertical ? rect.height : rect.width;
    final color =
        _esEscena(s) && !neon ? tema.escenarioTexto : tema.sectorTexto;
    final espaciado = neon ? 1.0 : 3.0;
    var tam = math.min(30.0, alto * 0.6);
    var tp = _texto(texto, tam, color, espaciado: espaciado);
    // Si no entra en el lado largo, se achica hasta que entre.
    final entra = largo * 0.9;
    if (tp.width > entra && tp.width > 0) {
      tam = tam * entra / tp.width;
      tp = _texto(texto, tam, color, espaciado: espaciado * entra / tp.width);
    }
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (s.vertical) canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _rayado(Canvas canvas, RRect rrect, Color color) {
    canvas.save();
    canvas.clipRRect(rrect);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    final r = rrect.outerRect;
    for (var x = r.left - r.height; x < r.right; x += 16) {
      canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), p);
    }
    canvas.restore();
  }

  // ── Mesas ───────────────────────────────────────────────────────────────

  void _mesa(Canvas canvas, MesaPlano m, NivelDetalle nivel, RectPlano caja) {
    final info = estado.info(m.numero);
    final c = Offset(m.x, m.y);
    final r = radioDibujo(armado, tema);
    final foco = _enFoco(m.numero);
    final conSillas = tema.sillas && nivel.sillas;

    if (conSillas) _sillas(canvas, c, r, info, foco);

    switch (tema.estilo) {
      case EstiloPlano.gala:
        _mesaGala(canvas, c, r, info, foco, nivel);
      case EstiloPlano.arquitecto:
        _mesaArquitecto(canvas, c, r, info, foco);
      case EstiloPlano.neon:
        _mesaNeon(canvas, c, r, info, foco);
    }

    // Las marcas salen del dato y no del estado: una mesa fijada que ya tiene
    // familia sigue mostrando el candado, y una libre que quedó ocupada, la
    // raya.
    if (nivel.adornos) {
      if (m.pasto) _marcaPasto(canvas, c, r);
      if (info.libre) _marcaLibre(canvas, c, r);
      if (info.fijadaPara != null) _candado(canvas, c, r);
    }

    if (nivel.numeros) _numero(canvas, m, c, r, info, foco);

    final familia = familiaConApellido(info, nivel);
    if (familia != null) {
      _apellido(
        canvas,
        familia.apellido,
        franjaApellido(c, r, caja, conSillas: conSillas),
        foco ? tema.titulo : tema.tituloSuave,
      );
    }
  }

  /// El apellido, centrado en su [franja]. Si no entra, primero se achica la
  /// letra (hasta el 75 %) y después se corta con "…".
  void _apellido(Canvas canvas, String texto, Rect franja, Color color) {
    final base = franja.height;
    var tp = _texto(texto, base, color);
    if (tp.width > franja.width) {
      final factor = math.max(0.75, franja.width / tp.width);
      tp = _texto(texto, base * factor, color);
      if (tp.width > franja.width) {
        tp = _texto(texto, base * factor, color, maxAncho: franja.width);
      }
    }
    tp.paint(canvas, Offset(franja.center.dx - tp.width / 2, franja.top));
  }

  bool _conFamilia(InfoMesa i) =>
      i.estado == EstadoMesa.ocupada ||
      i.estado == EstadoMesa.fijada ||
      i.estado == EstadoMesa.conflicto;

  void _mesaGala(
    Canvas canvas,
    Offset c,
    double r,
    InfoMesa info,
    bool foco,
    NivelDetalle nivel,
  ) {
    final llena = _conFamilia(info);
    canvas.drawCircle(
      c,
      r,
      Paint()..color = foco ? tema.resaltado : tema.mesaRelleno,
    );
    final borde = info.estado == EstadoMesa.conflicto
        ? tema.conflicto
        : llena || foco
            ? tema.mesaBorde
            : tema.mesaVacia;
    if (foco && tema.brillo) {
      _conBrillo(canvas, (p) => canvas.drawCircle(c, r, p),
          color: tema.resaltado, ancho: 3);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = borde,
    );
    if (llena && nivel.adornos) {
      canvas.drawCircle(
        c,
        r - 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = borde.withValues(alpha: 0.7),
      );
      // La joya de la división, a la una en punto.
      if (!foco && info.division != null && info.division! >= 0) {
        final a = -math.pi / 3;
        final j = c + Offset(math.cos(a), math.sin(a)) * r;
        canvas.drawCircle(j, 7.5, Paint()..color = tema.fondo);
        canvas.drawCircle(
          j,
          6,
          Paint()..color = tema.colorDivision(info.division),
        );
      }
    }
  }

  void _mesaArquitecto(
    Canvas canvas,
    Offset c,
    double r,
    InfoMesa info,
    bool foco,
  ) {
    final llena = _conFamilia(info);
    final relleno = foco
        ? tema.resaltado
        : llena && info.division != null && info.division! >= 0
            ? tema.colorDivision(info.division)
            : tema.mesaRelleno;
    canvas.drawCircle(c, r, Paint()..color = relleno);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = info.estado == EstadoMesa.conflicto ? 4 : 2
        ..color = info.estado == EstadoMesa.conflicto
            ? tema.conflicto
            : foco
                ? tema.resaltado
                : llena
                    ? tema.mesaBorde
                    : tema.mesaVacia,
    );
  }

  void _mesaNeon(
    Canvas canvas,
    Offset c,
    double r,
    InfoMesa info,
    bool foco,
  ) {
    final llena = _conFamilia(info);
    // Una mesa vacía en foco se pinta con el color del resaltado: con el suyo
    // (el apagado de las vacías) el número oscuro no se leía.
    final color = info.estado == EstadoMesa.conflicto
        ? tema.conflicto
        : llena && info.division != null && info.division! >= 0
            ? tema.colorDivision(info.division)
            : llena
                ? tema.mesaBorde
                : foco
                    ? tema.resaltado
                    : tema.mesaVacia;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = foco ? color : tema.mesaRelleno,
    );
    if (llena || foco) {
      _conBrillo(canvas, (p) => canvas.drawCircle(c, r, p),
          color: color, ancho: foco ? 5 : 4);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = llena || foco ? 3 : 2.5
        ..color = llena || foco ? Color.lerp(color, Colors.white, 0.25)! : color,
    );
  }

  void _sillas(
    Canvas canvas,
    Offset c,
    double r,
    InfoMesa info,
    bool foco,
  ) {
    final llena = _conFamilia(info) || foco;
    final relleno = Paint()
      ..color = llena ? const Color(0xFFD3D1C7) : const Color(0xFFE8E6DF);
    final borde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = llena ? const Color(0xFF888780) : const Color(0xFFC4C2B9);
    final extra = Paint()..color = tema.numeroDeDivision(info.division);
    void silla(double angulo, Paint p, {bool conBorde = true}) {
      canvas.save();
      canvas.translate(
        c.dx + math.cos(angulo) * (r + 9),
        c.dy + math.sin(angulo) * (r + 9),
      );
      canvas.rotate(angulo + math.pi / 2);
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 12, height: 7),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(rr, p);
      if (conBorde) canvas.drawRRect(rr, borde);
      canvas.restore();
    }

    for (var i = 0; i < 8; i++) {
      silla(math.pi / 8 + i * math.pi / 4, relleno);
    }
    // Las extra van en los huecos de los costados, en el tono de la división.
    for (var i = 0; i < info.sillasExtra.clamp(0, 2); i++) {
      silla(i == 0 ? 0 : math.pi, extra, conBorde: false);
    }
  }

  void _numero(
    Canvas canvas,
    MesaPlano m,
    Offset c,
    double r,
    InfoMesa info,
    bool foco,
  ) {
    final llena = _conFamilia(info);
    final color = foco
        ? tema.resaltadoNumero
        : info.estado == EstadoMesa.conflicto
            ? tema.conflicto
            : !llena
                ? tema.numeroVacia
                : tema.estilo == EstiloPlano.arquitecto
                    ? tema.numeroDeDivision(info.division)
                    : tema.numero;
    final tres = m.numero >= 100;
    final base = tema.estilo == EstiloPlano.gala ? 0.95 : 0.82;
    final tam = r * base * (tres ? 0.78 : 1);
    final tp = _texto('${m.numero}', tam, color,
        peso: tema.pesoNumero,
        sombra: tema.estilo == EstiloPlano.neon && llena && !foco);
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  // ── Marcas ──────────────────────────────────────────────────────────────

  void _marcaPasto(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = tema.pasto;
    _circuloPunteado(canvas, c, r + 5, p, segmentos: 18, lleno: 0.35);
  }

  void _marcaLibre(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = tema.numeroVacia;
    canvas.drawLine(
      c + Offset(-r * 0.62, r * 0.62),
      c + Offset(r * 0.62, -r * 0.62),
      p,
    );
  }

  /// El candado va a las once: a la una está la joya de la división (Gala).
  void _candado(Canvas canvas, Offset c, double r) {
    final centro = c + Offset(-r * 0.72, -r * 0.72);
    final fondo = Paint()..color = tema.fondo;
    final color = Paint()..color = tema.tituloSuave;
    canvas.drawCircle(centro, 11, fondo);
    final cuerpo = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centro + const Offset(0, 2.5), width: 12, height: 9),
      const Radius.circular(2),
    );
    canvas.drawRRect(cuerpo, color);
    canvas.drawArc(
      Rect.fromCenter(center: centro + const Offset(0, -2), width: 8, height: 9),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = tema.tituloSuave,
    );
  }

  void _circuloPunteado(
    Canvas canvas,
    Offset c,
    double r,
    Paint p, {
    int segmentos = 16,
    double lleno = 0.5,
  }) {
    final paso = 2 * math.pi / segmentos;
    for (var i = 0; i < segmentos; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * paso,
        paso * lleno,
        false,
        p,
      );
    }
  }

  // ── Utilidades ──────────────────────────────────────────────────────────

  /// Dibuja un trazo con un halo difuso del mismo color debajo.
  void _conBrillo(
    Canvas canvas,
    void Function(Paint) trazo, {
    required Color color,
    required double ancho,
  }) {
    trazo(Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho * 3
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
  }

  /// Con [maxAncho], el texto va en un renglón y se corta con "…" si no entra.
  TextPainter _texto(
    String texto,
    double tam,
    Color color, {
    FontWeight? peso,
    double espaciado = 0,
    bool sombra = false,
    double? maxAncho,
  }) {
    final clave =
        '$texto|$tam|${color.toARGB32()}|$peso|$espaciado|$sombra|$maxAncho';
    return _textos.putIfAbsent(clave, () {
      final tp = TextPainter(
        text: TextSpan(
          text: texto,
          style: TextStyle(
            fontFamily: tema.fuente,
            fontSize: tam,
            color: color,
            fontWeight: peso,
            letterSpacing: espaciado,
            height: 1,
            fontFeatures: const [
              ui.FontFeature.liningFigures(),
              ui.FontFeature.tabularFigures(),
            ],
            shadows: sombra
                ? [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 8)]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: maxAncho == null ? null : 1,
        ellipsis: maxAncho == null ? null : '…',
      )..layout(maxWidth: maxAncho ?? double.infinity);
      return tp;
    });
  }

  @override
  bool shouldRepaint(PintorPlano old) =>
      old.armado != armado ||
      old.hoja != hoja ||
      old.tema != tema ||
      old.estado != estado ||
      old.seleccionada != seleccionada ||
      !setEquals(old.resaltadas, resaltadas);
}

/// Lo que se mueve encima del plano: el pulso de las mesas resaltadas y, en
/// el tótem, el camino desde el ingreso.
class PintorResaltado extends CustomPainter {
  PintorResaltado({
    required this.armado,
    required this.hoja,
    required this.tema,
    required this.estado,
    required this.resaltadas,
    required this.pulso,
    this.ruta,
    this.progresoRuta = 1,
  }) : super(repaint: pulso);

  final ArmadoSalon armado;
  final String hoja;
  final TemaPlano tema;

  /// Para saber qué mesas llevan apellido debajo: el anillo no los cruza.
  final EstadoPlano estado;
  final Set<int> resaltadas;
  final Animation<double> pulso;

  /// Puntos en coordenadas del plano (el tótem, en diciembre).
  final List<Offset>? ruta;
  final double progresoRuta;

  @override
  void paint(Canvas canvas, Size size) {
    final h = armado.hoja(hoja);
    if (h == null) return;
    final encuadre = EncuadrePlano.de(h.caja, size);
    canvas.save();
    encuadre.aplicar(canvas);

    final puntos = ruta;
    if (puntos != null && puntos.length > 1 && progresoRuta > 0) {
      final camino = Path()..moveTo(puntos.first.dx, puntos.first.dy);
      for (final p in puntos.skip(1)) {
        camino.lineTo(p.dx, p.dy);
      }
      final medida = camino.computeMetrics().toList();
      final total = medida.fold<double>(0, (s, m) => s + m.length);
      var resta = total * progresoRuta.clamp(0, 1);
      final visible = Path();
      for (final m in medida) {
        if (resta <= 0) break;
        visible.addPath(m.extractPath(0, math.min(resta, m.length)), Offset.zero);
        resta -= m.length;
      }
      canvas.drawPath(
        visible,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = tema.ruta.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        visible,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = tema.ruta,
      );
    }

    final p = pulso.value;
    final r = radioDibujo(armado, tema);
    final nivel = NivelDetalle.para(armado.radio * encuadre.escala);
    final conSillas = tema.sillas && nivel.sillas;
    final enHoja = [
      for (final n in resaltadas)
        if (armado.mesa(n)?.hoja == hoja) armado.mesa(n)!,
    ];
    // Los apellidos de lo resaltado quedan afuera del anillo: se recortan
    // todas las franjas antes de dibujar ninguno, porque el anillo de una mesa
    // también pasa por el apellido de la de al lado.
    for (final m in enHoja) {
      if (familiaConApellido(estado.info(m.numero), nivel) == null) continue;
      canvas.clipRect(
        franjaApellido(Offset(m.x, m.y), r, h.caja, conSillas: conSillas)
            .inflate(3),
        clipOp: ui.ClipOp.difference,
      );
    }
    for (final m in enHoja) {
      canvas.drawCircle(
        Offset(m.x, m.y),
        r + 6 + p * 26,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = tema.resaltado.withValues(alpha: (1 - p) * 0.9),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorResaltado old) =>
      old.armado != armado ||
      old.hoja != hoja ||
      old.tema != tema ||
      old.estado != estado ||
      old.pulso != pulso ||
      old.ruta != ruta ||
      old.progresoRuta != progresoRuta ||
      !setEquals(old.resaltadas, resaltadas);
}
