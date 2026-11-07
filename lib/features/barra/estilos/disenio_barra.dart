import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cómo se ve VENDER. Los eligió el usuario con las maquetas (3-nov, noche): **Noche
/// dorada** (negro y dorado, la foto grande con el nombre encima) y **Mostrador**
/// (tarjetas blancas, el precio enorme, los pagos como barras en la tablet). Cada
/// equipo recuerda el suyo.
enum DisenioBarra {
  nocheDorada('noche_dorada', 'Noche dorada'),
  mostrador('mostrador', 'Mostrador');

  const DisenioBarra(this.clave, this.nombre);

  /// Lo que se guarda en el equipo.
  final String clave;
  final String nombre;

  /// Una clave vacía o que esta versión no conoce va a Noche dorada: nunca una
  /// pantalla rota.
  static DisenioBarra deClave(String? clave) =>
      values.firstWhere((d) => d.clave == clave, orElse: () => nocheDorada);
}

/// Los colores de VENDER que el tema de Material no tiene: la tarjeta, el precio, la
/// marca del stock, los tres pagos. Los valores salen de la maqueta aprobada
/// (`build/maquetas/barra_disenios.html`).
@immutable
class TemaBarra extends ThemeExtension<TemaBarra> {
  final DisenioBarra disenio;

  /// El fondo de la pantalla: Noche dorada tiene un brillo arriba a la izquierda.
  final Gradient fondo;

  /// El costado de la cuenta (tablet y PC) y la cuenta de abajo (celular).
  final Color panel;
  final Color tarjeta;
  final Color tarjetaBorde;

  /// El borde (Noche dorada) o el halo (Mostrador) de un producto que está en la cuenta.
  final Color elegida;
  final Color nombre;
  final Color precio;
  final double precioTam;

  /// El − n + de la tarjeta.
  final Color pasoFondo;
  final Color pasoTexto;

  /// Sin foto: la inicial sobre este degradé.
  final Color inicialDesde;
  final Color inicialHasta;
  final Color inicialTexto;

  /// "Quedan 4" sobre la foto.
  final Color marcaFondo;
  final Color marcaTexto;

  /// "Agotado", "Sin stock" y el aviso de que quedan pocos.
  final Color marcaAviso;
  final Color total;
  final Color efectivo;
  final Color transferencia;
  final Color mixto;
  final Color mixtoTexto;

  /// Mixto sin relleno, con el borde del acento (Noche dorada).
  final bool mixtoConBorde;

  /// En la tablet y la PC, los tres pagos como barras anchas, una debajo de otra
  /// (Mostrador). En el celular van siempre en fila.
  final bool pagosApilados;

  const TemaBarra({
    required this.disenio,
    required this.fondo,
    required this.panel,
    required this.tarjeta,
    required this.tarjetaBorde,
    required this.elegida,
    required this.nombre,
    required this.precio,
    required this.precioTam,
    required this.pasoFondo,
    required this.pasoTexto,
    required this.inicialDesde,
    required this.inicialHasta,
    required this.inicialTexto,
    required this.marcaFondo,
    required this.marcaTexto,
    required this.marcaAviso,
    required this.total,
    required this.efectivo,
    required this.transferencia,
    required this.mixto,
    required this.mixtoTexto,
    required this.mixtoConBorde,
    required this.pagosApilados,
  });

  static const dorado = Color(0xFFD4AF37);
  static const doradoClaro = Color(0xFFE2BF55);

  static const nocheDorada = TemaBarra(
    disenio: DisenioBarra.nocheDorada,
    fondo: RadialGradient(
      center: Alignment(-0.6, -1.2),
      radius: 1.4,
      colors: [Color(0xFF1D1A12), Color(0xFF0C0C0D)],
      stops: [0, 0.55],
    ),
    panel: Color(0xFF121214),
    tarjeta: Color(0xFF151517),
    tarjetaBorde: Color(0x0FFFFFFF),
    elegida: dorado,
    nombre: Colors.white,
    precio: doradoClaro,
    precioTam: 16,
    pasoFondo: dorado,
    pasoTexto: Color(0xFF141108),
    inicialDesde: Color(0xFF2B2412),
    inicialHasta: Color(0xFF4A3C16),
    inicialTexto: Color(0xFFECD07A),
    marcaFondo: Color(0x8C000000),
    marcaTexto: Color(0xFFF0E6C8),
    marcaAviso: Color(0xD9D64838),
    total: doradoClaro,
    efectivo: Color(0xFF2D8A55),
    transferencia: Color(0xFF0A87CC),
    mixto: Colors.transparent,
    mixtoTexto: doradoClaro,
    mixtoConBorde: true,
    pagosApilados: false,
  );

  static const mostrador = TemaBarra(
    disenio: DisenioBarra.mostrador,
    fondo: LinearGradient(colors: [Color(0xFF17181B), Color(0xFF17181B)]),
    panel: Color(0xFF0F1012),
    tarjeta: Colors.white,
    tarjetaBorde: Colors.white,
    elegida: Color(0xFFF5C542),
    nombre: Color(0xFF111111),
    precio: Color(0xFF111111),
    precioTam: 22,
    pasoFondo: Color(0xFFF1F1F3),
    pasoTexto: Color(0xFF111111),
    inicialDesde: Color(0xFFECECEF),
    inicialHasta: Color(0xFFE2E2E6),
    inicialTexto: Color(0xFF555555),
    marcaFondo: Color(0xEBFFFFFF),
    marcaTexto: Color(0xFF333333),
    marcaAviso: Color(0xFFE23B2E),
    total: Colors.white,
    efectivo: Color(0xFF1FAA5C),
    transferencia: Color(0xFF009EE3),
    mixto: Color(0xFF3B3D43),
    mixtoTexto: Colors.white,
    mixtoConBorde: false,
    pagosApilados: true,
  );

  static TemaBarra de(DisenioBarra d) => switch (d) {
        DisenioBarra.nocheDorada => nocheDorada,
        DisenioBarra.mostrador => mostrador,
      };

  /// El de la pantalla, o Noche dorada si se pinta fuera de VENDER (un test suelto).
  static TemaBarra of(BuildContext context) =>
      Theme.of(context).extension<TemaBarra>() ?? nocheDorada;

  /// Un diseño no se mezcla con el otro: se cambia de una vez.
  @override
  TemaBarra copyWith() => this;

  @override
  TemaBarra lerp(TemaBarra? other, double t) => other == null || t < 0.5 ? this : other;
}

/// El tema de Material de VENDER con cada diseño: oscuro, con el acento del diseño, y
/// [TemaBarra] adentro. Lo usan también la hoja de cobro y la pantalla de los vales,
/// que se abren desde VENDER. De [base] (el tema de la app) toma solo las letras: los
/// colores de los botones y las casillas de la app son para fondo claro.
ThemeData temaDeVender(DisenioBarra d, {ThemeData? base}) {
  final barra = TemaBarra.de(d);
  final noche = d == DisenioBarra.nocheDorada;
  final acento = noche ? TemaBarra.dorado : Colors.white;
  final esquema = ColorScheme.fromSeed(
    seedColor: noche ? TemaBarra.dorado : const Color(0xFF009EE3),
    brightness: Brightness.dark,
  ).copyWith(
    primary: acento,
    onPrimary: noche ? const Color(0xFF141108) : const Color(0xFF111111),
    surface: noche ? const Color(0xFF161618) : const Color(0xFF1E1F23),
    onSurface: noche ? const Color(0xFFF3EFE4) : Colors.white,
    error: const Color(0xFFFF6B5E),
  );
  final letras = (base ?? ThemeData(brightness: Brightness.dark)).textTheme;
  // Las de los chips salen de las letras de la app: un TextStyle suelto (solo el
  // color) dejaba los chips sin la familia de la app.
  final letraChip = letras.labelLarge ?? const TextStyle();
  final tema = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: esquema,
    // Sólido: la pantalla de los vales es otra ruta y no tiene el degradé detrás.
    // VENDER pinta el suyo y deja el Scaffold transparente.
    scaffoldBackgroundColor: noche ? const Color(0xFF0C0C0D) : const Color(0xFF17181B),
    canvasColor: esquema.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: noche ? Colors.transparent : const Color(0xFF0F1012),
      foregroundColor: noche ? TemaBarra.doradoClaro : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: noche ? Colors.transparent : const Color(0xFF26282D),
      selectedColor: acento,
      labelStyle: letraChip.copyWith(color: noche ? const Color(0xFFCBC6B8) : const Color(0xFFE9E9E9)),
      secondaryLabelStyle: letraChip.copyWith(color: esquema.onPrimary, fontWeight: FontWeight.bold),
      side: BorderSide(color: noche ? const Color(0x1AFFFFFF) : Colors.transparent),
      showCheckmark: false,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: noche ? const Color(0x0DFFFFFF) : Colors.white,
      hintStyle: TextStyle(color: noche ? const Color(0xFF8F8B80) : const Color(0xFF7A7A7A)),
      prefixIconColor: noche ? const Color(0xFF8F8B80) : const Color(0xFF7A7A7A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: noche ? const Color(0x14FFFFFF) : Colors.transparent),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: noche ? const Color(0x14FFFFFF) : Colors.transparent),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: esquema.surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: esquema.surface),
    dividerColor: noche ? const Color(0x1AFFFFFF) : const Color(0xFF2C2E33),
    // La raya de un texto tachado (una venta anulada) con el color de la letra: si no,
    // queda la del tema claro de la app, casi negra, y sobre el fondo oscuro no se ve.
    textTheme: letras.apply(
      bodyColor: esquema.onSurface,
      displayColor: esquema.onSurface,
      decorationColor: esquema.onSurface,
    ),
    extensions: [barra],
  );
  return tema;
}

/// El diseño que eligió este equipo, en `SharedPreferences` (clave `barra.disenio`).
/// Nunca tira: si no se puede leer, Noche dorada.
class DisenioRecordado {
  static const _clave = 'barra.disenio';

  const DisenioRecordado();

  Future<DisenioBarra> leer() async {
    try {
      final p = await SharedPreferences.getInstance();
      return DisenioBarra.deClave(p.getString(_clave));
    } catch (_) {
      return DisenioBarra.nocheDorada;
    }
  }

  Future<void> guardar(DisenioBarra d) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_clave, d.clave);
    } catch (_) {}
  }
}

final disenioRecordadoProvider = Provider<DisenioRecordado>((ref) => const DisenioRecordado());

/// El diseño de VENDER en este equipo: arranca en Noche dorada y se pone el recordado
/// apenas se lee. Elegir otro lo guarda.
class DisenioDeLaBarra extends Notifier<DisenioBarra> {
  @override
  DisenioBarra build() {
    ref.read(disenioRecordadoProvider).leer().then((d) {
      if (ref.mounted) state = d;
    });
    return DisenioBarra.nocheDorada;
  }

  Future<void> elegir(DisenioBarra d) async {
    state = d;
    await ref.read(disenioRecordadoProvider).guardar(d);
  }
}

final disenioDeLaBarraProvider =
    NotifierProvider<DisenioDeLaBarra, DisenioBarra>(DisenioDeLaBarra.new);
