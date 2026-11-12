import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/totem_config.dart';
import '../../plano/estilos/estilo_plano.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/modelo/estado_plano.dart';
import '../../plano/widgets/vista_plano.dart';
import '../services/bienvenidas_totem.dart';
import '../services/contenido_bienvenida.dart';
import '../services/cuadro_del_salon.dart';
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

  /// El salón de la fiesta (6.4.0): en un masivo sorteado se ve entero toda la
  /// espera, con las frases en "el cuadro" ([CuadroDelSalon]); al llegar una
  /// familia, su nombre salta en grande y se acomoda en el cuadro, con su mesa
  /// encendida y el camino. Null: sin salón (un particular, antes del sorteo,
  /// el tótem por el navegador): todo como siempre.
  final ArmadoSalon? plano;

  /// Para las pruebas y las muestras, quieta: en qué parte de la llegada se
  /// dibuja. Null: acomodada.
  final FaseLlegada? faseFija;

  /// Para las muestras, quieta: cuánto se acomodó, de 0 (en grande) a 1. Manda
  /// sobre [faseFija].
  final double? acomodoFijo;

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
    this.faseFija,
    this.acomodoFijo,
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

  /// Lo que tarda el nombre en achicarse y acomodarse en el cuadro, después de
  /// los segundos en grande.
  static const acomodo = Duration(milliseconds: 800);

  /// El camino en el plano empieza a dibujarse a mitad del acomodo, y tarda
  /// esto.
  static const caminoDura = Duration(milliseconds: 1600);

  /// Cuánto se ve el salón detrás del nombre en grande.
  static const salonDetrasDelNombre = 0.22;

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

  /// Con el salón: de 0 (el nombre en grande) a 1 (acomodado en el cuadro).
  late final AnimationController _acomodo = AnimationController(
    vsync: this,
    duration: EscenaTotem.acomodo,
  );

  /// Cuándo el nombre deja de estar en grande.
  Timer? _alAcomodar;

  /// Lo que dura el nombre en grande, según la config.
  Duration get _nombreEnGrande =>
      TiemposDeBienvenida.de(widget.cfg, conSalon: true).nombre;

  /// Pone el acomodo de la llegada que está: quieta, la fase pedida; si no,
  /// en grande hasta que pasen sus segundos. [deNuevo]: es otra llegada.
  void _programarAcomodo({required bool deNuevo}) {
    _alAcomodar?.cancel();
    if (widget.quieta) {
      _acomodo.value = widget.acomodoFijo?.clamp(0.0, 1.0) ??
          (widget.faseFija == FaseLlegada.grande ? 0 : 1);
      return;
    }
    if (widget.llegada == null || widget.plano == null) {
      _acomodo.value = 0;
      return;
    }
    if (!deNuevo && _acomodo.value > 0) return;
    final empezo = widget.empezo ?? DateTime.now();
    final falta = empezo.add(_nombreEnGrande).difference(DateTime.now());
    if (falta <= Duration.zero) {
      // Ya pasaron (la escena se armó tarde, o achicaron los segundos).
      if (_acomodo.value == 0) _acomodo.forward(from: 0);
      return;
    }
    _acomodo.value = 0;
    _alAcomodar = Timer(falta, () {
      if (mounted) _acomodo.forward(from: 0);
    });
  }

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
    _programarAcomodo(deNuevo: true);
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
    final otraLlegada = widget.claveLlegada != old.claveLlegada ||
        (old.llegada == null) != (widget.llegada == null) ||
        old.empezo != widget.empezo ||
        (old.plano == null) != (widget.plano == null) ||
        old.faseFija != widget.faseFija ||
        old.acomodoFijo != widget.acomodoFijo;
    if (widget.quieta || otraLlegada) {
      _programarAcomodo(deNuevo: true);
    } else if (old.cfg.llegadaNombreSeg != widget.cfg.llegadaNombreSeg) {
      // Le cambiaron los segundos a mano, con el nombre en grande.
      _programarAcomodo(deNuevo: false);
    }
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
    _alAcomodar?.cancel();
    _acomodo.dispose();
    _entrada.dispose();
    _reloj.dispose();
    super.dispose();
  }

  // Dónde van el salón y el cuadro: una vez por plano, pantalla y lugar, no en
  // cada cuadro.
  CuadroDelSalon? _cuadro;
  ArmadoSalon? _cuadroPlano;
  Size? _cuadroPantalla;
  String? _cuadroLugar;

  CuadroDelSalon? _cuadroPara(Size pantalla, double u) {
    final plano = widget.plano;
    if (plano == null) return null;
    if (!identical(_cuadroPlano, plano) ||
        _cuadroPantalla != pantalla ||
        _cuadroLugar != widget.cfg.llegadaLugar) {
      _cuadroPlano = plano;
      _cuadroPantalla = pantalla;
      _cuadroLugar = widget.cfg.llegadaLugar;
      _cuadro = CuadroDelSalon.para(
        plano,
        pantalla: pantalla,
        u: u,
        elegido: LugarElegido.deClave(widget.cfg.llegadaLugar),
      );
    }
    return _cuadro;
  }

  // El salón sin nadie, para la espera: el mismo mientras no cambie el plano.
  EstadoPlano? _vacio;
  ArmadoSalon? _vacioPlano;

  EstadoPlano _salonVacio(ArmadoSalon plano) {
    if (!identical(_vacioPlano, plano) || _vacio == null) {
      _vacioPlano = plano;
      _vacio = EstadoPlano.desde(armado: plano);
    }
    return _vacio!;
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
    final tema =
        widget.plano == null ? null : temaPlanoDelTotem(estilo, color);
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth.isFinite ? c.maxWidth : 1080.0;
        final alto = c.maxHeight.isFinite ? c.maxHeight : 1920.0;
        final u = math.min(ancho, alto * 9 / 16) / 27;
        final cuadro = tema == null ? null : _cuadroPara(Size(ancho, alto), u);
        return ClipRect(
          child: AnimatedBuilder(
            animation: Listenable.merge([_entrada, _reloj, _acomodo]),
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
                  if (cuadro == null || tema == null) ...[
                    if (e < 1)
                      Opacity(
                        opacity: (1 - e * 1.6).clamp(0.0, 1.0),
                        child: escena.espera(datos),
                      ),
                    if (llegada != null && e > 0)
                      Opacity(
                        opacity: (e * 1.8).clamp(0.0, 1.0),
                        child: escena.llegada(datos, llegada),
                      ),
                  ] else
                    ..._conElSalon(escena, datos, cuadro, tema, guia, receta),
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
                            // Sobre un fondo propio claro, oscuro. Y sobre
                            // el salón a pantalla completa, si es claro.
                            color: receta != null && receta.textoOscuro
                                ? Color.lerp(
                                    receta.colores.saludo,
                                    Colors.black,
                                    0.35,
                                  )
                                : cuadro != null &&
                                        tema != null &&
                                        ancho > alto * 1.2 &&
                                        tema.fondo.computeLuminance() > 0.5
                                    // Oscuro en la medida en que el salón
                                    // claro está a la vista: detrás del
                                    // nombre en grande sigue blanco.
                                    ? Color.lerp(
                                        Colors.white,
                                        const Color(0xFF2B2823),
                                        _opacidadDelSalon(e),
                                      )!
                                        .withValues(alpha: 0.85)
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

  /// Cuánto se dibujó del camino, de 0 a 1: arranca a mitad del acomodo y
  /// tarda [EscenaTotem.caminoDura]. Quieta, entero.
  double get _progresoCamino {
    final a = widget.empezo;
    if (widget.quieta || a == null) return 1;
    final ms = DateTime.now().difference(a).inMilliseconds -
        _nombreEnGrande.inMilliseconds -
        EscenaTotem.acomodo.inMilliseconds ~/ 2;
    return (ms / EscenaTotem.caminoDura.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Cuánto se ve el salón: entero en la espera; detrás del nombre en grande,
  /// apenas; y vuelve mientras el nombre se acomoda.
  double _opacidadDelSalon(double entrada) {
    if (widget.llegada == null) return 1;
    const atras = EscenaTotem.salonDetrasDelNombre;
    final a =
        Curves.easeInOutCubic.transform(_acomodo.value.clamp(0.0, 1.0));
    return (1 + (atras + (1 - atras) * a - 1) * entrada.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
  }

  /// Con el salón (6.4.0, pedido del jefe el 4-nov): el salón entero siempre a
  /// la vista, lo de la espera en el cuadro y, cuando llega una familia, su
  /// nombre en grande con el salón apagado detrás que después se achica hasta
  /// el cuadro, mientras su mesa se enciende y se dibuja el camino.
  ///
  /// El nombre se arma una sola vez, a la medida del cuadro, y se agranda
  /// entero: así se achica sin moverse nada adentro. Si el cuadro cae adentro
  /// del salón (la pista o un hueco), va sobre un cartel oscuro: el salón es
  /// claro y las letras de las apariencias, no.
  List<Widget> _conElSalon(
    EscenaEstilo escena,
    DatosEscena d,
    CuadroDelSalon cuadro,
    TemaPlano tema,
    PlanoDeLaLlegada? guia,
    RecetaDibujada? receta,
  ) {
    final plano = widget.plano!;
    final llegada = widget.llegada;
    final e = d.entrada.clamp(0.0, 1.0);
    final a = llegada == null
        ? 0.0
        : Curves.easeInOutCubic.transform(_acomodo.value.clamp(0.0, 1.0));
    final encendido = llegada != null && guia != null && _acomodo.value > 0;

    final opacidad = _opacidadDelSalon(d.entrada);

    final enElSalon = cuadro.lugar == LugarDelCuadro.pista ||
        cuadro.lugar == LugarDelCuadro.hueco;
    // En una tele acostada el salón es toda la pantalla (pedido del usuario,
    // 12-nov-2026): el fondo del plano llega a los cuatro bordes, sin las dos
    // bandas con el fondo de la apariencia a los costados. El dibujo no cambia
    // de lugar ni de tamaño (ya ocupa todo el alto), y su borde sigue latiendo.
    final pantallaCompleta = d.apaisado;
    // Opaco: que no se transparente el nombre del sector de abajo.
    final cartelClaro = receta != null && receta.textoOscuro;
    final cartel =
        cartelClaro ? const Color(0xFFF7F5F0) : const Color(0xFF121218);
    Widget sobreCartel(Widget hijo, double cuanto) => cuanto <= 0
        ? hijo
        : DecoratedBox(
            decoration: BoxDecoration(
              color: cartel.withValues(alpha: cartel.a * cuanto),
              borderRadius: BorderRadius.circular(d.u * 0.6),
              border: Border.all(
                color: d.color.withValues(alpha: 0.45 * cuanto),
                width: math.max(1, d.u * 0.06),
              ),
            ),
            child: hijo,
          );

    // Lo de adentro se arma en su tamaño de siempre, con la forma del cuadro,
    // y se achica entero: así nada se parte en renglones ni cambia de lugar.
    final escala =
        CuadroDelSalon.escalaDelContenido(cuadro.cuadro.size, d.u);
    final aMedida = cuadro.cuadro.size / escala;
    final enCuadro = d.conPlanoEn(aMedida, alCostado: cuadro.alCostado);
    Widget achicado(Widget hijo) => FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.fromSize(size: aMedida, child: hijo),
        );
    // En grande: casi toda la pantalla, con su propia forma; al acomodarse se
    // achica hacia el cuadro mientras aparece la tarjeta acomodada.
    final grande = _enGrande(Size(d.ancho, d.alto), d.u);
    final enGrande = d.conPlanoEn(grande.size, alCostado: false);
    final hacia = Rect.lerp(grande, _conLaForma(grande.size, cuadro.cuadro), a)!;
    // Que no se vean las dos a la vez: la grande se va en la primera parte
    // del acomodo, mientras se achica; la acomodada llega en la segunda.
    final sale = llegada == null ? 0.0 : (1 - a / 0.55).clamp(0.0, 1.0);
    final entra = llegada == null ? 0.0 : ((a - 0.45) / 0.55).clamp(0.0, 1.0);

    // Lo de la espera y la tarjeta acomodada en una franja al lado del salón:
    // a pantalla completa caen sobre el fondo claro del plano, y las letras de
    // las apariencias son claras. Van sobre el cartel, como en la pista.
    Widget enLaFranja(Widget hijo) =>
        pantallaCompleta ? sobreCartel(hijo, 1) : hijo;

    final panel = PanelPlano(
      armado: plano,
      hoja: encendido ? guia.hoja : cuadro.hoja,
      estado: encendido ? guia.estado : _salonVacio(plano),
      resaltadas: encendido ? guia.mesas : const {},
      ruta: encendido ? guia.ruta : null,
      tema: tema,
      borde: d.color,
      u: d.u,
      relleno: cuadro.relleno,
      animar: !widget.quieta,
      progresoCamino: _progresoCamino,
      // Mientras el camino marca la mesa, el borde late.
      pulsar: encendido,
    );

    return [
      if (pantallaCompleta)
        // El fondo y el panel se apagan juntos, como una sola cosa: detrás del
        // nombre en grande no se nota dónde termina uno y empieza el otro.
        Positioned.fill(
          child: Opacity(
            opacity: opacidad,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  key: const Key('salon_a_pantalla_completa'),
                  color: tema.fondo,
                ),
                Positioned.fromRect(rect: cuadro.panel, child: panel),
              ],
            ),
          ),
        )
      else
        Positioned.fromRect(
          rect: cuadro.panel,
          child: Opacity(opacity: opacidad, child: panel),
        ),
      if (e < 1)
        Positioned.fromRect(
          rect: cuadro.cuadro,
          child: Opacity(
            opacity: (1 - e * 1.6).clamp(0.0, 1.0),
            // Adentro del salón, resumido: se lee de lejos en un lugar chico.
            child: enElSalon
                ? sobreCartel(
                    ResumenEnElSalon.deLaEspera(d, oscuro: cartelClaro),
                    1,
                  )
                : enLaFranja(achicado(escena.espera(enCuadro))),
          ),
        ),
      // El nombre en grande, sobre el salón apagado, con cartel. Se va
      // achicando hacia el cuadro mientras aparece el acomodado.
      if (llegada != null && e > 0 && sale > 0)
        Positioned.fromRect(
          rect: hacia,
          child: Opacity(
            opacity: ((e * 1.8).clamp(0.0, 1.0) * sale).clamp(0.0, 1.0),
            child: sobreCartel(
              FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(
                  size: grande.size,
                  child: escena.llegada(enGrande, llegada),
                ),
              ),
              // Apenas transparente: detrás se adivinan el salón y el fondo.
              0.8,
            ),
          ),
        ),
      // Acomodado en el cuadro: sobre el salón (la pista, un hueco) con
      // cartel; en una franja, sobre el fondo de la apariencia, sin.
      if (llegada != null && e > 0 && entra > 0)
        Positioned.fromRect(
          rect: cuadro.cuadro,
          child: Opacity(
            opacity: ((e * 1.8).clamp(0.0, 1.0) * entra).clamp(0.0, 1.0),
            // En la pista, el nombre y la mesa, en grande: el detalle ya se vio
            // con el nombre en grande.
            child: enElSalon
                ? sobreCartel(
                    ResumenEnElSalon.deLaLlegada(d, llegada, oscuro: cartelClaro),
                    1,
                  )
                : enLaFranja(achicado(escena.llegada(enCuadro, llegada))),
          ),
        ),
    ];
  }

  /// Dónde va el nombre en grande: casi toda la pantalla, sin pisar "N más en
  /// camino".
  static Rect _enGrande(Size pantalla, double u) => Rect.fromLTRB(
        u * CuadroDelSalon.margenEnU * 2,
        u * CuadroDelSalon.margenEnU * 2,
        pantalla.width - u * CuadroDelSalon.margenEnU * 2,
        pantalla.height - u * CuadroDelSalon.abajoEnU,
      );

  /// Un rectángulo con la forma de [forma], lo más grande que entra en
  /// [adentro], al medio: hacia donde se achica el nombre en grande.
  static Rect _conLaForma(Size forma, Rect adentro) {
    if (forma.width <= 0 || forma.height <= 0) return adentro;
    final s = math.min(adentro.width / forma.width, adentro.height / forma.height);
    return Rect.fromCenter(
      center: adentro.center,
      width: forma.width * s,
      height: forma.height * s,
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

/// Lo que va adentro del salón (la pista de baile, un hueco entre las mesas):
/// resumido, para que se lea de lejos en un lugar chico. En la espera, el
/// título, el subtítulo y el saludo; en la llegada, el nombre y la mesa, en
/// grande (pedido del usuario, 5-nov: la tarjeta en la pista). En la letra de
/// la apariencia y el color del evento.
class ResumenEnElSalon extends StatelessWidget {
  final DatosEscena d;
  final String grande;
  final String? acento;
  final double tamanoAcento;
  final String? chico;

  /// Sobre un cartel claro ("Tu fondo" con texto oscuro): letras oscuras.
  final bool oscuro;

  const ResumenEnElSalon._({
    required this.d,
    required this.grande,
    this.acento,
    this.tamanoAcento = 2.8,
    this.chico,
    this.oscuro = false,
  });

  /// El título, el subtítulo y el saludo.
  factory ResumenEnElSalon.deLaEspera(DatosEscena d, {bool oscuro = false}) {
    final sub = d.cfg.subtitulo.trim();
    return ResumenEnElSalon._(
      d: d,
      grande: d.cfg.titulo,
      acento: sub.isEmpty ? null : sub,
      tamanoAcento: 1.3,
      chico: d.cfg.mensajeBienvenida,
      oscuro: oscuro,
    );
  }

  /// El nombre y la mesa.
  factory ResumenEnElSalon.deLaLlegada(
    DatosEscena d,
    ContenidoBienvenida c, {
    bool oscuro = false,
  }) =>
      ResumenEnElSalon._(
        d: d,
        grande: c.nombres.length <= 1
            ? c.nombres.join()
            : '${c.nombres.first} y ${c.nombres.length - 1} más',
        acento: c.mesa == null ? null : '${c.rotuloMesa.toUpperCase()} ${c.mesa}',
        oscuro: oscuro,
      );

  String get _familia => switch (d.estilo) {
        EstiloTotem.neon => FuentesTotem.tubo,
        EstiloTotem.gala => FuentesTotem.gala,
        _ => FuentesTotem.cartelera,
      };

  @override
  Widget build(BuildContext context) {
    final u = d.u;
    final texto = oscuro ? const Color(0xFF1C1A16) : Colors.white;
    const cifras = [FontFeature.liningFigures()];
    return Padding(
      padding: EdgeInsets.all(u * 0.5),
      child: LayoutBuilder(
        builder: (context, c) => Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              // Un nombre largo va en dos renglones antes que achicarse tanto.
              constraints: BoxConstraints(maxWidth: math.max(c.maxWidth, u * 16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    grande,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _familia,
                      fontWeight: FontWeight.w700,
                      fontSize: u * 2.2,
                      height: 1.05,
                      color: texto,
                      fontFeatures: cifras,
                    ),
                  ),
                  if (acento != null) ...[
                    SizedBox(height: u * 0.3),
                    Text(
                      acento!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _familia,
                        fontWeight: FontWeight.w700,
                        fontSize: u * tamanoAcento,
                        letterSpacing: u * 0.06,
                        color: d.color,
                        fontFeatures: cifras,
                      ),
                    ),
                  ],
                  if (chico != null && chico!.trim().isNotEmpty) ...[
                    SizedBox(height: u * 0.3),
                    Text(
                      chico!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: FuentesTotem.linea,
                        fontSize: u * 1.0,
                        color: texto.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// En qué parte de la llegada está el nombre, con el salón.
enum FaseLlegada {
  /// En grande, con el salón apagado detrás.
  grande,

  /// En el cuadro, con su mesa encendida y el camino.
  acomodada,
}

/// El salón en el tótem: una hoja del plano en el tema del tótem
/// ([temaPlanoDelTotem]); en la espera, sin nadie; en la llegada, con la mesa
/// de la familia encendida y el camino desde el ingreso, y con [pulsar] el
/// borde late en el color del evento (pedido del usuario, 5-nov: "que haga un
/// efecto pulso los bordes del plano").
class PanelPlano extends StatefulWidget {
  final ArmadoSalon armado;
  final String hoja;
  final EstadoPlano estado;
  final Set<int> resaltadas;

  /// El camino desde el ingreso, en coordenadas del plano. Null: sin camino.
  final List<Offset>? ruta;
  final TemaPlano tema;

  /// El color del evento: el borde del panel.
  final Color borde;
  final double u;

  /// Lo que hay entre el borde y el dibujo ([CuadroDelSalon.relleno]).
  final double relleno;

  /// False: quieto (tests y muestras).
  final bool animar;

  /// Cuánto se dibujó del camino desde el ingreso, de 0 a 1.
  final double progresoCamino;

  /// El borde late: mientras el camino marca la mesa de la familia.
  final bool pulsar;

  /// Cuánto tarda un latido del borde.
  static const latido = Duration(milliseconds: 1400);

  const PanelPlano({
    super.key,
    required this.armado,
    required this.hoja,
    required this.estado,
    this.resaltadas = const {},
    this.ruta,
    required this.tema,
    required this.borde,
    required this.u,
    this.relleno = 0,
    this.animar = true,
    this.progresoCamino = 1,
    this.pulsar = false,
  });

  /// El de la llegada de una familia: su mesa encendida y su camino.
  factory PanelPlano.deLaLlegada(
    PlanoDeLaLlegada guia, {
    Key? key,
    required TemaPlano tema,
    required Color borde,
    required double u,
    double relleno = 0,
    bool animar = true,
    double progresoCamino = 1,
    bool pulsar = true,
  }) =>
      PanelPlano(
        key: key,
        armado: guia.armado,
        hoja: guia.hoja,
        estado: guia.estado,
        resaltadas: guia.mesas,
        ruta: guia.ruta,
        tema: tema,
        borde: borde,
        u: u,
        relleno: relleno,
        animar: animar,
        progresoCamino: progresoCamino,
        pulsar: pulsar,
      );

  @override
  State<PanelPlano> createState() => _PanelPlanoState();
}

class _PanelPlanoState extends State<PanelPlano>
    with SingleTickerProviderStateMixin {
  late final AnimationController _latido = AnimationController(
    vsync: this,
    duration: PanelPlano.latido,
  );

  @override
  void initState() {
    super.initState();
    _ajustar();
  }

  @override
  void didUpdateWidget(PanelPlano old) {
    super.didUpdateWidget(old);
    _ajustar();
  }

  /// Late solo si hay que pulsar y se anima: quieto, la escena se queda
  /// quieta (y un `pumpAndSettle` termina).
  void _ajustar() {
    final mover = widget.pulsar && widget.animar;
    if (mover && !_latido.isAnimating) {
      _latido.repeat();
    } else if (!mover && _latido.isAnimating) {
      _latido
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  /// De 0 a 1 y de vuelta, en cada latido. Quieto y pulsando, a mitad.
  double get _cuanto {
    if (!widget.pulsar) return 0;
    if (!widget.animar) return 0.6;
    return 0.5 - 0.5 * math.cos(2 * math.pi * _latido.value);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final u = w.u;
    final redondeo = BorderRadius.circular(u * 0.6);
    final dibujo = ClipRRect(
      borderRadius: redondeo,
      child: ColoredBox(
        color: w.tema.fondo,
        child: Padding(
          padding: EdgeInsets.all(w.relleno),
          child: VistaPlano(
            armado: w.armado,
            hoja: w.hoja,
            tema: w.tema,
            estado: w.estado,
            resaltadas: w.resaltadas,
            ruta: w.ruta,
            progresoRuta: w.progresoCamino,
            animar: w.animar,
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _latido,
      child: dibujo,
      builder: (context, dibujo) {
        final p = _cuanto;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: redondeo,
            boxShadow: p <= 0
                ? null
                : [
                    BoxShadow(
                      color: w.borde.withValues(alpha: 0.6 * p),
                      blurRadius: u * (0.5 + 1.1 * p),
                      spreadRadius: u * 0.15 * p,
                    ),
                  ],
          ),
          position: DecorationPosition.background,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: redondeo,
              border: Border.all(
                color: w.borde.withValues(alpha: 0.55 + 0.45 * p),
                width: math.max(1, u * (0.06 + 0.12 * p)),
              ),
            ),
            child: dibujo,
          ),
        );
      },
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

/// La música, debajo de la mesa. Las sillas ya no van en el salón (6.4.0):
/// las ve la recepcionista.
Widget musicaDeLaLlegada(
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
