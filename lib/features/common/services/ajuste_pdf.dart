/// Cómo se acomoda el contenido de un PDF para que entre en la hoja.
///
/// La regla es **abreviar antes que achicar**: la letra chica es el último
/// recurso, no el primero. Los niveles se prueban en orden y se usa el
/// **primero que entra**, midiendo el papel de verdad — no estimando por
/// cantidad de líneas, que con líneas largas se queda corto y con líneas
/// cortas achica de gancho.
///
/// El nivel 0 no toca nada: un cobro común sale exactamente igual que siempre.
/// Solo se sube un escalón si el anterior no alcanzó.
class AjustePdf {
  /// Posición en la escalera. 0 = papel intacto.
  final int nivel;

  /// Escala de la tipografía. Se aplica último y con piso.
  final double texto;

  /// Escala de espaciados y márgenes: el aire se puede comprimir mucho más que
  /// la letra, porque el aire no se lee.
  final double aire;

  /// `false` oculta los subtextos auxiliares (`nom. $X`, explicaciones del
  /// arrastre). El dato principal de cada línea nunca se toca.
  final bool subtextos;

  /// `true` usa rótulos cortos (`Cuota 3/9 · vto 31/05` en vez de
  /// `Cuota 3 de 9 — venció 31/05/2026`).
  final bool abreviar;

  /// Cuántas cuotas nombra cada recuadro de mora antes de agrupar el resto en
  /// un renglón `y N cuotas más`.
  ///
  /// **Nunca llega a cero.** El detalle de la mora se abrevia por escalones,
  /// no se da de baja: un papel que reclama plata sin decir de qué cuotas sale
  /// es exactamente el que motivó este ajuste. Por eso va aparte de
  /// [subtextos], que sí apaga texto auxiliar.
  final int maxFilasMora;

  const AjustePdf({
    required this.nivel,
    this.texto = 1.0,
    this.aire = 1.0,
    this.subtextos = true,
    this.abreviar = false,
    this.maxFilasMora = 6,
  });

  /// Papel sin compactar. Es el que sale en la gran mayoría de los cobros.
  static const intacto = AjustePdf(nivel: 0);

  /// De menos a más invasivo. Cada escalón agrega una medida y conserva las
  /// anteriores.
  static const escalera = <AjustePdf>[
    intacto,
    // 1 · Solo se junta el aire. La letra queda igual.
    AjustePdf(nivel: 1, aire: 0.7),
    // 2 · Se sacan los subtextos auxiliares.
    AjustePdf(nivel: 2, aire: 0.55, subtextos: false, maxFilasMora: 4),
    // 3 · Rótulos abreviados: dicen lo mismo en menos lugar.
    AjustePdf(
      nivel: 3,
      aire: 0.5,
      subtextos: false,
      abreviar: true,
      maxFilasMora: 3,
    ),
    // 4 · Recién acá se achica la tipografía, y con piso.
    AjustePdf(
      nivel: 4,
      texto: 0.92,
      aire: 0.45,
      subtextos: false,
      abreviar: true,
      maxFilasMora: 2,
    ),
    AjustePdf(
      nivel: 5,
      texto: 0.84,
      aire: 0.4,
      subtextos: false,
      abreviar: true,
      maxFilasMora: 2,
    ),
    AjustePdf(
      nivel: 6,
      texto: 0.76,
      aire: 0.35,
      subtextos: false,
      abreviar: true,
      maxFilasMora: 1,
    ),
  ];

  bool get esIntacto => nivel == 0;

  /// Fuente escalada, nunca por debajo del piso legible.
  ///
  /// El piso es lo que impide que "que entre" degenere en "que no se lea": la
  /// 4.6.2 se dedicó justamente a hacer legibles estos papeles.
  double fs(double base, {double piso = 7}) {
    final v = base * texto;
    return v < piso ? piso : v;
  }

  /// Espaciado / padding escalado, con un mínimo para que no colapse a cero.
  double sp(double base) {
    if (base <= 0) return 0;
    final v = base * aire;
    return v < 1 ? 1 : v;
  }
}
