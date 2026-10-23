import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/totem_config.dart';
import '../../plano/estilos/estilo_plano.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/widgets/vista_plano.dart';
import '../services/contenido_bienvenida.dart';
import '../services/foto_guardada.dart';
import '../services/plano_de_la_llegada.dart';
import 'escena_cristal.dart';
import 'escena_gala.dart';
import 'escena_neon.dart';
import 'escena_poster.dart';
import 'escena_tu_fondo.dart';
import 'fondo_propio.dart';
import 'forma_foto.dart';
import 'fondo_totem.dart';
import 'fuentes_totem.dart';
import 'plano_del_totem.dart';
import 'totem_estilo.dart';
import 'tu_fondo.dart';

/// Lo que se ve en el tótem: la espera o una llegada, en la apariencia del
/// evento, sobre su fondo animado.
///
/// Qué dice una llegada lo decide [ContenidoBienvenida] (quién, con quién, la
/// mesa, las sillas, la música); cuándo empieza y cuándo se va, quien la usa
/// (`ReproductorBienvenidas`). Acá solo se dibuja. La usan la ventana del
/// tótem y, en chico, Recepción y Personalizar.
class EscenaTotem extends StatefulWidget {
  final EstiloTotem estilo;
  final TotemConfig cfg;

  /// La apariencia si [estilo] es "Tu fondo" y la imagen no está en la PC ni
  /// baja: la del tipo de evento. Nunca una pantalla rota.
  final EstiloTotem respaldo;

  /// La foto del evento, si manda sobre la de [cfg]: en Personalizar, la
  /// recién elegida, que todavía no se subió. Null: la de `cfg.imagenUrl`.
  final ImageProvider? foto;

  /// El fondo de "Tu fondo", si manda sobre el de [cfg] (en Personalizar, el
  /// recién elegido). Null: el de `cfg.fondoUrl`, guardado en la PC.
  final ImageProvider? fondo;

  /// El QR de la espera. Null: sin QR (un evento masivo).
  final String? qrUrl;

  /// Lo que va pegado a la foto de la espera: en Personalizar, las manijas
  /// para agrandarla. Null: nada (el tótem).
  final Widget Function(Widget foto)? alrededorDeLaFoto;

  /// Lo que va alrededor de la foto y las frases de la espera, juntas, con lo
  /// que mide la pantalla: en Personalizar, para moverlas arrastrando. Null:
  /// nada (el tótem).
  final Widget Function(Widget bloque, Size pantalla)? alrededorDelBloque;

  /// Lo que va pegado a las frases de la espera: en Personalizar, las manijas
  /// para agrandarlas. Null: nada (el tótem).
  final Widget Function(Widget frases)? alrededorDelTexto;

  /// La llegada que se muestra; null en la espera.
  final ContenidoBienvenida? llegada;

  /// El salón de la fiesta: en la llegada de un masivo, abajo (o al costado)
  /// va el plano con la mesa de la familia encendida. Null: sin plano (un
  /// particular, el tótem por el navegador).
  final ArmadoSalon? plano;

  /// Qué llegada es: si cambia, la animación de entrada vuelve a empezar.
  final Object? claveLlegada;

  /// La llegada se está yendo.
  final bool saliendo;

  /// "N más en camino".
  final int enCamino;

  /// Cuándo empezó y cuándo se va la llegada: la línea de abajo marca el
  /// tiempo.
  final DateTime? empezo;
  final DateTime? fin;

  /// Quieta, al final de la entrada (los tests y las muestras): sin
  /// animaciones, con el fondo en [tiempoFijo] y la línea en [progresoFijo].
  final bool quieta;
  final double tiempoFijo;
  final double progresoFijo;

  const EscenaTotem({
    super.key,
    required this.estilo,
    required this.cfg,
    this.respaldo = EstiloTotem.cristal,
    this.foto,
    this.fondo,
    this.qrUrl,
    this.alrededorDeLaFoto,
    this.alrededorDelBloque,
    this.alrededorDelTexto,
    this.llegada,
    this.plano,
    this.claveLlegada,
    this.saliendo = false,
    this.enCamino = 0,
    this.empezo,
    this.fin,
    this.quieta = false,
    this.tiempoFijo = 4,
    this.progresoFijo = 0.35,
  });

  /// Lo que tarda en entrar una llegada.
  static const entrada = Duration(milliseconds: 1350);

  /// Lo que tarda en irse. Quien la usa espera esto antes de la siguiente.
  static const salida = Duration(milliseconds: 700);

  /// El camino en el plano empieza a dibujarse cuando la tarjeta ya casi
  /// entró, y tarda esto.
  static const caminoEmpieza = Duration(milliseconds: 900);
  static const caminoDura = Duration(milliseconds: 1600);

  /// Cuántas veces se armó el plano de una llegada. Solo los tests: se arma
  /// una vez por llegada, no en cada cuadro.
  @visibleForTesting
  static int planosArmados = 0;

  @override
  State<EscenaTotem> createState() => _EscenaTotemState();
}

class _EscenaTotemState extends State<EscenaTotem>
    with TickerProviderStateMixin {
  late final AnimationController _entrada = AnimationController(
    vsync: this,
    duration: EscenaTotem.entrada,
    reverseDuration: EscenaTotem.salida,
  );

  /// Un reloj que da vueltas: lo que titila, gira o brilla, y la línea del
  /// tiempo.
  late final AnimationController _reloj = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  /// La imagen de "Tu fondo", si es la apariencia: se carga una vez y se
  /// suelta al cambiar.
  final _fondo = CargaDelFondo();

  @override
  void initState() {
    super.initState();
    _fondo.addListener(_cambioElFondo);
    _cargarFondo();
    if (widget.quieta) {
      _entrada.value = widget.llegada == null ? 0 : 1;
    } else {
      _reloj.repeat();
      if (widget.llegada != null) _entrada.forward(from: 0);
    }
  }

  void _cambioElFondo() {
    if (mounted) setState(() {});
  }

  /// La recién elegida en Personalizar, o la del evento (en la PC, la
  /// guardada: anda sin internet).
  void _cargarFondo() => _fondo.cargar(
        widget.estilo == EstiloTotem.tuFondo
            ? widget.fondo ?? fondoDelEvento(widget.cfg)
            : null,
      );

  @override
  void didUpdateWidget(covariant EscenaTotem old) {
    super.didUpdateWidget(old);
    _cargarFondo();
    if (widget.quieta) {
      _entrada.value = widget.llegada == null ? 0 : 1;
      return;
    }
    if (widget.llegada == null) {
      if (_entrada.value != 0 && !widget.saliendo) _entrada.value = 0;
      return;
    }
    if (widget.saliendo && !old.saliendo) {
      _entrada.reverse();
    } else if (widget.claveLlegada != old.claveLlegada ||
        (old.llegada == null && !widget.saliendo)) {
      _entrada.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fondo
      ..removeListener(_cambioElFondo)
      ..dispose();
    _entrada.dispose();
    _reloj.dispose();
    super.dispose();
  }

  // El plano de la llegada se arma una vez por llegada (y por plano), no en
  // cada cuadro.
  PlanoDeLaLlegada? _guia;
  ArmadoSalon? _guiaPlano;
  String? _guiaMesa;
  String? _guiaNombre;

  PlanoDeLaLlegada? _guiaPara(ContenidoBienvenida? c) {
    if (c == null || widget.plano == null) return null;
    final nombre = c.nombres.isEmpty ? '' : c.nombres.first;
    if (!identical(_guiaPlano, widget.plano) ||
        _guiaMesa != c.mesa ||
        _guiaNombre != nombre) {
      _guiaPlano = widget.plano;
      _guiaMesa = c.mesa;
      _guiaNombre = nombre;
      _guia = PlanoDeLaLlegada.para(widget.plano, mesa: c.mesa, nombre: nombre);
      EscenaTotem.planosArmados++;
    }
    return _guia;
  }

  /// La que se dibuja: "Tu fondo" necesita su imagen; si no está en la PC ni
  /// baja (o el evento no tiene), [EscenaTotem.respaldo]. Mientras carga
  /// sigue siendo "Tu fondo", sobre negro: es un instante.
  EstiloTotem get _estilo {
    if (widget.estilo != EstiloTotem.tuFondo) return widget.estilo;
    if (_fondo.de != null && !_fondo.fallo) return EstiloTotem.tuFondo;
    return widget.respaldo == EstiloTotem.tuFondo
        ? EstiloTotem.cristal
        : widget.respaldo;
  }

  EscenaEstilo _escenaDe(EstiloTotem estilo) => switch (estilo) {
        EstiloTotem.neon => const EscenaNeon(),
        EstiloTotem.cristal => const EscenaCristal(),
        EstiloTotem.poster => const EscenaPoster(),
        EstiloTotem.gala => const EscenaGala(),
        EstiloTotem.tuFondo => const EscenaTuFondo(),
      };

  double get _progreso {
    if (widget.quieta) return widget.progresoFijo;
    final a = widget.empezo, b = widget.fin;
    if (a == null || b == null) return 0;
    final total = b.difference(a).inMilliseconds;
    if (total <= 0) return 1;
    return (DateTime.now().difference(a).inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final estilo = _estilo;
    // En "Tu fondo", los colores salen de la imagen: el brillo hace de color
    // del evento (la línea del tiempo, el borde y la mesa del plano).
    final receta =
        estilo == EstiloTotem.tuFondo ? RecetaDibujada.de(widget.cfg) : null;
    final color = receta?.colores.brillo ?? widget.cfg.colorAcento;
    final escena = _escenaDe(estilo);
    // La guardada en la PC: sin internet se sigue viendo (sección 5).
    final foto = widget.foto ?? fotoDelEvento(widget.cfg);
    final guia = _guiaPara(widget.llegada);
    final tema = guia == null ? null : temaPlanoDelTotem(estilo, color);
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth.isFinite ? c.maxWidth : 1080.0;
        final alto = c.maxHeight.isFinite ? c.maxHeight : 1920.0;
        final u = math.min(ancho, alto * 9 / 16) / 27;
        return ClipRect(
          child: AnimatedBuilder(
            animation: Listenable.merge([_entrada, _reloj]),
            builder: (context, _) {
              final e = _entrada.value;
              final reloj = widget.quieta
                  ? widget.tiempoFijo
                  : _reloj.lastElapsedDuration == null
                      ? 0.0
                      : _reloj.value * 60;
              final datos = DatosEscena(
                cfg: widget.cfg,
                estilo: estilo,
                foto: foto,
                color: color,
                segundo: receta?.colores.saludo ?? segundoNeon(color),
                u: u,
                ancho: ancho,
                alto: alto,
                apaisado: ancho > alto * 1.2,
                qrUrl: widget.qrUrl,
                enCamino: widget.enCamino,
                entrada: e,
                reloj: reloj,
                alrededorDeLaFoto: widget.alrededorDeLaFoto,
                alrededorDelBloque: widget.alrededorDelBloque,
                alrededorDelTexto: widget.alrededorDelTexto,
              );
              final llegada = widget.llegada;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (receta != null)
                    FondoPropio(
                      imagen: _fondo.imagen,
                      chica: _fondo.chica,
                      receta: receta,
                      // Con el texto oscuro, oscurecer en la llegada lo
                      // ensucia: va como Cristal, sin atenuar.
                      atenuado: receta.textoOscuro ? 1 : 1 - 0.45 * e,
                      fogonazo: _fogonazo(e),
                      tiempoFijo: widget.quieta ? widget.tiempoFijo : null,
                    )
                  else
                    FondoTotem(
                      estilo: estilo,
                      color: color,
                      atenuado: estilo == EstiloTotem.cristal ? 1 : 1 - 0.45 * e,
                      fogonazo: _fogonazo(e),
                      tiempoFijo: widget.quieta ? widget.tiempoFijo : null,
                    ),
                  ...escena.capasDeFondo(datos),
                  if (e < 1)
                    Opacity(
                      opacity: (1 - e * 1.6).clamp(0.0, 1.0),
                      child: escena.espera(datos),
                    ),
                  if (llegada != null && e > 0)
                    Opacity(
                      opacity: (e * 1.8).clamp(0.0, 1.0),
                      child: guia == null || tema == null
                          ? escena.llegada(datos, llegada)
                          : _conPlano(escena, datos, llegada, guia, tema),
                    ),
                  if (llegada != null && widget.enCamino > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: u * 1.4,
                      child: Opacity(
                        opacity: e.clamp(0.0, 1.0),
                        child: Text(
                          '${widget.enCamino} más en camino',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: FuentesTotem.linea,
                            fontWeight: FontWeight.w700,
                            fontSize: u * 0.75,
                            letterSpacing: u * 0.15,
                            // Sobre un fondo propio claro, oscuro.
                            color: receta != null && receta.textoOscuro
                                ? Color.lerp(
                                    receta.colores.saludo,
                                    Colors.black,
                                    0.35,
                                  )
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  if (llegada != null)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      height: u * 0.22,
                      width: ancho * _progreso,
                      child: ColoredBox(
                        color: color.withValues(alpha: 0.9 * e),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Cuánto se dibujó del camino, de 0 a 1: arranca cuando la tarjeta ya
  /// entró ([EscenaTotem.caminoEmpieza]) y tarda [EscenaTotem.caminoDura].
  /// Quieta, entero.
  double get _progresoCamino {
    final a = widget.empezo;
    if (widget.quieta || a == null) return 1;
    final ms = DateTime.now().difference(a).inMilliseconds -
        EscenaTotem.caminoEmpieza.inMilliseconds;
    return (ms / EscenaTotem.caminoDura.inMilliseconds).clamp(0.0, 1.0);
  }

  /// La llegada con el plano: en una pantalla vertical, la llegada arriba y el
  /// plano abajo; apaisada, la llegada a la izquierda y el plano a la derecha.
  /// Abajo de todo quedan "N más en camino" y la línea del tiempo.
  Widget _conPlano(
    EscenaEstilo escena,
    DatosEscena d,
    ContenidoBienvenida c,
    PlanoDeLaLlegada guia,
    TemaPlano tema,
  ) {
    final u = d.u;
    final Rect llegada;
    final Rect plano;
    if (d.apaisado) {
      final mitad = d.ancho * 0.5;
      llegada = Rect.fromLTWH(0, 0, mitad, d.alto);
      plano = Rect.fromLTRB(mitad, u * 1.6, d.ancho - u * 1.2, d.alto - u * 3.4);
    } else {
      final corte = d.alto * 0.5;
      llegada = Rect.fromLTWH(0, 0, d.ancho, corte);
      plano = Rect.fromLTRB(
        u * 1.2,
        corte + u * 0.4,
        d.ancho - u * 1.2,
        d.alto - u * 3.4,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: llegada,
          child: escena.llegada(
            d.conPlanoEn(llegada.size, alCostado: d.apaisado),
            c,
          ),
        ),
        Positioned.fromRect(
          rect: plano,
          child: Opacity(
            opacity: d.tramo(0.35, 0.8),
            child: PanelPlano(
              guia: guia,
              tema: tema,
              borde: d.color,
              u: u,
              animar: !widget.quieta,
              progresoCamino: _progresoCamino,
            ),
          ),
        ),
      ],
    );
  }

  /// El fogonazo del fondo: sube y baja cerca de 1,15 s después de empezar.
  static double _fogonazo(double e) {
    final t = e * EscenaTotem.entrada.inMilliseconds / 1000;
    return math.max(0, 1 - (t - 1.15).abs() / 0.35);
  }
}

/// Lo que una apariencia necesita para dibujarse.
class DatosEscena {
  final TotemConfig cfg;
  final EstiloTotem estilo;

  /// La foto del evento (la de [cfg], o la que se acaba de elegir en
  /// Personalizar). Null: sin foto.
  final ImageProvider? foto;

  /// El color del evento y el segundo neón ([segundoNeon]).
  final Color color;
  final Color segundo;

  /// La unidad de medida: un 27avo del ancho de una pantalla vertical. Todo se
  /// mide en [u], así se ve igual en la tele, en Recepción y en Personalizar.
  final double u;

  /// Lo que mide la pantalla, en píxeles.
  final double ancho;
  final double alto;
  final bool apaisado;
  final String? qrUrl;
  final int enCamino;

  /// La entrada de la llegada, de 0 a 1.
  final double entrada;

  /// Segundos de un reloj que da vueltas: lo que titila, gira o brilla.
  final double reloj;

  /// La llegada va en una parte de la pantalla: en la otra está el plano.
  /// [ancho] y [alto] son los de esa parte.
  final bool conPlano;

  /// El plano va al costado (pantalla apaisada) y no abajo: lo de abajo de la
  /// pantalla, como el horizonte de Neón, sigue a la vista.
  final bool planoAlCostado;

  /// Ver [EscenaTotem.alrededorDeLaFoto].
  final Widget Function(Widget foto)? alrededorDeLaFoto;

  /// Ver [EscenaTotem.alrededorDelBloque].
  final Widget Function(Widget bloque, Size pantalla)? alrededorDelBloque;

  /// Ver [EscenaTotem.alrededorDelTexto].
  final Widget Function(Widget frases)? alrededorDelTexto;

  const DatosEscena({
    required this.cfg,
    required this.estilo,
    required this.foto,
    required this.color,
    required this.segundo,
    required this.u,
    required this.ancho,
    required this.alto,
    required this.apaisado,
    required this.qrUrl,
    required this.enCamino,
    required this.entrada,
    required this.reloj,
    this.conPlano = false,
    this.planoAlCostado = false,
    this.alrededorDeLaFoto,
    this.alrededorDelBloque,
    this.alrededorDelTexto,
  });

  /// Lo mismo, para la parte de la pantalla que deja el plano.
  ///
  /// La medida sale de esa parte (una llegada mide unos 22 × 24 [u]), y nunca
  /// es menor que la de la pantalla entera: en una vertical queda igual, y en
  /// una apaisada la mitad izquierda se aprovecha entera. Lo que no entre lo
  /// achica `Centrado`.
  DatosEscena conPlanoEn(Size parte, {required bool alCostado}) => DatosEscena(
        cfg: cfg,
        estilo: estilo,
        foto: foto,
        color: color,
        segundo: segundo,
        u: math.max(u, math.min(parte.width / 22, parte.height / 24)),
        ancho: parte.width,
        alto: parte.height,
        apaisado: parte.width > parte.height * 1.2,
        qrUrl: qrUrl,
        enCamino: enCamino,
        entrada: entrada,
        reloj: reloj,
        conPlano: true,
        planoAlCostado: alCostado,
        alrededorDeLaFoto: alrededorDeLaFoto,
        alrededorDelBloque: alrededorDelBloque,
        alrededorDelTexto: alrededorDelTexto,
      );

  /// La parte de [entrada] que va de [desde] a [hasta], de 0 a 1.
  double tramo(double desde, double hasta, {Curve curva = Curves.easeOut}) =>
      curva.transform(((entrada - desde) / (hasta - desde)).clamp(0.0, 1.0));

  TotemConfig get c => cfg;

  /// Dónde va lo de la espera (la foto y las frases, juntas), dentro del lugar
  /// que deja cada apariencia. Al medio, como siempre, si nadie lo movió.
  Alignment get ubicacionDeLaEspera =>
      Alignment(cfg.ubicacionX / 100, cfg.ubicacionY / 100);

  /// Lo de la espera, con lo que le ponga Personalizar para moverlo.
  Widget bloque(Widget lo) =>
      alrededorDelBloque?.call(lo, Size(ancho, alto)) ?? lo;

  /// Las frases de la espera (todo lo que va debajo de la foto), en su tamaño
  /// ([TotemConfig.textoTamano]) y con lo que les ponga Personalizar para
  /// agrandarlas.
  Widget frases(List<Widget> todas) {
    final Widget columna = Escalado(
      factor: cfg.textoTamano / 100,
      child: Column(mainAxisSize: MainAxisSize.min, children: todas),
    );
    return alrededorDelTexto?.call(columna) ?? columna;
  }
}

/// Su hijo, más grande o más chico: a diferencia de `Transform.scale`, ocupa
/// lo que mide agrandado, así lo de abajo se corre y nada se pisa.
class Escalado extends SingleChildRenderObjectWidget {
  final double factor;

  const Escalado({super.key, required this.factor, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEscalado(factor);

  @override
  void updateRenderObject(BuildContext context, RenderEscalado renderObject) {
    renderObject.factor = factor;
  }
}

/// Lo que dibuja [Escalado].
class RenderEscalado extends RenderProxyBox {
  RenderEscalado(this._factor);

  double _factor;
  double get factor => _factor;
  set factor(double v) {
    if (v == _factor) return;
    _factor = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final hijo = child;
    if (hijo == null) {
      size = constraints.smallest;
      return;
    }
    // Se le da al hijo el lugar que tiene, achicado, y se agranda lo que mide.
    final c = constraints;
    hijo.layout(
      BoxConstraints(
        minWidth: c.minWidth / _factor,
        maxWidth: c.maxWidth / _factor,
        minHeight: c.minHeight / _factor,
        maxHeight: c.maxHeight / _factor,
      ),
      parentUsesSize: true,
    );
    size = c.constrain(hijo.size * _factor);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final hijo = child;
    if (hijo == null) return;
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.diagonal3Values(_factor, _factor, 1),
      (context, offset) => context.paintChild(hijo, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final hijo = child;
    if (hijo == null) return false;
    return result.addWithPaintTransform(
      transform: Matrix4.diagonal3Values(_factor, _factor, 1),
      position: position,
      hitTest: (result, p) => hijo.hitTest(result, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(Matrix4.diagonal3Values(_factor, _factor, 1));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height / _factor) ?? 0) * _factor;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height / _factor) ?? 0) * _factor;
  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(width / _factor) ?? 0) * _factor;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(width / _factor) ?? 0) * _factor;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final hijo = child;
    if (hijo == null) return constraints.smallest;
    final c = constraints;
    return c.constrain(
      hijo.getDryLayout(BoxConstraints(
            minWidth: c.minWidth / _factor,
            maxWidth: c.maxWidth / _factor,
            minHeight: c.minHeight / _factor,
            maxHeight: c.maxHeight / _factor,
          )) *
          _factor,
    );
  }
}

/// Una apariencia: cómo se dibuja la espera y cómo una llegada.
abstract class EscenaEstilo {
  const EscenaEstilo();

  /// Lo que va entre el fondo animado y el contenido (la foto a pantalla
  /// completa del Póster).
  List<Widget> capasDeFondo(DatosEscena d) => const [];

  Widget espera(DatosEscena d);

  Widget llegada(DatosEscena d, ContenidoBienvenida c);
}

// ── Piezas comunes ─────────────────────────────────────────────────────────

/// El plano en la llegada: la hoja de la mesa de la familia, con su mesa
/// encendida y el camino desde el ingreso, en el tema de la apariencia
/// ([temaPlanoDelTotem]).
class PanelPlano extends StatelessWidget {
  final PlanoDeLaLlegada guia;
  final TemaPlano tema;

  /// El color del evento: el borde del panel.
  final Color borde;
  final double u;

  /// False: quieto (tests y muestras).
  final bool animar;

  /// Cuánto se dibujó del camino desde el ingreso, de 0 a 1.
  final double progresoCamino;

  const PanelPlano({
    super.key,
    required this.guia,
    required this.tema,
    required this.borde,
    required this.u,
    this.animar = true,
    this.progresoCamino = 1,
  });

  @override
  Widget build(BuildContext context) {
    final redondeo = BorderRadius.circular(u * 0.6);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: redondeo,
        border: Border.all(
          color: borde.withValues(alpha: 0.35),
          width: math.max(1, u * 0.05),
        ),
      ),
      child: ClipRRect(
        borderRadius: redondeo,
        child: VistaPlano(
          armado: guia.armado,
          hoja: guia.hoja,
          tema: tema,
          estado: guia.estado,
          resaltadas: guia.mesas,
          ruta: guia.ruta,
          progresoRuta: progresoCamino,
          animar: animar,
        ),
      ),
    );
  }
}

/// Lo que va en el medio de la pantalla, que nunca se corta: si no entra, se
/// achica entero. A lo ancho, los textos se parten en renglones.
class Centrado extends StatelessWidget {
  final Widget child;
  final EdgeInsets margen;

  /// Dónde va dentro del margen. Al medio, si no se dice.
  final Alignment ubicacion;

  const Centrado({
    super.key,
    required this.child,
    required this.margen,
    this.ubicacion = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margen,
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment(
            ubicacion.x.clamp(-1.0, 1.0),
            ubicacion.y.clamp(-1.0, 1.0),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// La foto de la espera como se eligió en Personalizar: su forma y su tamaño.
/// Null si se apagó ([TotemConfig.mostrarFoto]).
///
/// [lado] es el ancho al 100 %, el de siempre en cada apariencia. [alrededor]
/// le pone algo a la foto ya armada (el anillo de Gala), con su medida.
Widget? fotoDeLaEspera(
  DatosEscena d, {
  required double lado,
  required Color borde,
  required double grosor,
  Color? brillo,
  Widget Function(Widget foto, FormaFoto forma, Size medida)? alrededor,
}) {
  if (!d.cfg.mostrarFoto) return null;
  final forma = FormaFoto.de(d.cfg.fotoForma);
  final ancho = lado * d.cfg.fotoTamano / 100;
  Widget foto = FotoEvento(
    imagen: d.foto,
    lado: ancho,
    borde: borde,
    grosor: grosor,
    forma: forma,
    brillo: brillo,
  );
  // Las manijas de Personalizar van pegadas a la foto.
  foto = d.alrededorDeLaFoto?.call(foto) ?? foto;
  return alrededor == null ? foto : alrededor(foto, forma, forma.medida(ancho));
}

/// La foto del evento en su forma (el círculo, si nadie eligió otra); sin
/// foto, o si no baja, el logo de la empresa. "Tal cual" la muestra entera,
/// sin recortar ni marco.
class FotoEvento extends StatelessWidget {
  final ImageProvider? imagen;

  /// El ancho.
  final double lado;
  final Color borde;
  final double grosor;
  final FormaFoto forma;

  /// Un resplandor de este color alrededor ("Tu fondo"). Null: sin.
  final Color? brillo;

  const FotoEvento({
    super.key,
    required this.imagen,
    required this.lado,
    required this.borde,
    this.grosor = 2,
    this.forma = FormaFoto.circulo,
    this.brillo,
  });

  @override
  Widget build(BuildContext context) {
    final medida = forma.medida(lado);
    final talCual = forma == FormaFoto.talCual;
    final logo = Padding(
      padding: EdgeInsets.all(talCual ? 0 : medida.shortestSide * 0.18),
      child: Image.asset(
        'assets/icons/logo-transparent-final.png',
        fit: BoxFit.contain,
        color: const Color(0xFFF2F0EB),
        errorBuilder: (_, _, _) => Icon(
          Icons.celebration_rounded,
          size: medida.shortestSide * 0.5,
          color: const Color(0xFFF2F0EB),
        ),
      ),
    );
    final imagen = this.imagen;
    if (talCual) {
      return SizedBox.fromSize(
        size: medida,
        child: imagen == null
            ? logo
            : Image(
                image: imagen,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => logo,
              ),
      );
    }
    return SizedBox.fromSize(
      size: medida,
      child: CustomPaint(
        painter: _FondoDeLaForma(forma: forma, grosor: grosor, brillo: brillo),
        foregroundPainter: _BordeDeLaForma(forma: forma, color: borde, grosor: grosor),
        child: ClipPath(
          clipper: _RecorteDeLaForma(forma, grosor),
          child: SizedBox.expand(
            child: imagen == null
                ? logo
                : Image(
                    image: imagen,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => logo,
                  ),
          ),
        ),
      ),
    );
  }
}

/// La foto va dentro del borde: el contorno de la forma, achicado el grosor.
class _RecorteDeLaForma extends CustomClipper<Path> {
  final FormaFoto forma;
  final double grosor;

  _RecorteDeLaForma(this.forma, this.grosor);

  @override
  Path getClip(Size size) => forma.camino((Offset.zero & size).deflate(grosor));

  @override
  bool shouldReclip(_RecorteDeLaForma old) =>
      old.forma != forma || old.grosor != grosor;
}

/// Detrás de la foto: el resplandor, si hay, y un fondo oscuro para el logo.
class _FondoDeLaForma extends CustomPainter {
  final FormaFoto forma;
  final double grosor;
  final Color? brillo;

  _FondoDeLaForma({required this.forma, required this.grosor, this.brillo});

  @override
  void paint(Canvas canvas, Size size) {
    final camino = forma.camino(Offset.zero & size);
    final b = brillo;
    if (b != null) {
      canvas.drawPath(
        camino,
        Paint()
          ..color = b.withValues(alpha: b.a * 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, size.shortestSide * 0.12),
      );
    }
    canvas.drawPath(camino, Paint()..color = Colors.black.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_FondoDeLaForma old) =>
      old.forma != forma || old.grosor != grosor || old.brillo != brillo;
}

/// El borde, sobre la foto: el contorno de la forma, por dentro.
class _BordeDeLaForma extends CustomPainter {
  final FormaFoto forma;
  final Color color;
  final double grosor;

  _BordeDeLaForma({required this.forma, required this.color, required this.grosor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      forma.camino((Offset.zero & size).deflate(grosor / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_BordeDeLaForma old) =>
      old.forma != forma || old.color != color || old.grosor != grosor;
}

/// El QR de un evento particular, con el texto de Personalizar debajo.
class QrDelTotem extends StatelessWidget {
  final String url;
  final String texto;
  final double u;
  final Color marco;

  /// El color del texto de abajo. Null: blanco, sobre los fondos oscuros.
  final Color? colorTexto;

  const QrDelTotem({
    super.key,
    required this.url,
    required this.texto,
    required this.u,
    required this.marco,
    this.colorTexto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(u * 0.3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(u * 0.35),
            border: Border.all(color: marco, width: u * 0.08),
          ),
          child: QrImageView(
            data: url,
            version: QrVersions.auto,
            size: u * 5,
            padding: EdgeInsets.zero,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF121212),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF121212),
            ),
          ),
        ),
        SizedBox(height: u * 0.45),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: FuentesTotem.linea,
            fontSize: u * 0.55,
            letterSpacing: u * 0.12,
            color: colorTexto ?? Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// El brillo de un neón: un núcleo blanco y dos halos del color.
List<Shadow> brilloNeon(Color color, double u, {double fuerza = 1}) => [
      Shadow(color: Colors.white.withValues(alpha: 0.8 * fuerza), blurRadius: u * 0.12),
      Shadow(color: color.withValues(alpha: fuerza), blurRadius: u * 0.35),
      Shadow(color: color.withValues(alpha: 0.7 * fuerza), blurRadius: u * 0.9),
    ];

/// Un texto que aparece letra por letra: con [progreso] en 0 no se ve nada, en
/// 1 está entero. El lugar lo ocupa desde el principio, así nada se mueve.
Widget letraPorLetra(String texto, TextStyle estilo, double progreso,
    {TextAlign align = TextAlign.center}) {
  final letras = texto.characters.toList();
  final n = letras.length;
  return Text.rich(
    TextSpan(
      children: [
        for (var i = 0; i < n; i++)
          TextSpan(
            text: letras[i],
            style: estilo.copyWith(
              color: (estilo.color ?? Colors.white).withValues(
                alpha: ((progreso * (n + 3) - i) / 3).clamp(0.0, 1.0) *
                    (estilo.color?.a ?? 1),
              ),
              shadows: ((progreso * (n + 3) - i) / 3) >= 1 ? estilo.shadows : null,
            ),
          ),
      ],
    ),
    textAlign: align,
  );
}

/// Lo de abajo del nombre: con quién viene o a quién acompaña.
String? conQuienDe(ContenidoBienvenida c) => c.conQuien ?? c.acompanaA;

/// Las sillas y la música, debajo de la mesa.
Widget sillasYMusica(
  ContenidoBienvenida c,
  DatosEscena d, {
  required String familia,
  Color? colorMusica,
  FontStyle estiloMusica = FontStyle.normal,
}) {
  final u = d.u;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (c.sillas != null) ...[
        SizedBox(height: u * 0.35),
        Text(
          c.sillas!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: FuentesTotem.linea,
            fontSize: u * 0.85,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ),
      ],
      if (c.musica != null) ...[
        SizedBox(height: u * 0.4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono y no el carácter de la nota: las letras no lo tienen.
            Icon(Icons.music_note_rounded,
                size: u * 0.95, color: colorMusica ?? d.color),
            SizedBox(width: u * 0.25),
            Flexible(
              child: Text(
                c.musica!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: familia,
                  fontStyle: estiloMusica,
                  // Las cifras alineadas también en la serif de Gala.
                  fontFeatures: const [FontFeature.liningFigures()],
                  fontSize: u * 0.9,
                  color: colorMusica ?? d.color,
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
