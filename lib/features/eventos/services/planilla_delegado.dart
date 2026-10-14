import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../models/contrato_alumno.dart';

/// El Excel que completa el delegado de una institución: los acompañantes
/// (hasta [kMaxAcompanantes]) y la música elegida de cada alumno.
///
/// Se **exporta** un archivo por institución (una institución es una fiesta),
/// con todos sus alumnos activos, y se **importa** de vuelta sobre esa misma
/// fiesta. Acá está todo lo que decide, sin pantalla y sin base:
///
/// - [PlanillaDelegado.armar]: los alumnos → los bytes del Excel;
/// - [PlanillaDelegado.leer]: los bytes → los renglones, tal como vinieron;
/// - [PlanillaDelegado.comparar]: los renglones contra los alumnos de la
///   fiesta → qué se cargaría, qué ya estaba, qué vino vacío y qué hay que
///   revisar. **No escribe nada**: es el simulacro que se muestra antes de
///   guardar.
///
/// Las reglas (pedido del usuario, 13-oct-2026):
/// - una institución no pisa a otra: el archivo lleva el código de su fiesta y
///   el de cada alumno, y un Excel de otra institución no entra;
/// - del alumno solo se escriben acompañantes y música: cualquier otro cambio
///   del Excel (un nombre, una división) se ignora;
/// - un casillero vacío nunca borra lo que ya estaba;
/// - con más de [kMaxAcompanantes], ese alumno no se carga.
const int kMaxAcompanantes = 2;

/// Lo que dice la planilla arriba de los alumnos, para saber de qué fiesta es.
const String _marcaPlanilla = 'Planilla:';

/// El color de los casilleros que completa el delegado. [bloquearPlanilla] lo
/// busca para dejar escribir solo ahí.
const String kColorCasilleroDelegado = 'FFFFF2CC';

/// Un renglón del Excel, tal como vino.
class RenglonDelegado {
  /// La fila del Excel, contando desde 1, para poder nombrarla.
  final int fila;
  final String codigo;
  final String alumno;
  final String acompanantes;
  final String musica;

  const RenglonDelegado({
    required this.fila,
    required this.codigo,
    required this.alumno,
    required this.acompanantes,
    required this.musica,
  });
}

/// Lo que se pudo leer de un Excel.
class LecturaPlanilla {
  /// La fiesta para la que se exportó. Null si alguien borró ese renglón.
  final String? eventoId;

  /// El nombre de la institución escrito en el título, para poder decir de
  /// quién es un Excel que no corresponde.
  final String? institucion;
  final List<RenglonDelegado> renglones;

  /// Por qué no se pudo leer, en palabras. Null si se leyó.
  final String? problema;

  const LecturaPlanilla({
    required this.eventoId,
    required this.institucion,
    required this.renglones,
    this.problema,
  });

  const LecturaPlanilla.ilegible(String this.problema)
      : eventoId = null,
        institucion = null,
        renglones = const [];
}

/// Lo que se le cargaría a un alumno.
class CambioDelegado {
  final ContratoAlumno alumno;

  /// Los acompañantes que quedarían. Null: el Excel no los cambia.
  final List<String>? acompanantes;

  /// La música que quedaría. Null: el Excel no la cambia.
  final String? musica;

  const CambioDelegado({
    required this.alumno,
    required this.acompanantes,
    required this.musica,
  });

  /// El alumno ya tenía algo distinto en lo que se cambia: hay que mostrarlo
  /// antes de guardar. Si estaba vacío, no se pisa nada.
  bool get pisaAlgo =>
      (acompanantes != null &&
          PlanillaDelegado.limpios(alumno.nombresAcompanantes).isNotEmpty) ||
      (musica != null && (alumno.musicaElegida ?? '').trim().isNotEmpty);

  /// Algún acompañante vino con una coma. La coma no separa (los nombres del
  /// sistema son "APELLIDO, NOMBRE"), así que se tomó como una sola persona:
  /// queda marcado para que alguien lo mire.
  bool get conComa => (acompanantes ?? const []).any((n) => n.contains(','));

  /// Cómo se leyó el renglón, para la ventana de antes de guardar.
  String get leido => [
        ...?acompanantes,
        if (musica != null) 'Música: $musica',
      ].join(' · ');

  /// Lo que tenía en lo que se cambia, en el mismo formato que [leido].
  String get tenia => [
        if (acompanantes != null)
          ...PlanillaDelegado.limpios(alumno.nombresAcompanantes),
        if (musica != null && (alumno.musicaElegida ?? '').trim().isNotEmpty)
          'Música: ${alumno.musicaElegida!.trim()}',
      ].join(' · ');

  /// Lo que hay que escribir en el alumno: solo lo que cambia.
  Map<String, dynamic> get datos => {
        if (acompanantes != null) ...{
          'nombres_acompanantes': acompanantes,
          'cantidad_acompanantes': acompanantes!.length,
        },
        if (musica != null) 'musica_elegida': musica,
      };
}

/// Un renglón que no se carga, con el motivo en palabras.
class RevisarDelegado {
  final String quien;
  final String motivo;
  const RevisarDelegado(this.quien, this.motivo);

  @override
  String toString() => '$quien: $motivo';
}

/// El simulacro de una importación: qué pasaría, sin haber escrito nada.
class ResultadoPlanilla {
  /// Los alumnos a los que se les cargaría algo, por nombre.
  final List<CambioDelegado> cambios;

  /// Renglones completados que ya coinciden con lo cargado.
  final int iguales;

  /// Renglones con los dos casilleros vacíos: no tocan nada.
  final int vacios;
  final List<RevisarDelegado> revisar;

  /// El Excel no es de esta fiesta, o no se pudo leer: no entra nada.
  final String? rechazo;

  const ResultadoPlanilla({
    required this.cambios,
    required this.iguales,
    required this.vacios,
    required this.revisar,
    this.rechazo,
  });

  const ResultadoPlanilla.rechazado(String this.rechazo)
      : cambios = const [],
        iguales = 0,
        vacios = 0,
        revisar = const [];

  bool get sePuedeImportar => rechazo == null && cambios.isNotEmpty;
}

class PlanillaDelegado {
  const PlanillaDelegado._();

  static const _encabezados = [
    'N°',
    'Alumno',
    'División',
    'Acompañantes (hasta $kMaxAcompanantes)',
    'Música',
    'Código',
  ];

  /// En qué fila van los encabezados (contando desde 0). Los alumnos empiezan
  /// en la siguiente.
  static const filaEncabezados = 4;

  /// La columna de Acompañantes, la de Música y la del Código (contando
  /// desde 0).
  static const columnaAcompanantes = 3;
  static const columnaMusica = 4;
  static const columnaCodigo = 5;

  /// Los nombres con algo escrito, sin espacios de más.
  static List<String> limpios(Iterable<String> nombres) => [
        for (final n in nombres)
          if (n.trim().isNotEmpty) _unEspacio(n),
      ];

  static String _unEspacio(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Para comparar nombres: sin acentos, sin mayúsculas, solo letras y números.
  static String _llave(String s) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = con.indexOf(ch);
      final llano = i >= 0 ? sin[i] : ch;
      if (RegExp(r'[a-z0-9]').hasMatch(llano)) b.write(llano);
    }
    return b.toString();
  }

  /// El nombre de un alumno sin la marca de baja.
  static String nombreLimpio(ContratoAlumno a) =>
      _unEspacio(a.nombreAlumno.replaceFirst('[BAJA]', ''));

  /// El código de cada alumno en la planilla: una letra y el principio de su
  /// id. Empieza con letra para que ningún programa lo tome por un número o
  /// una fecha. Se alarga solo si dos alumnos de la fiesta coincidieran.
  static Map<String, String> codigos(Iterable<ContratoAlumno> alumnos) {
    final lista = alumnos.toList();
    for (var largo = 8; largo < 32; largo += 4) {
      final porId = <String, String>{
        for (final a in lista)
          a.id: 'K${_hex(a.id).padRight(largo, '0').substring(0, largo)}',
      };
      if (porId.values.toSet().length == lista.length) return porId;
    }
    return {for (final a in lista) a.id: 'K${_hex(a.id)}'};
  }

  static String _hex(String id) => id.replaceAll('-', '').toUpperCase();

  /// Los nombres de un casillero de acompañantes.
  ///
  /// Se separan con barra, punto y coma, "+", "&", un renglón nuevo o " y ".
  /// **La coma no separa**: los nombres del sistema son "APELLIDO, NOMBRE".
  static List<String> separarAcompanantes(String casillero) => limpios(
        casillero.split(RegExp(r'[/;+&\n\r]|\s+[yY]\s+')),
      );

  /// Los alumnos que van a la planilla: los activos, por división y apellido.
  static List<ContratoAlumno> alumnosDeLaPlanilla(
    Iterable<ContratoAlumno> alumnos,
  ) {
    final activos = [
      for (final a in alumnos)
        if (!a.esBajaTemporal && a.nombreAlumno.trim().isNotEmpty) a,
    ];
    int porTexto(String a, String b) => _llave(a).compareTo(_llave(b));
    activos.sort((a, b) {
      final da = (a.cursoDivision ?? '').trim();
      final db = (b.cursoDivision ?? '').trim();
      // Sin división, al final.
      if (da.isEmpty != db.isEmpty) return da.isEmpty ? 1 : -1;
      final d = porTexto(da, db);
      return d != 0 ? d : porTexto(a.nombreAlumno, b.nombreAlumno);
    });
    return activos;
  }

  // ── Exportar ──────────────────────────────────────────────────────────────

  /// El Excel de una institución, sin bloquear (ver `bloquearPlanilla`).
  static Uint8List armar({
    required String eventoId,
    required String institucion,
    required Iterable<ContratoAlumno> alumnos,
  }) {
    final lista = alumnosDeLaPlanilla(alumnos);
    final codigo = codigos(lista);
    final excel = Excel.createExcel();
    const hoja = 'Alumnos';
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', hoja);
    final sheet = excel[hoja];

    CellIndex en(int columna, int fila) =>
        CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: fila);
    void escribir(int columna, int fila, String texto, CellStyle estilo) {
      final celda = sheet.cell(en(columna, fila));
      celda.value = TextCellValue(texto);
      celda.cellStyle = estilo;
    }

    final ultima = _encabezados.length - 1;
    final titulo = CellStyle(bold: true, fontSize: 14);
    final ayuda = CellStyle(
      fontSize: 10,
      textWrapping: TextWrapping.WrapText,
      verticalAlign: VerticalAlign.Top,
    );
    final chico = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#888888'),
    );
    final encabezado = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#D9D9D9'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final fijo = CellStyle();
    final paraCompletar = CellStyle(
      backgroundColorHex:
          ExcelColor.fromHexString('#${kColorCasilleroDelegado.substring(2)}'),
    );

    escribir(0, 0, '$institucion · Acompañantes y música', titulo);
    sheet.merge(en(0, 0), en(ultima, 0));
    escribir(
      0,
      1,
      'Completá solo las columnas amarillas: Acompañantes y Música. Hasta '
          '$kMaxAcompanantes acompañantes por alumno, separados por una barra: '
          'Marta Acosta / Hugo Ríos.',
      ayuda,
    );
    sheet.merge(en(0, 1), en(ultima, 1));
    sheet.setRowHeight(1, 30);
    escribir(
      0,
      2,
      'No cambies los nombres de los alumnos.  $_marcaPlanilla $eventoId',
      chico,
    );
    sheet.merge(en(0, 2), en(ultima, 2));

    for (var c = 0; c < _encabezados.length; c++) {
      escribir(c, filaEncabezados, _encabezados[c], encabezado);
    }
    for (var i = 0; i < lista.length; i++) {
      final a = lista[i];
      final f = filaEncabezados + 1 + i;
      escribir(0, f, '${i + 1}', fijo);
      escribir(1, f, nombreLimpio(a), fijo);
      escribir(2, f, (a.cursoDivision ?? '').trim(), fijo);
      escribir(
        columnaAcompanantes,
        f,
        limpios(a.nombresAcompanantes).join(' / '),
        paraCompletar,
      );
      escribir(columnaMusica, f, (a.musicaElegida ?? '').trim(), paraCompletar);
      escribir(ultima, f, codigo[a.id]!, chico);
    }

    sheet.setColumnWidth(0, 5);
    sheet.setColumnWidth(1, 34);
    sheet.setColumnWidth(2, 11);
    sheet.setColumnWidth(columnaAcompanantes, 44);
    sheet.setColumnWidth(columnaMusica, 34);
    sheet.setColumnWidth(ultima, 13);

    return Uint8List.fromList(excel.encode()!);
  }

  // ── Importar ──────────────────────────────────────────────────────────────

  /// Lee un Excel como vino. No tira: si no se puede, lo dice en
  /// [LecturaPlanilla.problema].
  static LecturaPlanilla leer(Uint8List bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      return const LecturaPlanilla.ilegible(
        'No se pudo abrir el archivo. Tiene que ser el Excel (.xlsx) que se '
        'exportó desde acá.',
      );
    }

    for (final tabla in excel.tables.values) {
      final filas = [
        for (final fila in tabla.rows)
          [for (final celda in fila) _texto(celda?.value)],
      ];
      // Los encabezados: la primera fila con un casillero "Alumno" y otro que
      // empieza con "Acompañantes". Se buscan por nombre, no por lugar: el
      // delegado puede haber corrido una columna o agregado un renglón arriba.
      // Tienen que ser casilleros distintos: la ayuda de arriba nombra las dos
      // cosas en una sola frase.
      bool esAlumno(String c) => _llave(c) == 'alumno';
      bool esAcomp(String c) => _llave(c).startsWith('acompanante');
      final dondeEncabezados =
          filas.indexWhere((f) => f.any(esAlumno) && f.any(esAcomp));
      if (dondeEncabezados < 0) continue;

      final nombres = [for (final c in filas[dondeEncabezados]) _llave(c)];
      int empieza(String parte) =>
          nombres.indexWhere((n) => n.startsWith(parte));
      final cAlumno = nombres.indexOf('alumno');
      final cAcomp = empieza('acompanante');
      final cMusica = empieza('musica');
      final cCodigo = empieza('codigo');

      String? eventoId;
      String? institucion;
      for (final fila in filas.take(dondeEncabezados)) {
        for (final c in fila) {
          final m = RegExp(
            '${RegExp.escape(_marcaPlanilla)}\\s*([0-9a-fA-F-]{36})',
          ).firstMatch(c);
          if (m != null) eventoId = m.group(1)!.toLowerCase();
          final corte = c.indexOf(' · Acompañantes y música');
          if (corte > 0) institucion = c.substring(0, corte).trim();
        }
      }

      String en(List<String> fila, int c) =>
          c >= 0 && c < fila.length ? fila[c] : '';
      final renglones = <RenglonDelegado>[];
      for (var i = dondeEncabezados + 1; i < filas.length; i++) {
        final fila = filas[i];
        final r = RenglonDelegado(
          fila: i + 1,
          codigo: _unEspacio(en(fila, cCodigo)).toUpperCase(),
          alumno: _unEspacio(en(fila, cAlumno)),
          acompanantes: en(fila, cAcomp).trim(),
          musica: _unEspacio(en(fila, cMusica)),
        );
        // Un renglón sin alumno ni código es un renglón en blanco.
        if (r.codigo.isEmpty && r.alumno.isEmpty) continue;
        renglones.add(r);
      }
      return LecturaPlanilla(
        eventoId: eventoId,
        institucion: institucion,
        renglones: renglones,
      );
    }
    return const LecturaPlanilla.ilegible(
      'El archivo no tiene las columnas Alumno y Acompañantes. Tiene que ser '
      'el Excel que se exportó desde acá.',
    );
  }

  /// El texto de un casillero. Un número entero escrito a mano llega como
  /// "12.0": se le saca el decimal.
  static String _texto(CellValue? valor) {
    if (valor == null) return '';
    final s = valor.toString();
    return s.endsWith('.0') && double.tryParse(s) != null
        ? s.substring(0, s.length - 2)
        : s;
  }

  /// Compara lo leído con los alumnos de la fiesta [eventoId]. **No escribe
  /// nada.** [alumnos] son todos los de esa fiesta, también los de baja.
  static ResultadoPlanilla comparar({
    required LecturaPlanilla lectura,
    required Iterable<ContratoAlumno> alumnos,
    required String eventoId,
    required String institucion,
  }) {
    if (lectura.problema != null) {
      return ResultadoPlanilla.rechazado(lectura.problema!);
    }
    final deOtra = lectura.institucion?.trim().isNotEmpty == true
        ? lectura.institucion!.trim()
        : 'otra institución';
    if (lectura.eventoId != null && lectura.eventoId != eventoId.toLowerCase()) {
      return ResultadoPlanilla.rechazado(
        'Este Excel es de $deOtra y estás en $institucion. No se importó nada.',
      );
    }

    final todos = alumnos.toList();
    final porNombre = <String, List<ContratoAlumno>>{};
    for (final a in todos) {
      porNombre.putIfAbsent(_llave(nombreLimpio(a)), () => []).add(a);
    }

    /// Los alumnos de la fiesta cuyo id empieza como dice el código. Se busca
    /// por el principio y no por el código entero: [codigos] lo alarga si dos
    /// alumnos coinciden, y eso puede pasar después de haber exportado.
    List<ContratoAlumno> conCodigo(String codigo) {
      final hex = codigo.startsWith('K') ? codigo.substring(1) : codigo;
      if (hex.length < 8) return const [];
      return [
        for (final a in todos)
          if (_hex(a.id).startsWith(hex)) a,
      ];
    }

    final revisar = <RevisarDelegado>[];
    final leidos = <String, ({RenglonDelegado r, List<String> acomp})>{};
    final repetidos = <String>{};
    var ajenos = 0;

    for (final r in lectura.renglones) {
      final quien = r.alumno.isNotEmpty ? r.alumno : 'Fila ${r.fila}';
      ContratoAlumno? a;
      if (r.codigo.isNotEmpty) {
        var deEseCodigo = conCodigo(r.codigo);
        if (deEseCodigo.length > 1) {
          // Dos ids que empiezan igual: decide el nombre.
          deEseCodigo = [
            for (final c in deEseCodigo)
              if (_llave(nombreLimpio(c)) == _llave(r.alumno)) c,
          ];
        }
        if (deEseCodigo.length != 1) {
          ajenos++;
          revisar.add(
            RevisarDelegado(
              quien,
              'su código no es de esta institución. No se carga.',
            ),
          );
          continue;
        }
        a = deEseCodigo.single;
        if (r.alumno.isNotEmpty &&
            _llave(r.alumno) != _llave(nombreLimpio(a))) {
          revisar.add(
            RevisarDelegado(
              quien,
              'el Excel dice "${r.alumno}" y ese código es de '
              '"${nombreLimpio(a)}". No se carga.',
            ),
          );
          continue;
        }
      } else {
        final candidatos = porNombre[_llave(r.alumno)] ?? const [];
        if (candidatos.length != 1) {
          if (candidatos.isEmpty) ajenos++;
          revisar.add(
            RevisarDelegado(
              quien,
              candidatos.isEmpty
                  ? 'no tiene código y no hay un alumno con ese nombre en '
                      'esta institución. No se carga.'
                  : 'no tiene código y hay ${candidatos.length} alumnos con '
                      'ese nombre. No se carga.',
            ),
          );
          continue;
        }
        a = candidatos.single;
      }

      final nombre = nombreLimpio(a);
      if (a.esBajaTemporal) {
        revisar.add(RevisarDelegado(nombre, 'está dado de baja. No se carga.'));
        continue;
      }
      final acomp = separarAcompanantes(r.acompanantes);
      // Más del máximo no entra, salvo que sea lo que el alumno ya tiene
      // cargado (una excepción del jefe, que salió así en la planilla).
      if (acomp.length > kMaxAcompanantes &&
          !_mismos(limpios(a.nombresAcompanantes), acomp)) {
        revisar.add(
          RevisarDelegado(
            nombre,
            'trae ${acomp.length} acompañantes y el máximo es '
            '$kMaxAcompanantes. No se carga.',
          ),
        );
        continue;
      }
      final previo = leidos[a.id];
      if (previo != null) {
        final igual = _mismos(previo.acomp, acomp) && previo.r.musica == r.musica;
        if (!igual && repetidos.add(a.id)) {
          revisar.add(
            RevisarDelegado(
              nombre,
              'aparece dos veces en el Excel con datos distintos. No se carga.',
            ),
          );
        }
        continue;
      }
      leidos[a.id] = (r: r, acomp: acomp);
    }

    // Ni un renglón es de acá: el Excel es de otra institución, aunque le
    // hayan borrado el renglón que lo decía.
    if (lectura.renglones.isNotEmpty &&
        ajenos == lectura.renglones.length) {
      return ResultadoPlanilla.rechazado(
        'Este Excel es de $deOtra y estás en $institucion. No se importó nada.',
      );
    }

    final porId = {for (final a in todos) a.id: a};
    final cambios = <CambioDelegado>[];
    var iguales = 0;
    var vacios = 0;
    for (final e in leidos.entries) {
      if (repetidos.contains(e.key)) continue;
      final a = porId[e.key]!;
      final acomp = e.value.acomp;
      final musica = e.value.r.musica;
      if (acomp.isEmpty && musica.isEmpty) {
        vacios++;
        continue;
      }
      final tenia = limpios(a.nombresAcompanantes);
      final cambiaAcomp = acomp.isNotEmpty && !_mismos(tenia, acomp);
      if (cambiaAcomp && tenia.length > kMaxAcompanantes) {
        revisar.add(
          RevisarDelegado(
            nombreLimpio(a),
            'ya tiene ${tenia.length} acompañantes cargados, más que el '
            'máximo: no se toca desde el Excel.',
          ),
        );
        continue;
      }
      final cambiaMusica =
          musica.isNotEmpty && musica != _unEspacio(a.musicaElegida ?? '');
      if (!cambiaAcomp && !cambiaMusica) {
        iguales++;
        continue;
      }
      cambios.add(
        CambioDelegado(
          alumno: a,
          acompanantes: cambiaAcomp ? acomp : null,
          musica: cambiaMusica ? musica : null,
        ),
      );
    }
    cambios.sort(
      (x, y) => _llave(x.alumno.nombreAlumno)
          .compareTo(_llave(y.alumno.nombreAlumno)),
    );
    return ResultadoPlanilla(
      cambios: cambios,
      iguales: iguales,
      vacios: vacios,
      revisar: revisar,
    );
  }

  static bool _mismos(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
