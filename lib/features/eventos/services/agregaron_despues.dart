import '../../../models/contrato_alumno.dart';
import 'lugares_al_sorteo.dart';
import 'retiro_entradas.dart';

/// Una familia que cargó una mesa adicional o sillas extra **después del
/// sorteo** de su fiesta: las entradas de eso pagan el precio del día, sin
/// descuento.
class AgregoDespues {
  final ContratoAlumno alumno;

  /// Las mesas adicionales que no tenía al sorteo.
  final int mesas;

  /// Las sillas extra que no tenía al sorteo.
  final int sillas;

  /// Las entradas que se compran por eso, sin descuento. Puede ser 0: los VIP
  /// que no entran en la mesa del contrato ocupan esos lugares sin pagar la
  /// entrada (`EntradasDeAlumno.cosas`).
  final int entradas;

  const AgregoDespues({
    required this.alumno,
    required this.mesas,
    required this.sillas,
    required this.entradas,
  });

  String get id => alumno.id;

  /// "1 mesa adicional y 2 sillas extra".
  String get queAgrego => [
        if (mesas > 0) mesas == 1 ? '1 mesa adicional' : '$mesas mesas adicionales',
        if (sillas > 0) sillas == 1 ? '1 silla extra' : '$sillas sillas extra',
      ].join(' y ');

  /// "8 entradas", o "sin entradas para comprar" si las ocupan sus VIP.
  String get cuantasEntradas => switch (entradas) {
        0 => 'sin entradas para comprar',
        1 => '1 entrada',
        _ => '$entradas entradas',
      };

  @override
  String toString() => 'AgregoDespues(${alumno.id}: $queAgrego, $cuantasEntradas)';
}

/// Quiénes de una fiesta agregaron una mesa adicional o sillas extra después
/// del sorteo (pedido del usuario, 27-nov-2026: "que solo avise").
///
/// **La regla no cambia** (17-nov-2026): con el descuento de PRECIOS va lo que
/// la familia ya tenía cargado al sorteo, pagado o no; lo que agregó después
/// paga el precio del día. Cuándo lo pagó no cuenta: cuenta cuándo lo cargó.
///
/// **No es otra cuenta:** sale de `EntradasDeAlumno.cosas`, la misma que usan la
/// entrega, la planilla y A PAGAR de VENDER (`APagarDeLaFamilia`). Así el aviso
/// dice exactamente lo que el programa cobra sin descuento. No se resta "lo de
/// hoy menos lo del sorteo" a mano: los VIP de más ocupan lugares, y las
/// entradas de una cosa pueden ser menos que sus lugares.
///
/// El programa lo sabe solo: compara lo cargado hoy con lo anotado al sortear
/// ([FotoDeLosLugares], que desde la 6.9.2 se toma en cada sorteo). Nadie
/// acepta ni tilda nada.
class AgregaronDespues {
  /// Si la fiesta tiene anotado lo del sorteo.
  final EstadoDeLosLugares estado;

  /// Cuándo fue el sorteo de la fiesta, si lo hay.
  final DateTime? sorteoEl;

  /// En orden alfabético.
  final List<AgregoDespues> familias;

  const AgregaronDespues._(this.estado, this.sorteoEl, this.familias);

  /// Sin sorteo, o sin nada que avisar.
  static const nadie =
      AgregaronDespues._(EstadoDeLosLugares.sinSorteo, null, []);

  /// [alumnos]: los de la lista, **sin las bajas temporales** (quien los pasa
  /// decide: a una baja no se le vende).
  ///
  /// Sin lo anotado al sorteo ([EstadoDeLosLugares.sinAnotar] o `sinSorteo`) no
  /// hay nadie: todo va con descuento, como antes de la regla. Para la fiesta
  /// sin anotar, [sinAnotar] lo dice.
  factory AgregaronDespues.de({
    required FotoDeLosLugares foto,
    required Iterable<ContratoAlumno> alumnos,
  }) {
    final familias = <AgregoDespues>[];
    if (foto.estado == EstadoDeLosLugares.anotados) {
      for (final a in alumnos) {
        final despues = [
          for (final c in RetiroEntradas.entradasDe(a, foto: foto).cosas)
            if (!c.alSorteo) c,
        ];
        if (despues.isEmpty) continue;
        familias.add(AgregoDespues(
          alumno: a,
          mesas: despues.where((c) => c.esMesa).length,
          sillas: despues.where((c) => !c.esMesa).length,
          entradas: despues.fold(0, (s, c) => s + c.entradas),
        ));
      }
      familias.sort((x, y) => x.alumno.nombreAlumno.compareTo(y.alumno.nombreAlumno));
    }
    return AgregaronDespues._(foto.estado, foto.sorteoEl, List.unmodifiable(familias));
  }

  bool get hay => familias.isNotEmpty;

  /// La fiesta se sorteó y no tiene anotado qué tenía cada familia: el programa
  /// no puede saber quién agregó después, y todo va con descuento. No tiene que
  /// pasar (todos los equipos anotan al sortear); si pasa, se le avisa al jefe.
  bool get sinAnotar => estado == EstadoDeLosLugares.sinAnotar;

  /// La de [alumnoId], o null si no agregó nada después.
  AgregoDespues? de(String alumnoId) {
    for (final f in familias) {
      if (f.id == alumnoId) return f;
    }
    return null;
  }

  /// Para saber si la lista cambió: quién y qué, en orden.
  String get firma =>
      [for (final f in familias) '${f.id}|${f.mesas}|${f.sillas}|${f.entradas}'].join(';');
}
