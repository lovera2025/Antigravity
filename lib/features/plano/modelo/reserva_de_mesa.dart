/// Para quién se reservó una mesa, y quiénes se sientan (6.5.0).
///
/// El 10-nov-2026 el jefe pidió, después del sorteo, **una mesa para los
/// profesores**: se la regala la empresa, sin contrato ni pago, y la quiere
/// dejar acomodada en el plano con los nombres de quienes van. No es un alumno:
/// es una mesa del plano que se dejó libre ("Dejar libre") diciendo para quién.
///
/// **Va todo en el motivo de la mesa libre** (`MesaLibre.motivo`), como texto:
/// `Reservada para Profes: García, Ana; López, Luis`. Sin claves nuevas en el
/// plano de la fiesta: una PC con una versión anterior lo lee como un motivo
/// cualquiera y no pierde nada al guardar.
///
/// - Tiene que empezar con "Reservada para" ([prefijo]). Una mesa libre con
///   otro motivo ("Columna", "Paso de mozos") **no es una reserva**: no se usa,
///   y en el plano sigue tachada.
/// - Lo que sigue, hasta los dos puntos, es **para quién** ([para]): el nombre
///   que lleva la mesa en el plano.
/// - Después de los dos puntos van **quiénes** ([quienes]), separados por punto
///   y coma o por renglón. **La coma no separa:** los nombres se escriben
///   "GARCÍA, ANA".
class ReservaDeMesa {
  final String para;
  final List<String> quienes;

  const ReservaDeMesa(this.para, [this.quienes = const []]);

  static const prefijo = 'Reservada para';

  static final _forma =
      RegExp(r'^\s*reservada\s+para\s+(.*)$', caseSensitive: false, dotAll: true);

  /// Lo que dice el motivo de una mesa libre. Null si no es una reserva: sin
  /// motivo, o con uno que no empieza con "Reservada para".
  static ReservaDeMesa? deMotivo(String? motivo) {
    final m = _forma.firstMatch(motivo ?? '');
    if (m == null) return null;
    final resto = m.group(1)!;
    final corte = resto.indexOf(':');
    final para = _limpio(corte < 0 ? resto : resto.substring(0, corte));
    if (para.isEmpty) return null;
    return ReservaDeMesa(
      para,
      corte < 0 ? const [] : nombresDe(resto.substring(corte + 1)),
    );
  }

  /// Los nombres de un texto, uno por renglón o separados por punto y coma.
  static List<String> nombresDe(String texto) => [
        for (final parte in texto.split(RegExp(r'[;\n\r]+')))
          if (_limpio(parte).isNotEmpty) _limpio(parte),
      ];

  static String _limpio(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// El apellido de "GARCÍA, ANA"; un nombre sin coma va entero.
  static String apellidoDe(String nombre) {
    final coma = nombre.indexOf(',');
    return _limpio(coma < 0 ? nombre : nombre.substring(0, coma));
  }

  /// Lo que va escrito debajo de la mesa **en la pantalla** (pedido del usuario,
  /// 10-nov: "en vez de decir profe, que digan los nombres de cada uno, con
  /// posibilidad de desplegar si son muchos"). Debajo de una mesa entra un
  /// renglón: con un nombre, su apellido; con varios, el primero y cuántos más
  /// ("GARCÍA +4"), y la lista entera se despliega al tocar la mesa. Sin
  /// nombres todavía, para quién es.
  String get rotuloEnPantalla => switch (quienes.length) {
        0 => para,
        1 => apellidoDe(quienes.single),
        final n => '${apellidoDe(quienes.first)} +${n - 1}',
      };

  /// Cómo se guarda en el motivo de la mesa libre. Los dos puntos de [para] y
  /// los punto y coma de los nombres se sacan: ahí se corta al leer.
  String get motivo {
    final p = _limpio(para.replaceAll(':', ' '));
    final q = [
      for (final n in quienes)
        if (_limpio(n.replaceAll(';', ',')).isNotEmpty)
          _limpio(n.replaceAll(';', ',')),
    ];
    return q.isEmpty ? '$prefijo $p' : '$prefijo $p: ${q.join('; ')}';
  }
}
