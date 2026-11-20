import '../../../core/utils/uuid_utils.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import 'entrega_por_partes.dart';

/// Cómo quedó una parte de una entrega de la caja: sigue, **se anuló** (con
/// hora, quién y motivo) o **no cuenta porque se volvió a entregar** (otra
/// entrega de la misma parte vino después sin anular esta: dos equipos sin
/// internet, o una PC con la 6.9.x).
class ComoQuedoLaParte {
  final DateTime? anuladaAt;
  final String? anuladaPor;
  final String? motivoAnulacion;
  final DateTime? reemplazadaAt;
  final String? reemplazadaPor;

  const ComoQuedoLaParte.vigente()
      : anuladaAt = null,
        anuladaPor = null,
        motivoAnulacion = null,
        reemplazadaAt = null,
        reemplazadaPor = null;

  const ComoQuedoLaParte.anulada({required DateTime at, String? por, String? motivo})
      : anuladaAt = at,
        anuladaPor = por,
        motivoAnulacion = motivo,
        reemplazadaAt = null,
        reemplazadaPor = null;

  const ComoQuedoLaParte.reemplazada({required DateTime at, required String por})
      : anuladaAt = null,
        anuladaPor = null,
        motivoAnulacion = null,
        reemplazadaAt = at,
        reemplazadaPor = por;

  bool get anulada => anuladaAt != null;
  bool get reemplazada => reemplazadaAt != null;
  bool get vigente => !anulada && !reemplazada;

  /// Por qué no cuenta, o null si sigue. [hora] da el formato de la hora.
  String? texto(String Function(DateTime) hora) {
    if (anulada) {
      final por = (anuladaPor ?? '').trim();
      final motivo = (motivoAnulacion ?? '').trim();
      return 'ANULADA el ${hora(anuladaAt!)}'
          '${por.isEmpty ? '' : ' por $por'}'
          '${motivo.isEmpty ? '' : ': $motivo'}';
    }
    if (reemplazada) {
      return 'NO CUENTA: se volvió a entregar el ${hora(reemplazadaAt!)} por $reemplazadaPor';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ComoQuedoLaParte &&
      other.anuladaAt == anuladaAt &&
      other.anuladaPor == anuladaPor &&
      other.motivoAnulacion == motivoAnulacion &&
      other.reemplazadaAt == reemplazadaAt &&
      other.reemplazadaPor == reemplazadaPor;

  @override
  int get hashCode =>
      Object.hash(anuladaAt, anuladaPor, motivoAnulacion, reemplazadaAt, reemplazadaPor);
}

/// El tono de un renglón de [EntregaDeLaCaja.estado]: quién retiró (normal, o
/// apagado si no cuenta), una anulación, o lo que no cuenta porque se volvió a
/// entregar.
enum TonoDeLaLinea { normal, apagado, anulada, noCuenta }

/// Un renglón de lo que dice una entrega en la columna "Quién retiró".
class LineaDeLaEntrega {
  final String texto;
  final TonoDeLaLinea tono;
  const LineaDeLaEntrega(this.texto, this.tono);
}

/// Una entrega sin cargo, para la caja de entregas del cierre de caja: una parte
/// (las pulseras o las generales) o **las 8 juntas** de una PC con la 6.9.x.
class EntregaDeLaCaja {
  final String alumnoId;

  /// El egresado, como está cargado ("ACOSTA, LUCÍA").
  final String familia;

  /// Quién la anotó (el operador, la cajera, "Jefe").
  final String quien;
  final DateTime cuando;

  /// La parte, o null si es la entrega de las 8 juntas (las dos partes).
  final ParteEntrega? parte;
  final int pulseras;
  final int generales;
  final List<TramoTalonario> tramos;
  final ParentescoRetiro? parentesco;
  final String? retiroNombre;
  final String? otraPersonaMotivo;
  final bool autorizacionFirmada;

  /// Una entrega de las 8 juntas, hecha con una 6.9.x (o su copia).
  final bool deLasOchoJuntas;

  /// La familia está hoy de baja: lo suyo no cuenta en los números de arriba
  /// (`ResumenPorPartes`), pero se entregó igual y va en las filas y el TOTAL
  /// (decisión del usuario, 20-nov-2026).
  final bool deBaja;

  /// Cómo quedó cada parte que lleva: una entrega de una parte lleva solo la
  /// suya; la de las 8 juntas, las dos.
  final ComoQuedoLaParte? lasPulseras;
  final ComoQuedoLaParte? lasGenerales;

  const EntregaDeLaCaja({
    required this.alumnoId,
    required this.familia,
    required this.quien,
    required this.cuando,
    required this.parte,
    required this.pulseras,
    required this.generales,
    this.tramos = const [],
    this.parentesco,
    this.retiroNombre,
    this.otraPersonaMotivo,
    this.autorizacionFirmada = false,
    this.deLasOchoJuntas = false,
    this.deBaja = false,
    this.lasPulseras,
    this.lasGenerales,
  });

  bool get pulserasVigentes => lasPulseras?.vigente ?? false;
  bool get generalesVigentes => lasGenerales?.vigente ?? false;

  /// Lo que suma en su persona: lo de cada parte que sigue.
  int get pulserasQueCuentan => pulserasVigentes ? pulseras : 0;
  int get generalesQueCuentan => generalesVigentes ? generales : 0;

  /// Su familia cuenta en FAMILIAS: algo que sigue, con cantidad (las
  /// generales en 0 de una familia de 8 o más con cena no son nada).
  bool get cuentaAlgo => pulserasQueCuentan + generalesQueCuentan > 0;

  /// Alguna de sus partes sigue.
  bool get vigente => pulserasVigentes || generalesVigentes;

  /// Las 8 juntas, con cada parte distinta (una sigue y la otra no, o las dos
  /// no cuentan por motivos distintos).
  bool get partida => parte == null && lasPulseras != lasGenerales;

  ComoQuedoLaParte? get _entera =>
      partida ? null : (lasPulseras ?? lasGenerales);

  /// Toda la entrega se anuló (sin partir).
  bool get anulada => _entera?.anulada ?? false;
  DateTime? get anuladaAt => _entera?.anuladaAt;
  String? get anuladaPor => _entera?.anuladaPor;
  String? get motivoAnulacion => _entera?.motivoAnulacion;

  /// Toda la entrega no cuenta porque se volvió a entregar (sin partir).
  bool get reemplazada => _entera?.reemplazada ?? false;
  DateTime? get reemplazadaAt => _entera?.reemplazadaAt;
  String? get reemplazadaPor => _entera?.reemplazadaPor;

  bool get algoAnulado =>
      (lasPulseras?.anulada ?? false) || (lasGenerales?.anulada ?? false);
  bool get algoReemplazado =>
      (lasPulseras?.reemplazada ?? false) || (lasGenerales?.reemplazada ?? false);

  /// Los números van apagados: lleva generales y ya no cuentan.
  bool get numerosApagados => generales > 0 && !generalesVigentes;

  /// "Pulseras VIP", "Generales", "Pulseras y generales".
  String get que => switch (parte) {
        ParteEntrega.pulseras => 'Pulseras VIP',
        ParteEntrega.generales => 'Generales',
        null => 'Pulseras y generales',
      };

  /// "3", "5", "1 + 7" (las 8 juntas: las pulseras más las generales).
  String get cantidad => parte == null
      ? '$pulseras + $generales'
      : '${parte == ParteEntrega.pulseras ? pulseras : generales}';

  /// "Madre · MARTA ACOSTA", "Otra persona · TÍA ROSA (autorización firmada)".
  String get quienRetiro {
    final nombre = (retiroNombre ?? '').trim();
    final partes = [
      if (parentesco != null) parentesco!.etiqueta,
      if (nombre.isNotEmpty) nombre,
    ];
    final base = partes.join(' · ');
    if (parentesco == ParentescoRetiro.otraPersona && autorizacionFirmada) {
      return '$base (autorización firmada)';
    }
    return base;
  }

  /// "del 5001 al 5005", "sin número" (las generales que vinieron sin
  /// numerar), o "" si no lleva generales.
  String get numeros {
    if (generales <= 0) return '';
    if (tramos.isEmpty) return 'sin número';
    return 'del ${TramoTalonario.legible(tramos)}';
  }

  /// Lo que va en la columna "Quién retiró", **lo único que leen la pantalla y
  /// el papel** (así dicen lo mismo):
  /// - si sigue: quién retiró;
  /// - anulada entera: el motivo, en lugar de quién retiró (como en la maqueta);
  /// - no cuenta entera: quién retiró, apagado (ese material salió y el jefe
  ///   tiene que saber quién lo tiene), y debajo por qué no cuenta;
  /// - partida: quién retiró y un renglón por cada parte que no cuenta, con
  ///   "Pulseras VIP: " o "Generales: " delante.
  List<LineaDeLaEntrega> estado(String Function(DateTime) hora) {
    final retiro = quienRetiro;
    TonoDeLaLinea tonoDe(ComoQuedoLaParte c) =>
        c.anulada ? TonoDeLaLinea.anulada : TonoDeLaLinea.noCuenta;
    if (!partida) {
      final c = _entera!;
      if (c.anulada) return [LineaDeLaEntrega(c.texto(hora)!, TonoDeLaLinea.anulada)];
      if (c.reemplazada) {
        return [
          if (retiro.isNotEmpty) LineaDeLaEntrega(retiro, TonoDeLaLinea.apagado),
          LineaDeLaEntrega(c.texto(hora)!, TonoDeLaLinea.noCuenta),
        ];
      }
      return [if (retiro.isNotEmpty) LineaDeLaEntrega(retiro, TonoDeLaLinea.normal)];
    }
    return [
      if (retiro.isNotEmpty)
        LineaDeLaEntrega(retiro, vigente ? TonoDeLaLinea.normal : TonoDeLaLinea.apagado),
      for (final (nombre, c) in [('Pulseras VIP', lasPulseras!), ('Generales', lasGenerales!)])
        if (!c.vigente) LineaDeLaEntrega('$nombre: ${c.texto(hora)}', tonoDe(c)),
    ];
  }
}

/// Una anulación que no va al lado de ninguna entrega de la lista: la entrega
/// que anuló ya no está guardada (una PC con la 6.9.x guarda una sola entrega
/// por familia y la reescribe al volver a entregar) o ya estaba anulada (dos
/// equipos anularon lo mismo). Se cuenta en ANULADAS y se ve aparte.
class AnulacionAnterior {
  final String alumnoId;
  final String familia;
  final DateTime cuando;
  final String? por;
  final String? motivo;
  final bool deBaja;

  const AnulacionAnterior({
    required this.alumnoId,
    required this.familia,
    required this.cuando,
    this.por,
    this.motivo,
    this.deBaja = false,
  });

  /// "Anulación de una entrega anterior, por Jefe: se equivocó de familia".
  String get texto {
    final p = (por ?? '').trim();
    final m = (motivo ?? '').trim();
    return 'Anulación de una entrega anterior'
        '${p.isEmpty ? '' : ', por $p'}'
        '${m.isEmpty ? '' : ': $m'}';
  }
}

/// Lo que entregó una persona: un renglón de la tabla de la caja de entregas.
class PersonaDeLaCaja {
  final String quien;

  /// Lo que sigue entregado (sin lo anulado ni lo que no cuenta), cada
  /// material con lo suyo. **Con lo de las familias hoy de baja.**
  final int pulseras;
  final int generales;

  /// Las familias con algo suyo que sigue entregado.
  final int familias;

  /// Su última entrega, anulada o no.
  final DateTime? ultima;

  /// Todo lo suyo, de lo más viejo a lo más nuevo, también lo que no cuenta.
  final List<EntregaDeLaCaja> entregas;

  const PersonaDeLaCaja({
    required this.quien,
    required this.pulseras,
    required this.generales,
    required this.familias,
    required this.ultima,
    required this.entregas,
  });

  /// Sus entregas con algo anulado.
  int get anuladas => entregas.where((e) => e.algoAnulado).length;

  /// Sus entregas con algo que no cuenta porque se volvió a entregar.
  int get sinEfecto => entregas.where((e) => e.algoReemplazado).length;
}

/// La caja de entregas de una fiesta, para el cierre de caja (pedido del usuario,
/// 20-nov-2026: "que el jefe mire la caja de entregas con sus detalles como lo
/// hace o cierre de caja"). **Solo para mirar e imprimir**: anular sigue en
/// ENTRADAS de la fiesta.
///
/// **No es otra cuenta:** lo que tiene que llegar y lo entregado sale de
/// [ResumenPorPartes], y qué pasó con cada entrega, de [HistoriaDeLaEntrega]
/// (las mismas novedades y el mismo orden que [EstadoDeLaEntrega], también con
/// relojes distintos y con la 6.9.x de por medio): lo último de cada parte es
/// lo que dice el estado. Lo nuevo es agrupar por quién la anotó y listar cada
/// una, con lo que pasó después.
///
/// **La conciliación** (revisión del 20-nov-2026, `test/caja_de_entregas_test.dart`):
/// lo de las filas, menos lo de las familias hoy de baja, es lo de la tarjeta
/// de arriba: las pulseras, las generales y las familias
/// (`familiasConTodo + familiasConUnaSolaParte`).
class CajaDeEntregas {
  final ResumenPorPartes resumen;

  /// Una por quien entregó, por nombre.
  final List<PersonaDeLaCaja> personas;

  /// Cuántas veces se anuló algo: cada anulación de esta versión (lo que se
  /// anuló junto, las dos partes o las copias de una anulación de la fila, es
  /// una) y la que guarda la fila de una 6.9.x (aunque después se haya vuelto a
  /// entregar), sin su reflejo ni su copia.
  final int anuladas;

  /// Las anulaciones que no van al lado de ninguna entrega de la lista.
  final List<AnulacionAnterior> anulacionesAnteriores;

  const CajaDeEntregas({
    required this.resumen,
    required this.personas,
    required this.anuladas,
    this.anulacionesAnteriores = const [],
  });

  bool get sinEntregas => personas.isEmpty;

  /// Las familias con una sola de las dos partes entregada (contadas familia
  /// por familia: nunca da negativo).
  int get conUnaSolaParte => resumen.familiasConUnaSolaParte;

  /// Todas las entregas, de la más vieja a la más nueva.
  List<EntregaDeLaCaja> get todas => [
        for (final p in personas) ...p.entregas,
      ]..sort((a, b) => a.cuando.compareTo(b.cuando));

  /// El TOTAL de la tabla: la suma de las filas (con lo de las bajas).
  int get pulserasDeLasFilas => personas.fold(0, (s, p) => s + p.pulseras);
  int get generalesDeLasFilas => personas.fold(0, (s, p) => s + p.generales);

  /// FAMILIAS del TOTAL: las familias distintas con algo que cuenta. **No es
  /// la suma de la columna**: la que recibió las pulseras de una persona y las
  /// generales de otra está en las dos filas y es una sola.
  int get familiasConAlgo => {
        for (final e in todas)
          if (e.cuentaAlgo) e.alumnoId,
      }.length;

  /// La columna FAMILIAS suma más que el TOTAL: alguna familia está en dos filas.
  bool get familiasEnDosFilas =>
      personas.fold(0, (s, p) => s + p.familias) > familiasConAlgo;

  /// Lo que cuenta en las filas y es de familias hoy de baja.
  int get pulserasDeBaja => todas
      .where((e) => e.deBaja)
      .fold(0, (s, e) => s + e.pulserasQueCuentan);
  int get generalesDeBaja => todas
      .where((e) => e.deBaja)
      .fold(0, (s, e) => s + e.generalesQueCuentan);
  List<String> get familiasDeBaja => {
        for (final e in todas)
          if (e.deBaja && e.cuentaAlgo) e.alumnoId: e.familia,
      }.values.toList()
        ..sort();

  /// "Incluye 3 pulseras de 1 familia hoy de baja (PÉREZ, CARO): arriba no
  /// cuentan.", o null si no hay nada de bajas. Hasta 3 nombres, separados por
  /// un punto (los nombres llevan coma).
  String? get textoDeLasBajas {
    final familias = familiasDeBaja;
    if (familias.isEmpty) return null;
    final p = pulserasDeBaja, g = generalesDeBaja;
    final que = [
      if (p > 0) p == 1 ? '1 pulsera' : '$p pulseras',
      if (g > 0) g == 1 ? '1 general' : '$g generales',
    ].join(' y ');
    final nombres = familias.length <= 3
        ? familias.join(' · ')
        : '${familias.take(3).join(' · ')} y ${familias.length - 3} más';
    final cuantas = familias.length == 1 ? '1 familia' : '${familias.length} familias';
    return 'Incluye $que de $cuantas hoy de baja ($nombres): arriba no cuentan.';
  }

  /// La nota de debajo del TOTAL cuando una familia está en dos filas.
  static const notaDeLasFamilias = 'Una familia que recibió las pulseras de una '
      'persona y las generales de otra está en las dos filas: en el total cuenta '
      'una vez.';

  /// [alumnos]: los que cuentan para lo que tiene que llegar (sin las bajas,
  /// como VENDER). [todos]: también las bajas, porque lo que se les entregó se
  /// entregó igual. [renglones]: los de `entradas_entregas` de la fiesta.
  static CajaDeEntregas de({
    required List<ContratoAlumno> alumnos,
    required List<ContratoAlumno> todos,
    required Map<String, EntradasRetiro> retiros,
    required Iterable<EntregaEntradas> renglones,
  }) {
    final cuentanArriba = {for (final a in alumnos) a.id};
    final porAlumno = EntregaEntradas.porAlumno([
      for (final r in renglones)
        if (r.parte != null && r.accion != null) r,
    ]);
    final entregas = <EntregaDeLaCaja>[];
    final anteriores = <AnulacionAnterior>[];
    var anuladas = 0;
    for (final a in todos) {
      final rs = porAlumno[a.id] ?? const <EntregaEntradas>[];
      final f = retiros[a.id];
      final familia = a.nombreAlumno.replaceAll('[BAJA]', '').trim();
      final deBaja = !cuentanArriba.contains(a.id);
      final h = HistoriaDeLaEntrega.de(retiro: f, renglones: rs);
      final historias = {
        for (final p in ParteEntrega.values) p: _sinLaFilaCopiada(h.parte(p), f, p),
      };

      // Qué pasó después de cada entrega: la novedad que le sigue en su parte.
      final tumbaron = <String>{};
      var laDeLaFilaTumbo = false;
      ComoQuedoLaParte despues(ParteEntrega p, int i) {
        final hist = historias[p]!;
        if (i == hist.length - 1) return const ComoQuedoLaParte.vigente();
        final s = hist[i + 1];
        final r = s.renglon;
        if (s.esEntrega) {
          return ComoQuedoLaParte.reemplazada(
            at: s.momento,
            por: _quien(r != null ? r.hechoPor : f?.entregadoPor),
          );
        }
        if (r != null) {
          tumbaron.add(r.id);
          return ComoQuedoLaParte.anulada(at: s.momento, por: r.hechoPor, motivo: _motivo(r.motivo));
        }
        laDeLaFilaTumbo = true;
        return ComoQuedoLaParte.anulada(at: s.momento, por: f?.anuladoPor, motivo: f?.anuladoMotivo);
      }

      // Cada renglón de entrega, con su parte.
      for (final p in ParteEntrega.values) {
        final hist = historias[p]!;
        for (var i = 0; i < hist.length; i++) {
          final r = hist[i].renglon;
          if (r == null || !hist[i].esEntrega) continue;
          final como = despues(p, i);
          entregas.add(EntregaDeLaCaja(
            alumnoId: a.id,
            familia: familia,
            quien: _quien(r.hechoPor),
            cuando: r.createdAt,
            parte: p,
            pulseras: p == ParteEntrega.pulseras ? r.cantidad : 0,
            generales: p == ParteEntrega.generales ? r.cantidad : 0,
            tramos: r.tramos,
            parentesco: r.parentesco,
            retiroNombre: r.retiroNombre,
            otraPersonaMotivo: r.otraPersonaMotivo,
            autorizacionFirmada: r.autorizacionFirmada,
            deLasOchoJuntas: r.motivo == EntregaEntradas.kCopiaDeLaFila,
            deBaja: deBaja,
            lasPulseras: p == ParteEntrega.pulseras ? como : null,
            lasGenerales: p == ParteEntrega.generales ? como : null,
          ));
        }
      }

      // La entrega de las 8 juntas de una 6.9.x (la fila), con las partes en
      // las que quedó su novedad: las dos, una sola o ninguna.
      if (f != null) {
        int filaEn(ParteEntrega p) =>
            historias[p]!.indexWhere((n) => n.deLaFila && n.esEntrega);
        final ip = filaEn(ParteEntrega.pulseras);
        final ig = filaEn(ParteEntrega.generales);
        if (ip >= 0 || ig >= 0) {
          final qp = ip >= 0 ? despues(ParteEntrega.pulseras, ip) : null;
          final qg = ig >= 0 ? despues(ParteEntrega.generales, ig) : null;
          final parte = qp != null && qg != null
              ? null
              : (qp != null ? ParteEntrega.pulseras : ParteEntrega.generales);
          entregas.add(EntregaDeLaCaja(
            alumnoId: a.id,
            familia: familia,
            quien: _quien(f.entregadoPor),
            cuando: (ip >= 0
                    ? historias[ParteEntrega.pulseras]![ip]
                    : historias[ParteEntrega.generales]![ig])
                .momento,
            parte: parte,
            pulseras: qp != null ? f.vip : 0,
            generales: qg != null ? f.generales : 0,
            tramos: qg != null ? f.tramos : const [],
            parentesco: f.parentesco,
            retiroNombre: f.retiroNombre,
            otraPersonaMotivo: f.otraPersonaMotivo,
            autorizacionFirmada: f.autorizacionFirmada,
            deLasOchoJuntas: true,
            deBaja: deBaja,
            lasPulseras: qp,
            lasGenerales: qg,
          ));
        }
      }

      // La anulación que guarda la fila (de una 6.9.x): cuenta aunque después
      // se haya vuelto a entregar, salvo que sea el reflejo de un renglón o
      // tenga su copia (con la hora corrida, quizás: es la misma anulación).
      final enLaFila = h.anulacionEnLaFila;
      EntregaEntradas? suCopia;
      var cuentaLaDeLaFila = false;
      if (f != null && enLaFila != null && !h.anulacionEsReflejo) {
        for (final r in rs) {
          if (_esCopiaDeLaAnulacion(r, a.id, f, enLaFila)) {
            suCopia = r;
            break;
          }
        }
        cuentaLaDeLaFila = suCopia == null;
      }
      if (laDeLaFilaTumbo && suCopia != null) tumbaron.add(suCopia.id);

      // Los renglones de anulación, por acto: lo que se anuló junto (las dos
      // partes a la vez, o las copias de una anulación de la fila, una por
      // parte) lleva la misma hora y el mismo quién, y es **una** anulación.
      final actos = <String, List<EntregaEntradas>>{};
      for (final r in rs) {
        if (!r.esAnulacion) continue;
        actos
            .putIfAbsent(
              '${r.createdAt.toUtc().toIso8601String()}|${(r.hechoPor ?? '').trim()}',
              () => [],
            )
            .add(r);
      }
      for (final acto in actos.values) {
        anuladas++;
        if (acto.any((r) => tumbaron.contains(r.id))) continue;
        final r = acto.first;
        anteriores.add(AnulacionAnterior(
          alumnoId: a.id,
          familia: familia,
          cuando: r.createdAt,
          por: r.hechoPor,
          motivo: _motivo(r.motivo),
          deBaja: deBaja,
        ));
      }
      if (cuentaLaDeLaFila) {
        anuladas++;
        if (!laDeLaFilaTumbo) {
          NovedadDeLaParte? enLaHistoria;
          for (final p in ParteEntrega.values) {
            for (final n in historias[p]!) {
              if (n.deLaFila && n.esAnulacion) enLaHistoria = n;
            }
          }
          anteriores.add(AnulacionAnterior(
            alumnoId: a.id,
            familia: familia,
            cuando: enLaHistoria?.momento ?? enLaFila!,
            por: f!.anuladoPor,
            motivo: f.anuladoMotivo,
            deBaja: deBaja,
          ));
        }
      }
    }

    final porQuien = <String, List<EntregaDeLaCaja>>{};
    for (final e in entregas) {
      porQuien.putIfAbsent(e.quien, () => []).add(e);
    }
    final personas = [
      for (final MapEntry(key: quien, value: suyas) in porQuien.entries)
        _persona(quien, suyas),
    ]..sort((a, b) => a.quien.toLowerCase().compareTo(b.quien.toLowerCase()));
    anteriores.sort((a, b) => a.cuando.compareTo(b.cuando));
    return CajaDeEntregas(
      resumen: ResumenPorPartes.de(
        alumnos: alumnos,
        retiros: retiros,
        renglones: renglones,
      ),
      personas: personas,
      anuladas: anuladas,
      anulacionesAnteriores: List.unmodifiable(anteriores),
    );
  }

  /// La historia de [p] sin la entrega de la fila **cuando lo que le sigue
  /// (saltando anulaciones) es su copia**: la copia es esa misma entrega,
  /// escrita como renglón antes de reescribir la fila (`copiasDeLaFila`), y la
  /// fila puede volver a aparecer a su hora de antes (relojes distintos). Sin
  /// esto, la entrega de la fila se listaba dos veces y lo de antes decía que
  /// se volvió a entregar por la propia copia (revisión del 20-nov-2026, caso
  /// M1). Lo último de la historia no cambia: después de la fila viene una
  /// entrega.
  static List<NovedadDeLaParte> _sinLaFilaCopiada(
    List<NovedadDeLaParte> hist,
    EntradasRetiro? f,
    ParteEntrega p,
  ) {
    if (f == null) return hist;
    final i = hist.indexWhere((n) => n.deLaFila && n.esEntrega);
    if (i < 0) return hist;
    for (var j = i + 1; j < hist.length; j++) {
      if (!hist[j].esEntrega) continue;
      final r = hist[j].renglon;
      final esSuCopia = r != null &&
          r.motivo == EntregaEntradas.kCopiaDeLaFila &&
          _mismo(r.hechoPor, f.entregadoPor) &&
          r.cantidad == (p == ParteEntrega.pulseras ? f.vip : f.generales) &&
          _mismo(r.retiroNombre, f.retiroNombre);
      if (!esSuCopia) return hist;
      return [...hist.take(i), ...hist.skip(i + 1)];
    }
    return hist;
  }

  /// [r] es la copia de la anulación que guarda la fila [f]: un renglón de
  /// anulación con el id de las copias (`UuidUtils.entradasEntregaCopiaId` a
  /// su propia hora), de quien anuló la fila, con su motivo, y a la hora de la
  /// fila o después (las copias pueden llevar la hora corrida 1 ms).
  static bool _esCopiaDeLaAnulacion(
    EntregaEntradas r,
    String alumnoId,
    EntradasRetiro f,
    DateTime enLaFila,
  ) =>
      r.esAnulacion &&
      r.id ==
          UuidUtils.entradasEntregaCopiaId(
            alumnoId,
            r.parteClave,
            QueSeHizo.anulacion.clave,
            r.createdAt.toUtc().toIso8601String(),
          ) &&
      _mismo(r.hechoPor, f.anuladoPor) &&
      _mismo(r.motivo, f.anuladoMotivo ?? EntregaEntradas.kCopiaDeLaFila) &&
      !r.createdAt.isBefore(enLaFila);

  static bool _mismo(String? a, String? b) => (a ?? '').trim() == (b ?? '').trim();

  static PersonaDeLaCaja _persona(String quien, List<EntregaDeLaCaja> suyas) {
    int orden(EntregaDeLaCaja e) => switch (e.parte) {
          null => 0,
          ParteEntrega.pulseras => 1,
          ParteEntrega.generales => 2,
        };
    suyas.sort((a, b) {
      final c = a.cuando.compareTo(b.cuando);
      return c != 0 ? c : orden(a).compareTo(orden(b));
    });
    var pulseras = 0, generales = 0;
    final familias = <String>{};
    for (final e in suyas) {
      pulseras += e.pulserasQueCuentan;
      generales += e.generalesQueCuentan;
      if (e.cuentaAlgo) familias.add(e.alumnoId);
    }
    return PersonaDeLaCaja(
      quien: quien,
      pulseras: pulseras,
      generales: generales,
      familias: familias.length,
      ultima: suyas.isEmpty ? null : suyas.last.cuando,
      entregas: List.unmodifiable(suyas),
    );
  }

  static String _quien(String? hechoPor) {
    final q = (hechoPor ?? '').trim();
    return q.isEmpty ? 'Sin nombre' : q;
  }

  /// El motivo de una anulación copiada de la fila puede ser la nota de la
  /// copia: esa no dice nada.
  static String? _motivo(String? m) =>
      m == null || m == EntregaEntradas.kCopiaDeLaFila ? null : m;
}
