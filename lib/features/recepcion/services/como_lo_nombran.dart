import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../models/como_lo_nombran.dart';
import '../../../models/contrato_alumno.dart';
import 'lista_puerta.dart';
import 'puerta_del_evento.dart' show normalizarPuerta;

/// Las reglas de **"Cómo lo nombran"** (el locutor, v85, 28-nov-2026;
/// `docs/SPEC_locutor_2026-11-18.md`), puras: sin base ni pantalla.

/// Hasta cuántas letras se escribe cómo nombrar a alguien.
const kTopeNombre = 60;

/// Cómo lo lee el locutor si nadie lo cambió: "PÉREZ, JUAN IGNACIO" → "JUAN IGNACIO PÉREZ"
/// (con una sola coma; sin coma o con más de una, como está), sin "[BAJA]" y con un solo
/// espacio entre palabras. **El tótem nunca saluda con esto**: sin un cambio, saluda con
/// lo cargado, como siempre.
String deCorrido(String cargado) {
  final limpio = cargado.replaceAll('[BAJA]', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final partes = limpio.split(',');
  if (partes.length != 2) return limpio;
  final apellido = partes[0].trim(), nombres = partes[1].trim();
  if (apellido.isEmpty || nombres.isEmpty) return limpio;
  return '$nombres $apellido';
}

/// Los signos que se dejan (además de letras latinas, cifras y espacio).
const _signos = '\'’‘"“”.,-()!¡?¿&/·';

bool _letraPermitida(int r) =>
    (r >= 0x30 && r <= 0x39) || // cifras
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x17F && r != 0xD7 && r != 0xF7) || // Latin-1 y Latin Extended-A
    r == 0x20 ||
    _signos.runes.contains(r);

/// **Lo que se guarda de lo que escribió la recepcionista** (y lo que manda el celular):
/// sin saltos ni espacios de más, sin emojis ni letras raras (las letras de la tele no las
/// tienen), cortado en [kTopeNombre]. Null si queda vacío o si es igual a lo cargado o a
/// [deCorrido]: eso no es un cambio.
String? limpiarNombre(String? texto, {String cargado = ''}) {
  if (texto == null) return null;
  final b = StringBuffer();
  for (final r in texto.runes) {
    if (r == 0x0A || r == 0x0D || r == 0x09) {
      b.write(' ');
    } else if (_letraPermitida(r)) {
      b.writeCharCode(r);
    }
  }
  var limpio = b.toString().replaceAll(RegExp(r' +'), ' ').trim();
  final runas = limpio.runes.toList();
  if (runas.length > kTopeNombre) limpio = String.fromCharCodes(runas.take(kTopeNombre)).trim();
  if (limpio.isEmpty) return null;
  final n = normalizarPuerta(limpio);
  if (cargado.trim().isNotEmpty && (n == normalizarPuerta(cargado) || n == normalizarPuerta(deCorrido(cargado)))) {
    return null;
  }
  return limpio;
}

/// Un lugar de la familia que se puede nombrar: un acompañante con nombre en la lista
/// ([cargado]) o uno sin nombre (`cargado` vacío).
class LugarParaNombrar {
  /// 1, 2, 3…: el mismo de `idInvitadoPuerta` para los que tienen nombre.
  final int lugar;
  final String cargado;

  const LugarParaNombrar(this.lugar, this.cargado);

  bool get sinNombre => cargado.isEmpty;
}

/// Los lugares de los acompañantes de [a]: primero los que tienen nombre, **en el mismo
/// orden y con el mismo número que la lista de la puerta** (`filasPuertaDesdeAlumnos`),
/// y después los sin nombre hasta su cantidad. Nunca más.
List<LugarParaNombrar> lugaresDe(ContratoAlumno a) {
  final conNombre = [
    for (final f in filasPuertaDesdeAlumnos([a]))
      if (!f.esAlumno) f.nombre,
  ];
  final lugares = [for (final (i, n) in conNombre.indexed) LugarParaNombrar(i + 1, n)];
  final total = (a.cantidadAcompanantes > conNombre.length ? a.cantidadAcompanantes : conNombre.length)
      .clamp(0, kMaxLugaresPorAlumno - 1);
  for (var l = conNombre.length + 1; l <= total; l++) {
    lugares.add(LugarParaNombrar(l, ''));
  }
  return lugares;
}

/// Lo que manda la recepcionista: cómo nombrar al egresado y a cada lugar, y la firma
/// de lo que estaba viendo ([antes]: si cambió mientras editaba, hay conflicto).
class DatosNombres {
  /// Cómo nombrarlo; vacío o null = como en la lista.
  final String? alumno;

  /// Por lugar; un lugar que no está vuelve a como en la lista.
  final Map<int, String> lugares;
  final String antes;

  const DatosNombres({this.alumno, this.lugares = const {}, required this.antes});

  Map<String, Object?> toJson() => {
        'a': alumno ?? '',
        'l': [
          for (final e in (lugares.entries.toList()..sort((x, y) => x.key.compareTo(y.key)))) [e.key, e.value],
        ],
        'antes': antes,
      };

  /// La que mandó un celular. Acota los largos (un mensaje no puede traer cualquier
  /// cosa); null si no se entiende.
  static DatosNombres? fromJson(Object? j) {
    if (j is! Map) return null;
    final antes = j['antes'];
    if (antes is! String || antes.length > 64) return null;
    String? corto(Object? v) => v is String ? (v.length > 200 ? v.substring(0, 200) : v) : null;
    final lugares = <int, String>{};
    final l = j['l'];
    if (l is List) {
      for (final e in l.take(kMaxLugaresPorAlumno)) {
        if (e is List && e.length == 2 && e[0] is int && e[0] > 0 && e[0] < kMaxLugaresPorAlumno) {
          final n = corto(e[1]);
          if (n != null) lugares[e[0] as int] = n;
        }
      }
    }
    return DatosNombres(alumno: corto(j['a']), lugares: lugares, antes: antes);
  }

  @override
  bool operator ==(Object other) =>
      other is DatosNombres &&
      other.alumno == alumno &&
      other.antes == antes &&
      other.lugares.length == lugares.length &&
      lugares.entries.every((e) => other.lugares[e.key] == e.value);

  @override
  int get hashCode => Object.hash(alumno, antes, lugares.length);
}

/// **Cómo nombran a una familia, ya cruzado con lo que dice hoy la lista.** La fila
/// guardada dice "a quien estaba cargado como X, nombralo Y": si la oficina reordenó o
/// corrigió los acompañantes, cada nombre va a quien corresponde por lo cargado, y lo que
/// ya no cruza con nadie va a [sobrantes] (se muestra, no se aplica a otra persona, y se
/// descarta al guardar).
class NombresDeLaFamilia {
  final String alumnoCargado;
  final List<LugarParaNombrar> lugares;

  /// Cómo nombran al egresado (null: como en la lista).
  final String? alumno;

  /// Cómo nombran a cada lugar, solo los cambiados.
  final Map<int, String> porLugar;

  /// Lo que quedó sin aplicar: "«Lau» (era de GÓMEZ, LAURA)".
  final List<String> sobrantes;
  final String? cambiadoPor;
  final String? cambiadoAt;

  /// La huella de lo que se ve (16 letras): si cambia mientras se edita, hay conflicto.
  final String firma;

  const NombresDeLaFamilia._({
    required this.alumnoCargado,
    required this.lugares,
    required this.alumno,
    required this.porLugar,
    required this.sobrantes,
    required this.cambiadoPor,
    required this.cambiadoAt,
    required this.firma,
  });

  /// Sin nada cambiado.
  bool get vacia => alumno == null && porLugar.isEmpty;

  /// Lo que dice el locutor del egresado: lo nombrado o, si no, lo cargado de corrido.
  String get alumnoParaElLocutor => alumno ?? deCorrido(alumnoCargado);

  static int? _ms(String? iso) => iso == null ? null : DateTime.tryParse(iso)?.toUtc().millisecondsSinceEpoch;

  /// La firma: solo el contenido (lo cargado y lo guardado), nunca `updated_at`. Sin fila
  /// y fila vacía dan la misma.
  static String _firmar(String alumnoCargado, List<LugarParaNombrar> lugares, ComoLoNombran? fila) {
    final contenido = jsonEncode([
      alumnoCargado,
      [for (final l in lugares) [l.lugar, l.cargado]],
      if (fila != null && !fila.vacia)
        [fila.alumno ?? '', fila.alumnoCargado ?? '', fila.acompanantesJson, fila.cambiadoPor ?? '', _ms(fila.cambiadoAt)],
    ]);
    return sha256.convert(utf8.encode(contenido)).toString().substring(0, 16);
  }

  factory NombresDeLaFamilia.de({
    required String alumnoCargado,
    required List<LugarParaNombrar> lugares,
    ComoLoNombran? fila,
  }) {
    final sobrantes = <String>[];
    String? alumno;
    if (fila?.alumno != null) {
      final era = fila!.alumnoCargado;
      if (era == null || normalizarPuerta(era) == normalizarPuerta(alumnoCargado)) {
        alumno = fila.alumno;
      } else {
        sobrantes.add('«${fila.alumno}» (era de $era)');
      }
    }
    final porLugar = <int, String>{};
    for (final e in fila?.acompanantes ?? const <NombreDeAcompanante>[]) {
      int? destino;
      if (e.cargado.isEmpty) {
        final l = lugares.where((x) => x.lugar == e.lugar && x.sinNombre).firstOrNull;
        if (l != null && !porLugar.containsKey(l.lugar)) destino = l.lugar;
      } else {
        final buscado = normalizarPuerta(e.cargado);
        bool sirve(LugarParaNombrar x) => !x.sinNombre && normalizarPuerta(x.cargado) == buscado && !porLugar.containsKey(x.lugar);
        destino = lugares.where((x) => x.lugar == e.lugar && sirve(x)).firstOrNull?.lugar ??
            lugares.where(sirve).firstOrNull?.lugar;
      }
      if (destino == null) {
        sobrantes.add(e.cargado.isEmpty ? '«${e.nombre}» (acompañante ${e.lugar})' : '«${e.nombre}» (era de ${e.cargado})');
      } else {
        porLugar[destino] = e.nombre;
      }
    }
    return NombresDeLaFamilia._(
      alumnoCargado: alumnoCargado,
      lugares: List.unmodifiable(lugares),
      alumno: alumno,
      porLugar: Map.unmodifiable(porLugar),
      sobrantes: List.unmodifiable(sobrantes),
      cambiadoPor: fila?.cambiadoPor,
      cambiadoAt: fila?.cambiadoAt,
      firma: _firmar(alumnoCargado, lugares, fila),
    );
  }

  /// La de un alumno con su fila (o sin ella).
  factory NombresDeLaFamilia.delAlumno(ContratoAlumno a, ComoLoNombran? fila) =>
      NombresDeLaFamilia.de(alumnoCargado: a.nombreAlumno.trim(), lugares: lugaresDe(a), fila: fila);

  /// Lo de ahora, con la fila que hay en la base en este momento.
  NombresDeLaFamilia conFila(ComoLoNombran? filaAhora) =>
      NombresDeLaFamilia.de(alumnoCargado: alumnoCargado, lugares: lugares, fila: filaAhora);

  /// **La fila nueva** con lo que pidió la recepcionista, o null si queda igual. Lo que
  /// se escribió se limpia y se corta; un lugar que no es de esta familia no se toma.
  ComoLoNombran? filaCon(
    DatosNombres datos, {
    required String eventoId,
    required String contratoId,
    required String por,
    required DateTime ahora,
    String? createdAt,
  }) {
    final nuevoAlumno = limpiarNombre(datos.alumno, cargado: alumnoCargado);
    final nuevos = <int, String>{};
    for (final l in lugares) {
      final n = limpiarNombre(datos.lugares[l.lugar], cargado: l.cargado);
      if (n != null) nuevos[l.lugar] = n;
    }
    final igual = nuevoAlumno == alumno &&
        nuevos.length == porLugar.length &&
        nuevos.entries.every((e) => porLugar[e.key] == e.value) &&
        sobrantes.isEmpty;
    if (igual) return null;
    return ComoLoNombran.para(
      eventoId: eventoId,
      contratoAlumnoId: contratoId,
      alumno: nuevoAlumno,
      alumnoCargado: alumnoCargado,
      acompanantes: [
        for (final l in lugares)
          if (nuevos[l.lugar] case final n?) NombreDeAcompanante(lugar: l.lugar, cargado: l.cargado, nombre: n),
      ],
      cambiadoPor: por,
      createdAt: createdAt,
      ahora: ahora,
    );
  }

  /// Para los celulares y el locutor (lo que ya está cruzado, no la fila cruda).
  Map<String, Object?> toJson() => {
        'ac': alumnoCargado,
        'lu': [for (final l in lugares) [l.lugar, l.cargado]],
        if (alumno != null) 'a': alumno,
        if (porLugar.isNotEmpty) 'l': [for (final e in porLugar.entries) [e.key, e.value]],
        if (sobrantes.isNotEmpty) 's': sobrantes,
        if (cambiadoPor != null) 'cp': cambiadoPor,
        if (cambiadoAt != null) 'ca': cambiadoAt,
        'f': firma,
      };

  static NombresDeLaFamilia? fromJson(Object? j) {
    if (j is! Map) return null;
    final lu = j['lu'], f = j['f'], ac = j['ac'];
    if (lu is! List || f is! String || ac is! String) return null;
    final lugares = [
      for (final e in lu)
        if (e is List && e.length == 2 && e[0] is int && e[1] is String) LugarParaNombrar(e[0] as int, e[1] as String),
    ];
    final l = j['l'];
    final s = j['s'];
    return NombresDeLaFamilia._(
      alumnoCargado: ac,
      lugares: lugares,
      alumno: j['a'] is String ? j['a'] as String : null,
      porLugar: {
        if (l is List)
          for (final e in l)
            if (e is List && e.length == 2 && e[0] is int && e[1] is String) e[0] as int: e[1] as String,
      },
      sobrantes: [
        if (s is List)
          for (final x in s)
            if (x is String) x,
      ],
      cambiadoPor: j['cp'] is String ? j['cp'] as String : null,
      cambiadoAt: j['ca'] is String ? j['ca'] as String : null,
      firma: f,
    );
  }
}
