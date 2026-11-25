/// El nombre de una barra para compararlo: sin espacios de más, en minúsculas y sin
/// acentos. "Barra 1", " barra  1 " y "BARRA 1" son la misma barra; "Barra1" no
/// (la caja elige su barra de una lista, así que no hace falta adivinar).
///
/// **Todo lo que compara barras pasa por acá**: el reparto del jefe, la barra de cada
/// caja (`sede`), los movimientos del repositor y su id fijo. Si cada lado comparara a
/// su manera, una caja escrita distinto vendería sin descontar (revisión del 25-nov).
String claveDeBarra(String nombre) {
  final sinEspacios = nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  const con = 'áàäâéèëêíìïîóòöôúùüûñ';
  const sin = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final c in sinEspacios.split('')) {
    final i = con.indexOf(c);
    b.write(i < 0 ? c : sin[i]);
  }
  return b.toString();
}

/// Si [nombre] es el depósito, escrito como sea ("deposito", "Depósito").
bool esElDeposito(String nombre) => claveDeBarra(nombre) == 'deposito';
