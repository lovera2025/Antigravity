import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:arguello_events/models/presupuesto.dart';
import '../../eventos/utils/evento_presentacion.dart';
import 'presupuesto_pdf_sections.dart';

/// Opcional: texto comercial más humano para el PDF usando un LLM compatible con OpenAI Chat Completions.
///
/// Compile-time (--dart-define):
/// - `PRESUPUESTO_LLM_API_KEY` — Bearer (vacío ⇒ no se llama al modelo y el PDF usa la redacción de plantillas actual).
/// - `PRESUPUESTO_LLM_CHAT_URL` — URL POST (default OpenAI Chat Completions).
/// - `PRESUPUESTO_LLM_MODEL` — ej. `gpt-4o-mini`.
class PresupuestoRedaccionLlmResult {
  PresupuestoRedaccionLlmResult({
    required this.fraseIntro,
    required this.parrafoPresentacion,
    required List<String?> cuerpos,
  }) : _cuerpos = List<String?>.from(cuerpos);

  final String? fraseIntro;
  final String? parrafoPresentacion;
  final List<String?> _cuerpos;

  List<String?> cuerpoOverridesFor(int esperadoCantidadSecciones) {
    if (_cuerpos.length != esperadoCantidadSecciones) {
      return List<String?>.filled(esperadoCantidadSecciones, null);
    }
    return [
      for (final s in _cuerpos)
        if (s == null || s.trim().isEmpty)
          null
        else
          s.trim(),
    ];
  }

  String? fraseIntroUsable() {
    final t = fraseIntro?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// Párrafo que sustituye el texto después de la frase intro. Si null, se deja el original.
  String? parrafoPresentacionUsable() {
    final t = parrafoPresentacion?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}

class PresupuestoRedaccionLlmService {
  static const String _apiKey = String.fromEnvironment('PRESUPUESTO_LLM_API_KEY');
  static const String _chatUrl = String.fromEnvironment(
    'PRESUPUESTO_LLM_CHAT_URL',
    defaultValue: 'https://api.openai.com/v1/chat/completions',
  );
  static const String _model = String.fromEnvironment(
    'PRESUPUESTO_LLM_MODEL',
    defaultValue: 'gpt-4o-mini',
  );

  /// Si no hay API key o falla la red/parseo, devuelve `null` (el caller usa plantillas actuales).
  static Future<PresupuestoRedaccionLlmResult?> generarSiConfigurado(
    Presupuesto p,
    List<PresupuestoPdfSeccion> secciones,
  ) async {
    if (_apiKey.isEmpty) return null;

    final variationSeed = p.id.hashCode.abs() % 100000;
    final userPayload = jsonEncode(payloadRedaccionSecciones(p, secciones, variationSeed));
    final nombres = EventoPresentacion.payloadNombresPresupuesto(p);

    const system = '''Sos redactor comercial de eventos en Argentina (español rioplatense, tono cálido y profesional).
Tu salida es SOLO un JSON válido UTF-8 (sin markdown fenced, sin texto fuera del JSON).

Objetivo: texto que ayude a vender la propuesta, sonando humano y NO repetitivo entre presupuestos.

Esquema exacto obligatorio:
{"frase_intro":"...","parrafo_presentacion":"...","cuerpos":["...","..."]}

Reglas estrictas:
- Usá EXACTAMENTE los nombres del JSON de entrada (nombre_festejado, solicitante, encabezado_pdf). No inventes personas.
- No inventes servicios, precios, fechas, lugares ni datos que no estén en el JSON de entrada del usuario.
- No listes precios ni totales en la redacción (los muestra el PDF).
- Cambiá aperturas y ritmo entre bloques; evitá clones de frases entre ítems.
- frase_intro: 1 oración clara que presente la propuesta usando festejado y solicitante cuando corresponda.
- parrafo_presentacion: 2 a 4 oraciones de bienvenida comercial (después de frase_intro).
- cuerpos: un string por cada entrada en secciones[], MISMO orden y MISMA cantidad de elementos que el array `secciones` del usuario.
- Si la sección es grupo/combo: una sola narrativa unificada (no repetir plantillas robot).
- Cantidades y nombres de servicio: respetalos literalmente cuando importen; si el cliente cargó "detalle_cargado_por_usuario_para_pdf", priorizalo.''';

    final user = StringBuffer()
      ..writeln('Nombres estructurados (usar tal cual en la redacción):')
      ..writeln(jsonEncode(nombres))
      ..writeln()
      ..writeln('Datos estructurados para redactar (variation_seed y secciones):')
      ..writeln(userPayload);

    final body = jsonEncode({
      'model': _model,
      'temperature': 0.85,
      'response_format': const {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system.toString()},
        {'role': 'user', 'content': user.toString()},
      ],
    });

    try {
      final res = await http
          .post(
            Uri.parse(_chatUrl),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 50));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final outer = jsonDecode(res.body) as Map<String, dynamic>;
      final choices = outer['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final content = (choices.first as Map)['message']?['content'];
      if (content is! String) return null;

      final parsed = _parseJsonFromAssistant(content);
      if (parsed == null) return null;

      final fraseIntro = parsed['frase_intro']?.toString();
      final parrafo = parsed['parrafo_presentacion']?.toString();
      final bloquesRaw = parsed['cuerpos'];
      if (bloquesRaw is! List) return null;

      final cuerpos = <String?>[
        for (final e in bloquesRaw) e?.toString(),
      ];

      return PresupuestoRedaccionLlmResult(
        fraseIntro: fraseIntro,
        parrafoPresentacion: parrafo,
        cuerpos: cuerpos,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseJsonFromAssistant(String raw) {
    var t = raw.trim();
    final block = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
    final m = block.firstMatch(t);
    if (m != null && m.groupCount >= 1) {
      t = m.group(1)!.trim();
    } else {
      final i0 = t.indexOf('{');
      final i1 = t.lastIndexOf('}');
      if (i0 >= 0 && i1 > i0) {
        t = t.substring(i0, i1 + 1);
      }
    }
    try {
      return jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
