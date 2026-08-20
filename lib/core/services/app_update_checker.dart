import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Releases públicos de Junior Eventos (mismo origin que el código).
const String kAppUpdateGithubOwner = 'lovera2025';
const String kAppUpdateGithubRepo = 'Antigravity';

const String _kPrefsLastCheckYmd = 'app_update_last_check_ymd';
const String kPrefsWhatsNewSeenVersion = 'app_whats_new_seen_version';

/// Resultado de comparar esta PC contra GitHub Releases.
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final String? setupDownloadUrl;
  final bool hayNueva;
  final String notes;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    this.setupDownloadUrl,
    required this.hayNueva,
    required this.notes,
  });
}

/// Aviso de versión nueva en Windows. DESCARGAR baja el Setup y abre el
/// instalador; no abre el navegador. Si no hay releases o falla la red, no
/// dice nada.
class AppUpdateChecker {
  AppUpdateChecker({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  static bool get habilitado =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// `4.7.4` vs `4.7.3` → positivo si [a] es más nueva.
  static int compareSemver(String a, String b) {
    List<int> parts(String raw) {
      final t = raw.trim();
      final sinV = t.startsWith('v') || t.startsWith('V') ? t.substring(1) : t;
      final core = sinV.split('+').first.split('-').first;
      final nums = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      while (nums.length < 3) {
        nums.add(0);
      }
      return nums.take(3).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  /// GitHub convierte espacios del asset a puntos
  /// (`Setup Junior Eventos v4.7.5.exe` → `Setup.Junior.Eventos.v4.7.5.exe`).
  static String normalizeSetupAssetName(String name) {
    var n = name.toLowerCase().trim();
    if (n.endsWith('.exe')) n = n.substring(0, n.length - 4);
    return n.replaceAll(RegExp(r'[._]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool looksLikeJuniorSetupExe(String name) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.exe')) return false;
    final stem = normalizeSetupAssetName(name);
    return stem.contains('setup junior eventos') ||
        stem.contains('junior eventos');
  }

  /// URL directa si GitHub no lista assets (mismo nombre que sube Inno/gh).
  static String constructedSetupUrl(String latestVersion) {
    final ver = latestVersion.trim();
    final core = ver.startsWith('v') || ver.startsWith('V')
        ? ver.substring(1)
        : ver;
    return 'https://github.com/$kAppUpdateGithubOwner/$kAppUpdateGithubRepo'
        '/releases/download/v$core/Setup.Junior.Eventos.v$core.exe';
  }

  static String? setupAssetUrl(List<dynamic>? assets, String latestVersion) {
    if (assets == null) return null;
    final needle = normalizeSetupAssetName(
      'setup junior eventos v$latestVersion.exe',
    );
    String? juniorUrl;
    String? onlyExeUrl;
    var exeCount = 0;
    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString() ?? '';
      final url = raw['browser_download_url']?.toString();
      if (url == null || url.isEmpty) continue;
      if (!name.toLowerCase().endsWith('.exe')) continue;
      exeCount++;
      onlyExeUrl = url;
      final stem = normalizeSetupAssetName(name);
      if (stem == needle || looksLikeJuniorSetupExe(name)) {
        juniorUrl = url;
        if (stem == needle) return url;
      }
    }
    return juniorUrl ?? (exeCount == 1 ? onlyExeUrl : null);
  }

  /// Notas del Release en texto plano para el aviso breve.
  static String plainNotesFromGithubBody(String? body, String version) {
    final raw = (body ?? '').trim();
    if (raw.isEmpty) return 'Junior Eventos $version está lista.';
    final lines = <String>[];
    for (final line in raw.split('\n')) {
      var t = line.trim();
      if (t.isEmpty) continue;
      t = t.replaceFirst(RegExp(r'^[-*]\s+'), '');
      t = t.replaceAll('**', '');
      if (t.isEmpty) continue;
      lines.add(t);
    }
    if (lines.isEmpty) return 'Junior Eventos $version está lista.';
    return lines.join('\n');
  }

  static AppUpdateInfo? fromGithubRelease({
    required Map<String, dynamic> json,
    required String currentVersion,
  }) {
    final tag = (json['tag_name']?.toString() ?? '').trim();
    if (tag.isEmpty) return null;
    final latest = tag.startsWith('v') || tag.startsWith('V')
        ? tag.substring(1)
        : tag;
    final html = (json['html_url']?.toString() ?? '').trim();
    final assets = json['assets'];
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latest,
      releaseUrl: html.isNotEmpty
          ? html
          : 'https://github.com/$kAppUpdateGithubOwner/$kAppUpdateGithubRepo/releases/latest',
      setupDownloadUrl: setupAssetUrl(
            assets is List ? assets : null,
            latest,
          ) ??
          constructedSetupUrl(latest),
      hayNueva: compareSemver(latest, currentVersion) > 0,
      notes: plainNotesFromGithubBody(json['body']?.toString(), latest),
    );
  }

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version.split('+').first.trim();
  }

  Future<AppUpdateInfo?> consultar() async {
    if (!habilitado) return null;
    final current = await currentVersion();
    final uri = Uri.https(
      'api.github.com',
      '/repos/$kAppUpdateGithubOwner/$kAppUpdateGithubRepo/releases/latest',
    );
    try {
      final request = _http == null
          ? http.get(uri, headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'JuniorEventos/$current',
            })
          : _http.get(uri, headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'JuniorEventos/$current',
            });
      final res = await request.timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      return fromGithubRelease(json: decoded, currentVersion: current);
    } catch (_) {
      return null;
    }
  }

  /// Una vez por día calendario. `null` si ya se chequéo hoy o no hay novedad.
  Future<AppUpdateInfo?> consultarSiCorrespondeHoy() async {
    if (!habilitado) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final hoy = _ymdHoy();
      if (prefs.getString(_kPrefsLastCheckYmd) == hoy) return null;
      final info = await consultar();
      await prefs.setString(_kPrefsLastCheckYmd, hoy);
      if (info == null || !info.hayNueva) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> whatsNewSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefsWhatsNewSeenVersion);
  }

  static Future<void> markWhatsNewSeen(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsWhatsNewSeenVersion, version);
  }

  static String _ymdHoy() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
