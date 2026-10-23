import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'fondo_totem.dart';
import 'fuentes_totem.dart';
import 'plano_del_totem.dart';
import 'totem_estilo.dart';

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

  /// El QR de la espera. Null: sin QR (un evento masivo).
  final String? qrUrl;

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
    this.qrUrl,
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

  @override
  void initState() {
    super.initState();
    if (widget.quieta) {
      _entrada.value = widget.llegada == null ? 0 : 1;
    } else {
      _reloj.repeat();
      if (widget.llegada != null) _entrada.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant EscenaTotem old) {
    super.didUpdateWidget(old);
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

  /// La que se dibuja: "Tu fondo" necesita su imagen; sin ella, [respaldo].
  EstiloTotem get _estilo => widget.estilo == EstiloTotem.tuFondo
      ? (widget.respaldo == EstiloTotem.tuFondo
          ? EstiloTotem.cristal
          : widget.respaldo)
      : widget.estilo;

  EscenaEstilo _escenaDe(EstiloTotem estilo) => switch (estilo) {
        EstiloTotem.neon => const EscenaNeon(),
        EstiloTotem.cristal => const EscenaCristal(),
        EstiloTotem.poster => const EscenaPoster(),
        EstiloTotem.gala => const EscenaGala(),
        EstiloTotem.tuFondo => const EscenaCristal(),
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
    final color = widget.cfg.colorAcento;
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
                segundo: segundoNeon(color),
                u: u,
                ancho: ancho,
                alto: alto,
                apaisado: ancho > alto * 1.2,
                qrUrl: widget.qrUrl,
                enCamino: widget.enCamino,
                entrada: e,
                reloj: reloj,
              );
              final llegada = widget.llegada;
              return Stack(
                fit: StackFit.expand,
                children: [
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
                            color: Colors.white.withValues(alpha: 0.85),
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
      );

  /// La parte de [entrada] que va de [desde] a [hasta], de 0 a 1.
  double tramo(double desde, double hasta, {Curve curva = Curves.easeOut}) =>
      curva.transform(((entrada - desde) / (hasta - desde)).clamp(0.0, 1.0));

  TotemConfig get c => cfg;
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

  const Centrado({super.key, required this.child, required this.margen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margen,
      child: LayoutBuilder(
        builder: (context, c) => Center(
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

/// La foto del evento en un círculo; sin foto, o si no baja, el logo de la
/// empresa.
class FotoEvento extends StatelessWidget {
  final ImageProvider? imagen;
  final double lado;
  final Color borde;
  final double grosor;

  const FotoEvento({
    super.key,
    required this.imagen,
    required this.lado,
    required this.borde,
    this.grosor = 2,
  });

  @override
  Widget build(BuildContext context) {
    final logo = Padding(
      padding: EdgeInsets.all(lado * 0.18),
      child: Image.asset(
        'assets/icons/logo-transparent-final.png',
        fit: BoxFit.contain,
        color: const Color(0xFFF2F0EB),
        errorBuilder: (_, _, _) => Icon(
          Icons.celebration_rounded,
          size: lado * 0.5,
          color: const Color(0xFFF2F0EB),
        ),
      ),
    );
    return Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: borde, width: grosor),
      ),
      child: ClipOval(
        child: imagen == null
            ? logo
            : Image(
                image: imagen!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => logo,
              ),
      ),
    );
  }
}

/// El QR de un evento particular, con el texto de Personalizar debajo.
class QrDelTotem extends StatelessWidget {
  final String url;
  final String texto;
  final double u;
  final Color marco;

  const QrDelTotem({
    super.key,
    required this.url,
    required this.texto,
    required this.u,
    required this.marco,
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
            color: Colors.white.withValues(alpha: 0.75),
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
