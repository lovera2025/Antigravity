/// Los anchos en los que cambia el acomodo de una pantalla, en un solo lugar.
///
/// - **Celular:** menos de [celular].
/// - **Tablet:** de [celular] a [pc].
/// - **PC:** más de [pc].
///
/// Los usan Personalizar tótem (ventana al centro en la PC, hoja a pantalla
/// completa en tablet y celular) y Recepción.
abstract final class CortesPantalla {
  static const double celular = 600;
  static const double pc = 1024;

  static bool esPc(double ancho) => ancho > pc;
}
