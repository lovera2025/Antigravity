# La 6.3.4: cambiar la fecha de un cobro lo saca de su caja (sin publicar)

7-nov-2026. Programado en **`release/6.3.x`** (`19ee217`, carpeta `..\arguello_events_6.3.x`, sobre la 6.3.3 instalada) y pasado a
**`feature/v4.6-cierre-por-sesiones`** (`851fb1d`). Sin SQL. **No hay versión ni tag todavía.**

## Para retomar en otro chat

**Decidido el 7-nov a la noche: no sale sola.** Va con todo junto en la 6.4.0, desde `feature/v4.6-cierre-por-sesiones`, con el
arreglo del aviso entre PCs (`docs/SPEC_pulso_por_el_socket_2026-11-07.md`, sin programar), la barra y Entradas. Lo dijo así: "sumalo al
plan en general, entonces después sacamos todo junto". `release/6.3.x` queda como está.

**El pago de ENRIQUE, MAXIMO sigue en la caja del modo jefe del 7-nov** (abajo, "Qué pasó"). Dos maneras de sacarlo:
- con la versión nueva instalada, volver a ponerle la fecha 23/10 en Corregir medio de pago: sale solo;
- antes, a mano en la nube (`sesion_caja_id` en null de ese solo pago, `770cb528-7e79-43ef-8690-a4eeedd70548`): **después de las 20,
  con el antes y el después a la vista y su OK** (`correcciones-de-datos-acotadas`). Las PCs lo bajan en 5 minutos como mucho; ninguna
  conserva la caja vieja al bajarlo (el pull reescribe la fila; revisado el 7-nov).

> Frase para retomar: "Seguimos con lo de la fecha de un cobro: leé 'Para retomar en otro chat' de
> docs/CONTEXTO_v6.3.4_2026-11-07.md."

## Qué pasó

El jefe cargó el 7-nov a las 09:26 un pago de **ENRIQUE, MAXIMO** ($50.000 en efectivo, entrega de la cuota base) que la familia había
pagado el **23-oct**, y a las 09:27 le cambió la fecha al 23 en Mi Empresa → lápiz → **Corregir medio de pago**. El pago siguió en su
cierre de caja del 7 (la caja automática del modo jefe, "Sesión automática · cobro en modo jefe", abierta a las 09:26).

**Por qué:** el cierre arma la lista **por la caja en la que se cobró** (`sesion_caja_id`), no por la fecha del pago
(`cargarDatosCierreSesion` → `obtenerIngresosDeSesiones`). Cambiar la fecha solo cambiaba `fecha_pago`. No era un error de la 6.3.3.
Los datos del alumno estaban bien: un solo pago, del 23-oct, saldo $473.600, sin mora (eximido hasta el 30-nov).

**La regla del usuario:** "si yo pongo la plata, está bien; pero si le cambio la fecha y pongo el 23, debería mandarme esa plata al 23:
desaparecer de la caja, porque no corresponde a hoy".

## Qué cambió

En `FinanzasRepository.actualizarFechaPagoRegistro` y el diálogo `CorregirMedioPagoDialog`:
- **Otro día con la caja abierta → sale de la caja** (`sesion_caja_id` en null, también en lo que sube). Lo decide
  `cajaTrasCambioDeFecha` (`lib/features/cierre_caja/services/fecha_y_caja.dart`): los días de una caja van del que se abrió al que se
  cerró (o hasta hoy si sigue abierta), en hora de Argentina, así **una caja abierta a la noche sigue siendo de su fiesta hasta la
  madrugada**. **Una caja ya cerrada no se toca:** el arqueo se hizo con esa plata; la fecha cambia igual y el aviso lo dice. En Mi
  Empresa el cobro queda en su día nuevo. Sin caja, en la vista de contraste del cierre del jefe de ese día aparece como cobro sin caja.
- **Todo el cobro junto:** en un masivo, la cuota, la mesa y la mora del mismo cobro (`lineasDelMismoCobro`) cambian de fecha juntas, en
  una transacción. Antes cambiaba solo la línea tildada y el cobro quedaba partido en dos días; y con "Tildar todo el cobro" el diálogo
  escondía la fecha (solo la mostraba con una línea). Ahora la muestra si lo tildado es un solo cobro.
- **Sin fechas futuras:** el calendario llega hasta hoy (antes, un año adelante).
- **La mora del alumno se revisa en el momento** (`revisarMora(soloContratos:)`), al cambiar la fecha y también al **anular un cobro por
  error**: la mora se calcula con la fecha de los pagos, y antes la corregía la revisión del arranque siguiente, en cualquier PC y sin
  que nadie lo viera.

"Anular cobro por error" se revisó entero (el usuario pidió revisar todo lo del lápiz): no tenía errores; solo se le sumó la revisión de
la mora en el momento.

## Las pruebas

`test/cambiar_fecha_saca_de_la_caja_test.dart` (8, con una base temporal): ENRIQUE sale de la caja abierta y sube así; cambiar la hora el
mismo día lo deja; una caja abierta a la noche se queda con el día de antes; una caja cerrada no se toca; un cobro sin caja solo cambia de
fecha; **todo el cobro junto** (la cuota y su mora salen, el otro cobro del mismo alumno no); los dos diálogos revisan la mora en el
momento y el calendario no pasa de hoy; y los días de una caja. La suite entera de
la 6.3.x, en verde (3.454).
