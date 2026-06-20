/// Fecha calendario (yyyy-mm-dd, AR) desde la cual los datos operativos de
/// cierre de caja (guía de cambio, anotaciones PDF) participan del sync manual.
/// Registros anteriores no se suben ni se migran desde SharedPreferences.
const String kCierreCajaSyncFechaCorte = '2026-06-18';

bool cierreCajaFechaElegibleSync(String fechaIso) =>
    fechaIso.compareTo(kCierreCajaSyncFechaCorte) >= 0;
