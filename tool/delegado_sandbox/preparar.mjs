// Deja el sandbox listo para un recorrido a mano: datos como al principio y un
// link creado para la fiesta A, con el límite en una semana a las 20:00.
// Uso: node preparar.mjs [cuántos delegados]   (con el servidor levantado)
const A = 'aaaaaaaa-0000-4000-8000-000000000001';
const jefe = async (fn, args = {}) => (await fetch(`http://localhost:8800/rest/v1/rpc/${fn}`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', authorization: 'Bearer jefe' },
  body: JSON.stringify(args),
})).json();

await jefe('sandbox_reiniciar');
const d = new Date(Date.now() + 7 * 864e5);
const dia = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const r = await jefe('delegado_link_crear', {
  p_evento: A, p_fiesta: 'Escuela Normal · Promo 2026', p_vence_local: `${dia} 20:00`, p_cupo: Number(process.argv[2] ?? 3),
});
console.log(r.ok ? `Programa: http://localhost:8800/?panel\nCelular:  http://localhost:8801/?delegado&clave=${r.clave}` : r);
