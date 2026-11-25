import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/nota_operativa_contrato.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sillas_reparto.dart';
import '../../plano/services/divisiones.dart';
import 'lugares_al_sorteo.dart';
import 'mesas_extra_utils.dart';
import 'pago_para_sorteo.dart';
import 'reparto_de_sillas.dart';
import 'retiro_entradas.dart';
import 'salon_mesas.dart';
import 'sorteo_mesas_motor.dart';

/// Qué versión de la planilla del sorteo se imprime.
enum VersionPlanillaSorteo {
  /// Para la oficina: con teléfonos, observaciones y a quién llamar.
  interna,

  /// Para entregar por división: sin teléfonos ni observaciones, que son
  /// datos de otras familias.
  paraRepartir,
}

/// En qué orden van los egresados (6.9.4).
enum OrdenPlanillaSorteo {
  /// Una hoja por división, por apellido: como siempre.
  alfabetico,

  /// Todo el salón en una lista, de la mesa 1 a la última: para recorrer las
  /// mesas una por una (pedido del usuario, 25-nov-2026).
  porMesa,
}

/// Cómo figura en la planilla el reparto de las sillas extra.
enum RepartoSillas {
  /// No tiene sillas extra: no hay nada que repartir.
  noAplica,

  /// Hay que llamar a la familia para que elija, o revisar su cuenta (tiene
  /// más sillas de las que entran). Mientras tanto la planilla muestra el
  /// reparto de siempre: de a 2 por mesa, la principal primero.
  pendiente,

  /// La familia eligió, o había una sola forma de repartirlas.
  confirmado,
}

/// Un renglón de la planilla del sorteo: un egresado con todo lo que la noche
/// necesita saber de su familia.
///
/// Se arma sin tocar el PDF ([PlanillaSorteo.fila]) para poder probar cada
/// caso con tests; el dibujo solo lo pone en la hoja.
class FilaPlanillaSorteo {
  final String alumnoId;

  /// El nombre tal como está cargado (en mayúsculas).
  final String egresado;

  /// Un acompañante por renglón. Vacío: no tiene ninguno cargado.
  final List<String> acompanantes;

  /// "12", "sin mesa (sin pagar)", "sin asignar".
  final String mesaPrincipal;

  /// Cómo se ocupa la mesa principal: "3 con cena · 5 generales". `null` si
  /// todavía no tiene mesa.
  final String? ocupacionPrincipal;

  /// Las entradas generales de la mesa principal: las que completan sus 8
  /// lugares sin cargo, después de los que tienen cena (`EntradasDeAlumno`,
  /// la misma cuenta de la entrega y la venta). **Las sillas extra no cuentan
  /// acá**: sus entradas se compran aparte ([entradasSillas]). Negativo si la
  /// familia no entra en todos sus lugares. `null` si todavía no tiene mesa.
  final int? generalesPrincipal;

  /// Las generales sin cargo de la familia, tenga o no mesa todavía: para los
  /// totales.
  final int entradasGenerales;

  /// Las entradas de sus mesas adicionales: se compran aparte, con el
  /// descuento de PRECIOS las de lo que tenía al sorteo y sin descuento las de
  /// lo que agregó después.
  final LugaresAparte entradasAdicional;

  /// Lo mismo, de sus sillas extra.
  final LugaresAparte entradasSillas;

  /// Las mesas extra: "13", "13-14", "13 · 40 (separada)", "138 (pasto)",
  /// "1 sin asignar", o "-".
  final String adicional;

  /// La mesa principal es del pasto: hay que avisarle a la familia.
  final bool principalEnPasto;

  /// Cuántas de sus mesas son del pasto (la principal o las adicionales).
  final int mesasEnPasto;

  /// "(!) le falta 1 mesa", si los números no coinciden con la cuenta.
  final String? alertaMesas;

  /// Sillas extra por mesa: "2P · 1A" (principal y adicional), "3" si todavía
  /// no tiene mesa, o "-". Con "(sin pagar)" si no tienen nada pagado.
  final String sillas;

  final RepartoSillas reparto;
  final String telefono;
  final String musica;

  /// La nota operativa sin resolver, o vacío. Solo en la versión interna.
  final String observaciones;

  /// No tiene mesa porque no pagó nada de la cuota base: la fila va en rojo.
  final bool sinMesa;

  /// Egresado y acompañantes: todos tienen cena.
  final int conCena;

  /// El número de la mesa principal, la del contrato. Null sin mesa (o con un
  /// número que no se entiende).
  final int? numeroPrincipal;

  /// Los números de sus mesas adicionales, en el orden del contrato.
  final List<int> numerosAdicionales;

  const FilaPlanillaSorteo({
    required this.alumnoId,
    required this.egresado,
    required this.acompanantes,
    required this.mesaPrincipal,
    required this.ocupacionPrincipal,
    required this.generalesPrincipal,
    this.entradasGenerales = 0,
    this.entradasAdicional =
        const LugaresAparte(conDescuento: 0, sinDescuento: 0),
    this.entradasSillas = const LugaresAparte(conDescuento: 0, sinDescuento: 0),
    required this.adicional,
    this.principalEnPasto = false,
    this.mesasEnPasto = 0,
    required this.alertaMesas,
    required this.sillas,
    required this.reparto,
    required this.telefono,
    required this.musica,
    required this.observaciones,
    required this.sinMesa,
    required this.conCena,
    this.numeroPrincipal,
    this.numerosAdicionales = const [],
  });

  /// Todas sus mesas en un renglón: "12 + 13-14".
  String get todasLasMesas =>
      adicional == '-' ? mesaPrincipal : '$mesaPrincipal + $adicional';
}

/// Un renglón de la planilla **por número de mesa** (6.9.4).
///
/// La familia va entera en su mesa principal ([esAdicional] en false), y cada
/// mesa adicional tiene su renglón corto en su número, así la columna de la
/// mesa va de la 1 a la última sin saltear ninguna.
class RenglonPorMesa {
  /// El número de la mesa. Null: la familia no tiene mesa (va al final).
  final int? mesa;

  final FilaPlanillaSorteo fila;

  /// La división del egresado, como está escrita.
  final String division;

  /// Es una mesa adicional de [fila]: va el renglón corto.
  final bool esAdicional;

  const RenglonPorMesa({
    required this.mesa,
    required this.fila,
    required this.division,
    this.esAdicional = false,
  });
}

/// Una división en la hoja de resumen.
class ResumenDivision {
  final String division;
  final int egresados;
  final int mesas;

  /// Los números de la división de a tramos: "1-24", "1-10 · 15-20", o "-".
  final String numeros;

  /// El bloque de mesas que le tocó en un sorteo por división: "1-24". Null
  /// si la fiesta no se sorteó por bloques o esta división no tiene el suyo.
  final String? bloque;

  final int sillasExtra;
  final int conCena;

  /// Las generales sin cargo: las que completan la mesa principal de cada uno.
  final int generales;

  /// Las de las mesas adicionales y las sillas extra, que se compran aparte:
  /// con el descuento de PRECIOS, y sin descuento las de lo agregado después
  /// del sorteo.
  final int conDescuento;
  final int sinDescuento;
  final int repartosPendientes;
  final int sinMesa;

  const ResumenDivision({
    required this.division,
    required this.egresados,
    required this.mesas,
    required this.numeros,
    this.bloque,
    required this.sillasExtra,
    required this.conCena,
    this.generales = 0,
    this.conDescuento = 0,
    this.sinDescuento = 0,
    required this.repartosPendientes,
    required this.sinMesa,
  });
}

/// Los totales de la noche, para la primera hoja.
class ResumenPlanillaSorteo {
  final int egresados;
  final int mesas;
  final int mesasAsignadas;
  final int sillasExtra;
  final int sillasSinPagar;
  final int conCena;

  /// Las generales sin cargo de toda la fiesta, y las que se compran aparte
  /// (con el descuento de PRECIOS y sin descuento).
  final int generales;
  final int conDescuento;
  final int sinDescuento;
  final int sinMesa;
  final int repartosPendientes;
  final List<ResumenDivision> divisiones;

  /// A quién llamar para que elija cómo reparte sus sillas extra.
  final List<({FilaPlanillaSorteo fila, String division})> aLlamar;

  /// El salón tiene mesas en el pasto (se usen o no).
  final bool hayPasto;

  /// Cuántas mesas del pasto tienen familia.
  final int mesasEnPasto;

  /// A quién avisarle que le tocó una mesa en el pasto.
  final List<({FilaPlanillaSorteo fila, String division})> aAvisarPasto;

  /// Alguna división tiene su bloque de mesas.
  bool get hayBloques => divisiones.any((d) => d.bloque != null);

  const ResumenPlanillaSorteo({
    required this.egresados,
    required this.mesas,
    required this.mesasAsignadas,
    required this.sillasExtra,
    required this.sillasSinPagar,
    required this.conCena,
    this.generales = 0,
    this.conDescuento = 0,
    this.sinDescuento = 0,
    required this.sinMesa,
    required this.repartosPendientes,
    required this.divisiones,
    required this.aLlamar,
    this.hayPasto = false,
    this.mesasEnPasto = 0,
    this.aAvisarPasto = const [],
  });
}

/// Arma la planilla del sorteo a partir de las cuentas, lo pagado, las notas y
/// el reparto de sillas que eligió cada familia.
///
/// Todo sale de lo que ya está guardado ([SalonMesas], `numero_mesa`, los
/// pagos, las notas operativas y `sillas_reparto`): la planilla no guarda nada
/// ni inventa datos.
class PlanillaSorteo {
  PlanillaSorteo._();

  /// Nombre de la hoja de los que no tienen división cargada.
  static const sinDivision = 'Sin curso asignado';

  /// La división como está cargada, o [sinDivision].
  static String division(ContratoAlumno a) {
    final d = a.cursoDivision?.trim() ?? '';
    return d.isEmpty ? sinDivision : d;
  }

  /// Los que van en la planilla: todos menos los de baja.
  static List<ContratoAlumno> activos(Iterable<ContratoAlumno> alumnos) =>
      alumnos.where((a) => !a.esBajaTemporal).toList();

  static String _tramo(List<int> t) =>
      t.length == 1 ? '${t.first}' : '${t.first}-${t.last}';

  /// Un tramo de mesas extra, diciendo cuáles son del pasto y si está
  /// separado de la principal: "13-14", "137-138 (pasto)", "40 (separada)",
  /// "140 (separada, pasto)". Si solo una parte es del pasto, se parte:
  /// "129-130 · 131 (pasto)".
  static String _tramoExtra(
    List<int> tramo,
    Set<int> pasto, {
    bool separada = false,
  }) {
    final partes = <String>[];
    var desde = 0;
    for (var i = 1; i <= tramo.length; i++) {
      if (i < tramo.length &&
          pasto.contains(tramo[i]) == pasto.contains(tramo[desde])) {
        continue;
      }
      final notas = [
        if (separada) 'separada',
        if (pasto.contains(tramo[desde])) 'pasto',
      ];
      partes.add(
        '${_tramo(tramo.sublist(desde, i))}'
        '${notas.isEmpty ? '' : ' (${notas.join(', ')})'}',
      );
      desde = i;
    }
    return partes.join(' · ');
  }

  /// Los números de a tramos, en orden: "1-3 · 7".
  static String numerosEnTramos(Iterable<int> numeros) {
    final lista = numeros.toSet().toList()..sort();
    if (lista.isEmpty) return '-';
    return SorteoMesasMotor.tramosDe(lista).map(_tramo).join(' · ');
  }

  /// El renglón de un egresado.
  ///
  /// La **mesa principal** es la primera de su tramo más largo; el resto de ese
  /// tramo y los tramos separados son la **adicional** (sus mesas extra). Las
  /// sillas extra se reparten como eligió la familia ([RepartoDeSillas]); si
  /// todavía no eligió, como siempre: de a 2 por mesa, la principal primero.
  ///
  /// [pasto] son las mesas del pasto del plano de la fiesta: a quien le tocó
  /// una hay que avisarle.
  static FilaPlanillaSorteo fila(
    ContratoAlumno a, {
    PagoAlumno? pago,
    NotaOperativaContrato? nota,
    SillasReparto? repartoElegido,
    Set<int> pasto = const {},
    DistanciaLejos? lejos,

    /// Lo que cada familia tenía al sorteo: el descuento es solo para eso.
    FotoDeLosLugares? foto,
  }) {
    final tramos = SalonMesas.tramos(a);
    final crudo = a.numeroMesa?.trim() ?? '';
    // La principal es la del contrato, la primera anotada (6.9.4): la misma
    // que dicen la puerta y el plano. Hasta la 6.9.3 era la primera del tramo
    // más largo, y con "12, 67, 68" la planilla decía 67.
    final principal = tramos.isEmpty ? null : SalonMesas.principal(a);
    final tramoPrincipal = principal == null
        ? const <int>[]
        : tramos.firstWhere((t) => t.contains(principal));

    // ── Mesa principal ────────────────────────────────────────────────────
    final sinPagarBase = pago != null && !pago.pagoBase;
    final String mesaPrincipal;
    var sinMesa = false;
    if (principal != null) {
      mesaPrincipal = '$principal';
    } else if (crudo.isNotEmpty) {
      // Un número que no se entiende: se muestra tal cual, como la grilla.
      mesaPrincipal = crudo;
    } else if (sinPagarBase) {
      // El papel no dice "sin pagar" (pedido del usuario, 12-nov-2026): el rojo
      // de SIN MESA ya lo dice.
      mesaPrincipal = 'sin mesa';
      sinMesa = true;
    } else {
      mesaPrincipal = 'sin asignar';
    }

    // ── Adicional: sus mesas extra ────────────────────────────────────────
    // Las del bloque de la principal, sin ella. Casi siempre la principal es la
    // primera de su bloque ("12-14": la 13 y la 14); con la 107 y la 106 que
    // le dio el jefe después, la adicional es la 106.
    final extrasDelBloque = [
      for (final n in tramoPrincipal)
        if (n != principal) n,
    ];
    final partes = <String>[
      for (final t in SorteoMesasMotor.tramosDe(extrasDelBloque))
        _tramoExtra(t, pasto),
      for (final t in tramos)
        if (!identical(t, tramoPrincipal)) _tramoExtra(t, pasto, separada: true),
    ];
    final extras = SalonMesas.mesasExtra(a);
    final String adicional;
    if (partes.isNotEmpty) {
      // Lo que se pidió, solo si de verdad quedó separada.
      adicional = lejos != null && tramos.length > 1
          ? '${partes.join(' · ')} · lejos · ${lejos.texto}'
          : partes.join(' · ');
    } else if (extras > 0 && principal == null) {
      adicional = extras == 1 ? '1 mesa extra' : '$extras mesas extra';
    } else {
      adicional = '-';
    }
    final alerta = SalonMesas.avisoMesas(a);

    // ── Con cena y generales en la principal ──────────────────────────────
    final ocupacion = SalonMesas.ocupacion(a);
    final conCena = ocupacion.personas;
    final vigente = RepartoDeSillas.vigente(a, repartoElegido);
    final estadoReparto = RepartoDeSillas.estado(a, repartoElegido);
    final reparto = SalonMesas.repartoSillas(
      a,
      sillasPrincipal: vigente?.principal,
    );
    final sillasPrincipal = principal == null
        ? 0
        : reparto
            .where((e) => e.$1 == principal)
            .fold<int>(0, (s, e) => s + e.$2);
    // La misma cuenta de la entrega y la venta (regla del 4-nov): en la mesa
    // principal van los que tienen cena y las generales que completan sus 8
    // lugares. Hasta el 17-nov acá se sumaban las sillas extra como generales
    // ("1 con cena · 9 generales") y las entradas de la adicional no figuraban.
    final entradas = RetiroEntradas.entradasDe(a, foto: foto);
    String? ocupacionPrincipal;
    int? generales;
    if (principal != null) {
      // No entran contando todos sus lugares, no solo la principal: con dos
      // mesas, 10 con cena entran.
      generales = entradas.entran
          ? entradas.generales
          : entradas.lugares - conCena;
      ocupacionPrincipal = generales >= 0
          ? '$conCena con cena · $generales '
              '${generales == 1 ? 'general' : 'generales'}'
          : '$conCena con cena · (!) faltan ${-generales} lugares';
    }

    // ── Sillas extra: "2P · 1A" ───────────────────────────────────────────
    final sillasExtra = SalonMesas.sillasExtra(a);
    String sillas;
    if (sillasExtra == 0) {
      sillas = '-';
    } else if (reparto.isEmpty) {
      // Todavía sin mesa: si la familia ya eligió, se dice cómo ("2P · 1A").
      sillas = estadoReparto == EstadoRepartoSillas.elegido && vigente != null
          ? vigente.texto
          : '$sillasExtra';
    } else {
      final enAdicional = reparto
          .where((e) => e.$1 != principal)
          .fold<int>(0, (s, e) => s + e.$2);
      sillas = [
        if (sillasPrincipal > 0) '${sillasPrincipal}P',
        if (enAdicional > 0) '${enAdicional}A',
      ].join(' · ');
      final sinLugar = sillasExtra - sillasPrincipal - enAdicional;
      if (sinLugar > 0) sillas = '$sillas · (!) $sinLugar sin lugar';
    }

    // ── Acompañantes, uno por renglón ─────────────────────────────────────
    final nombres = [
      for (final n in a.nombresAcompanantes)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    final sinNombre = max(0, a.cantidadAcompanantes - nombres.length);
    final acompanantes = [
      ...nombres,
      if (sinNombre == 1) '1 acompañante sin nombre',
      if (sinNombre > 1) '$sinNombre acompañantes sin nombre',
    ];

    // ── Observaciones: la nota operativa sin resolver ─────────────────────
    final pendiente =
        nota != null && nota.tieneTexto && !nota.resuelto ? nota.texto.trim() : '';

    String oGuion(String? s) => s?.trim().isNotEmpty == true ? s!.trim() : '-';

    return FilaPlanillaSorteo(
      alumnoId: a.id,
      egresado: a.nombreAlumno.trim(),
      acompanantes: acompanantes,
      mesaPrincipal: mesaPrincipal,
      ocupacionPrincipal: ocupacionPrincipal,
      generalesPrincipal: generales,
      entradasGenerales: entradas.generales,
      entradasAdicional: entradas.deMesas,
      entradasSillas: entradas.deSillas,
      adicional: adicional,
      principalEnPasto: principal != null && pasto.contains(principal),
      mesasEnPasto: tramos.expand((t) => t).where(pasto.contains).length,
      alertaMesas: alerta == null ? null : '(!) $alerta',
      sillas: sillas,
      reparto: switch (estadoReparto) {
        EstadoRepartoSillas.noAplica => RepartoSillas.noAplica,
        EstadoRepartoSillas.unicaOpcion ||
        EstadoRepartoSillas.elegido =>
          RepartoSillas.confirmado,
        EstadoRepartoSillas.aConfirmar ||
        EstadoRepartoSillas.revisar =>
          RepartoSillas.pendiente,
      },
      telefono: oGuion(a.telefono),
      musica: oGuion(a.musicaElegida),
      observaciones: pendiente,
      sinMesa: sinMesa,
      conCena: conCena,
      numeroPrincipal: principal,
      numerosAdicionales: [
        for (final n in SalonMesas.enOrdenDelContrato(a))
          if (n != principal) n,
      ],
    );
  }

  /// Una hoja por división, en orden alfabético, con sus egresados también
  /// en orden alfabético. "Sin curso asignado" va al final.
  static Map<String, List<FilaPlanillaSorteo>> porDivision(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
    Map<String, SillasReparto> repartos = const {},
    Set<int> pasto = const {},
    Map<String, DistanciaLejos> lejos = const {},
    FotoDeLosLugares? foto,
  }) {
    final grupos = <String, List<ContratoAlumno>>{};
    for (final a in activos(alumnos)) {
      grupos.putIfAbsent(division(a), () => []).add(a);
    }
    final claves = grupos.keys.toList()
      ..sort((x, y) {
        if (x == sinDivision) return 1;
        if (y == sinDivision) return -1;
        return x.compareTo(y);
      });
    return {
      for (final d in claves)
        d: (grupos[d]!..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno)))
            .map(
              (a) => fila(
                a,
                pago: pagos?[a.id],
                nota: notas[a.id],
                repartoElegido: repartos[a.id],
                pasto: pasto,
                lejos: lejos[a.id],
                foto: foto,
              ),
            )
            .toList(),
    };
  }

  /// Todo el salón en un solo orden, **de la mesa 1 a la última** (6.9.4): un
  /// renglón por familia en su mesa principal y uno corto por cada mesa
  /// adicional, en su número. Los que no tienen mesa van al final, por
  /// apellido. Mismos egresados que [porDivision] (sin los de baja), con la
  /// misma cuenta de cada fila ([fila]).
  static List<RenglonPorMesa> porMesa(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
    Map<String, SillasReparto> repartos = const {},
    Set<int> pasto = const {},
    Map<String, DistanciaLejos> lejos = const {},
    FotoDeLosLugares? foto,
  }) {
    final renglones = <RenglonPorMesa>[];
    for (final a in activos(alumnos)) {
      final f = fila(
        a,
        pago: pagos?[a.id],
        nota: notas[a.id],
        repartoElegido: repartos[a.id],
        pasto: pasto,
        lejos: lejos[a.id],
        foto: foto,
      );
      final d = division(a);
      renglones.add(RenglonPorMesa(mesa: f.numeroPrincipal, fila: f, division: d));
      for (final n in f.numerosAdicionales) {
        renglones.add(
          RenglonPorMesa(mesa: n, fila: f, division: d, esAdicional: true),
        );
      }
    }
    renglones.sort((x, y) {
      final mx = x.mesa, my = y.mesa;
      if (mx != my) {
        if (mx == null) return 1;
        if (my == null) return -1;
        return mx.compareTo(my);
      }
      if (x.esAdicional != y.esAdicional) return x.esAdicional ? 1 : -1;
      final c = x.fila.egresado.compareTo(y.fila.egresado);
      return c != 0 ? c : x.fila.alumnoId.compareTo(y.fila.alumnoId);
    });
    return renglones;
  }

  /// Los totales de la noche y el detalle por división.
  ///
  /// [pasto] y [bloques] salen del plano de la fiesta, si tiene: las mesas del
  /// pasto y el bloque que le tocó a cada división en el sorteo.
  static ResumenPlanillaSorteo resumen(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
    Map<String, SillasReparto> repartos = const {},
    Set<int> pasto = const {},
    List<BloqueDivision> bloques = const [],
    FotoDeLosLugares? foto,
  }) {
    final lista = activos(alumnos);
    final porDiv = porDivision(
      lista,
      pagos: pagos,
      notas: notas,
      repartos: repartos,
      pasto: pasto,
      foto: foto,
    );
    int generales(Iterable<FilaPlanillaSorteo> filas) =>
        filas.fold<int>(0, (s, f) => s + f.entradasGenerales);
    int conDescuento(Iterable<FilaPlanillaSorteo> filas) => filas.fold<int>(
          0,
          (s, f) =>
              s +
              f.entradasAdicional.conDescuento +
              f.entradasSillas.conDescuento,
        );
    int sinDescuento(Iterable<FilaPlanillaSorteo> filas) => filas.fold<int>(
          0,
          (s, f) =>
              s +
              f.entradasAdicional.sinDescuento +
              f.entradasSillas.sinDescuento,
        );
    final porId = {for (final a in lista) a.id: a};
    // Los bloques se guardan por la clave de la división ("5A"); la planilla
    // la muestra como está escrita ("5° A").
    final bloqueDe = {for (final b in bloques) b.division: b.texto()};

    final divisiones = <ResumenDivision>[];
    final aLlamar = <({FilaPlanillaSorteo fila, String division})>[];
    final aAvisarPasto = <({FilaPlanillaSorteo fila, String division})>[];
    for (final entrada in porDiv.entries) {
      final filas = entrada.value;
      final cuentas = [for (final f in filas) porId[f.alumnoId]!];
      divisiones.add(
        ResumenDivision(
          division: entrada.key,
          egresados: filas.length,
          mesas: cuentas.fold<int>(0, (s, a) => s + SalonMesas.mesas(a)),
          numeros: numerosEnTramos([
            for (final a in cuentas)
              ...MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa),
          ]),
          bloque: entrada.key == sinDivision
              ? null
              : bloqueDe[Divisiones.clave(entrada.key)],
          sillasExtra:
              cuentas.fold<int>(0, (s, a) => s + SalonMesas.sillasExtra(a)),
          conCena: filas.fold<int>(0, (s, f) => s + f.conCena),
          generales: generales(filas),
          conDescuento: conDescuento(filas),
          sinDescuento: sinDescuento(filas),
          repartosPendientes:
              filas.where((f) => f.reparto == RepartoSillas.pendiente).length,
          sinMesa: filas.where((f) => f.sinMesa).length,
        ),
      );
      for (final f in filas) {
        if (f.reparto == RepartoSillas.pendiente) {
          aLlamar.add((fila: f, division: entrada.key));
        }
        if (f.mesasEnPasto > 0) {
          aAvisarPasto.add((fila: f, division: entrada.key));
        }
      }
    }

    final todas = [for (final filas in porDiv.values) ...filas];
    return ResumenPlanillaSorteo(
      egresados: lista.length,
      mesas: lista.fold<int>(0, (s, a) => s + SalonMesas.mesas(a)),
      mesasAsignadas: lista.fold<int>(
        0,
        (s, a) => s + MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length,
      ),
      sillasExtra: lista.fold<int>(0, (s, a) => s + SalonMesas.sillasExtra(a)),
      sillasSinPagar: pagos == null
          ? 0
          : lista
              .where((a) => !(pagos[a.id]?.pagoSillas ?? false))
              .fold<int>(0, (s, a) => s + SalonMesas.sillasExtra(a)),
      conCena: todas.fold<int>(0, (s, f) => s + f.conCena),
      generales: generales(todas),
      conDescuento: conDescuento(todas),
      sinDescuento: sinDescuento(todas),
      sinMesa: todas.where((f) => f.sinMesa).length,
      repartosPendientes:
          todas.where((f) => f.reparto == RepartoSillas.pendiente).length,
      divisiones: divisiones,
      aLlamar: aLlamar,
      hayPasto: pasto.isNotEmpty,
      mesasEnPasto: todas.fold<int>(0, (s, f) => s + f.mesasEnPasto),
      aAvisarPasto: aAvisarPasto,
    );
  }
}
