import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import '../../plano/modelo/armado_salon.dart';
import 'camino_a_la_mesa.dart';

/// Dónde quedó el cuadro: lo de la espera (la foto y las frases) y, en la
/// llegada, la tarjeta achicada.
enum LugarDelCuadro {
  /// Adentro de la pista de baile del salón.
  pista,

  /// En el lugar libre más grande entre las mesas.
  hueco,

  /// En lo que el salón deja libre al entrar en la pantalla.
  franjaLibre,

  /// No había lugar: el salón se achicó para dejarlo.
  franjaForzada,
}

/// Dónde quiere el jefe el nombre de la llegada (Personalizar → LA LLEGADA).
/// Se guarda en `totem_config.llegada_lugar`: vacío es automático.
enum LugarElegido {
  automatico,
  pista,
  arriba,
  abajo,
  izquierda,
  derecha;

  /// Una clave vacía o desconocida es automático: nunca una pantalla rota.
  static LugarElegido deClave(String? clave) => LugarElegido.values.firstWhere(
        (l) => l != automatico && l.name == clave,
        orElse: () => automatico,
      );

  /// Lo que se guarda. Null: automático.
  String? get clave => this == automatico ? null : name;

  String get etiqueta => switch (this) {
        automatico => 'Automático',
        pista => 'En la pista',
        arriba => 'Arriba',
        abajo => 'Abajo',
        izquierda => 'Izquierda',
        derecha => 'Derecha',
      };
}

/// Dónde van, en la pantalla del tótem, el salón entero y "el cuadro": lo de la
/// espera mientras la gente hace la fila y, cuando llega una familia, su tarjeta
/// achicada junto a la mesa encendida (pedido del jefe, 4-nov).
///
/// **Se decide una vez por plano, pantalla y lugar elegido**, y es el mismo en
/// la espera y en la llegada: la tarjeta cae donde estaban las frases y el salón
/// no se mueve.
///
/// Automático: donde mejor se lee, entre la pista de baile, el hueco más grande
/// sin mesas y la franja que el salón deja libre (arriba o a la izquierda); la
/// pista, si se lee casi igual (el jefe la nombró). Si nada alcanza, una franja
/// arriba (o a la izquierda en una tele apaisada) y el salón se achica a lo que
/// queda. Un lado elegido es la franja de ese lado; "En la pista", la pista
/// aunque quede chica (sin pista, automático).
///
/// En la Normal, en una tele vertical va arriba; en una apaisada, a la
/// izquierda: ahí la pista se lee la mitad de grande.
///
/// Sin pantalla ni base: solo cuentas, en píxeles de la pantalla del tótem.
class CuadroDelSalon {
  /// La hoja que se muestra ([hojaPrincipal]).
  final String hoja;

  /// El panel del salón, con su [relleno] alrededor del dibujo.
  final Rect panel;

  /// Lo de la espera, y la tarjeta achicada en la llegada.
  final Rect cuadro;

  final LugarDelCuadro lugar;

  /// El radio de una mesa en la pantalla: de esto depende cuánto detalle entra.
  final double radioPx;

  /// El cuadro queda al lado del salón y no arriba ni abajo.
  final bool alCostado;

  /// Lo que hay entre el borde del panel y el dibujo del salón.
  final double relleno;

  const CuadroDelSalon({
    required this.hoja,
    required this.panel,
    required this.cuadro,
    required this.lugar,
    required this.radioPx,
    required this.alCostado,
    required this.relleno,
  });

  /// Lo que ocupa el dibujo del salón: el panel sin su relleno.
  Rect get salon => panel.deflate(relleno);

  // Todo en unidades de la escena (`u`, un 27avo del ancho de una pantalla
  // vertical): así se ve igual en la tele, en Recepción y en Personalizar.

  /// El relleno del panel.
  static const rellenoEnU = 0.35;

  /// Lo más chico que puede ser el cuadro: una foto y tres renglones.
  static const anchoMinimoEnU = 12.0;
  static const altoMinimoEnU = 9.0;

  /// Los márgenes de la pantalla. Abajo, el lugar de "N más en camino" y la
  /// línea del tiempo.
  static const margenEnU = 0.8;
  static const abajoEnU = 2.6;

  /// Lo que se achica el cuadro adentro de la pista o del hueco, para no tocar
  /// las mesas.
  static const holguraEnU = 0.3;

  /// Entre el cuadro y el panel, cuando van uno al lado del otro.
  static const separacionEnU = 0.5;

  /// Una franja forzada ocupa al menos esta parte de la pantalla.
  static const franjaArribaMinima = 0.25;
  static const franjaCostadoMinima = 0.3;

  /// Lo que mide lo de adentro del cuadro (una llegada, la espera) para verse
  /// en su tamaño de siempre, en `u`. Más chico, se achica entero.
  static const contenidoAnchoEnU = 22.0;
  static const contenidoAltoEnU = 24.0;

  /// La pista gana en automático si se lee al menos esto de bien comparada con
  /// el mejor lugar.
  static const pistaSiSeLee = 0.85;

  /// Cuánto se achica lo de adentro de un cuadro de [tam]: 1 si entra en su
  /// tamaño de siempre.
  static double escalaDelContenido(Size tam, double u) => math.min(
        1.0,
        math.min(
          tam.width / (contenidoAnchoEnU * u),
          tam.height / (contenidoAltoEnU * u),
        ),
      );

  /// Null sin plano, sin mesas o sin lugar en la pantalla.
  static CuadroDelSalon? para(
    ArmadoSalon? armado, {
    required Size pantalla,
    required double u,
    LugarElegido elegido = LugarElegido.automatico,
  }) {
    if (armado == null || armado.mesas.isEmpty) return null;
    if (u <= 0 || pantalla.width <= 0 || pantalla.height <= 0) return null;
    final hoja = hojaPrincipal(armado);
    if (hoja == null) return null;
    final caja = armado.hoja(hoja)?.caja;
    if (caja == null || caja.ancho <= 0 || caja.alto <= 0) return null;

    final relleno = u * rellenoEnU;
    final disponible = Rect.fromLTRB(
      u * margenEnU,
      u * margenEnU,
      pantalla.width - u * margenEnU,
      pantalla.height - u * abajoEnU,
    );
    final area = disponible.deflate(relleno);
    if (area.width <= 0 || area.height <= 0) return null;
    final minimo = Size(u * anchoMinimoEnU, u * altoMinimoEnU);
    final calculo = _Calculo(
      armado: armado,
      hoja: hoja,
      caja: caja,
      disponible: disponible,
      area: area,
      minimo: minimo,
      relleno: relleno,
      holgura: u * holguraEnU,
      separacion: u * separacionEnU,
    );

    if (elegido == LugarElegido.pista) {
      final pista = calculo.enLaPista(minimoAlcanza: false);
      if (pista != null) return pista;
    } else if (elegido != LugarElegido.automatico) {
      return calculo.franja(elegido, forzada: false, minimoAlcanza: true) ??
          calculo.franja(elegido, forzada: true, minimoAlcanza: false);
    }

    // Donde mejor se lee; la pista, si se lee casi igual.
    double legible(CuadroDelSalon c) => escalaDelContenido(c.cuadro.size, u);
    final pista = calculo.enLaPista(minimoAlcanza: true);
    final opciones = [
      ?pista,
      ?calculo.enElHueco(),
      ?calculo.franja(LugarElegido.arriba, forzada: false, minimoAlcanza: true),
      ?calculo.franja(
        LugarElegido.izquierda,
        forzada: false,
        minimoAlcanza: true,
      ),
    ];
    if (opciones.isNotEmpty) {
      var mejor = opciones.first;
      for (final o in opciones.skip(1)) {
        if (legible(o) > legible(mejor)) mejor = o;
      }
      if (pista != null && legible(pista) >= pistaSiSeLee * legible(mejor)) {
        return pista;
      }
      return mejor;
    }
    final apaisada = pantalla.width > pantalla.height * 1.2;
    return calculo.franja(
      apaisada ? LugarElegido.izquierda : LugarElegido.arriba,
      forzada: true,
      minimoAlcanza: false,
    );
  }

  /// La hoja que se muestra: la del ingreso (de ahí sale el camino); si
  /// ninguna lo tiene, la de más mesas. Null sin hojas.
  static String? hojaPrincipal(ArmadoSalon armado) {
    if (armado.hojas.isEmpty) return null;
    for (final h in armado.hojas) {
      if (CaminoALaMesa.ingresoEn(armado, h.id) != null &&
          armado.mesasDeHoja(h.id).isNotEmpty) {
        return h.id;
      }
    }
    var mejor = armado.hojas.first.id;
    var cuantas = -1;
    for (final h in armado.hojas) {
      final n = armado.mesasDeHoja(h.id).length;
      if (n > cuantas) {
        mejor = h.id;
        cuantas = n;
      }
    }
    return mejor;
  }

  /// El rectángulo libre de [hoja] (sin mesas con sus sillas ni sectores) que
  /// mejor contiene uno de [minAncho] × [minAlto], en coordenadas del plano:
  /// el que más se puede agrandar sin salirse. Null si la hoja no existe.
  static RectPlano? huecoMasGrande(
    ArmadoSalon armado,
    String hoja, {
    required double minAncho,
    required double minAlto,
  }) {
    final caja = armado.hoja(hoja)?.caja;
    if (caja == null || minAncho <= 0 || minAlto <= 0) return null;
    var paso = armado.radio * 0.5;
    while ((caja.ancho / paso).ceil() * (caja.alto / paso).ceil() > _maxCeldas) {
      paso *= 1.25;
    }
    final columnas = math.max(1, (caja.ancho / paso).ceil());
    final filas = math.max(1, (caja.alto / paso).ceil());
    final tapada = List<bool>.filled(columnas * filas, false);

    double x0(int k) => caja.x + k * paso;
    double y0(int f) => caja.y + f * paso;

    // Las mesas, con sus sillas: la celda se tapa si el círculo la toca.
    final r = armado.radio * CaminoALaMesa.conSillas;
    for (final m in armado.mesasDeHoja(hoja)) {
      final k0 = ((m.x - r - caja.x) / paso).floor().clamp(0, columnas - 1);
      final k1 = ((m.x + r - caja.x) / paso).floor().clamp(0, columnas - 1);
      final f0 = ((m.y - r - caja.y) / paso).floor().clamp(0, filas - 1);
      final f1 = ((m.y + r - caja.y) / paso).floor().clamp(0, filas - 1);
      for (var f = f0; f <= f1; f++) {
        for (var k = k0; k <= k1; k++) {
          final celda = RectPlano(x0(k), y0(f), paso, paso);
          if (celda.solapeConCirculo(m.x, m.y, r) > 0) {
            tapada[f * columnas + k] = true;
          }
        }
      }
    }
    // Los sectores, todos: tienen su nombre escrito.
    for (final s in armado.sectoresDeHoja(hoja)) {
      final k0 = ((s.caja.x - caja.x) / paso).floor().clamp(0, columnas - 1);
      final k1 =
          ((s.caja.derecha - caja.x) / paso).ceil().clamp(1, columnas) - 1;
      final f0 = ((s.caja.y - caja.y) / paso).floor().clamp(0, filas - 1);
      final f1 = ((s.caja.abajo - caja.y) / paso).ceil().clamp(1, filas) - 1;
      for (var f = f0; f <= f1; f++) {
        for (var k = k0; k <= k1; k++) {
          tapada[f * columnas + k] = true;
        }
      }
    }

    // El rectángulo máximo por histograma: para cada fila, cuántas celdas
    // libres hay hacia arriba en cada columna; con una pila, cada barra da el
    // rectángulo más ancho de su altura.
    final alto = List<int>.filled(columnas, 0);
    RectPlano? mejor;
    var mejorPuntaje = 0.0;
    void probar(int izquierda, int derecha, int fila, int h) {
      final ancho = (derecha - izquierda + 1) * paso;
      final altoU = h * paso;
      final p = math.min(ancho / minAncho, altoU / minAlto);
      if (p <= mejorPuntaje) return;
      mejorPuntaje = p;
      final x = x0(izquierda);
      final y = y0(fila - h + 1);
      mejor = RectPlano(
        x,
        y,
        math.min(ancho, caja.derecha - x),
        math.min(altoU, caja.abajo - y),
      );
    }

    for (var f = 0; f < filas; f++) {
      for (var k = 0; k < columnas; k++) {
        alto[k] = tapada[f * columnas + k] ? 0 : alto[k] + 1;
      }
      final pila = <int>[];
      for (var k = 0; k <= columnas; k++) {
        final h = k == columnas ? 0 : alto[k];
        while (pila.isNotEmpty && alto[pila.last] >= h) {
          final arriba = pila.removeLast();
          final hb = alto[arriba];
          if (hb > 0) {
            final izquierda = pila.isEmpty ? 0 : pila.last + 1;
            probar(izquierda, k - 1, f, hb);
          }
        }
        pila.add(k);
      }
    }
    return mejor;
  }

  /// La grilla más grande que se arma para buscar el hueco.
  static const _maxCeldas = 60000;

  @override
  bool operator ==(Object other) =>
      other is CuadroDelSalon &&
      other.hoja == hoja &&
      other.panel == panel &&
      other.cuadro == cuadro &&
      other.lugar == lugar &&
      other.radioPx == radioPx &&
      other.alCostado == alCostado &&
      other.relleno == relleno;

  @override
  int get hashCode =>
      Object.hash(hoja, panel, cuadro, lugar, radioPx, alCostado, relleno);

  @override
  String toString() => 'CuadroDelSalon(${lugar.name}, panel: $panel, '
      'cuadro: $cuadro, radio: ${radioPx.toStringAsFixed(1)} px)';
}

/// Las cuentas de [CuadroDelSalon.para], con lo que comparten.
class _Calculo {
  final ArmadoSalon armado;
  final String hoja;
  final RectPlano caja;

  /// La pantalla sin sus márgenes.
  final Rect disponible;

  /// Donde entra el dibujo del salón: lo disponible sin el relleno del panel.
  final Rect area;
  final Size minimo;
  final double relleno;
  final double holgura;
  final double separacion;

  _Calculo({
    required this.armado,
    required this.hoja,
    required this.caja,
    required this.disponible,
    required this.area,
    required this.minimo,
    required this.relleno,
    required this.holgura,
    required this.separacion,
  });

  /// Cuánto se puede agrandar lo mínimo adentro de [r]: 1 o más, entra.
  double puntaje(Rect r) =>
      math.min(r.width / minimo.width, r.height / minimo.height);

  /// El salón entero, lo más grande que entra en [en], alineado como dicen
  /// [ax] y [ay] (de -1 a 1).
  Rect encajar(Rect en, {double ax = 0, double ay = 0}) {
    final s = math.min(en.width / caja.ancho, en.height / caja.alto);
    final w = caja.ancho * s;
    final h = caja.alto * s;
    return Rect.fromLTWH(
      en.left + (en.width - w) * (ax + 1) / 2,
      en.top + (en.height - h) * (ay + 1) / 2,
      w,
      h,
    );
  }

  /// Un rectángulo del plano, en la pantalla, con el salón dibujado en [salon].
  Rect aPantalla(RectPlano r, Rect salon) {
    final s = salon.width / caja.ancho;
    return Rect.fromLTWH(
      salon.left + (r.x - caja.x) * s,
      salon.top + (r.y - caja.y) * s,
      r.ancho * s,
      r.alto * s,
    );
  }

  CuadroDelSalon _armar(
    Rect salon,
    Rect cuadro,
    LugarDelCuadro lugar, {
    bool alCostado = false,
  }) =>
      CuadroDelSalon(
        hoja: hoja,
        panel: salon.inflate(relleno),
        cuadro: cuadro,
        lugar: lugar,
        radioPx: armado.radio * salon.width / caja.ancho,
        alCostado: alCostado,
        relleno: relleno,
      );

  /// Adentro de la pista más grande de la hoja, con el salón al medio. Null si
  /// no hay pista o, con [minimoAlcanza], si no entra lo mínimo.
  CuadroDelSalon? enLaPista({required bool minimoAlcanza}) {
    final pistas = [
      for (final s in armado.sectoresDeHoja(hoja))
        if (s.tipo == TipoSector.pista) s.caja,
    ];
    if (pistas.isEmpty) return null;
    pistas.sort((a, b) => (b.ancho * b.alto).compareTo(a.ancho * a.alto));
    final salon = encajar(area);
    final cuadro = aPantalla(pistas.first, salon).deflate(holgura);
    if (cuadro.width <= 0 || cuadro.height <= 0) return null;
    if (minimoAlcanza && puntaje(cuadro) < 1) return null;
    return _armar(salon, cuadro, LugarDelCuadro.pista);
  }

  /// En el hueco más grande entre las mesas, con el salón al medio. Null si no
  /// entra lo mínimo.
  CuadroDelSalon? enElHueco() {
    final salon = encajar(area);
    final s = salon.width / caja.ancho;
    final hueco = CuadroDelSalon.huecoMasGrande(
      armado,
      hoja,
      minAncho: minimo.width / s,
      minAlto: minimo.height / s,
    );
    if (hueco == null) return null;
    final cuadro = aPantalla(hueco, salon).deflate(holgura);
    if (puntaje(cuadro) < 1) return null;
    return _armar(salon, cuadro, LugarDelCuadro.hueco);
  }

  /// El cuadro del lado [lado] y el salón del otro. Libre: el salón tan grande
  /// como entra, y el cuadro en lo que sobra (null si no alcanza lo mínimo con
  /// [minimoAlcanza]). Forzada: primero se reserva la franja y el salón entra
  /// en lo que queda.
  CuadroDelSalon? franja(
    LugarElegido lado, {
    required bool forzada,
    required bool minimoAlcanza,
  }) {
    final vertical = lado == LugarElegido.arriba || lado == LugarElegido.abajo;
    final reserva = !forzada
        ? 0.0
        : vertical
            ? math.max(
                minimo.height,
                disponible.height * CuadroDelSalon.franjaArribaMinima,
              )
            : math.max(
                minimo.width,
                disponible.width * CuadroDelSalon.franjaCostadoMinima,
              );
    final paraElSalon = switch (lado) {
      LugarElegido.arriba => Rect.fromLTRB(
          area.left, area.top + reserva + separacion, area.right, area.bottom),
      LugarElegido.abajo => Rect.fromLTRB(
          area.left, area.top, area.right, area.bottom - reserva - separacion),
      LugarElegido.izquierda => Rect.fromLTRB(
          area.left + reserva + separacion, area.top, area.right, area.bottom),
      _ => Rect.fromLTRB(
          area.left, area.top, area.right - reserva - separacion, area.bottom),
    };
    if (paraElSalon.width <= 0 || paraElSalon.height <= 0) return null;
    // El salón, pegado al lado de enfrente: lo que sobra queda junto al cuadro.
    final salon = switch (lado) {
      LugarElegido.arriba => encajar(paraElSalon, ay: 1),
      LugarElegido.abajo => encajar(paraElSalon, ay: -1),
      LugarElegido.izquierda => encajar(paraElSalon, ax: 1),
      _ => encajar(paraElSalon, ax: -1),
    };
    final panel = salon.inflate(relleno);
    final cuadro = switch (lado) {
      LugarElegido.arriba => Rect.fromLTRB(disponible.left, disponible.top,
          disponible.right, panel.top - separacion),
      LugarElegido.abajo => Rect.fromLTRB(disponible.left,
          panel.bottom + separacion, disponible.right, disponible.bottom),
      LugarElegido.izquierda => Rect.fromLTRB(disponible.left,
          disponible.top, panel.left - separacion, disponible.bottom),
      _ => Rect.fromLTRB(panel.right + separacion, disponible.top,
          disponible.right, disponible.bottom),
    };
    if (cuadro.width <= 0 || cuadro.height <= 0) return null;
    if (minimoAlcanza && puntaje(cuadro) < 1) return null;
    return _armar(
      salon,
      cuadro,
      forzada ? LugarDelCuadro.franjaForzada : LugarDelCuadro.franjaLibre,
      alCostado: !vertical,
    );
  }
}
