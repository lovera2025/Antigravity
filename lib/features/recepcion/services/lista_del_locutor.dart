import 'dart:convert';

import 'como_lo_nombran.dart';
import 'puerta_del_evento.dart';

/// **Lo que ve el locutor** (28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`, etapa 4):
/// institución → división → familias por apellido, y de cada familia cómo nombrar al
/// egresado y a sus acompañantes. Sin música, sin mesa, sin DNI. Pura: se arma con la
/// misma [PuertaDelEvento] que ve Recepción (una por escuela que atiende la central).
///
/// Quedan afuera los profes (una mesa reservada), lo cargado a mano y las bajas (que
/// [PuertaDelEvento.masivo] ya no trae).
class ListaDelLocutor {
  final List<InstitucionDelLocutor> instituciones;

  const ListaDelLocutor(this.instituciones);

  static const vacia = ListaDelLocutor([]);

  /// La de las escuelas de la noche (en la tele pueden ser dos). Una fiesta particular
  /// no suma nada: el locutor es de los eventos masivos.
  factory ListaDelLocutor.de(Iterable<PuertaDelEvento> puertas) {
    final porInstitucion = <String, Map<String, List<FamiliaDelLocutor>>>{};
    for (final p in puertas) {
      if (!p.masivo) continue;
      for (final g in p.grupos) {
        final f = FamiliaDelLocutor.delGrupo(g);
        if (f == null) continue;
        final i = _nombreONo(g.institucion, 'Sin institución');
        final d = _nombreONo(g.division, 'Sin división');
        ((porInstitucion[i] ??= {})[d] ??= []).add(f);
      }
    }
    final instituciones = [
      for (final i in _ordenados(porInstitucion.keys))
        InstitucionDelLocutor(i, [
          for (final d in _ordenados(porInstitucion[i]!.keys))
            DivisionDelLocutor(
              d,
              porInstitucion[i]![d]!
                ..sort((a, b) => normalizarPuerta(a.alumno.cargado).compareTo(normalizarPuerta(b.alumno.cargado))),
            ),
        ]),
    ];
    return ListaDelLocutor(instituciones);
  }

  static String _nombreONo(String? s, String si) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? si : t;
  }

  static List<String> _ordenados(Iterable<String> nombres) =>
      nombres.toList()..sort((a, b) => normalizarPuerta(a).compareTo(normalizarPuerta(b)));

  /// Todas las familias, en el orden de la lista.
  Iterable<FamiliaDelLocutor> get familias sync* {
    for (final i in instituciones) {
      for (final d in i.divisiones) {
        yield* d.familias;
      }
    }
  }

  bool get estaVacia => instituciones.isEmpty;

  /// Cuántas familias tienen algo cambiado.
  int get cambiadas => familias.where((f) => f.cambiada).length;

  /// **La huella de lo que dice**: se le manda al locutor solo si cambió (un ingreso no
  /// cambia nada de esto).
  String get firma => jsonEncode(toJson());

  List<Object?> toJson() => [for (final i in instituciones) i.toJson()];

  /// La que llegó por el wifi; vacía si no se entiende.
  static ListaDelLocutor fromJson(Object? j) {
    if (j is! List) return vacia;
    return ListaDelLocutor([
      for (final i in j) ?InstitucionDelLocutor.fromJson(i),
    ]);
  }

  /// Las familias donde aparece cada palabra de [consulta], en lo nombrado o en lo
  /// cargado, del egresado o de un acompañante.
  List<FamiliaDelLocutor> buscar(String consulta) {
    final palabras = normalizarPuerta(consulta).split(' ').where((p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return familias.toList();
    return [
      for (final f in familias)
        if (palabras.every(f._buscable.contains)) f,
    ];
  }
}

class InstitucionDelLocutor {
  final String nombre;
  final List<DivisionDelLocutor> divisiones;

  const InstitucionDelLocutor(this.nombre, this.divisiones);

  Map<String, Object?> toJson() => {'n': nombre, 'd': [for (final d in divisiones) d.toJson()]};

  static InstitucionDelLocutor? fromJson(Object? j) {
    if (j is! Map || j['n'] is! String || j['d'] is! List) return null;
    return InstitucionDelLocutor(j['n'] as String, [
      for (final d in j['d'] as List) ?DivisionDelLocutor.fromJson(d),
    ]);
  }
}

class DivisionDelLocutor {
  final String nombre;
  final List<FamiliaDelLocutor> familias;

  const DivisionDelLocutor(this.nombre, this.familias);

  Map<String, Object?> toJson() => {'n': nombre, 'f': [for (final f in familias) f.toJson()]};

  static DivisionDelLocutor? fromJson(Object? j) {
    if (j is! Map || j['n'] is! String || j['f'] is! List) return null;
    return DivisionDelLocutor(j['n'] as String, [
      for (final f in j['f'] as List) ?FamiliaDelLocutor.fromJson(f),
    ]);
  }
}

/// Una persona como la lee el locutor: [nombre] es lo que dice en voz alta; [cargado], lo
/// de la ficha (se muestra chico cuando se cambió, para no confundir a la persona).
class NombreDelLocutor {
  final String nombre;
  final String cargado;
  final bool cambiado;

  const NombreDelLocutor({required this.nombre, required this.cargado, required this.cambiado});

  /// Sin cambio no viaja el nombre: la página lo saca de lo cargado (`deCorrido`).
  Map<String, Object?> toJson() => {'c': cargado, if (cambiado) 'n': nombre, if (cambiado) 'x': true};

  static NombreDelLocutor? fromJson(Object? j) {
    if (j is! Map || j['c'] is! String) return null;
    final c = j['c'] as String;
    final x = j['x'] == true && j['n'] is String;
    return NombreDelLocutor(nombre: x ? j['n'] as String : deCorrido(c), cargado: c, cambiado: x);
  }
}

class FamiliaDelLocutor {
  /// El contrato del alumno.
  final String id;
  final NombreDelLocutor alumno;
  final List<NombreDelLocutor> acompanantes;

  /// Los acompañantes que vienen sin nombre y nadie nombró.
  final int sinNombre;

  /// Cuándo se cambió algo (milisegundos, UTC), o null.
  final int? cambiadoAt;

  FamiliaDelLocutor({
    required this.id,
    required this.alumno,
    this.acompanantes = const [],
    this.sinNombre = 0,
    this.cambiadoAt,
  }) : _buscable = normalizarPuerta([
          alumno.nombre,
          alumno.cargado,
          for (final a in acompanantes) ...[a.nombre, a.cargado],
        ].join(' '));

  final String _buscable;

  bool get cambiada => alumno.cambiado || acompanantes.any((a) => a.cambiado);

  /// La del egresado de [g], o null si no va en la lista del locutor (profes, cargado a
  /// mano, sin contrato).
  static FamiliaDelLocutor? delGrupo(GrupoPuerta g) {
    final contrato = g.contratoId;
    if (contrato == null || g.cargadoAMano || g.reservadaPara != null) return null;
    final n = g.nombres;
    if (n == null) {
      return FamiliaDelLocutor(
        id: contrato,
        alumno: _comoEsta(g.titular),
        acompanantes: [for (final a in g.acompanantes) _comoEsta(a)],
        sinNombre: g.acompanantesSinNombre,
      );
    }
    final acompanantes = <NombreDelLocutor>[];
    var sinNombre = 0;
    for (final l in n.lugares) {
      final nombrado = n.porLugar[l.lugar];
      if (nombrado != null) {
        acompanantes.add(NombreDelLocutor(nombre: nombrado, cargado: l.cargado, cambiado: true));
      } else if (l.sinNombre) {
        sinNombre++;
      } else {
        acompanantes.add(NombreDelLocutor(nombre: deCorrido(l.cargado), cargado: l.cargado, cambiado: false));
      }
    }
    final alumno = n.alumno;
    final ca = n.cambiadoAt == null ? null : DateTime.tryParse(n.cambiadoAt!)?.toUtc().millisecondsSinceEpoch;
    return FamiliaDelLocutor(
      id: contrato,
      alumno: NombreDelLocutor(
        nombre: alumno ?? deCorrido(n.alumnoCargado),
        cargado: n.alumnoCargado,
        cambiado: alumno != null,
      ),
      acompanantes: acompanantes,
      sinNombre: sinNombre,
      cambiadoAt: n.vacia ? null : ca,
    );
  }

  static NombreDelLocutor _comoEsta(PersonaPuerta p) => NombreDelLocutor(
        nombre: p.nombrado ?? deCorrido(p.nombre),
        cargado: p.nombre,
        cambiado: p.nombrado != null,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'a': alumno.toJson(),
        if (acompanantes.isNotEmpty) 'ac': [for (final a in acompanantes) a.toJson()],
        if (sinNombre > 0) 's': sinNombre,
        if (cambiadoAt != null) 'ca': cambiadoAt,
      };

  static FamiliaDelLocutor? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final a = NombreDelLocutor.fromJson(j['a']);
    if (a == null) return null;
    final ac = j['ac'];
    return FamiliaDelLocutor(
      id: j['id'] as String,
      alumno: a,
      acompanantes: [
        if (ac is List)
          for (final x in ac) ?NombreDelLocutor.fromJson(x),
      ],
      sinNombre: j['s'] is int ? j['s'] as int : 0,
      cambiadoAt: j['ca'] is int ? j['ca'] as int : null,
    );
  }
}
