import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/nota_operativa_contrato.dart';
import 'mesas_extra_utils.dart';
import 'pago_para_sorteo.dart';
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

/// Cómo reparte la familia sus sillas extra entre sus mesas.
enum RepartoSillas {
  /// No tiene sillas extra: no hay nada que repartir.
  noAplica,

  /// Tiene sillas extra y todavía no confirmó cómo las reparte. Hasta que
  /// exista la confirmación (Fase 2), todo reparto está pendiente y la
  /// planilla muestra el de siempre: de a 2 por mesa, la principal primero.
  pendiente,

  /// La familia confirmó el reparto.
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

  /// Las entradas generales de la mesa principal: sus lugares (8 más las
  /// sillas extra que van ahí) menos los que tienen cena. Negativo si no
  /// entran. `null` si todavía no tiene mesa.
  final int? generalesPrincipal;

  /// Las mesas extra: "13", "13-14", "13 · 40 (separada)", "1 sin asignar",
  /// o "-".
  final String adicional;

  /// "(!) le falta 1 mesa", si los números no coinciden con la cuenta.
  final String? alertaMesas;

  /// Sillas extra por mesa: "2P · 1A" (principal y adicional), "3" si todavía
  /// no tiene mesa, o "-". Con "(sin pagar)" si no tienen nada pagado.
  final String sillas;

  final RepartoSillas reparto;
  final String telefono;
  final String musica;

  /// La nota operativa sin resolver, o vacío.
  final String observaciones;

  /// Hay algo que avisar esa noche: la fila va en amarillo.
  final bool avisar;

  /// No tiene mesa porque no pagó nada de la cuota base: la fila va en rojo.
  final bool sinMesa;

  /// Egresado y acompañantes: todos tienen cena.
  final int conCena;

  const FilaPlanillaSorteo({
    required this.alumnoId,
    required this.egresado,
    required this.acompanantes,
    required this.mesaPrincipal,
    required this.ocupacionPrincipal,
    required this.generalesPrincipal,
    required this.adicional,
    required this.alertaMesas,
    required this.sillas,
    required this.reparto,
    required this.telefono,
    required this.musica,
    required this.observaciones,
    required this.avisar,
    required this.sinMesa,
    required this.conCena,
  });
}

/// Una división en la hoja de resumen.
class ResumenDivision {
  final String division;
  final int egresados;
  final int mesas;

  /// Los números de la división de a tramos: "1-24", "1-10 · 15-20", o "-".
  final String numeros;

  final int sillasExtra;
  final int conCena;
  final int repartosPendientes;
  final int sinMesa;

  const ResumenDivision({
    required this.division,
    required this.egresados,
    required this.mesas,
    required this.numeros,
    required this.sillasExtra,
    required this.conCena,
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
  final int sinMesa;
  final int repartosPendientes;
  final int paraAvisar;
  final List<ResumenDivision> divisiones;

  /// A quién llamar para que elija cómo reparte sus sillas extra.
  final List<({FilaPlanillaSorteo fila, String division})> aLlamar;

  const ResumenPlanillaSorteo({
    required this.egresados,
    required this.mesas,
    required this.mesasAsignadas,
    required this.sillasExtra,
    required this.sillasSinPagar,
    required this.conCena,
    required this.sinMesa,
    required this.repartosPendientes,
    required this.paraAvisar,
    required this.divisiones,
    required this.aLlamar,
  });
}

/// Arma la planilla del sorteo a partir de las cuentas, lo pagado y las notas.
///
/// Todo sale de lo que ya está guardado ([SalonMesas], `numero_mesa`, los
/// pagos y las notas operativas): la planilla no guarda nada ni inventa
/// datos. Lo que todavía no existe en la base (la confirmación del reparto, la
/// marca de avisar) se deduce de lo que sí hay y queda dicho acá.
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
  /// sillas extra se reparten como en [SalonMesas.repartoSillas]: de a 2 por
  /// mesa, la principal primero.
  static FilaPlanillaSorteo fila(
    ContratoAlumno a, {
    PagoAlumno? pago,
    NotaOperativaContrato? nota,
  }) {
    final tramos = SalonMesas.tramos(a);
    final crudo = a.numeroMesa?.trim() ?? '';
    final principal = tramos.isEmpty ? null : tramos.first.first;

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
      mesaPrincipal = 'sin mesa (sin pagar)';
      sinMesa = true;
    } else {
      mesaPrincipal = 'sin asignar';
    }

    // ── Adicional: sus mesas extra ────────────────────────────────────────
    final extrasDelBloque =
        tramos.isEmpty ? const <int>[] : tramos.first.skip(1).toList();
    final partes = <String>[
      if (extrasDelBloque.isNotEmpty) _tramo(extrasDelBloque),
      for (final t in tramos.skip(1)) '${_tramo(t)} (separada)',
    ];
    final extras = SalonMesas.mesasExtra(a);
    final sinPagarMesas = pago != null && !pago.pagoMesas;
    final String adicional;
    if (partes.isNotEmpty) {
      adicional = partes.join(' · ');
    } else if (extras > 0 && principal == null) {
      adicional = extras == 1
          ? '1 mesa extra${sinPagarMesas ? ' (sin pagar)' : ''}'
          : '$extras mesas extra${sinPagarMesas ? ' (sin pagar)' : ''}';
    } else {
      adicional = '-';
    }
    var alerta = SalonMesas.avisoMesas(a);
    if (alerta != null && sinPagarMesas && alerta.startsWith('le falta')) {
      alerta = '$alerta (sin pagar)';
    }

    // ── Con cena y generales en la principal ──────────────────────────────
    final ocupacion = SalonMesas.ocupacion(a);
    final conCena = ocupacion.personas;
    final reparto = SalonMesas.repartoSillas(a);
    final sillasPrincipal = principal == null
        ? 0
        : reparto
            .where((e) => e.$1 == principal)
            .fold<int>(0, (s, e) => s + e.$2);
    String? ocupacionPrincipal;
    int? generales;
    if (principal != null) {
      final lugares = SalonMesas.sillasPorMesa + sillasPrincipal;
      generales = lugares - conCena;
      ocupacionPrincipal = generales >= 0
          ? '$conCena con cena · $generales '
              '${generales == 1 ? 'general' : 'generales'}'
          : '$conCena con cena · (!) faltan ${-generales} lugares';
    }

    // ── Sillas extra: "2P · 1A" ───────────────────────────────────────────
    final sillasExtra = SalonMesas.sillasExtra(a);
    final sinPagarSillas = pago != null && sillasExtra > 0 && !pago.pagoSillas;
    String sillas;
    if (sillasExtra == 0) {
      sillas = '-';
    } else if (reparto.isEmpty) {
      sillas = '$sillasExtra';
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
    if (sinPagarSillas) sillas = '$sillas (sin pagar)';

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
      adicional: adicional,
      alertaMesas: alerta == null ? null : '(!) $alerta',
      sillas: sillas,
      reparto:
          sillasExtra > 0 ? RepartoSillas.pendiente : RepartoSillas.noAplica,
      telefono: oGuion(a.telefono),
      musica: oGuion(a.musicaElegida),
      observaciones: pendiente,
      avisar: pendiente.isNotEmpty,
      sinMesa: sinMesa,
      conCena: conCena,
    );
  }

  /// Una hoja por división, en orden alfabético, con sus egresados también
  /// en orden alfabético. "Sin curso asignado" va al final.
  static Map<String, List<FilaPlanillaSorteo>> porDivision(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
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
            .map((a) => fila(a, pago: pagos?[a.id], nota: notas[a.id]))
            .toList(),
    };
  }

  /// Los totales de la noche y el detalle por división.
  static ResumenPlanillaSorteo resumen(
    Iterable<ContratoAlumno> alumnos, {
    Map<String, PagoAlumno>? pagos,
    Map<String, NotaOperativaContrato> notas = const {},
  }) {
    final lista = activos(alumnos);
    final porDiv = porDivision(lista, pagos: pagos, notas: notas);
    final porId = {for (final a in lista) a.id: a};

    final divisiones = <ResumenDivision>[];
    final aLlamar = <({FilaPlanillaSorteo fila, String division})>[];
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
          sillasExtra:
              cuentas.fold<int>(0, (s, a) => s + SalonMesas.sillasExtra(a)),
          conCena: filas.fold<int>(0, (s, f) => s + f.conCena),
          repartosPendientes:
              filas.where((f) => f.reparto == RepartoSillas.pendiente).length,
          sinMesa: filas.where((f) => f.sinMesa).length,
        ),
      );
      for (final f in filas) {
        if (f.reparto == RepartoSillas.pendiente) {
          aLlamar.add((fila: f, division: entrada.key));
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
      sinMesa: todas.where((f) => f.sinMesa).length,
      repartosPendientes:
          todas.where((f) => f.reparto == RepartoSillas.pendiente).length,
      paraAvisar: todas.where((f) => f.avisar).length,
      divisiones: divisiones,
      aLlamar: aLlamar,
    );
  }
}
