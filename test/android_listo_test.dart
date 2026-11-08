// La app en la tablet de la barra (Android, 6.4.0, etapa 9): firmada con la clave de
// Junior Eventos, con su ícono, que sale con cada versión y que no se rompe en lo que
// la tablet no tiene (la segunda ventana del tótem). Lo de la red del salón lo cuida
// `android_central_barra_test.dart`. Se leen los archivos, como
// `instalador_puesto_test.dart`: gradle y el instalador no se corren acá.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/app_update_checker.dart';
import 'package:arguello_events/core/services/kiosk_launcher.dart';
import 'package:arguello_events/features/barra/services/pantalla_despierta.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/dashboard/widgets/actualizar_app.dart';

import 'helpers/operadores_en_memoria.dart';

/// Cuenta lo que se le pide a las ventanas: en la tablet, nada.
class _VentanasQueNoEstan implements VentanasTotem {
  int pedidos = 0;

  Never _no() {
    pedidos++;
    throw MissingPluginException('desktop_multi_window no existe en Android');
  }

  @override
  Future<List<int>> abiertas() async => _no();
  @override
  Future<int> crear(String argumentos, {required Size tamanio, required String titulo}) async => _no();
  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) async => _no();
  @override
  Future<void> mostrar(int id) async => _no();
  @override
  Future<void> esconder(int id) async => _no();
}

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final instalador = File('installer/build_installer.ps1').readAsStringSync();

  group('la firma', () {
    test('release firma con la clave de android/key.properties', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('create("release")'));
      for (final campo in ['storeFile', 'storePassword', 'keyAlias', 'keyPassword']) {
        expect(gradle, contains('keyProperties.getProperty("$campo")'), reason: campo);
      }
      // La de prueba, solo si no hay clave.
      expect(
        gradle,
        matches(RegExp(
          r'signingConfig = if \(hayClaveDeFirma\) \{\s*signingConfigs\.getByName\("release"\)\s*\} else \{\s*signingConfigs\.getByName\("debug"\)',
        )),
      );
      expect('signingConfigs.getByName("debug")'.allMatches(gradle), hasLength(1));
    });

    test('el id de la app no cambia (otro id es otra app, sin sus ventas)', () {
      expect(gradle, contains('applicationId = "ar.com.junioreventos.app"'));
    });

    test('la clave y su contraseña no van a git', () {
      final raiz = File('.gitignore').readAsLinesSync().map((l) => l.trim()).toSet();
      expect(raiz, containsAll(['/android/key.properties', '*.jks', '*.keystore']));
      final android = File('android/.gitignore').readAsLinesSync().map((l) => l.trim()).toSet();
      expect(android, contains('key.properties'));
    });
  });

  test('el Bluetooth de la impresora: buscar sin ubicación desde Android 12, y los '
      'permisos viejos solo hasta Android 11', () {
    expect(
      manifest,
      contains('android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"'),
    );
    expect(manifest, contains('android.permission.BLUETOOTH_CONNECT'));
    for (final p in ['BLUETOOTH', 'BLUETOOTH_ADMIN', 'ACCESS_FINE_LOCATION']) {
      expect(manifest, contains('android.permission.$p" android:maxSdkVersion="30"'), reason: p);
    }
  });

  group('el instalador arma el APK', () {
    List<String> lineas() => instalador.split('\n').map((l) => l.trim()).toList();

    test('frena sin la clave, antes de compilar nada', () {
      final freno = instalador.indexOf(r'if (-not (Test-Path $keyProps))');
      expect(freno, greaterThan(0));
      expect(instalador, contains(r'$keyProps = Join-Path $root "android\key.properties"'));
      expect(freno, lessThan(instalador.indexOf('flutter build windows --release\n')));
      final bloque = instalador.substring(freno, instalador.indexOf('}', freno));
      expect(bloque, contains('Write-Error'));
    });

    test('compila el APK y comprueba con qué clave salió', () {
      expect(lineas(), contains('flutter build apk --release --split-per-abi'));
      expect(instalador, contains(r'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'));
      expect(instalador, contains(r'verify --print-certs'));
      expect(instalador, contains('CN=Junior Eventos'));
    });

    test('lo deja en dist con el nombre que busca la app', () {
      expect(instalador, contains(r'$apk = Join-Path $root "installer\dist\Junior Eventos v$semver.apk"'));
      expect(instalador, contains(r'Copy-Item $apkArmado $apk -Force'));
      // El nombre que sube GitHub (con puntos) es el que encuentra la tablet.
      final url = AppUpdateChecker.apkAssetUrl([
        {'name': 'Junior.Eventos.v6.4.0.apk', 'browser_download_url': 'https://x/apk'},
      ], '6.4.0');
      expect(url, 'https://x/apk');
    });
  });

  test('el ícono es el de Junior Eventos, también el adaptativo', () {
    expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(), isTrue);
    final png = File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync();
    // El de Flutter que traía el proyecto.
    expect(md5.convert(png).toString(), isNot('57838d52c318faff743130c3fcfae0c6'));
  });

  group('el tótem en la tablet', () {
    tearDown(KioskLauncher.reiniciar);

    test('no se abre ni pregunta por ventanas: se ve apagado', () async {
      final ventanas = _VentanasQueNoEstan();
      KioskLauncher.ventanas = ventanas;
      KioskLauncher.disponibleEnLaPrueba = false;

      await KioskLauncher.launch('11111111-1111-1111-1111-111111111111');
      await KioskLauncher.notifyListReset();

      expect(ventanas.pedidos, 0);
      expect(KioskLauncher.isTotemActive, isFalse);
    });

    test('la tarjeta TÓTEM del panel se apaga con el motivo donde no se puede', () {
      final panel = File('lib/features/dashboard/dashboard_screen.dart').readAsStringSync();
      final tarjeta = panel.substring(panel.indexOf("label: 'TÓTEM'"));
      expect(
        tarjeta.substring(0, tarjeta.indexOf('),')),
        contains('KioskLauncher.disponible ? null : KioskLauncher.motivoNoDisponible'),
      );
      expect(panel, contains('onTap: apagada ? null : a.onTap'));
    });
  });

  group('la versión nueva en la tablet', () {
    tearDown(() => AppUpdateChecker.enAndroidEnLaPrueba = null);

    test('el release elige el APK; sin APK, la página del release', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v6.4.1',
          'html_url': 'https://github.com/x/y/releases/tag/v6.4.1',
          'assets': [
            {'name': 'Setup.Junior.Eventos.v6.4.1.exe', 'browser_download_url': 'https://x/exe'},
            {'name': 'Junior.Eventos.v6.4.1.apk', 'browser_download_url': 'https://x/apk'},
          ],
        },
        currentVersion: '6.4.0',
      )!;
      expect(info.hayNueva, isTrue);
      expect(info.apkDownloadUrl, 'https://x/apk');
      expect(info.descargaEnAndroid, 'https://x/apk');
      expect(info.setupDownloadUrl, 'https://x/exe');

      final viejo = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v6.3.3',
          'html_url': 'https://github.com/x/y/releases/tag/v6.3.3',
          'assets': [
            {'name': 'Setup.Junior.Eventos.v6.3.3.exe', 'browser_download_url': 'https://x/exe'},
          ],
        },
        currentVersion: '6.3.2',
      )!;
      expect(viejo.apkDownloadUrl, isNull);
      expect(viejo.descargaEnAndroid, 'https://github.com/x/y/releases/tag/v6.3.3');
    });

    test('con dos APK, el de la versión; nunca uno de otra', () {
      final assets = [
        {'name': 'Junior.Eventos.v6.4.0.apk', 'browser_download_url': 'https://x/viejo'},
        {'name': 'Junior.Eventos.v6.4.1.apk', 'browser_download_url': 'https://x/nuevo'},
      ];
      expect(AppUpdateChecker.apkAssetUrl(assets, '6.4.1'), 'https://x/nuevo');
      expect(AppUpdateChecker.apkAssetUrl(assets, '6.4.2'), isNull);
      expect(AppUpdateChecker.apkAssetUrl(null, '6.4.1'), isNull);
    });

    test('el aviso está prendido en la tablet', () {
      AppUpdateChecker.enAndroidEnLaPrueba = true;
      expect(AppUpdateChecker.habilitado, isTrue);
      AppUpdateChecker.enAndroidEnLaPrueba = false;
      // En `flutter test` la plataforma dice Android pero no es una tablet: apagado.
      expect(AppUpdateChecker.habilitado, isFalse);
    });

    Future<void> abrirPin(WidgetTester tester, AppUpdateInfo? nueva) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...OperadoresEnPrueba().reemplazos,
          versionNuevaEnLaTabletProvider.overrideWith((ref) async => nueva),
        ],
        child: const MaterialApp(home: RoleGateScreen()),
      ));
      await tester.pump();
      await tester.pump();
    }

    const nueva = AppUpdateInfo(
      currentVersion: '6.4.0',
      latestVersion: '6.4.1',
      releaseUrl: 'https://github.com/x/y/releases/tag/v6.4.1',
      apkDownloadUrl: 'https://x/Junior.Eventos.v6.4.1.apk',
      hayNueva: true,
      notes: 'Arreglos de la barra',
    );

    testWidgets('la pantalla del PIN lo dice arriba', (tester) async {
      await abrirPin(tester, nueva);
      expect(find.byKey(const Key('entrada_version_nueva')), findsOneWidget);
      expect(find.text('Hay una versión nueva: 6.4.1'), findsOneWidget);
      expect(find.byKey(const Key('entrar_jefe')), findsOneWidget);
    });

    testWidgets('al día, no dice nada', (tester) async {
      await abrirPin(tester, null);
      expect(find.byKey(const Key('entrada_version_nueva')), findsNothing);
    });

    testWidgets('ACTUALIZAR en la tablet abre el APK en el navegador', (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppUpdateChecker.enAndroidEnLaPrueba = true;
      final abiertas = <Uri>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mostrarDialogoActualizacion(
                context,
                nueva,
                abrirEnElNavegador: (url) async {
                  abiertas.add(url);
                  return true;
                },
              ),
              child: const Text('PROBAR'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('PROBAR'));
      await tester.pumpAndSettle();
      expect(find.text('Arreglos de la barra'), findsOneWidget);
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
      expect(abiertas, [Uri.parse('https://x/Junior.Eventos.v6.4.1.apk')]);
      expect(find.text(kAvisoDescargaApk), findsOneWidget);
    });
  });

  group('la pantalla despierta mientras se vende', () {
    final pedidos = <MethodCall>[];

    setUp(() {
      pedidos.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PantallaDespierta.canal, (call) async {
        pedidos.add(call);
        return null;
      });
    });

    tearDown(() {
      PantallaDespierta.enAndroidEnLaPrueba = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PantallaDespierta.canal, null);
    });

    test('en la tablet prende y apaga; en la PC no pide nada', () async {
      PantallaDespierta.enAndroidEnLaPrueba = true;
      await PantallaDespierta.mantener(true);
      await PantallaDespierta.mantener(false);
      expect(pedidos.map((c) => '${c.method}:${c.arguments}'), ['despierta:true', 'despierta:false']);

      pedidos.clear();
      PantallaDespierta.enAndroidEnLaPrueba = false;
      await PantallaDespierta.mantener(true);
      expect(pedidos, isEmpty);
    });

    test('si el canal no contesta, no falla', () async {
      PantallaDespierta.enAndroidEnLaPrueba = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PantallaDespierta.canal, null);
      await PantallaDespierta.mantener(true);
    });

    test('la tablet tiene el canal, con el mismo nombre', () {
      final actividad = File(
        'android/app/src/main/kotlin/com/example/arguello_events/MainActivity.kt',
      ).readAsStringSync();
      expect(actividad, contains('"${PantallaDespierta.canal.name}"'));
      expect(actividad, contains('FLAG_KEEP_SCREEN_ON'));
    });

    test('VENDER la prende al abrir y la apaga al salir', () {
      final vender = File('lib/features/barra/widgets/vender_screen.dart').readAsStringSync();
      final init = vender.substring(vender.indexOf('void initState()'));
      expect(init.substring(0, init.indexOf('\n  }')), contains('PantallaDespierta.mantener(true)'));
      final dispose = vender.substring(vender.indexOf('void dispose()'));
      expect(dispose.substring(0, dispose.indexOf('\n  }')), contains('PantallaDespierta.mantener(false)'));
    });
  });
}
