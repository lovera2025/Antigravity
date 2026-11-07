import '../../../models/evento.dart';

/// Las fiestas que el jefe ve en BARRA: **la pantalla abre en la próxima** (elegido el
/// 7-nov), y CAMBIAR DE FIESTA muestra las que vienen y las últimas. A diferencia de la
/// cajera, no hace falta que tengan precios: el jefe es quien se los pone.
///
/// **La de anoche sigue siendo "la que viene" hasta el día siguiente:** la fiesta termina
/// de madrugada, y a la mañana el jefe quiere ver sus cajas desde la oficina.
class FiestasDelJefe {
  /// Desde ayer en adelante, la más cercana primero.
  final List<Evento> lasQueVienen;

  /// Las de antes de ayer, la más reciente primero: para revisar las cajas de una fiesta
  /// que ya pasó.
  final List<Evento> lasUltimas;

  const FiestasDelJefe({this.lasQueVienen = const [], this.lasUltimas = const []});

  /// Cuántas de las que ya pasaron se ofrecen.
  static const ultimasQueSeMuestran = 8;

  /// Con la que abre la pantalla: la próxima; si no hay ninguna, la última que pasó.
  Evento? get laQueAbre => lasQueVienen.firstOrNull ?? lasUltimas.firstOrNull;

  bool get vacia => lasQueVienen.isEmpty && lasUltimas.isEmpty;

  /// Todas, en el orden del menú.
  List<Evento> get todas => [...lasQueVienen, ...lasUltimas];

  /// Las de [eventos] que sirven, sin las canceladas. [hoy] es la fecha de la PC.
  factory FiestasDelJefe.de(Iterable<Evento> eventos, DateTime hoy) {
    final ayer = DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 1));
    DateTime dia(Evento e) =>
        DateTime(e.fechaEvento.year, e.fechaEvento.month, e.fechaEvento.day);
    final validas = eventos.where((e) => e.estado != EstadoEvento.cancelado);
    final vienen = validas.where((e) => !dia(e).isBefore(ayer)).toList()
      ..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
    final pasaron = validas.where((e) => dia(e).isBefore(ayer)).toList()
      ..sort((a, b) => b.fechaEvento.compareTo(a.fechaEvento));
    return FiestasDelJefe(
      lasQueVienen: List.unmodifiable(vienen),
      lasUltimas: List.unmodifiable(pasaron.take(ultimasQueSeMuestran)),
    );
  }

  /// La fiesta de [id] si está entre las que se muestran; si no, [laQueAbre].
  Evento? elegida(String? id) {
    if (id != null) {
      for (final e in todas) {
        if (e.id == id) return e;
      }
    }
    return laQueAbre;
  }
}

/// "viernes 4 de diciembre · la próxima": la fecha con cuándo es, si importa. Hoy y
/// anoche se dicen así; la que abre la pantalla, si todavía no pasó, es "la próxima".
String fechaConCuando(DateTime fecha, DateTime hoy, {bool esLaQueAbre = false}) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
  final texto = fechaDeLaFiesta(fecha);
  if (dia == hoyDia) return '$texto · hoy';
  if (dia == hoyDia.subtract(const Duration(days: 1))) return '$texto · anoche';
  if (esLaQueAbre && dia.isAfter(hoyDia)) return '$texto · la próxima';
  return texto;
}

/// "viernes 4 de diciembre", la fecha como se lee arriba de la pantalla.
String fechaDeLaFiesta(DateTime f) {
  const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
    'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  return '${dias[f.weekday - 1]} ${f.day} de ${meses[f.month - 1]}';
}
