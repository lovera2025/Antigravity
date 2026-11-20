import 'dart:math';

import '../../../core/utils/uuid_utils.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import 'retiro_entradas.dart';
import 'salon_mesas.dart';

/// Cómo está una parte de la entrega sin cargo de un egresado: las pulseras VIP
/// o las generales.
class EstadoDeUnaParte {
  final ParteEntrega parte;

  /// Lo que le corresponde hoy, según su cuenta (`EntradasDeAlumno`).
  final int leToca;

  /// La última novedad de esta parte es una entrega.
  final bool entregada;

  /// Lo que se llevó (0 si no está entregada).
  final int cantidad;

  /// Los números de las generales que se llevó, si se anotaron.
  final List<TramoTalonario> tramos;

  final int menores10;
  final ParentescoRetiro? parentesco;
  final String? retiroNombre;
  final String? otraPersonaMotivo;
  final bool autorizacionFirmada;
  final bool escribioEnPlanilla;

  /// Cuándo se entregó, y quién lo anotó.
  final DateTime? entregadaAt;
  final String? anotadoPor;

  /// La última novedad es una anulación: cuándo, quién y por qué.
  final DateTime? anuladaAt;
  final String? anuladaPor;
  final String? motivoAnulacion;

  /// La última novedad sale de la fila de `entradas_retiro` y no de un renglón:
  /// una entrega de una sola vez, o una anulación hecha desde una 6.9.x. Antes
  /// de reescribir esa fila hay que copiarla a un renglón
  /// ([EntregaPorPartes.copiasDeLaFila]): si no, se perdería.
  final bool deLaFila;

  const EstadoDeUnaParte({
    required this.parte,
    required this.leToca,
    this.entregada = false,
    this.cantidad = 0,
    this.tramos = const [],
    this.menores10 = 0,
    this.parentesco,
    this.retiroNombre,
    this.otraPersonaMotivo,
    this.autorizacionFirmada = false,
    this.escribioEnPlanilla = false,
    this.entregadaAt,
    this.anotadoPor,
    this.anuladaAt,
    this.anuladaPor,
    this.motivoAnulacion,
    this.deLaFila = false,
  });

  bool get anulada => anuladaAt != null;

  /// Hecha: se entregó, o no le toca nada (las generales de quien tiene 8 o más
  /// con cena). Una parte sin nada que entregar no frena el "Todo entregado".
  bool get hecha => entregada || leToca <= 0;

  /// Falta entregarla.
  bool get falta => !hecha;

  /// Se entregó y después cambió su cuenta: se llevó otra cantidad de la que
  /// hoy le corresponde.
  bool get cambioLaCuenta => entregada && cantidad != leToca;
}

/// Cómo está la entrega sin cargo de un egresado, en dos partes.
///
/// **Las reglas** (20-nov-2026):
/// - Cada parte se decide por su **última novedad**. Las novedades son los
///   renglones de `entradas_entregas` de esa parte (ordenados por `created_at`
///   y después por `id`) y lo que dice la fila de `entradas_retiro`, que vale
///   para **las dos partes** (era una entrega de las 8 juntas).
/// - **Una entrega vieja** (la fila en "entregado", hecha con la 6.9.x, sin
///   renglones) **cuenta como las dos partes entregadas**.
/// - **Si el jefe anuló la fila completa desde una 6.9.x**, esa anulación es
///   una novedad para las dos partes: la parte cuyo último renglón es anterior
///   queda sin entregar.
/// - La fila de `entradas_retiro` que escribe esta versión es **el reflejo** de
///   un renglón: la escribe con la misma hora que el renglón que la provocó (la
///   entrega que completó las dos partes, o la anulación). Una novedad de la
///   fila con un renglón de la misma acción a la misma hora exacta es ese
///   reflejo y no cuenta: lo que pasó lo dicen los renglones. Sin esto, anular
///   solo las generales anularía también las pulseras.
/// - Una parte que no le toca (cantidad 0) cuenta como hecha
///   ([EstadoDeUnaParte.hecha]).
/// - Un renglón con una parte o una acción que esta versión no conoce se
///   ignora: nunca se inventa qué fue.
class EstadoDeLaEntrega {
  final EstadoDeUnaParte pulseras;
  final EstadoDeUnaParte generales;

  const EstadoDeLaEntrega({required this.pulseras, required this.generales});

  /// Las dos partes hechas: "✓ Todo entregado".
  bool get todoEntregado => pulseras.hecha && generales.hecha;

  /// Alguna parte entregada.
  bool get algoEntregado => pulseras.entregada || generales.entregada;

  EstadoDeUnaParte parte(ParteEntrega p) =>
      p == ParteEntrega.pulseras ? pulseras : generales;

  /// [retiro]: la fila de `entradas_retiro` del alumno, si tiene. [renglones]:
  /// los suyos de `entradas_entregas`, en cualquier orden. [entradas]: lo que
  /// le corresponde hoy (`RetiroEntradas.entradasDe`).
  static EstadoDeLaEntrega de({
    EntradasRetiro? retiro,
    required List<EntregaEntradas> renglones,
    required EntradasDeAlumno entradas,
  }) {
    final validos = [
      for (final r in renglones)
        if (r.parte != null && r.accion != null) r,
    ]..sort(EntregaEntradas.enOrden);
    final deLaFila = _NovedadesDeLaFila.de(retiro, validos);
    return EstadoDeLaEntrega(
      pulseras: _parte(
        ParteEntrega.pulseras,
        entradas.vip,
        validos,
        deLaFila,
        retiro,
      ),
      generales: _parte(
        ParteEntrega.generales,
        entradas.generales,
        validos,
        deLaFila,
        retiro,
      ),
    );
  }

  /// Lo mismo, con lo que le corresponde según su cuenta de hoy.
  static EstadoDeLaEntrega deAlumno(
    ContratoAlumno alumno, {
    EntradasRetiro? retiro,
    required List<EntregaEntradas> renglones,
  }) =>
      de(
        retiro: retiro,
        renglones: renglones,
        entradas: RetiroEntradas.entradasDe(alumno),
      );

  static EstadoDeUnaParte _parte(
    ParteEntrega p,
    int leToca,
    List<EntregaEntradas> renglones,
    List<_Novedad> deLaFila,
    EntradasRetiro? retiro,
  ) {
    final novedades = <_Novedad>[
      ...deLaFila,
      for (final r in renglones)
        if (r.parte == p) _Novedad.deRenglon(r),
    ]..sort(_Novedad.enOrden);
    if (novedades.isEmpty) return EstadoDeUnaParte(parte: p, leToca: leToca);
    final ultima = novedades.last;
    final r = ultima.renglon;
    if (r != null) {
      if (r.esEntrega) {
        return EstadoDeUnaParte(
          parte: p,
          leToca: leToca,
          entregada: true,
          cantidad: r.cantidad,
          tramos: r.tramos,
          menores10: r.menores10,
          parentesco: r.parentesco,
          retiroNombre: r.retiroNombre,
          otraPersonaMotivo: r.otraPersonaMotivo,
          autorizacionFirmada: r.autorizacionFirmada,
          escribioEnPlanilla: r.escribioEnPlanilla,
          entregadaAt: r.createdAt,
          anotadoPor: r.hechoPor,
        );
      }
      return EstadoDeUnaParte(
        parte: p,
        leToca: leToca,
        anuladaAt: r.createdAt,
        anuladaPor: r.hechoPor,
        motivoAnulacion: r.motivo,
      );
    }
    // La última novedad es la fila de `entradas_retiro`.
    final f = retiro!;
    if (ultima.accion == QueSeHizo.entrega) {
      return EstadoDeUnaParte(
        parte: p,
        leToca: leToca,
        entregada: true,
        cantidad: p == ParteEntrega.pulseras ? f.vip : f.generales,
        tramos: p == ParteEntrega.generales ? f.tramos : const [],
        menores10: f.menores10,
        parentesco: f.parentesco,
        retiroNombre: f.retiroNombre,
        otraPersonaMotivo: f.otraPersonaMotivo,
        autorizacionFirmada: f.autorizacionFirmada,
        escribioEnPlanilla: f.escribioEnPlanilla,
        entregadaAt: ultima.momento,
        anotadoPor: f.entregadoPor,
        deLaFila: true,
      );
    }
    return EstadoDeUnaParte(
      parte: p,
      leToca: leToca,
      anuladaAt: ultima.momento,
      anuladaPor: f.anuladoPor,
      motivoAnulacion: f.anuladoMotivo,
      deLaFila: true,
    );
  }
}

/// Una novedad de una parte: un renglón, o lo que dice la fila de
/// `entradas_retiro` (que vale para las dos).
class _Novedad {
  final DateTime momento;
  final QueSeHizo accion;
  final EntregaEntradas? renglon;

  const _Novedad(this.momento, this.accion, this.renglon);

  factory _Novedad.deRenglon(EntregaEntradas r) =>
      _Novedad(r.createdAt, r.accion!, r);

  /// Por momento. A la misma hora, la fila antes que el renglón (el renglón
  /// manda), y dos renglones por su id.
  static int enOrden(_Novedad a, _Novedad b) {
    final c = a.momento.compareTo(b.momento);
    if (c != 0) return c;
    final ra = a.renglon, rb = b.renglon;
    if (ra == null && rb == null) return 0;
    if (ra == null) return -1;
    if (rb == null) return 1;
    return ra.id.compareTo(rb.id);
  }
}

class _NovedadesDeLaFila {
  _NovedadesDeLaFila._();

  /// Lo que dice la fila: su entrega (`entregado_at`) y su anulación
  /// (`anulado_at`), en el orden que dice su estado, sin los reflejos de un
  /// renglón de la misma acción a la misma hora.
  ///
  /// **Con relojes que no coinciden** (las dos horas al revés de lo que dice
  /// el estado; revisión del 20-nov-2026), lo que el estado da como último va
  /// después de la otra, y cómo depende de quién lo hizo:
  /// - **lo hizo una 6.9.x** (no es reflejo de un renglón): ese equipo vio la
  ///   fila como estaba, así que va **un milisegundo después de la otra hora**.
  ///   Si no, una anulación de las 8 juntas desde una 6.9.x con el reloj
  ///   atrasado dejaba entregadas las generales de un renglón posterior, y una
  ///   entrega de las 8 desde una 6.9.x atrasada quedaba antes de la anulación
  ///   de una parte;
  /// - **es el reflejo de un renglón** (lo escribió esta versión): lo que pasó
  ///   lo dicen los renglones, con su orden. Una anulación anterior en el
  ///   estado pero no en la hora no cuenta (las partes se volvieron a entregar
  ///   después, por renglones), y una entrega de una 6.9.x va un milisegundo
  ///   antes de la anulación que la refleja (la parte que no se anuló sigue
  ///   entregada).
  static List<_Novedad> de(EntradasRetiro? f, List<EntregaEntradas> renglones) {
    if (f == null) return const [];
    bool esReflejo(DateTime momento, QueSeHizo accion) => renglones.any(
          (r) => r.accion == accion && r.createdAt.isAtSameMomentAs(momento),
        );
    const unMs = Duration(milliseconds: 1);
    final entregaOriginal = f.entregado ? (f.entregadoAt ?? f.updatedAt) : f.entregadoAt;
    final anulacionOriginal =
        f.entregado ? f.anuladoAt : (f.anuladoAt ?? f.updatedAt);
    final entregaEsReflejo =
        entregaOriginal != null && esReflejo(entregaOriginal, QueSeHizo.entrega);
    final anulacionEsReflejo = anulacionOriginal != null &&
        esReflejo(anulacionOriginal, QueSeHizo.anulacion);
    DateTime? entrega = entregaEsReflejo ? null : entregaOriginal;
    DateTime? anulacion = anulacionEsReflejo ? null : anulacionOriginal;
    if (f.entregado) {
      // El estado dice que lo último fue la entrega.
      if (anulacionOriginal != null && !anulacionOriginal.isBefore(entregaOriginal!)) {
        if (entregaEsReflejo) {
          anulacion = null;
        } else {
          entrega = anulacionOriginal.add(unMs);
        }
      }
    } else {
      // El estado dice que lo último fue la anulación.
      if (entregaOriginal != null && !entregaOriginal.isBefore(anulacionOriginal!)) {
        if (anulacionEsReflejo) {
          if (entrega != null) entrega = anulacionOriginal.subtract(unMs);
        } else {
          anulacion = entregaOriginal.add(unMs);
        }
      }
    }
    return [
      if (entrega != null) _Novedad(entrega, QueSeHizo.entrega, null),
      if (anulacion != null) _Novedad(anulacion, QueSeHizo.anulacion, null),
    ];
  }
}

/// La cuenta de la entrega de una fiesta, por parte: cuántas pulseras y cuántas
/// generales tienen que llegar, cuántas se entregaron, y cuántas familias ya
/// tienen todo.
class ResumenPorPartes {
  final int familias;
  final int familiasConTodo;
  final int familiasConPulseras;
  final int familiasConGenerales;

  /// Lo que le corresponde a todas las familias (lo que tiene que llegar).
  final int pulserasTotales;
  final int generalesTotales;

  /// Lo que se llevaron, sumando las partes entregadas.
  final int pulserasEntregadas;
  final int generalesEntregadas;

  /// Las familias a las que les falta alguna parte y no se les puede entregar
  /// por la plata: deben, o la ficha y los pagos no coinciden. Solo si se
  /// pasaron sus deudas.
  final int conDeuda;

  const ResumenPorPartes({
    required this.familias,
    required this.familiasConTodo,
    required this.familiasConPulseras,
    required this.familiasConGenerales,
    required this.pulserasTotales,
    required this.generalesTotales,
    required this.pulserasEntregadas,
    required this.generalesEntregadas,
    this.conDeuda = 0,
  });

  /// "Pulseras VIP: 24 (entregadas 3) · Generales: 40 (entregadas 0)": cuántas
  /// tienen que llegar de cada material y cuántas ya se dieron.
  String get texto => 'Pulseras VIP: $pulserasTotales (entregadas $pulserasEntregadas)'
      ' · Generales: $generalesTotales (entregadas $generalesEntregadas)';

  /// [alumnos]: los que se cuentan (sin las bajas: eso lo decide quien llama).
  /// [deudas]: lo que debe cada uno (`RetiroEntradas.deudaDe`), para [conDeuda].
  static ResumenPorPartes de({
    required Iterable<ContratoAlumno> alumnos,
    required Map<String, EntradasRetiro> retiros,
    required Iterable<EntregaEntradas> renglones,
    Map<String, DeudaAlumno> deudas = const {},
  }) {
    final porAlumno = EntregaEntradas.porAlumno(renglones);
    var familias = 0, conTodo = 0, conPulseras = 0, conGenerales = 0;
    var pulserasTotales = 0, generalesTotales = 0;
    var pulserasEntregadas = 0, generalesEntregadas = 0;
    var conDeuda = 0;
    for (final a in alumnos) {
      familias++;
      final e = EstadoDeLaEntrega.deAlumno(
        a,
        retiro: retiros[a.id],
        renglones: porAlumno[a.id] ?? const [],
      );
      final d = deudas[a.id];
      if (!e.todoEntregado && d != null && (!d.pagoTodo || d.noCoincide)) {
        conDeuda++;
      }
      pulserasTotales += max(0, e.pulseras.leToca);
      generalesTotales += max(0, e.generales.leToca);
      if (e.pulseras.entregada) {
        conPulseras++;
        pulserasEntregadas += e.pulseras.cantidad;
      }
      if (e.generales.entregada) {
        conGenerales++;
        generalesEntregadas += e.generales.cantidad;
      }
      if (e.todoEntregado) conTodo++;
    }
    return ResumenPorPartes(
      familias: familias,
      familiasConTodo: conTodo,
      familiasConPulseras: conPulseras,
      familiasConGenerales: conGenerales,
      pulserasTotales: pulserasTotales,
      generalesTotales: generalesTotales,
      pulserasEntregadas: pulserasEntregadas,
      generalesEntregadas: generalesEntregadas,
      conDeuda: conDeuda,
    );
  }
}

/// Un renglón de la planilla de entrega en papel, **de un material**: la de las
/// pulseras VIP o la de las generales (20-nov-2026: cada una llega en su tanda
/// y se entrega con su planilla). Lo que la app ya sabe va impreso; el nombre
/// de quien retira queda siempre en blanco, porque lo escribe esa persona (no
/// se firma).
class FilaPlanillaEntrega {
  final String alumnoId;
  final String egresado;
  final String mesa;
  final ParteEntrega material;

  /// Cuántas: las que se llevó si ya retiró; si no, las que le corresponden.
  final int cantidad;

  /// Las generales: los números si ya retiró ("1043 al 1047"), "-" si se
  /// llevó sin número, vacío si no retiró. En las pulseras, vacío.
  final String delAl;

  /// Las pulseras: los menores de 10 si ya retiró; vacío si no.
  final String menores;

  /// El parentesco si ya retiró; vacío si no.
  final String parentesco;

  /// Por qué no se puede entregar ("Debe: no entregar"), o `null`.
  final String? noEntregar;

  final bool entregado;

  /// No le toca nada de este material: las generales de quien tiene 8 o más con
  /// cena.
  final bool noLleva;

  const FilaPlanillaEntrega({
    required this.alumnoId,
    required this.egresado,
    required this.mesa,
    required this.material,
    required this.cantidad,
    required this.delAl,
    required this.menores,
    required this.parentesco,
    required this.noEntregar,
    required this.entregado,
    this.noLleva = false,
  });
}

/// En qué grupo del filtro de VENDER va cada alumno.
enum GrupoDeRetiro {
  /// Pagó todo su contrato (cuotas, extras y mora) y le falta alguna parte.
  puedeRetirar,

  /// Debe algo: pasa por la caja.
  debe,

  /// La ficha y los pagos no coinciden, no tiene mesa, sus mesas no coinciden
  /// con su cuenta o no entran: lo revisa el jefe.
  revisar,

  /// Tiene las dos partes.
  yaRetiro,
}

/// Las reglas de la entrega en dos partes. Todo es puro.
class EntregaPorPartes {
  EntregaPorPartes._();

  /// El grupo de [alumno] para el filtro de VENDER. **Sin otra cuenta de deuda
  /// al lado**: lo que debe lo dice `RetiroEntradas.deudaDe` y si puede retirar,
  /// `RetiroEntradas.bloqueo`. Quien ya tiene las dos partes va a "Ya retiró"
  /// aunque hoy deba algo (no queda nada que entregarle).
  static GrupoDeRetiro grupoDe(
    ContratoAlumno alumno, {
    required DeudaAlumno deuda,
    required EstadoDeLaEntrega estado,
  }) {
    if (estado.todoEntregado) return GrupoDeRetiro.yaRetiro;
    return switch (RetiroEntradas.bloqueo(alumno, deuda)) {
      BloqueoRetiro.ninguno => GrupoDeRetiro.puedeRetirar,
      BloqueoRetiro.debe => GrupoDeRetiro.debe,
      BloqueoRetiro.cuentaNoCoincide ||
      BloqueoRetiro.sinMesa ||
      BloqueoRetiro.mesasNoCoinciden ||
      BloqueoRetiro.noEntran =>
        GrupoDeRetiro.revisar,
    };
  }

  /// Los números de las generales ya entregados a las **otras** familias de la
  /// fiesta, por nombre: los de la fila de `entradas_retiro` (una entrega de una
  /// sola vez) y los de los renglones de generales. Solo los de una parte que
  /// sigue entregada: anular las generales libera sus números.
  ///
  /// **No mira lo vendido**: las generales de los alumnos son otro material que
  /// el talonario de las anticipadas (20-nov-2026).
  ///
  /// [alumnos]: todos los de la fiesta, **también los de baja**: sus números
  /// entregados siguen teniendo dueño. Dos con el mismo nombre juntan sus
  /// números (como `RetiroEntradas.tramosDeOtros`).
  static Map<String, List<TramoTalonario>> numerosDeOtros(
    Iterable<ContratoAlumno> alumnos,
    Map<String, EntradasRetiro> retiros,
    Iterable<EntregaEntradas> renglones, {
    required String salvo,
  }) {
    final porAlumno = EntregaEntradas.porAlumno(renglones);
    final otros = <String, List<TramoTalonario>>{};
    for (final a in alumnos) {
      if (a.id == salvo) continue;
      final generales = EstadoDeLaEntrega.deAlumno(
        a,
        retiro: retiros[a.id],
        renglones: porAlumno[a.id] ?? const [],
      ).generales;
      if (!generales.entregada || generales.tramos.isEmpty) continue;
      otros.putIfAbsent(a.nombreAlumno.trim(), () => []).addAll(generales.tramos);
    }
    return otros;
  }

  /// Qué está mal en los números de una parte, o `null` si están bien.
  ///
  /// - Las pulseras van sin número.
  /// - Las generales: **los números son opcionales** (puede que no vengan
  ///   numeradas). Si se escriben, son exactamente [cantidad], no se pisan y no
  ///   repiten los de [deOtros] (la misma regla de siempre:
  ///   `RetiroEntradas.errorTramos`).
  static String? errorDeLosNumeros({
    required ParteEntrega parte,
    required List<TramoTalonario> tramos,
    required int cantidad,
    Map<String, List<TramoTalonario>> deOtros = const {},
  }) {
    if (tramos.isEmpty) return null;
    if (parte == ParteEntrega.pulseras) {
      return 'Las pulseras van sin número: sacá los números.';
    }
    return RetiroEntradas.errorTramos(
      tramos: tramos,
      generales: cantidad,
      deOtros: deOtros,
    );
  }

  /// "las pulseras VIP con cena" o "las entradas generales".
  static String nombreDe(ParteEntrega p) => 'las ${p.nombre}';

  /// Por qué **no se entrega [parte] ahora**, porque la otra ya se entregó con
  /// otra cuenta y entre las dos se llevaría más sin cargo de lo que le
  /// corresponde; o null si se puede. Revisión del 20-nov-2026: con 1
  /// acompañante se le daban las 6 generales, se sumaba otro acompañante y
  /// después se le daban 3 pulseras: 9 sin cargo para una mesa de 8 (y al
  /// revés, sacando un acompañante después de las pulseras).
  ///
  /// Si la otra se llevó de menos, esta se entrega igual (no se pasa del
  /// total). **La misma regla en el servicio que guarda (`EntregarParte`) y en
  /// las dos pantallas** (GRATIS de VENDER y el diálogo de la entrega).
  static String? frenoPorLaOtraParte(EstadoDeLaEntrega estado, ParteEntrega parte) {
    final esta = estado.parte(parte);
    final otra = estado.parte(
      parte == ParteEntrega.pulseras ? ParteEntrega.generales : ParteEntrega.pulseras,
    );
    if (esta.entregada || !otra.entregada) return null;
    final sinCargo = esta.leToca + otra.leToca;
    if (esta.leToca + otra.cantidad <= sinCargo) return null;
    return 'Ya se le entregaron ${otra.parte.cuantas(otra.cantidad)} con otra '
        'cuenta (hoy le corresponden ${otra.leToca}): entre las dos se llevaría '
        '${esta.leToca + otra.cantidad} sin cargo, y le corresponden $sinCargo. '
        'Pedile al jefe que lo revise desde ENTRADAS de la fiesta.';
  }

  /// "El egresado · PÉREZ, ANA · PÉREZ, LUIS · 1 sin nombre": quiénes van con
  /// cena en [cuantas] pulseras de [a] (el egresado y sus acompañantes).
  /// **Separados por un punto, nunca por coma**: los nombres llevan coma
  /// ("APELLIDO, NOMBRE"), y con comas no se podía contar cuántas pulseras eran
  /// ni quién faltaba (revisión del 20-nov-2026). La usan VENDER y el diálogo de
  /// la entrega, así dicen lo mismo.
  static String quienesVanConCena(ContratoAlumno a, int cuantas) {
    final acompanantes = [
      for (final n in a.nombresAcompanantes)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    final otros = cuantas - 1;
    if (otros <= 0) return 'Solo el egresado';
    final sinNombre = otros - acompanantes.length;
    return [
      'El egresado',
      ...acompanantes.take(otros),
      if (sinNombre > 0) '$sinNombre sin nombre',
    ].join(' · ');
  }

  /// La fila de `entradas_retiro` de [retiro] no dice lo mismo que las partes
  /// ([estado]) y hay que ponerla al día (`EntregarParte.completarLaFila`, con
  /// internet y mirando la nube antes). Pasa de dos maneras:
  /// - **falta la fila**: la familia tiene las dos partes y la fila no dice
  ///   "entregado" (cada parte la dio un equipo distinto y uno estaba sin
  ///   internet);
  /// - **la fila quedó vieja**: dice "entregado" pero una parte está anulada
  ///   por un renglón ([filaConLaAnulacion]). Pasa si el jefe anuló una parte
  ///   mientras otro equipo escribía la fila completa, o sin internet, antes de
  ///   bajarla (revisión del 20-nov-2026).
  ///
  /// Lo que lee la fila sola (el PLANO, una PC con la 6.9.x, la planilla vieja)
  /// tiene que ver lo mismo que dicen los renglones.
  static bool filaParaPonerAlDia({
    EntradasRetiro? retiro,
    required EstadoDeLaEntrega estado,
  }) {
    if (retiro?.entregado ?? false) {
      return filaConLaAnulacion(retiro: retiro!, estado: estado) != null;
    }
    return estado.todoEntregado &&
        ParteEntrega.values.any(
          (p) => estado.parte(p).entregada && !estado.parte(p).deLaFila,
        );
  }

  /// La fila de `entradas_retiro` anulada, cuando dice "entregado" y una parte
  /// está anulada por un renglón (y no se volvió a entregar). Es **el reflejo**
  /// de esa anulación: con su misma hora, quién y motivo ("Solo las pulseras VIP
  /// con cena: …" si queda la otra parte), como la escribe `anularParte`. Así una
  /// PC con la 6.9.x, el plano y la planilla vieja dejan de ver "Retiró", y esta
  /// versión sigue leyendo cada parte por sus renglones: la anulación de la fila
  /// es la del renglón, no otra, y no tapa la otra parte.
  ///
  /// Null si la fila no dice "entregado" o si no falta ninguna parte anulada
  /// (una parte que falta porque cambió la cuenta no es una anulación: esa fila
  /// no se toca).
  ///
  /// Antes de escribirla van las copias de lo que dependía de la fila
  /// ([copiasDeLaFila]): una parte entregada de una sola vez (la 6.9.x) no se
  /// pierde.
  ///
  /// [ahora]: cuándo se escribe (su `updated_at`; la hora de la anulación es la
  /// del renglón). Sin él, la de la anulación.
  static EntradasRetiro? filaConLaAnulacion({
    required EntradasRetiro retiro,
    required EstadoDeLaEntrega estado,
    DateTime? ahora,
  }) {
    if (!retiro.entregado) return null;
    final anuladas = [
      for (final p in ParteEntrega.values)
        if (estado.parte(p).falta &&
            estado.parte(p).anulada &&
            !estado.parte(p).deLaFila)
          estado.parte(p),
    ]..sort((a, b) => a.anuladaAt!.compareTo(b.anuladaAt!));
    if (anuladas.isEmpty) return null;
    final ultima = anuladas.last;
    final motivo = (ultima.motivoAnulacion ?? '').trim();
    final queSeAnulo = anuladas.length == ParteEntrega.values.length
        ? motivo
        : (motivo.isEmpty
            ? 'Solo ${nombreDe(ultima.parte)}'
            : 'Solo ${nombreDe(ultima.parte)}: $motivo');
    final f = RetiroEntradas.anular(
      retiro,
      motivo: queSeAnulo,
      quien: ultima.anuladaPor ?? '',
      ahora: ultima.anuladaAt!,
    );
    if (ahora == null || !ahora.isAfter(f.updatedAt)) return f;
    return EntradasRetiro(
      id: f.id,
      contratoAlumnoId: f.contratoAlumnoId,
      estado: f.estado,
      vip: f.vip,
      generales: f.generales,
      tramos: f.tramos,
      menores10: f.menores10,
      parentesco: f.parentesco,
      retiroNombre: f.retiroNombre,
      otraPersonaMotivo: f.otraPersonaMotivo,
      autorizacionFirmada: f.autorizacionFirmada,
      escribioEnPlanilla: f.escribioEnPlanilla,
      entregadoPor: f.entregadoPor,
      entregadoAt: f.entregadoAt,
      anuladoPor: f.anuladoPor,
      anuladoAt: f.anuladoAt,
      anuladoMotivo: f.anuladoMotivo,
      createdAt: f.createdAt,
      updatedAt: ahora,
    );
  }

  /// El renglón de [a] en la planilla de [material]: lo que le corresponde (o
  /// lo que se llevó, si ya retiró esa parte), y por qué no se le puede
  /// entregar si no se puede (`RetiroEntradas.textoBloqueo`).
  static FilaPlanillaEntrega filaPlanilla(
    ContratoAlumno a, {
    required ParteEntrega material,
    EntradasRetiro? retiro,
    List<EntregaEntradas> renglones = const [],
    required DeudaAlumno deuda,
  }) {
    final e = EstadoDeLaEntrega.deAlumno(a, retiro: retiro, renglones: renglones)
        .parte(material);
    final noLleva = !e.entregada && e.leToca <= 0;
    final generales = material == ParteEntrega.generales;
    return FilaPlanillaEntrega(
      alumnoId: a.id,
      egresado: a.nombreAlumno.trim(),
      mesa: SalonMesas.textoMesasPuerta(a) ?? '-',
      material: material,
      cantidad: e.entregada ? e.cantidad : max(0, e.leToca),
      delAl: !generales || !e.entregada
          ? ''
          : (e.tramos.isEmpty ? '-' : TramoTalonario.legible(e.tramos)),
      menores: !generales && e.entregada ? '${e.menores10}' : '',
      parentesco: e.entregada ? e.parentesco?.etiqueta ?? '' : '',
      noEntregar: e.entregada || noLleva
          ? null
          : RetiroEntradas.textoBloqueo(RetiroEntradas.bloqueo(a, deuda)),
      entregado: e.entregada,
      noLleva: noLleva,
    );
  }

  /// La hora que lleva un renglón nuevo de [parte]: la de [ahora] o, si este
  /// equipo ya conoce una novedad de esa parte más nueva, **un milisegundo
  /// después de esa novedad**. Las novedades son los renglones de esa parte y
  /// lo que dice la fila de `entradas_retiro` (que vale para las dos).
  ///
  /// **Cada equipo tiene su reloj** (revisión del 20-nov-2026): una tablet con
  /// la hora atrasada que vuelve a entregar algo que el jefe anuló desde la PC
  /// anotaba su entrega *antes* que la anulación, y la entrega no contaba. Así
  /// lo que se anota acá queda siempre después de lo que este equipo ya vio.
  static DateTime horaDelRenglon({
    required ParteEntrega parte,
    EntradasRetiro? retiro,
    required Iterable<EntregaEntradas> renglones,
    required DateTime ahora,
  }) {
    var hora = ahora.toUtc();
    void despuesDe(DateTime? momento) {
      if (momento == null) return;
      final siguiente = momento.toUtc().add(const Duration(milliseconds: 1));
      if (siguiente.isAfter(hora)) hora = siguiente;
    }

    for (final r in renglones) {
      if (r.parte == parte) despuesDe(r.createdAt);
    }
    if (retiro != null) {
      despuesDe(retiro.entregadoAt);
      despuesDe(retiro.anuladoAt);
      despuesDe(retiro.updatedAt);
    }
    return hora;
  }

  /// "MADRE PÉREZ, ANA, el 20/11/2026 15:30 hs (lo registró Carla)", con lo que
  /// se sabe. [fecha] da el formato de la fecha (`ArTime.formatFechaHora`).
  static String quienYCuando(
    EstadoDeUnaParte p, {
    required String Function(DateTime) fecha,
  }) {
    final quien = [
      if (p.parentesco != null) p.parentesco!.etiqueta,
      if ((p.retiroNombre ?? '').isNotEmpty) p.retiroNombre!,
    ].join(' ');
    final cuando = p.entregadaAt == null ? '' : 'el ${fecha(p.entregadaAt!)}';
    final por = (p.anotadoPor ?? '').isEmpty ? '' : ' (lo registró ${p.anotadoPor})';
    final partes = [quien, cuando].where((s) => s.isNotEmpty).join(', ');
    return '$partes$por'.trim();
  }

  /// Los renglones que copian lo que dice la fila de `entradas_retiro` para cada
  /// parte cuya última novedad sale de ella ([EstadoDeUnaParte.deLaFila]).
  ///
  /// Van **antes de reescribir esa fila**: la fila guarda una sola entrega y una
  /// sola anulación, y al reescribirla se perdería la de una entrega de una sola
  /// vez (la 6.9.x) de la que todavía depende una parte. Con la hora de la fila
  /// y un id que sale de esa hora: si dos equipos copian lo mismo, es el mismo
  /// renglón.
  static List<EntregaEntradas> copiasDeLaFila({
    required ContratoAlumno alumno,
    required EntradasRetiro? retiro,
    required EstadoDeLaEntrega estado,
    required String? deviceId,
    required DateTime ahora,
  }) {
    final f = retiro;
    if (f == null) return const [];
    final out = <EntregaEntradas>[];
    for (final p in ParteEntrega.values) {
      final e = estado.parte(p);
      if (!e.deLaFila) continue;
      final momento = (e.entregada ? e.entregadaAt : e.anuladaAt)!;
      final accion = e.entregada ? QueSeHizo.entrega : QueSeHizo.anulacion;
      out.add(
        EntregaEntradas(
          id: UuidUtils.entradasEntregaCopiaId(
            alumno.id,
            p.clave,
            accion.clave,
            momento.toUtc().toIso8601String(),
          ),
          contratoAlumnoId: alumno.id,
          eventoId: alumno.eventoId,
          parteClave: p.clave,
          accionClave: accion.clave,
          cantidad: e.entregada
              ? e.cantidad
              : (p == ParteEntrega.pulseras ? f.vip : f.generales),
          tramos: p == ParteEntrega.generales ? f.tramos : const [],
          menores10: e.entregada ? e.menores10 : 0,
          parentesco: e.entregada ? e.parentesco : null,
          retiroNombre: e.entregada ? e.retiroNombre : null,
          otraPersonaMotivo: e.entregada ? e.otraPersonaMotivo : null,
          autorizacionFirmada: e.entregada && e.autorizacionFirmada,
          escribioEnPlanilla: e.entregada && e.escribioEnPlanilla,
          motivo: e.entregada
              ? EntregaEntradas.kCopiaDeLaFila
              : (e.motivoAnulacion ?? EntregaEntradas.kCopiaDeLaFila),
          hechoPor: e.entregada ? e.anotadoPor : e.anuladaPor,
          deviceId: deviceId,
          createdAt: momento,
          updatedAt: ahora,
        ),
      );
    }
    return out;
  }

  /// La fila completa de `entradas_retiro` cuando la familia ya tiene las dos
  /// partes, para que una PC con la 6.9.x, el plano y la planilla vieja la vean
  /// "Retiró". Se arma con `RetiroEntradas.nuevaEntrega` (el id fijo, el nombre
  /// como se guarda, y conserva la anulación de antes) y lleva:
  /// - **lo que se llevó de verdad** en cada parte, no la cuenta de hoy: si la
  ///   cuenta cambió entre una parte y la otra, la 6.9.x lo ve como "cambió la
  ///   cuenta", que es la verdad;
  /// - quién retiró la última parte;
  /// - **la hora de la última entrega** como `entregado_at`: así es el reflejo
  ///   de ese renglón y nunca le gana a una anulación que todavía no bajó.
  ///
  /// Null si a la familia le falta alguna parte, o si no hay ninguna entrega de
  /// un renglón (la fila ya es la de una entrega de una sola vez).
  static EntradasRetiro? filaCompleta({
    required ContratoAlumno alumno,
    required EntradasRetiro? anterior,
    required EstadoDeLaEntrega estado,
    required DateTime ahora,
  }) {
    if (!estado.todoEntregado) return null;
    final entregadas = [
      for (final p in ParteEntrega.values)
        if (estado.parte(p).entregada && !estado.parte(p).deLaFila)
          estado.parte(p),
    ];
    if (entregadas.isEmpty) return null;
    entregadas.sort((a, b) => a.entregadaAt!.compareTo(b.entregadaAt!));
    final ultima = entregadas.last;
    final base = RetiroEntradas.nuevaEntrega(
      alumno: alumno,
      entradas: RetiroEntradas.entradasDe(alumno),
      tramos: estado.generales.entregada ? estado.generales.tramos : const [],
      menores10: max(estado.pulseras.menores10, estado.generales.menores10),
      parentesco: ultima.parentesco ?? ParentescoRetiro.egresado,
      nombre: ultima.retiroNombre ?? '',
      motivo: ultima.otraPersonaMotivo ?? '',
      autorizacionFirmada: ultima.autorizacionFirmada,
      quien: ultima.anotadoPor ?? '',
      ahora: ultima.entregadaAt!,
      anterior: anterior,
    );
    return EntradasRetiro(
      id: base.id,
      contratoAlumnoId: base.contratoAlumnoId,
      estado: base.estado,
      vip: estado.pulseras.entregada ? estado.pulseras.cantidad : 0,
      generales: estado.generales.entregada ? estado.generales.cantidad : 0,
      tramos: base.tramos,
      menores10: base.menores10,
      parentesco: base.parentesco,
      retiroNombre: base.retiroNombre,
      otraPersonaMotivo: base.otraPersonaMotivo,
      autorizacionFirmada: base.autorizacionFirmada,
      escribioEnPlanilla: entregadas.every((e) => e.escribioEnPlanilla),
      entregadoPor: base.entregadoPor,
      entregadoAt: base.entregadoAt,
      anuladoPor: base.anuladoPor,
      anuladoAt: base.anuladoAt,
      anuladoMotivo: base.anuladoMotivo,
      createdAt: anterior?.createdAt ?? base.createdAt,
      updatedAt: ahora,
    );
  }
}
