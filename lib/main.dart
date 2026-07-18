import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:io' show Platform;
import 'dart:convert';

import 'features/auth/login_screen.dart';
import 'features/caja_sesiones/providers/app_role_provider.dart';
import 'features/caja_sesiones/widgets/role_gate_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/cotizacion/public_selection_screen.dart';
import 'features/recepcion/operador_view.dart';
import 'features/recepcion/lista_invitados_screen.dart';
import 'features/recepcion/op_checkin_screen.dart';
import 'features/recepcion/recepcion_unified_screen.dart';
import 'features/totem/totem_display.dart';
import 'features/totem/totem_checkin_screen.dart';
import 'features/asesor/asesor_home_screen.dart';
import 'features/common/providers/user_role_provider.dart';
import 'features/common/widgets/operational_sync_coordinator.dart';
import 'services/supabase_service.dart';
import 'core/database/local_database.dart';

// URL base donde está deployada la app web (usada para generar QR de check-in)
const kWebBaseUrl = 'https://arguello-events.vercel.app';

// Supabase credentials
const supabaseUrl = 'https://bucnrydgojyzntgesxqb.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── DETECCIÓN DE MULTI-VENTANA (Desktop) ───────────────────────────────
  if (!kIsWeb && args.isNotEmpty && args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final String argumentJson = args.length > 2 ? args[2] : '{}';
    final Map<String, dynamic> arguments = jsonDecode(argumentJson);

    // No inicializamos el singleton global de Supabase en la ventana secundaria
    // para evitar el crash del plugin 'app_links' (MissingPluginException).
    // En su lugar, creamos un cliente independiente.
    final standaloneClient = SupabaseClient(supabaseUrl, supabaseAnonKey);

    // Not using windowManager in the secondary window because it crashes on Windows
    // (MissingPluginException) due to lack of multi-window support in window_manager plugin.
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      return null;
    });

    runApp(
      ProviderScope(
        overrides: [
          // Podemos sobreescribir el provider si TotemWindowApp lo usa
          supabaseProvider.overrideWithValue(standaloneClient),
        ],
        child: TotemWindowApp(
          windowId: windowId,
          arguments: arguments,
          client: standaloneClient,
        ),
      ),
    );
    return;
  }

  // Activar Path URL Strategy (elimina el # de la URL en web)
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // DETECCIÓN DE RUTA PÚBLICA (Catálogo QR)
  // Usamos el toString() completo para no depender de cómo procesa Flutter el path/fragment inicialmente
  final String currentUrl = kIsWeb ? Uri.base.toString() : "";
  final bool isCatalog = kIsWeb && currentUrl.contains('cotizar');
  final bool isBuscar = kIsWeb && currentUrl.contains('buscar');
  final bool isLista = kIsWeb && currentUrl.contains('lista');
  final bool isTotem = kIsWeb && currentUrl.contains('totem');
  final bool isOp = kIsWeb && currentUrl.contains('/op');

  // Initialize Supabase para AMBAS ramas (evita crashes)
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  } catch (e) {
    debugPrint('Error init Supabase: $e');
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(1024, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Junior Eventos',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (isCatalog) {
    debugPrint('V4 >>> LANZANDO SECTOR PÚBLICO: URL=$currentUrl');
    runApp(const ProviderScope(child: CatalogApp()));
  } else if (isOp) {
    final eventoId = Uri.base.queryParameters['evento'] ?? '';
    debugPrint('V4 >>> LANZANDO OPERADOR: eventoId=$eventoId');
    runApp(ProviderScope(child: OpApp(eventoId: eventoId)));
  } else if (isTotem) {
    final eventoId = Uri.base.queryParameters['evento'] ?? '';
    debugPrint('V4 >>> LANZANDO TÓTEM WEB: eventoId=$eventoId');
    runApp(ProviderScope(child: TotemWebApp(eventoId: eventoId)));
  } else if (isLista) {
    final eventoId = Uri.base.queryParameters['evento'] ?? '';
    debugPrint('V4 >>> LANZANDO LISTA PÚBLICA: eventoId=$eventoId');
    runApp(ProviderScope(child: ListaApp(eventoId: eventoId)));
  } else if (isBuscar) {
    final eventoId = Uri.base.queryParameters['evento'] ?? '';
    debugPrint('V4 >>> LANZANDO BUSCAR CHECK-IN: eventoId=$eventoId');
    runApp(ProviderScope(child: BuscarApp(eventoId: eventoId)));
  } else {
    // ── Desktop Admin: Inicializar SQLite local ────────────────────────────
    if (!kIsWeb) {
      try {
        // Inicializar DB
        await LocalDatabase.instance;
        debugPrint('✅ SQLite local inicializado correctamente');
      } catch (e) {
        debugPrint(
          '⚠️ Error al inicializar SQLite: $e (continuando sin cache local)',
        );
      }
    }
    debugPrint('V4 >>> LANZANDO SECTOR PRIVADO: Junior Eventos App');
    runApp(const ProviderScope(child: JuniorEventsApp()));
  }
}

/// App específica para el Catálogo Público.
/// Al ser independiente, NO tiene SplashScreen ni AuthWrapper.
class CatalogApp extends ConsumerWidget {
  const CatalogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Catálogo Junior Eventos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: const PublicSelectionScreen(),
    );
  }
}

/// App pública para operadores de recepción (check-in con PIN).
class OpApp extends ConsumerWidget {
  final String eventoId;
  const OpApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Recepción — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: OpCheckinScreen(eventoId: eventoId),
    );
  }
}

/// App pública para el tótem en pantalla externa (web, inmersivo).
class TotemWebApp extends ConsumerWidget {
  final String eventoId;
  const TotemWebApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Tótem — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: TotemDisplay(
        eventoId: eventoId,
        showExitButton: true,
        svc: SupabaseService(),
      ),
    );
  }
}

/// App pública para el check-in de invitados via QR del tótem.
class BuscarApp extends ConsumerWidget {
  final String eventoId;
  const BuscarApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Check-in — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: TotemCheckinScreen(eventoId: eventoId),
    );
  }
}

/// App pública para consultar la lista de invitados via QR del tótem.
class ListaApp extends ConsumerWidget {
  final String eventoId;
  const ListaApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Lista de Invitados — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: ListaInvitadosScreen(eventoId: eventoId),
    );
  }
}

/// App para la ventana secundaria del Tótem (Desktop).
class TotemWindowApp extends ConsumerWidget {
  final int windowId;
  final Map<String, dynamic> arguments;
  final SupabaseClient client;

  const TotemWindowApp({
    required this.windowId,
    required this.arguments,
    required this.client,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String eventoId = arguments['eventoId'] ?? '';

    return MaterialApp(
      title: 'Tótem — Junior Eventos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      home: TotemDisplay(
        eventoId: eventoId,
        showExitButton: true,
        svc: SupabaseService(client: client),
        windowId: windowId,
      ),
    );
  }
}

// Global Supabase client provider
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// Global theme mode provider using Notifier (Riverpod 3.x)
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void toggleTheme() {
    state = (state == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class JuniorEventsApp extends ConsumerWidget {
  const JuniorEventsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Junior Eventos',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          OperationalSyncCoordinator(child: child ?? const SizedBox.shrink()),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'AR')],
      locale: const Locale('es', 'AR'),
      onGenerateRoute: (settings) {
        // Rutas adicionales: operador (admin), tótem (pantalla vertical fullscreen), recepción unificada
        if (settings.name == '/totem_display') {
          final args = settings.arguments as Map<String, dynamic>?;
          final eventoId = args?['eventoId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (_) =>
                TotemDisplay(eventoId: eventoId, svc: SupabaseService()),
          );
        }
        if (settings.name == '/operador') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const OperadorView(),
          );
        }
        if (settings.name == '/recepcion_unified') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const RecepcionUnifiedScreen(),
          );
        }

        // Por defecto usamos SplashScreen para resolver auth/flow normal
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SplashScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    // Paleta Premium Base (Refinamiento Tenue)
    final Color primaryGold = const Color(0xFFD4AF37);
    final Color backgroundDark = const Color(0xFF0A0A0A);
    final Color surfaceDark = const Color(0xFF141414);
    final Color backgroundLight = const Color(
      0xFFF2F0EB,
    ); // Pearl / Warm Gray (Tenue)
    final Color surfaceLight = const Color(0xFFFBFBF9); // Creamy White

    var baseTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorSchemeSeed: primaryGold,
      scaffoldBackgroundColor: isDark ? backgroundDark : backgroundLight,
      cardColor: isDark ? surfaceDark : surfaceLight,
    );

    return baseTheme.copyWith(
      textTheme: GoogleFonts.outfitTextTheme(baseTheme.textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(
          textStyle: baseTheme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -0.5,
          ),
        ),
        titleMedium: GoogleFonts.outfit(
          textStyle: baseTheme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black87,
            letterSpacing: 0,
          ),
        ),
        bodyLarge: GoogleFonts.outfit(
          textStyle: baseTheme.textTheme.bodyLarge?.copyWith(
            color: isDark
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.black87,
            fontSize: 16,
          ),
        ),
      ),

      // Top Bar Ultra-Premium (Transparente o Glass)
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),

      // Input Decoration (Minimalist Luxury)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primaryGold, width: 1.5),
        ),
        labelStyle: TextStyle(
          color: isDark ? Colors.white54 : Colors.black54,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: primaryGold,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Card Theme (Soft shadows, subtle borders)
      cardTheme: CardThemeData(
        color: isDark ? surfaceDark : surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),

      // Transiciones fluidas
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  /// Un solo [Future.delayed] para el failsafe: si se recrea en cada build, el timer nunca termina.
  late final Future<void> _authSplashTimeout = Future.delayed(
    const Duration(seconds: 6),
  );

  /// Evita invalidar el rol en cada rebuild del [StreamBuilder] (podía provocar ciclos de actualización).
  String? _invalidatedRoleForUserId;

  /// Rehidrata sesión desde disco si el stream de auth tarda o falla (p. ej. sin internet).
  Session? _effectiveSession(
    AsyncSnapshot<AuthState> snapshot,
    SupabaseClient supabase,
  ) {
    if (snapshot.data?.session != null) {
      return snapshot.data!.session;
    }
    if (snapshot.hasError) {
      return supabase.auth.currentSession;
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return supabase.auth.currentSession;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final supabase = ref.watch(supabaseProvider);

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = _effectiveSession(snapshot, supabase);

        if (session != null) {
          final uid = session.user.id;
          if (_invalidatedRoleForUserId != uid) {
            _invalidatedRoleForUserId = uid;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.invalidate(userRoleProvider);
            });
          }
          return const _RoleRouter();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return FutureBuilder<void>(
            future: _authSplashTimeout,
            builder: (context, timerSnapshot) {
              if (timerSnapshot.connectionState == ConnectionState.done) {
                return const LoginScreen();
              }
              return const Scaffold(
                backgroundColor: Color(0xFF0A0A0A),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFD4AF37)),
                      SizedBox(height: 24),
                      Text(
                        'Sincronizando con la nube...',
                        style: TextStyle(
                          color: Colors.white30,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error de conexión con Supabase',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AuthWrapper()),
                      ),
                      child: const Text('REINTENTAR'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        _invalidatedRoleForUserId = null;
        return const LoginScreen();
      },
    );
  }
}

/// Router interno que consulta el rol del usuario y redirige.
class _RoleRouter extends ConsumerWidget {
  const _RoleRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(userRoleProvider);
    final appRole = ref.watch(appRoleProvider);

    return roleAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFD4AF37)),
              SizedBox(height: 24),
              Text(
                'Verificando permisos...',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
      error: (e, _) {
        // En caso de error, dar acceso mínimo (NUNCA dar admin por error)
        debugPrint('⚠️ Error checking role, showing Asesor view: $e');
        return const AsesorHomeScreen();
      },
      data: (role) {
        if (role.isAdmin) {
          if (appRole.kind == AppRoleKind.none) {
            return const RoleGateScreen();
          }
          if (appRole.esCaja && !appRole.tieneSesionCaja) {
            return const RoleGateScreen();
          }
          return const DashboardScreen();
        }
        return const AsesorHomeScreen();
      },
    );
  }
}
