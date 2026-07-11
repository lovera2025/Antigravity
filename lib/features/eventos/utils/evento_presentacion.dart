import '../../../core/utils/ar_time.dart';
import '../../../models/evento.dart';
import '../../../models/presupuesto.dart';

/// Textos de encabezado unificados (lista, detalle, PDF) para eventos particulares.
///
/// Regla: el operador carga **nombres** en Maestro Pro; la redacción comercial
/// larga la genera la IA ([PresupuestoRedaccionLlmService]).
class EventoPresentacion {
  EventoPresentacion._();

  /// Intenta extraer el homenajeado de observaciones legacy (texto libre).
  static String? homenajeadoDesdeObservaciones(String? observaciones) {
    if (observaciones == null || observaciones.trim().isEmpty) return null;
    final patterns = [
      RegExp(r'homenajeado\s*/?\s*a?\s*:\s*(.+)', caseSensitive: false, multiLine: true),
      RegExp(r'quinceañera\s*:\s*(.+)', caseSensitive: false, multiLine: true),
      RegExp(r'novio/a\s*1\s*:\s*(.+)', caseSensitive: false, multiLine: true),
      RegExp(r'beb[eé]\s*:\s*(.+)', caseSensitive: false, multiLine: true),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(observaciones);
      if (m != null) {
        final v = m.group(1)?.trim();
        if (v != null && v.isNotEmpty) {
          final line = v.split('\n').first.trim();
          if (line.isNotEmpty) return line;
        }
      }
    }
    return null;
  }

  static bool _pareceFraseMotivo(String s) {
    final l = s.toLowerCase().trim();
    return l.contains(' de ') ||
        l.startsWith('los ') ||
        l.startsWith('las ') ||
        l.startsWith('el ') ||
        l.startsWith('la ');
  }

  /// Separa [titulo_festejado] legacy en nombre corto + encabezado (migración v60).
  static ({String? nombreFestejado, String? encabezadoEvento}) dividirTituloFestejadoLegacy(
    String? tituloFestejado,
    String tipoEvento,
  ) {
    final raw = tituloFestejado?.trim();
    if (raw == null || raw.isEmpty) {
      return (nombreFestejado: null, encabezadoEvento: null);
    }
    if (_pareceFraseMotivo(raw)) {
      final corto = nombreHomenajeadoCorto(
            tituloFestejado: raw,
            tipoEvento: tipoEvento,
          ) ??
          raw;
      return (nombreFestejado: corto, encabezadoEvento: raw.toUpperCase());
    }
    return (nombreFestejado: raw, encabezadoEvento: null);
  }

  static String? nombreFestejadoEfectivoEvento(Evento evento) {
    final n = evento.nombreFestejado?.trim();
    if (n != null && n.isNotEmpty) return n;
    final legacy = dividirTituloFestejadoLegacy(evento.tituloFestejado, evento.tipo);
    if (legacy.nombreFestejado != null && legacy.nombreFestejado!.isNotEmpty) {
      return legacy.nombreFestejado;
    }
    return homenajeadoDesdeObservaciones(evento.observaciones);
  }

  static String? nombreFestejadoEfectivoPresupuesto(Presupuesto p) {
    final n = p.nombreFestejado?.trim();
    if (n != null && n.isNotEmpty) return n;
    final legacy = dividirTituloFestejadoLegacy(p.tituloFestejado, p.tipoEvento);
    if (legacy.nombreFestejado != null && legacy.nombreFestejado!.isNotEmpty) {
      return legacy.nombreFestejado;
    }
    return null;
  }

  @Deprecated('Use nombreFestejadoEfectivoEvento')
  static String? homenajeadoEfectivo(Evento evento) => nombreFestejadoEfectivoEvento(evento);

  static String solicitanteNombre(Evento evento) =>
      evento.cliente?.nombreCompleto.trim().isNotEmpty == true
          ? evento.cliente!.nombreCompleto.trim()
          : 'Cliente';

  /// Colegio / institución para PDFs de masivos (nunca solo el tipo genérico).
  ///
  /// Orden: institución del alumno → encabezado del evento → cliente → tipo.
  static String institucionOEventoParaPdf({
    required Evento evento,
    String? institucionAlumno,
  }) {
    final a = institucionAlumno?.trim();
    if (a != null && a.isNotEmpty) return a;
    final enc = evento.encabezadoEvento?.trim();
    if (enc != null && enc.isNotEmpty) return enc;
    final cli = evento.cliente?.nombreCompleto.trim();
    if (cli != null && cli.isNotEmpty) return cli;
    final tit = evento.tituloFestejado?.trim();
    if (tit != null && tit.isNotEmpty) return tit;
    return evento.tipoParaMostrar;
  }

  static String solicitantePresupuesto(Presupuesto p) =>
      p.cliente?.nombreCompleto.trim().isNotEmpty == true
          ? p.cliente!.nombreCompleto.trim()
          : 'quien suscribe';

  /// Arma "Los 15 de Pauli" cuando solo hay nombre suelto.
  static String componerEncabezadoDesdeTipo(String nombre, String tipoEvento) {
    final nombreLimpio = nombre.trim();
    final t = Evento.normalizarTipo(tipoEvento);
    if (t == '15 años') return 'LOS 15 DE $nombreLimpio';
    if (t == 'boda') return 'LA BODA DE $nombreLimpio';
    if (t == 'bautismo') return 'EL BAUTISMO DE $nombreLimpio';
    return '${Evento.formatearTipo(tipoEvento).toUpperCase()} DE $nombreLimpio';
  }

  /// Encabezado grande (PDF / lista / detalle).
  static String resolverEncabezado({
    String? encabezadoPersonalizado,
    String? nombreFestejado,
    required String tipoEvento,
    String? fallbackSolicitante,
  }) {
    final enc = encabezadoPersonalizado?.trim();
    if (enc != null && enc.isNotEmpty) return enc.toUpperCase();

    final nombre = nombreFestejado?.trim();
    if (nombre != null && nombre.isNotEmpty) {
      if (_pareceFraseMotivo(nombre)) return nombre.toUpperCase();
      return componerEncabezadoDesdeTipo(nombre, tipoEvento);
    }

    final sol = fallbackSolicitante?.trim();
    if (sol != null && sol.isNotEmpty) {
      return '${Evento.formatearTipo(tipoEvento).toUpperCase()} - $sol'.toUpperCase();
    }
    return Evento.formatearTipo(tipoEvento).toUpperCase();
  }

  static String tituloPrincipal(Evento evento) {
    final legacy = dividirTituloFestejadoLegacy(evento.tituloFestejado, evento.tipo);
    return resolverEncabezado(
      encabezadoPersonalizado: evento.encabezadoEvento ?? legacy.encabezadoEvento,
      nombreFestejado: nombreFestejadoEfectivoEvento(evento),
      tipoEvento: evento.tipo,
      fallbackSolicitante: solicitanteNombre(evento),
    );
  }

  static String encabezadoDesdePresupuesto(Presupuesto p) {
    final legacy = dividirTituloFestejadoLegacy(p.tituloFestejado, p.tipoEvento);
    return resolverEncabezado(
      encabezadoPersonalizado: p.encabezadoEvento ?? legacy.encabezadoEvento,
      nombreFestejado: nombreFestejadoEfectivoPresupuesto(p),
      tipoEvento: p.tipoEvento,
      fallbackSolicitante: p.cliente?.nombreCompleto,
    );
  }

  @Deprecated('Use encabezadoDesdePresupuesto')
  static String tituloMotivoDesdePresupuesto(Presupuesto p) => encabezadoDesdePresupuesto(p);

  static String subtituloFecha(DateTime fecha) =>
      '${fecha.day}/${fecha.month}/${fecha.year}';

  static String subtituloTipoYFecha(Evento evento) {
    final f = evento.fechaEvento;
    return '${evento.tipoParaMostrar.toUpperCase()} · ${subtituloFecha(f)}';
  }

  /// Con festejado cargado: solo fecha; sin festejado: tipo + fecha.
  static String subtituloEvento(Evento evento) {
    if (nombreFestejadoEfectivoEvento(evento) != null) {
      return subtituloFecha(evento.fechaEvento);
    }
    return subtituloTipoYFecha(evento);
  }

  /// Subtítulo del PDF/header: solo la fecha del evento (sin validez; esa va al resumen).
  /// Sin fecha cargada → string vacío (no inventa con fecha_vencimiento).
  static String subtituloDesdePresupuesto(Presupuesto p) {
    if (p.fechaEvento == null) return '';
    return 'Fecha del evento: ${ArTime.formatFechaLarga(p.fechaEvento!)}';
  }

  /// Frase corta de intro (sin IA): solo nombres explícitos, sin adivinar.
  static String fraseIntroDesdeNombres({
    required String? nombreFestejado,
    required String solicitante,
    bool paraPresupuesto = false,
  }) {
    final n = nombreFestejado?.trim();
    final sol = solicitante.trim().isNotEmpty ? solicitante.trim() : 'usted';
    final prefijo =
        paraPresupuesto ? 'Esta propuesta ha sido diseñada' : 'Este evento fue diseñado';

    if (n == null || n.isEmpty) {
      return '$prefijo para $sol.';
    }
    if (n.toLowerCase() == sol.toLowerCase()) {
      return '$prefijo para $n.';
    }
    return '$prefijo para $n, a solicitud de $sol.';
  }

  static String fraseIntroEvento(Evento evento, {bool paraPresupuesto = false}) {
    return fraseIntroDesdeNombres(
      nombreFestejado: nombreFestejadoEfectivoEvento(evento),
      solicitante: solicitanteNombre(evento),
      paraPresupuesto: paraPresupuesto,
    );
  }

  static String fraseIntroPresupuesto(Presupuesto p) {
    return fraseIntroDesdeNombres(
      nombreFestejado: nombreFestejadoEfectivoPresupuesto(p),
      solicitante: solicitantePresupuesto(p),
      paraPresupuesto: true,
    );
  }

  @Deprecated('Use fraseIntroEvento')
  static String? fraseDisenadoPara(Evento evento, {bool paraPresupuesto = false}) =>
      fraseIntroEvento(evento, paraPresupuesto: paraPresupuesto);

  @Deprecated('Use fraseIntroPresupuesto')
  static String? fraseDisenadoDesdePresupuesto(Presupuesto p) => fraseIntroPresupuesto(p);

  /// Extrae nombre corto de una frase tipo "Los 15 de Pauli" (legacy / migración).
  static String? nombreHomenajeadoCorto({
    String? tituloFestejado,
    required String tipoEvento,
  }) {
    final raw = tituloFestejado?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (!_pareceFraseMotivo(raw)) return raw;
    final match = RegExp(r'\bde\s+(.+)$', caseSensitive: false).firstMatch(raw);
    final extraido = match?.group(1)?.trim();
    if (extraido != null && extraido.isNotEmpty) return extraido;
    return raw;
  }

  static bool necesitaConfiguracionMaestra(Evento evento) {
    if (evento.modalidad != 'particular') return false;
    final enc = evento.encabezadoEvento?.trim();
    if (enc != null && enc.isNotEmpty) {
      final n = nombreFestejadoEfectivoEvento(evento);
      return n == null || n.isEmpty;
    }
    final legacy = dividirTituloFestejadoLegacy(evento.tituloFestejado, evento.tipo);
    if (legacy.encabezadoEvento != null && legacy.encabezadoEvento!.isNotEmpty) {
      final n = nombreFestejadoEfectivoEvento(evento);
      return n == null || n.isEmpty;
    }
    return true;
  }

  /// Payload estructurado para la IA (sin redacción inventada en Dart).
  static Map<String, String> payloadNombresEvento(Evento evento) {
    return {
      'encabezado_pdf': tituloPrincipal(evento),
      'nombre_festejado': nombreFestejadoEfectivoEvento(evento) ?? '',
      'solicitante': solicitanteNombre(evento),
      'tipo_evento': Evento.formatearTipo(evento.tipo),
    };
  }

  static Map<String, String> payloadNombresPresupuesto(Presupuesto p) {
    return {
      'encabezado_pdf': encabezadoDesdePresupuesto(p),
      'nombre_festejado': nombreFestejadoEfectivoPresupuesto(p) ?? '',
      'solicitante': solicitantePresupuesto(p),
      'tipo_evento': Evento.formatearTipo(p.tipoEvento),
    };
  }
}
