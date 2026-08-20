import 'package:arguello_events/core/services/app_update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareSemver', () {
    test('4.7.3 es igual a 4.7.3 (al día)', () {
      expect(AppUpdateChecker.compareSemver('4.7.3', '4.7.3'), 0);
      expect(AppUpdateChecker.compareSemver('v4.7.3', '4.7.3'), 0);
    });

    test('4.7.4 es más nueva que 4.7.3', () {
      expect(AppUpdateChecker.compareSemver('4.7.4', '4.7.3'), greaterThan(0));
      expect(AppUpdateChecker.compareSemver('4.7.3', '4.7.4'), lessThan(0));
    });

    test('ignora build +37 y prefijo v', () {
      expect(AppUpdateChecker.compareSemver('4.7.3+37', '4.7.3'), 0);
      expect(AppUpdateChecker.compareSemver('v4.8.0', '4.7.3'), greaterThan(0));
    });
  });

  group('fromGithubRelease', () {
    test('no avisa si latest es la instalada', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v4.7.3',
          'html_url':
              'https://github.com/lovera2025/Antigravity/releases/tag/v4.7.3',
          'assets': [
            {
              'name': 'Setup Junior Eventos v4.7.3.exe',
              'browser_download_url':
                  'https://github.com/lovera2025/Antigravity/releases/download/v4.7.3/Setup%20Junior%20Eventos%20v4.7.3.exe',
            },
          ],
        },
        currentVersion: '4.7.3',
      );
      expect(info, isNotNull);
      expect(info!.hayNueva, isFalse);
      expect(info.setupDownloadUrl, contains('Setup'));
    });

    test('avisa si latest es mayor', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v4.7.4',
          'html_url':
              'https://github.com/lovera2025/Antigravity/releases/tag/v4.7.4',
          'assets': const [],
        },
        currentVersion: '4.7.3',
      );
      expect(info!.hayNueva, isTrue);
      expect(info.latestVersion, '4.7.4');
    });

    test('reconoce el Setup con puntos que pone GitHub', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v4.7.5',
          'html_url':
              'https://github.com/lovera2025/Antigravity/releases/tag/v4.7.5',
          'assets': [
            {
              'name': 'Setup.Junior.Eventos.v4.7.5.exe',
              'browser_download_url':
                  'https://github.com/lovera2025/Antigravity/releases/download/v4.7.5/Setup.Junior.Eventos.v4.7.5.exe',
            },
          ],
        },
        currentVersion: '4.7.4',
      );
      expect(info, isNotNull);
      expect(info!.hayNueva, isTrue);
      expect(info.setupDownloadUrl, contains('Setup.Junior.Eventos.v4.7.5.exe'));
      expect(info.setupDownloadUrl, isNot(contains('/tag/')));
    });

    test('si no hay assets, arma la URL del Setup (no la página HTML)', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v4.7.6',
          'html_url':
              'https://github.com/lovera2025/Antigravity/releases/tag/v4.7.6',
          'assets': const [],
        },
        currentVersion: '4.7.4',
      );
      expect(
        info!.setupDownloadUrl,
        AppUpdateChecker.constructedSetupUrl('4.7.6'),
      );
      expect(info.setupDownloadUrl, contains('/download/'));
      expect(info.setupDownloadUrl, isNot(info.releaseUrl));
    });

    test('copia body del Release a notes en texto plano', () {
      final info = AppUpdateChecker.fromGithubRelease(
        json: {
          'tag_name': 'v4.7.7',
          'html_url':
              'https://github.com/lovera2025/Antigravity/releases/tag/v4.7.7',
          'body':
              'Instalador Windows de Junior Eventos 4.7.7.\n\n- **Labels** de caja legibles\n- Aviso breve con ACEPTAR',
          'assets': const [],
        },
        currentVersion: '4.7.6',
      );
      expect(info, isNotNull);
      expect(info!.notes, contains('Labels de caja legibles'));
      expect(info.notes, contains('Aviso breve con ACEPTAR'));
      expect(info.notes, isNot(contains('**')));
      expect(info.notes, isNot(contains('- Labels')));
    });

    test('notes vacías usan el fallback de versión', () {
      expect(
        AppUpdateChecker.plainNotesFromGithubBody('', '4.7.7'),
        'Junior Eventos 4.7.7 está lista.',
      );
      expect(
        AppUpdateChecker.plainNotesFromGithubBody(null, '4.7.7'),
        'Junior Eventos 4.7.7 está lista.',
      );
    });
  });

  group('normalizeSetupAssetName', () {
    test('puntos de GitHub equivalen a espacios de Inno', () {
      expect(
        AppUpdateChecker.normalizeSetupAssetName(
          'Setup.Junior.Eventos.v4.7.5.exe',
        ),
        AppUpdateChecker.normalizeSetupAssetName(
          'Setup Junior Eventos v4.7.5.exe',
        ),
      );
    });
  });
}
