import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import 'entrega_por_partes.dart';

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

  /// Sigue entregada: es lo último que pasó con esa parte.
  final bool vigente;

  /// Si se anuló después: cuándo, quién y por qué.
  final DateTime? anuladaAt;
  final String? anuladaPor;
  final String? motivoAnulacion;

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
    required this.vigente,
    this.anuladaAt,
    this.anuladaPor,
    this.motivoAnulacion,
  });

  bool get anulada => anuladaAt != null;

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
}

/// Lo que entregó una persona: un renglón de la tabla de la caja de entregas.
class PersonaDeLaCaja {
  final String quien;

  /// Lo que sigue entregado (sin lo anulado).
  final int pulseras;
  final int generales;

  /// Las familias con algo suyo que sigue entregado.
  final int familias;

  /// Su última entrega, anulada o no.
  final DateTime? ultima;

  /// Todo lo suyo, de lo más viejo a lo más nuevo, también lo anulado.
  final List<EntregaDeLaCaja> entregas;

  const PersonaDeLaCaja({
    required this.quien,
    required this.pulseras,
    required this.generales,
    required this.familias,
    required this.ultima,
    required this.entregas,
  });

  int get anuladas => entregas.where((e) => e.anulada).length;
}

/// La caja de entregas de una fiesta, para el cierre de caja (pedido del usuario,
/// 20-nov-2026: "que el jefe mire la caja de entregas con sus detalles como lo
/// hace o cierre de caja"). **Solo para mirar e imprimir**: anular sigue en
/// ENTRADAS de la fiesta.
///
/// **No es otra cuenta:** lo que tiene que llegar y lo entregado sale de
/// [ResumenPorPartes], y si cada entrega sigue en pie, de
/// [EstadoDeLaEntrega] (las mismas reglas de la entrega, también con relojes
/// distintos y con la 6.9.x de por medio). Lo nuevo es agrupar por quién la
/// anotó y listar cada una.
class CajaDeEntregas {
  final ResumenPorPartes resumen;

  /// Una por quien entregó, por nombre.
  final List<PersonaDeLaCaja> personas;

  /// Cuántas veces se anuló algo (una parte, o las 8 juntas desde una 6.9.x).
  final int anuladas;

  const CajaDeEntregas({
    required this.resumen,
    required this.personas,
    required this.anuladas,
  });

  bool get sinEntregas => personas.isEmpty;

  /// Las familias con una sola de las dos partes entregada.
  int get conUnaSolaParte =>
      resumen.familiasConPulseras +
      resumen.familiasConGenerales -
      2 * resumen.familiasConTodo;

  /// Todas las entregas, de la más vieja a la más nueva.
  List<EntregaDeLaCaja> get todas => [
        for (final p in personas) ...p.entregas,
      ]..sort((a, b) => a.cuando.compareTo(b.cuando));

  /// [alumnos]: los que cuentan para lo que tiene que llegar (sin las bajas,
  /// como VENDER). [todos]: también las bajas, porque lo que se les entregó se
  /// entregó igual. [renglones]: los de `entradas_entregas` de la fiesta.
  static CajaDeEntregas de({
    required List<ContratoAlumno> alumnos,
    required List<ContratoAlumno> todos,
    required Map<String, EntradasRetiro> retiros,
    required Iterable<EntregaEntradas> renglones,
  }) {
    final porAlumno = EntregaEntradas.porAlumno([
      for (final r in renglones)
        if (r.parte != null && r.accion != null) r,
    ]);
    final entregas = <EntregaDeLaCaja>[];
    var anuladas = 0;
    for (final a in todos) {
      final rs = porAlumno[a.id] ?? const <EntregaEntradas>[];
      final retiro = retiros[a.id];
      final estado = EstadoDeLaEntrega.deAlumno(a, retiro: retiro, renglones: rs);
      final familia = a.nombreAlumno.replaceAll('[BAJA]', '').trim();
      anuladas += rs.where((r) => r.esAnulacion).length;

      // Cada renglón de entrega: sigue en pie si es lo último de su parte.
      for (var i = 0; i < rs.length; i++) {
        final r = rs[i];
        if (!r.esEntrega) continue;
        final p = r.parte!;
        final hoy = estado.parte(p);
        final vigente = hoy.entregada &&
            !hoy.deLaFila &&
            hoy.entregadaAt != null &&
            hoy.entregadaAt!.isAtSameMomentAs(r.createdAt) &&
            (hoy.anotadoPor ?? '') == (r.hechoPor ?? '');
        // La anulación que la tumbó: la primera de su parte que vino después.
        EntregaEntradas? anulacion;
        for (final otra in rs.skip(i + 1)) {
          if (otra.parte == p && otra.esAnulacion) {
            anulacion = otra;
            break;
          }
          if (otra.parte == p && otra.esEntrega) break;
        }
        // O la de una 6.9.x, que vive en la fila.
        final deLaFila = !vigente &&
            anulacion == null &&
            hoy.anulada &&
            hoy.deLaFila &&
            hoy.anuladaAt!.isAfter(r.createdAt);
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
          vigente: vigente,
          anuladaAt: anulacion?.createdAt ?? (deLaFila ? hoy.anuladaAt : null),
          anuladaPor: anulacion?.hechoPor ?? (deLaFila ? hoy.anuladaPor : null),
          motivoAnulacion: anulacion != null
              ? _motivo(anulacion.motivo)
              : (deLaFila ? hoy.motivoAnulacion : null),
        ));
      }

      // Lo que vive solo en la fila de `entradas_retiro` (una PC con la 6.9.x):
      // lo último de alguna parte sale de ahí.
      final f = retiro;
      final pulseras = estado.pulseras;
      final generales = estado.generales;
      if (f == null || !(pulseras.deLaFila || generales.deLaFila)) continue;
      // Una anulación de las 8 juntas desde una 6.9.x: cuenta una vez.
      final anuladaEnLaFila = !f.entregado &&
          f.anuladoAt != null &&
          ((pulseras.deLaFila && pulseras.anulada) ||
              (generales.deLaFila && generales.anulada));
      if (anuladaEnLaFila) anuladas++;
      // La entrega de las 8 juntas, si no es el reflejo de un renglón (esa ya
      // está arriba, con su renglón): una entrada con las dos partes.
      final entregadoAt = f.entregadoAt;
      final esReflejo = entregadoAt != null &&
          rs.any((r) => r.esEntrega && r.createdAt.isAtSameMomentAs(entregadoAt));
      if (entregadoAt != null && !esReflejo) {
        final sigue = pulseras.deLaFila && pulseras.entregada;
        entregas.add(EntregaDeLaCaja(
          alumnoId: a.id,
          familia: familia,
          quien: _quien(f.entregadoPor),
          cuando: entregadoAt,
          parte: null,
          pulseras: f.vip,
          generales: f.generales,
          tramos: f.tramos,
          parentesco: f.parentesco,
          retiroNombre: f.retiroNombre,
          otraPersonaMotivo: f.otraPersonaMotivo,
          autorizacionFirmada: f.autorizacionFirmada,
          deLasOchoJuntas: true,
          vigente: sigue,
          anuladaAt: anuladaEnLaFila ? f.anuladoAt : null,
          anuladaPor: anuladaEnLaFila ? f.anuladoPor : null,
          motivoAnulacion: anuladaEnLaFila ? f.anuladoMotivo : null,
        ));
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
    return CajaDeEntregas(
      resumen: ResumenPorPartes.de(
        alumnos: alumnos,
        retiros: retiros,
        renglones: renglones,
      ),
      personas: personas,
      anuladas: anuladas,
    );
  }

  static PersonaDeLaCaja _persona(String quien, List<EntregaDeLaCaja> suyas) {
    suyas.sort((a, b) => a.cuando.compareTo(b.cuando));
    var pulseras = 0, generales = 0;
    final familias = <String>{};
    for (final e in suyas) {
      if (!e.vigente) continue;
      pulseras += e.pulseras;
      generales += e.generales;
      familias.add(e.alumnoId);
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
