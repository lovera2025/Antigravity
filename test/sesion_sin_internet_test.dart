// Entrar al programa sin internet con la sesión vencida (sección 5 de la
// 6.0.0). Con la librería de Supabase de verdad, haciendo lo mismo que hace al
// abrir el programa (`setInitialSession` y `recoverSession` con la sesión
// guardada), y la red cortada a propósito: no sale nada de la PC.
//
// El caso de todos los días: el permiso de Supabase dura una hora, así que el
// programa abierto al otro día arranca siempre con la sesión vencida.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/user_role_cache.dart';
import 'package:arguello_events/features/auth/sesion_sin_internet.dart';
import 'package:arguello_events/features/common/providers/user_role_provider.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;

const _uid = '11111111-0000-4000-8000-000000000001';

String _jwt(DateTime vence) {
  String b64(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': _uid, 'role': 'authenticated', 'exp': vence.millisecondsSinceEpoch ~/ 1000})}'
      '.firma';
}

Map<String, Object> _sesion(DateTime vence, {String refresco = 'refresco-1'}) => {
      'access_token': _jwt(vence),
      'expires_in': 3600,
      'refresh_token': refresco,
      'token_type': 'bearer',
      'user': {
        'id': _uid,
        'aud': 'authenticated',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-09-01T00:00:00Z',
      },
    };

/// La sesión que quedó guardada al cerrar el programa ayer: vencida.
final _guardadaAyer = jsonEncode(
    _sesion(DateTime.now().subtract(const Duration(hours: 14))));

/// La red: cortada, con internet, o con el servidor que rechaza la sesión.
class _Red {
  var hayInternet = false;
  var rechaza = false;
  var pedidosDeRenovar = 0;

  http.Client get cliente => MockClient((req) async {
        if (!hayInternet) throw const SocketException('Sin internet');
        if (req.url.path.endsWith('/token')) {
          pedidosDeRenovar++;
          if (rechaza) {
            return http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Invalid Refresh Token',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(_sesion(DateTime.now().add(const Duration(hours: 1)),
                refresco: 'refresco-2')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
}

class _Conexion extends ConnectivityService {
  _Conexion(this.estado);
  final AppConnectivity estado;
  @override
  AppConnectivity get currentStatus => estado;
}

/// Lo que ve la pantalla de inicio: cada aviso de Supabase, como lo arma el
/// `StreamBuilder` de `AuthWrapper`.
class _Avisos {
  _Avisos(GoTrueClient auth) {
    auth.onAuthStateChange.listen(
      (a) => lista.add(AsyncSnapshot.withData(ConnectionState.active, a)),
      onError: (Object e) =>
          lista.add(AsyncSnapshot.withError(ConnectionState.active, e)),
    );
  }
  final lista = <AsyncSnapshot<AuthState>>[];
}

void main() {
  late _Red red;
  late SupabaseClient supabase;

  setUp(() {
    red = _Red();
    supabase = SupabaseClient(
      'https://nube.test',
      'anon-de-test',
      httpClient: red.cliente,
    );
    // El renovador de cada 10 s hace lo mismo que `recoverSession`; acá se
    // lo para para que la prueba no dependa del reloj.
    supabase.auth.stopAutoRefresh();
  });

  tearDown(() => supabase.dispose());

  /// Lo que hace el programa al abrir (`supabase_flutter`): pone la guardada
  /// y trata de renovarla.
  Future<Object?> abrirElPrograma() async {
    await supabase.auth.setInitialSession(_guardadaAyer);
    try {
      await supabase.auth.recoverSession(_guardadaAyer);
      return null;
    } catch (e) {
      return e;
    }
  }

  test('sin internet y con la sesión vencida, entra', () async {
    final avisos = _Avisos(supabase.auth);
    final error = await abrirElPrograma();
    await Future<void>.delayed(Duration.zero);

    expect(error, isA<AuthRetryableFetchException>(),
        reason: 'no pudo renovarla por falta de internet');
    final guardada = supabase.auth.currentSession;
    expect(guardada, isNotNull, reason: 'la librería no la borra');
    expect(guardada!.isExpired, isTrue);
    expect(guardada.user.id, _uid);

    expect(avisos.lista, isNotEmpty);
    for (final aviso in avisos.lista) {
      expect(sesionParaEntrar(aviso, guardada)?.user.id, _uid,
          reason: 'con cada aviso, también el de error, se entra');
    }
    expect(avisos.lista.any((a) => a.hasError), isTrue);
  });

  test('vuelve internet: se renueva sola y sigue adentro', () async {
    final avisos = _Avisos(supabase.auth);
    await abrirElPrograma();
    red.hayInternet = true;
    await supabase.auth.refreshSession();
    await Future<void>.delayed(Duration.zero);

    final ahora = supabase.auth.currentSession!;
    expect(ahora.isExpired, isFalse);
    expect(ahora.refreshToken, 'refresco-2');
    expect(sesionParaEntrar(avisos.lista.last, ahora)?.user.id, _uid);
    expect(avisos.lista.last.data?.event, AuthChangeEvent.tokenRefreshed);
  });

  test('si el servidor la rechaza (cerraron la sesión), va al login', () async {
    red
      ..hayInternet = true
      ..rechaza = true;
    final avisos = _Avisos(supabase.auth);
    await abrirElPrograma();
    await Future<void>.delayed(Duration.zero);

    expect(red.pedidosDeRenovar, greaterThan(0));
    expect(supabase.auth.currentSession, isNull, reason: 'la borra');
    expect(
      avisos.lista.any((a) => a.data?.event == AuthChangeEvent.signedOut),
      isTrue,
    );
    // Después del aviso de salida llega el error del rechazo: tampoco entra.
    expect(sesionParaEntrar(avisos.lista.last, supabase.auth.currentSession),
        isNull);
  });

  test('sin ninguna sesión guardada en la PC, al login', () {
    final aviso = AsyncSnapshot<AuthState>.withData(
      ConnectionState.active,
      const AuthState(AuthChangeEvent.initialSession, null),
    );
    expect(sesionParaEntrar(aviso, null), isNull);
    expect(
      sesionParaEntrar(
          AsyncSnapshot<AuthState>.withError(
              ConnectionState.active, StateError('sin red')),
          null),
      isNull,
    );
  });

  test('mientras espera el primer aviso, con la guardada', () async {
    await supabase.auth.setInitialSession(_guardadaAyer);
    final guardada = supabase.auth.currentSession;
    expect(
      sesionParaEntrar(const AsyncSnapshot.waiting(), guardada)?.user.id,
      _uid,
    );
  });

  group('el rol, sin internet', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserRoleCache.save(
        UserRoleState(
          isAdmin: true,
          nombre: 'MAXI',
          permisos: UserPermissions.admin(),
          isLoading: false,
        ),
        _uid,
      );
    });

    /// Como al abrir el programa: la sesión guardada puesta y la renovación
    /// andando, sin esperarla (la app no la espera).
    Future<(UserRoleState, Duration)> rolCon(AppConnectivity estado) async {
      await supabase.auth.setInitialSession(_guardadaAyer);
      supabase.auth.recoverSession(_guardadaAyer).ignore();
      final c = ProviderContainer(overrides: [
        supabaseProvider.overrideWithValue(supabase),
        connectivityServiceProvider.overrideWithValue(_Conexion(estado)),
      ]);
      addTearDown(c.dispose);
      final reloj = Stopwatch()..start();
      final rol = await c.read(userRoleProvider.future);
      return (rol, reloj.elapsed);
    }

    test('sin red: el recordado en la PC, enseguida', () async {
      final (rol, tardo) = await rolCon(AppConnectivity.offline);
      expect(rol.isAdmin, isTrue);
      expect(rol.nombre, 'MAXI');
      expect(tardo, lessThan(const Duration(seconds: 1)));
    });

    test('con red pero sin salida a internet (un router solo): el recordado, '
        'sin esperar los 12 s', () async {
      final (rol, tardo) = await rolCon(AppConnectivity.online);
      expect(rol.isAdmin, isTrue);
      expect(tardo, lessThan(kEsperaDelRolRecordado + const Duration(seconds: 1)));
    });

    test('con internet, el de la nube, y queda recordado', () async {
      red.hayInternet = true;
      // La nube dice que ahora es Asesor.
      final c = ProviderContainer(overrides: [
        supabaseProvider.overrideWithValue(SupabaseClient(
          'https://nube.test',
          'anon-de-test',
          httpClient: MockClient((req) async => http.Response(
                req.url.path.contains('perfiles')
                    ? jsonEncode([
                        {'rol': 'Asesor', 'nombre': 'MAXI'}
                      ])
                    : '[]',
                200,
                headers: {'content-type': 'application/json'},
                request: req,
              )),
        )..auth.stopAutoRefresh()),
        connectivityServiceProvider
            .overrideWithValue(_Conexion(AppConnectivity.online)),
      ]);
      addTearDown(c.dispose);
      await c.read(supabaseProvider).auth.setInitialSession(jsonEncode(
          _sesion(DateTime.now().add(const Duration(hours: 1)))));
      final rol = await c.read(userRoleProvider.future);
      expect(rol.isAdmin, isFalse);
      expect((await UserRoleCache.load(_uid))!.isAdmin, isFalse);
    });

    test('sin nada recordado, el acceso mínimo, nunca jefe', () async {
      SharedPreferences.setMockInitialValues({});
      final (rol, _) = await rolCon(AppConnectivity.offline);
      expect(rol.isAdmin, isFalse);
    });
  });
}
