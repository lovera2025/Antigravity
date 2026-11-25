import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modo_tele.dart';

/// **Girar la tele** (pedido del jefe, 25-nov-2026): la tele colgada parada.
///
/// Google TV manda siempre la imagen acostada (1920 × 1080). Con la tele
/// colgada parada, la app gira todo lo que dibuja un cuarto de vuelta y lo
/// acomoda a la pantalla parada (540 × 960 puntos): el tótem, el menú, los
/// carteles. **Lo recuerda cada tele** ([GiroGuardado], en el equipo) y se
/// elige con el control o desde el celular de la recepción, sin PIN.
///
/// En cuartos de vuelta, en el sentido del reloj:
/// - 0: acostada, como siempre;
/// - 1: parada (lo de arriba queda a la derecha de la tele acostada);
/// - 2: acostada, dada vuelta;
/// - 3: parada, para el otro lado.
abstract final class Giro {
  static int normal(int cuartos) => cuartos % 4;

  static bool esParada(int cuartos) => normal(cuartos).isOdd;

  /// "Horizontal": si ya está acostada, queda como está (también dada vuelta).
  static int horizontal(int cuartos) => esParada(cuartos) ? 0 : normal(cuartos);

  /// "Vertical": si ya está parada, queda como está.
  static int vertical(int cuartos) => esParada(cuartos) ? normal(cuartos) : 1;

  /// "Dar vuelta": media vuelta, para la tele que se colgó para el otro lado.
  static int darVuelta(int cuartos) => normal(cuartos + 2);

  static String nombre(int cuartos) => esParada(cuartos) ? 'Vertical' : 'Horizontal';
}

/// El giro guardado en este equipo (`tele_giro_v1`). Se lee antes de abrir la
/// app (`main.dart`), como el modo tele: la tele arranca ya girada.
class GiroGuardado {
  static const clave = 'tele_giro_v1';

  static int _leido = 0;
  static int get leido => _leido;

  static Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _leido = Giro.normal(prefs.getInt(clave) ?? 0);
    } catch (e) {
      debugPrint('El giro de la tele no se pudo leer: $e');
      _leido = 0;
    }
  }

  static Future<void> guardar(int cuartos) async {
    _leido = Giro.normal(cuartos);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_leido == 0) {
        await prefs.remove(clave);
      } else {
        await prefs.setInt(clave, _leido);
      }
    } catch (e) {
      debugPrint('El giro de la tele no se pudo guardar: $e');
    }
  }
}

/// Cuántos cuartos de vuelta gira esta tele. Las pruebas lo reemplazan: en la
/// ventana de prueba hay dos teles en el mismo proceso.
final giroDeLaTeleProvider = NotifierProvider<GiroDeLaTeleNotifier, int>(GiroDeLaTeleNotifier.new);

class GiroDeLaTeleNotifier extends Notifier<int> {
  @override
  int build() => GiroGuardado.leido;

  Future<void> poner(int cuartos) async {
    state = Giro.normal(cuartos);
    await GiroGuardado.guardar(state);
  }
}

/// **La app entera, girada como la tele** (en el `builder` del `MaterialApp`:
/// así giran también los carteles y lo que se abre encima). Solo en modo tele:
/// en la PC (sin modo tele) devuelve el hijo tal cual.
class GiroDeLaApp extends ConsumerWidget {
  const GiroDeLaApp({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enLaTele = ref.watch(modoTeleProvider) != null;
    return TeleGirada(
      cuartos: enLaTele ? ref.watch(giroDeLaTeleProvider) : null,
      child: child,
    );
  }
}

/// Gira [child] [cuartos] cuartos de vuelta y le da las medidas de la pantalla
/// como la ve quien mira (parada: 540 × 960), y traduce las flechas del control
/// a lo que ve quien mira: con la tele parada, la flecha de arriba sube en lo
/// que se ve, no en la pantalla acostada.
///
/// - [cuartos] null: **el hijo tal cual** (la PC no cambia nada).
/// - [cuartos] 0 (la tele acostada): el mismo árbol que girada, sin girar
///   nada. Así cambiar el giro no rearma la pantalla (el menú, lo que se estaba
///   escribiendo); y se ve igual que sin esto, píxel por píxel
///   (`tool/tele_salones_de_verdad_test.dart`).
class TeleGirada extends StatefulWidget {
  const TeleGirada({super.key, required this.cuartos, required this.child});

  final int? cuartos;
  final Widget child;

  @override
  State<TeleGirada> createState() => _TeleGiradaState();

  /// Las direcciones, en el sentido del reloj.
  static const _enOrden = [
    TraversalDirection.up,
    TraversalDirection.right,
    TraversalDirection.down,
    TraversalDirection.left,
  ];

  /// Hacia dónde va en la pantalla acostada la dirección [d] de lo que ve
  /// quien mira, con [cuartos] de giro. Lo que está arriba en lo girado un
  /// cuarto queda a la derecha de la pantalla: arriba es derecha.
  static TraversalDirection enLaPantalla(TraversalDirection d, int cuartos) =>
      _enOrden[(_enOrden.indexOf(d) + Giro.normal(cuartos)) % 4];

  /// Las flechas del control, con la tele girada: cada una va a
  /// [FlechaEnLoQueSeVe] (acostada, ninguna: las de Flutter, como siempre).
  static Map<ShortcutActivator, Intent> flechasGiradas(int cuartos) => Giro.normal(cuartos) == 0
      ? const {}
      : {
          for (final (tecla, d) in const [
            (LogicalKeyboardKey.arrowUp, TraversalDirection.up),
            (LogicalKeyboardKey.arrowRight, TraversalDirection.right),
            (LogicalKeyboardKey.arrowDown, TraversalDirection.down),
            (LogicalKeyboardKey.arrowLeft, TraversalDirection.left),
          ])
            SingleActivator(tecla): FlechaEnLoQueSeVe(d),
        };

  /// La opción que sigue hacia [d] en lo que ve quien mira, entre [opciones]
  /// (cada una con su lugar en lo que se ve), desde [desde]. Primero las que
  /// están en la misma franja (para abajo: las que se pisan de costado con la
  /// de ahora), la más cerca; si no hay, la más cerca de todas. Null: no hay
  /// ninguna para ese lado.
  static T? siguiente<T>(Rect desde, TraversalDirection d, Map<T, Rect> opciones) {
    const tolerancia = 0.5;
    bool haciaAlla(Rect r) => switch (d) {
          TraversalDirection.down => r.top >= desde.bottom - tolerancia ||
              (r.center.dy > desde.center.dy + tolerancia && r.top > desde.top + tolerancia),
          TraversalDirection.up => r.bottom <= desde.top + tolerancia ||
              (r.center.dy < desde.center.dy - tolerancia && r.bottom < desde.bottom - tolerancia),
          TraversalDirection.right => r.left >= desde.right - tolerancia ||
              (r.center.dx > desde.center.dx + tolerancia && r.left > desde.left + tolerancia),
          TraversalDirection.left => r.right <= desde.left + tolerancia ||
              (r.center.dx < desde.center.dx - tolerancia && r.right < desde.right - tolerancia),
        };
    final vertical = d == TraversalDirection.up || d == TraversalDirection.down;
    bool enLaFranja(Rect r) => vertical
        ? r.right > desde.left + tolerancia && r.left < desde.right - tolerancia
        : r.bottom > desde.top + tolerancia && r.top < desde.bottom - tolerancia;
    // Lo que hay que andar para llegar: a lo largo y, el doble, de costado.
    double distancia(Rect r) {
      final largo = switch (d) {
        TraversalDirection.down => r.top - desde.bottom,
        TraversalDirection.up => desde.top - r.bottom,
        TraversalDirection.right => r.left - desde.right,
        TraversalDirection.left => desde.left - r.right,
      };
      final costado =
          vertical ? (r.center.dx - desde.center.dx).abs() : (r.center.dy - desde.center.dy).abs();
      return largo.clamp(0.0, double.infinity) + (enLaFranja(r) ? costado * 0.01 : costado * 2);
    }

    final hacia = opciones.entries.where((e) => haciaAlla(e.value)).toList();
    if (hacia.isEmpty) return null;
    final franja = hacia.where((e) => enLaFranja(e.value)).toList();
    final elegibles = franja.isNotEmpty ? franja : hacia;
    elegibles.sort((a, b) => distancia(a.value).compareTo(distancia(b.value)));
    return elegibles.first.key;
  }

  /// Las medidas como las ve quien mira: con la tele parada, el ancho es el alto
  /// de la pantalla, y los bordes (si la tele tuviera alguno) giran igual.
  static MediaQueryData medidasGiradas(MediaQueryData m, int cuartos) {
    final q = Giro.normal(cuartos);
    if (q == 0) return m;
    EdgeInsets girar(EdgeInsets e) => switch (q) {
          // Lo de arriba de lo girado queda a la derecha de la pantalla.
          1 => EdgeInsets.fromLTRB(e.top, e.right, e.bottom, e.left),
          2 => EdgeInsets.fromLTRB(e.right, e.bottom, e.left, e.top),
          _ => EdgeInsets.fromLTRB(e.bottom, e.left, e.top, e.right),
        };
    return m.copyWith(
      size: q.isOdd ? m.size.flipped : m.size,
      padding: girar(m.padding),
      viewPadding: girar(m.viewPadding),
      viewInsets: girar(m.viewInsets),
      systemGestureInsets: girar(m.systemGestureInsets),
      displayFeatures: const [],
    );
  }
}

class _TeleGiradaState extends State<TeleGirada> {
  final _giro = GlobalKey(debugLabel: 'tele girada');

  /// Lo de adentro del giro: ahí se mide lo que ve quien mira.
  RenderBox? _contenido() {
    final r = _giro.currentContext?.findRenderObject();
    return r is RenderRotatedBox ? r.child : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cuartos;
    if (c == null) return widget.child;
    final q = Giro.normal(c);
    final medidas = MediaQuery.maybeOf(context);
    return RotatedBox(
      key: _giro,
      quarterTurns: q,
      child: Actions(
        actions: {FlechaEnLoQueSeVe: _MoverEnLoQueSeVe(_contenido)},
        child: Shortcuts(
          shortcuts: TeleGirada.flechasGiradas(q),
          child: medidas == null
              ? widget.child
              : MediaQuery(data: TeleGirada.medidasGiradas(medidas, q), child: widget.child),
        ),
      ),
    );
  }
}

/// Una flecha del control con la tele girada: hacia [direccion] **en lo que ve
/// quien mira**.
///
/// No se usa `DirectionalFocusIntent` traducida: Flutter mide dónde está cada
/// opción con `FocusNode.rect`, que con la pantalla girada sale dado vuelta
/// (el borde izquierdo a la derecha del derecho) y la flecha saltaba a
/// cualquier lado. Esto mide cada opción adentro del giro, donde todo está
/// derecho.
class FlechaEnLoQueSeVe extends Intent {
  const FlechaEnLoQueSeVe(this.direccion);
  final TraversalDirection direccion;
}

class _MoverEnLoQueSeVe extends Action<FlechaEnLoQueSeVe> {
  _MoverEnLoQueSeVe(this.contenido);
  final RenderBox? Function() contenido;

  @override
  Object? invoke(FlechaEnLoQueSeVe intent) {
    final foco = FocusManager.instance.primaryFocus;
    final raiz = contenido();
    if (foco == null || raiz == null || !raiz.attached) return null;
    Rect? lugar(FocusNode n) {
      final o = n.context?.findRenderObject();
      if (o is! RenderBox || !o.attached || !o.hasSize) return null;
      // Solo lo de adentro del giro.
      RenderObject? p = o;
      while (p != null && p != raiz) {
        p = p.parent;
      }
      if (p == null) return null;
      return MatrixUtils.transformRect(o.getTransformTo(raiz), Offset.zero & o.size);
    }

    final desde = lugar(foco);
    if (desde == null) return null;
    final opciones = <FocusNode, Rect>{
      for (final n in foco.nearestScope?.traversalDescendants ?? const <FocusNode>[])
        if (n != foco) n: ?lugar(n),
    };
    final siguiente = TeleGirada.siguiente(desde, intent.direccion, opciones);
    if (siguiente == null) return null;
    siguiente.requestFocus();
    final c = siguiente.context;
    if (c != null && c.mounted) {
      unawaited(Scrollable.ensureVisible(
        c,
        alignmentPolicy: intent.direccion == TraversalDirection.down ||
                intent.direccion == TraversalDirection.right
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ));
    }
    return null;
  }
}
