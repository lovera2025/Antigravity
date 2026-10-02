import 'dart:math' as math;

import '../../../models/plano_evento.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';

/// Una división en la leyenda del plano impreso.
class DivisionEnPapel {
  /// Su lugar en la leyenda, que es también el de su relleno. Null: las
  /// familias sin división cargada.
  final int? indice;
  final String nombre;
  final int mesas;

  /// "1-44" o "1-10 · 15-20". Null si están salpicadas por el salón (un
  /// sorteo de toda la escuela junta): ahí una lista de tramos no dice nada.
  final String? numeros;

  const DivisionEnPapel({
    required this.indice,
    required this.nombre,
    required this.mesas,
    required this.numeros,
  });

  String get texto => numeros != null
      ? '$nombre: $numeros'
      : '$nombre: $mesas ${mesas == 1 ? 'mesa' : 'mesas'}';
}

/// Lo que cuenta el encabezado del plano impreso.
class ResumenPapel {
  final int mesas;
  final int conFamilia;

  /// Reservadas para una familia que todavía no tiene mesa.
  final int fijadas;
  final int libres;
  final int pasto;
  final int familiasEnPasto;
  final int sillasExtra;
  final int conflictos;

  const ResumenPapel({
    required this.mesas,
    required this.conFamilia,
    required this.fijadas,
    required this.libres,
    required this.pasto,
    required this.familiasEnPasto,
    required this.sillasExtra,
    required this.conflictos,
  });

  /// "132 mesas · 96 con familia · 2 fijadas · 3 libres · 4 familias en el
  /// pasto". Lo que está en cero no se nombra.
  String get texto => [
        mesas == 1 ? '1 mesa' : '$mesas mesas',
        if (pasto > 0) '$pasto de pasto',
        if (conFamilia > 0) '$conFamilia con familia',
        if (fijadas > 0) fijadas == 1 ? '1 fijada' : '$fijadas fijadas',
        if (libres > 0) libres == 1 ? '1 libre' : '$libres libres',
        if (familiasEnPasto > 0)
          familiasEnPasto == 1
              ? '1 familia en el pasto'
              : '$familiasEnPasto familias en el pasto',
        if (conflictos > 0)
          conflictos == 1 ? '1 para revisar' : '$conflictos para revisar',
      ].join(' · ');
}

/// El nombre de una división escrito sobre su bloque de mesas.
class EtiquetaPapel {
  final String texto;
  final RectPlano caja;

  const EtiquetaPapel(this.texto, this.caja);
}

/// Las cuentas del plano impreso que no dependen del PDF: qué parte de la hoja
/// va al papel, qué dice la leyenda y dónde entra el nombre de cada división.
///
/// Todo es cuenta pura, con tests. El dibujo está en
/// [PlanoPdf](../../common/services/plano_pdf.dart).
class PlanoPapel {
  PlanoPapel._();

  /// Lo que se deja alrededor de una mesa al recortar, en radios: entran sus
  /// sillas y el apellido de abajo.
  static const double aireEnRadios = 1.7;

  /// Con más tramos que estos, los números de una división no se listan.
  static const int maxTramosEnLeyenda = 3;

  /// La parte de la hoja que va al papel: lo que tiene mesas y sectores, con
  /// su aire. Nunca deja afuera una mesa ni un sector.
  ///
  /// Un salón armado a medida deja medio playón vacío, y dibujarlo entero
  /// achica las mesas hasta que el número no se lee. Pero ver el hormigón
  /// entero también sirve: ahí se recorta solo si agranda el dibujo al menos
  /// [gananciaMinima] veces. Una hoja sin el borde del hormigón se recorta
  /// siempre: lo que queda afuera es papel en blanco.
  ///
  /// [proporcion] es el ancho sobre el alto del lugar donde se dibuja.
  static RectPlano marco(
    ArmadoSalon armado,
    String hojaId, {
    double proporcion = 1.6,
    double gananciaMinima = 1.2,
  }) {
    final hoja = armado.hoja(hojaId);
    if (hoja == null) return const RectPlano(0, 0, 1, 1);
    final caja = hoja.caja;
    final mesas = armado.mesasDeHoja(hojaId);
    final sectores = armado.sectoresDeHoja(hojaId);
    if (mesas.isEmpty && sectores.isEmpty) return caja;

    final aire = armado.radio * aireEnRadios;
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    void incluir(double izq, double arriba, double der, double abajo) {
      x0 = math.min(x0, izq);
      y0 = math.min(y0, arriba);
      x1 = math.max(x1, der);
      y1 = math.max(y1, abajo);
    }

    for (final m in mesas) {
      incluir(m.x - aire, m.y - aire, m.x + aire, m.y + aire);
    }
    for (final s in sectores) {
      incluir(s.caja.x - 12, s.caja.y - 12, s.caja.derecha + 12, s.caja.abajo + 12);
    }
    // Nunca más que la hoja.
    x0 = math.max(x0, caja.x);
    y0 = math.max(y0, caja.y);
    x1 = math.min(x1, caja.derecha);
    y1 = math.min(y1, caja.abajo);
    if (x1 - x0 < 1 || y1 - y0 < 1) return caja;
    final usado = RectPlano(x0, y0, x1 - x0, y1 - y0);
    if (hoja.contorno == null) return usado;

    double escala(RectPlano r) => math.min(proporcion / r.ancho, 1 / r.alto);
    return escala(usado) >= escala(caja) * gananciaMinima ? usado : caja;
  }

  /// Cuántos metros de hormigón quedan fuera del [marco] hacia el fondo. Cero
  /// si la hoja no trae su borde o si entra entero.
  static double hormigonFueraM(
    ArmadoSalon armado,
    String hojaId,
    RectPlano marco,
  ) {
    final borde = armado.hoja(hojaId)?.contorno;
    if (borde == null) return 0;
    final fondo = borde.puntos.map((p) => p.y).reduce(math.max);
    return math.max(0, armado.aMetros(fondo - marco.abajo));
  }

  /// Las divisiones con sus mesas, en el orden de la leyenda. "Sin curso
  /// asignado" va al final. Cuenta las mesas con familia y las fijadas.
  static List<DivisionEnPapel> divisiones(EstadoPlano estado) {
    final porIndice = <int?, List<int>>{};
    for (final i in estado.mesas) {
      if (i.ocupantes.isEmpty && i.fijadaPara == null) continue;
      porIndice.putIfAbsent(i.division, () => []).add(i.numero);
    }
    DivisionEnPapel renglon(int? indice, String nombre) {
      final numeros = porIndice[indice]!..sort();
      final tramos = SorteoMesasMotor.tramosDe(numeros).length;
      return DivisionEnPapel(
        indice: indice,
        nombre: nombre,
        mesas: numeros.length,
        numeros: tramos <= maxTramosEnLeyenda
            ? PlanillaSorteo.numerosEnTramos(numeros)
            : null,
      );
    }

    return [
      for (var k = 0; k < estado.divisiones.length; k++)
        if (porIndice.containsKey(k))
          renglon(
            k,
            estado.nombresDivision[estado.divisiones[k]] ??
                estado.divisiones[k],
          ),
      if (porIndice.containsKey(null))
        renglon(null, PlanillaSorteo.sinDivision),
    ];
  }

  static ResumenPapel resumen(ArmadoSalon armado, EstadoPlano estado) {
    var conFamilia = 0, fijadas = 0, libres = 0, sillas = 0, conflictos = 0;
    final enPasto = <String>{};
    for (final m in armado.mesas) {
      final i = estado.info(m.numero);
      if (i.ocupantes.isNotEmpty) conFamilia++;
      if (i.estado == EstadoMesa.fijada) fijadas++;
      if (i.libre) libres++;
      if (i.estado == EstadoMesa.conflicto) conflictos++;
      sillas += i.sillasExtra;
      if (m.pasto) enPasto.addAll(i.ocupantes.map((o) => o.id));
    }
    return ResumenPapel(
      mesas: armado.cantidadComunes,
      conFamilia: conFamilia,
      fijadas: fijadas,
      libres: libres,
      pasto: armado.cantidadPasto,
      familiasEnPasto: enPasto.length,
      sillasExtra: sillas,
      conflictos: conflictos,
    );
  }

  /// De centro a centro, lo más cerca que una mesa tiene a otra debajo (que
  /// le pise el apellido). Null si ninguna tiene otra debajo.
  static double? pasoVertical(ArmadoSalon armado, String hojaId) {
    final mesas = armado.mesasDeHoja(hojaId);
    double? menor;
    for (final a in mesas) {
      for (final b in mesas) {
        if (b.y <= a.y + 1 || (a.x - b.x).abs() >= 2 * armado.radio) continue;
        final d = b.y - a.y;
        if (menor == null || d < menor) menor = d;
      }
    }
    return menor;
  }

  /// De centro a centro, lo más cerca que una mesa tiene a otra en su fila.
  /// Null si ninguna tiene otra al lado.
  static double? pasoHorizontal(ArmadoSalon armado, String hojaId) {
    final mesas = armado.mesasDeHoja(hojaId);
    double? menor;
    for (final a in mesas) {
      for (final b in mesas) {
        if (b.x <= a.x + 1 || (a.y - b.y).abs() >= armado.radio) continue;
        final d = b.x - a.x;
        if (menor == null || d < menor) menor = d;
      }
    }
    return menor;
  }

  /// Dónde va el apellido de una mesa: centrado debajo de ella. [ocupa] es el
  /// radio de lo que se dibuja de la mesa, con sus sillas.
  static RectPlano franjaApellido(
    MesaPlano m, {
    required double ocupa,
    required double ancho,
    required double alto,
  }) =>
      RectPlano(m.x - ancho / 2, m.y + ocupa + alto * 0.15, ancho, alto);

  static bool _sePisan(RectPlano a, RectPlano b) =>
      a.x < b.derecha && b.x < a.derecha && a.y < b.abajo && b.y < a.abajo;

  /// Dónde entra el nombre de cada división, si el sorteo fue por bloques.
  ///
  /// Va en el hueco de abajo de una mesa de su bloque que no lleve apellido
  /// (la segunda mesa de una familia, o una vacía), lo más cerca posible del
  /// centro del bloque. No pisa mesas, apellidos ni sectores.
  ///
  /// **Van todas o ninguna.** Si a una división de la hoja no se le encuentra
  /// lugar, la hoja sale sin etiquetas: con algunas sí y otras no, la zona sin
  /// nombre parecería de la división de al lado. La leyenda dice siempre qué
  /// mesas tiene cada una.
  static List<EtiquetaPapel> etiquetas({
    required ArmadoSalon armado,
    required String hoja,
    required EstadoPlano estado,
    required List<BloqueDivision> bloques,
    required RectPlano marco,

    /// El radio de lo que se dibuja de una mesa con sus sillas: debajo de eso
    /// va su apellido.
    required double ocupa,

    /// Hasta dónde no puede entrar una etiqueta, desde el centro de una mesa.
    /// Puede ser menos que [ocupa]: tapar la punta de una silla no molesta.
    required double despeje,
    required double alto,
    required double Function(String texto) ancho,
    required bool Function(int numero) llevaApellido,
    required double anchoApellido,
    required double altoApellido,
  }) {
    final mesas = armado.mesasDeHoja(hoja);
    final sectores = armado.sectoresDeHoja(hoja);
    final franjas = [
      for (final m in mesas)
        if (altoApellido > 0 && llevaApellido(m.numero))
          franjaApellido(m, ocupa: ocupa, ancho: anchoApellido, alto: altoApellido),
    ];
    final puestas = <EtiquetaPapel>[];

    for (final b in bloques) {
      final suyas = [for (final m in mesas) if (b.contiene(m.numero)) m];
      if (suyas.isEmpty) continue;
      final texto = estado.nombresDivision[b.division] ?? b.division;
      if (texto.trim().isEmpty) continue;
      final w = ancho(texto);
      final cx = suyas.fold(0.0, (s, m) => s + m.x) / suyas.length;
      final cy = suyas.fold(0.0, (s, m) => s + m.y) / suyas.length;

      RectPlano? mejor;
      var mejorD = double.infinity;
      for (final m in suyas) {
        if (altoApellido > 0 && llevaApellido(m.numero)) continue;
        // El hueco hasta la mesa de abajo; sin mesa abajo, pegada a esta.
        double? abajo;
        for (final o in mesas) {
          if (o.y <= m.y + 1 || (o.x - m.x).abs() >= 2 * armado.radio) continue;
          if (abajo == null || o.y < abajo) abajo = o.y;
        }
        final centroY =
            abajo != null ? (m.y + abajo) / 2 : m.y + ocupa + alto * 0.75;
        final caja = RectPlano(m.x - w / 2, centroY - alto / 2, w, alto);
        if (caja.x < marco.x ||
            caja.y < marco.y ||
            caja.derecha > marco.derecha ||
            caja.abajo > marco.abajo) {
          continue;
        }
        if (mesas.any((o) => caja.solapeConCirculo(o.x, o.y, despeje) > 0.5)) {
          continue;
        }
        if (franjas.any((f) => _sePisan(caja, f))) continue;
        if (sectores.any((s) => _sePisan(caja, s.caja))) continue;
        if (puestas.any((p) => _sePisan(caja, p.caja))) continue;
        final d = (m.x - cx) * (m.x - cx) + (centroY - cy) * (centroY - cy);
        if (d < mejorD) {
          mejorD = d;
          mejor = caja;
        }
      }
      if (mejor == null) return const [];
      puestas.add(EtiquetaPapel(texto, mejor));
    }
    return puestas;
  }
}
