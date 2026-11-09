/// De qué sector es la plata que se mira en el cierre de caja (6.4.0, decidido el 5-nov):
/// **la plata de cada sector no se mezcla**, cada uno tiene su cierre.
///
/// - COBROS: las cuotas, lo de siempre (por día y por sesión de caja).
/// - BARRA: lo de la barra **por fiesta** (la de anoche sigue al día siguiente).
/// - ENTRADAS: queda listo para cuando esté la venta de entradas.
enum SectorDelCierre {
  cobros('COBROS'),
  barra('BARRA'),
  entradas('ENTRADAS');

  const SectorDelCierre(this.nombre);

  final String nombre;
}

/// Los sectores que se eligen arriba del cierre. **Sin modo jefe, solo Cobros**: el
/// operario ve su cierre como siempre, sin las pestañas.
List<SectorDelCierre> sectoresDelCierre({required bool modoJefe}) =>
    modoJefe ? SectorDelCierre.values : const [SectorDelCierre.cobros];
