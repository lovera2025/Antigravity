# Portal de pagos web

**Estado:** relevado — nada implementado
**Objetivo:** temporada 2027
**Última revisión:** 25 de agosto de 2026 (sobre `main`, commit `41236b4`)

---

## La idea

Una web pública donde la familia entra, ve su estado de cuenta, elige qué
cuotas paga, ve el recargo desglosado, paga por Mercado Pago y descarga su
recibo. El pago llega solo a la app.

Hoy el circuito es manual: la familia escribe por WhatsApp, hay que decirle
cuánto es con recargo, pasarle el alias o cobrar con el Point por QR, esperar
el comprobante y recién ahí cargarlo. El portal saca todo ese ida y vuelta;
del lado nuestro queda solo confirmar.

## La regla que ordena todo lo demás

> **La web nunca crea una obligación, solo registra un pago.**

De acá sale el alcance y sale la arquitectura. Si alguna vez se discute
ampliar el portal, empezar por releer esta línea.

## Alcance

**Entra:**

- Ver estado de cuenta: cuotas del plan, extras, mora
- Elegir qué pagar (cuota completa o entrega parcial — la app ya soporta las dos)
- Ver el recargo por pago online desglosado, nunca sumado al capital
- Pagar por Mercado Pago
- Descargar el recibo

**No entra: autogestión de mesa/sillas extra.** La web muestra un contacto de
WhatsApp y eso se sigue resolviendo a mano.

*Por qué:* agregar una mesa toca el cupo físico del salón. Necesita control de
concurrencia (dos familias tomando la última mesa a la vez), fecha de corte,
reserva con vencimiento y reversión que libere el cupo. Es la parte cara y la
que más puede romper — si el sistema deja agregar una mesa que no existe, el
problema no es un número mal en la base, es que faltan sillas el día del
evento. Se pospone hasta que el portal de pagos esté andando.

*Detalle útil:* que el link de WhatsApp lleve el mensaje prearmado con el
nombre del alumno y el evento, para no arrancar preguntando "¿quién sos?".

---

## Lo que ya está en el repo y se reusa

| Qué | Dónde |
|---|---|
| Web pública ya desplegada, ruteo por URL (`/cotizar`, `/buscar`, `/lista`, `/totem`, `/op`) | `lib/main.dart:79-84` + `vercel.json` |
| `contratos_alumnos` y `pagos_contrato_alumno` ya sincronizan a Supabase | `lib/core/services/sync_engine.dart:408,410` |
| Precedente de escritura pública anónima (`INSERT` para rol `anon`) | `supabase/fix_rls_public.sql` — tabla `solicitudes_cotizacion` |
| Recargo ya modelado como línea aparte, con `monto_gross = 0` para no tocar el saldo | `kLineKindCargoCanal` en `lib/core/utils/pago_interes_mora.dart:5` |
| Mesa y sillas extra ya son un track separado del plan base | `lib/models/contrato_alumno.dart:15-23` |
| Mora: 1% de la cuota base × días de atraso; vencimiento = último día del mes | `lib/features/eventos/services/mora_cuota_calculator.dart:26,61-75` |
| Cálculos financieros en **funciones puras** (cuota pura, neto↔bruto, distribución base→mesa→sillas) | `lib/features/eventos/services/calculadora_financiera.dart` |
| Recibo compacto de una hoja | `generarReciboAlumno` en `lib/features/common/services/pdf_service.dart:1257` |

## Lo que no está

**No hay DNI en los contratos.** `ContratoAlumno` tiene nombre, teléfono,
institución, curso y número de mesa — no DNI. El DNI existe solo en
`invitados` (recepción / tótem), otra tabla y otro momento. Buscar por DNI
requiere agregar la columna **y conseguir y cargar el dato de cada alumno**,
que hoy no está en ningún lado.
→ `telefono` ya está en el contrato y ya está cargado.

**No hay nada de Mercado Pago.** Ni dependencia en `pubspec.yaml`, ni una
línea en `lib/`. El Point es 100% externo. Se construye de cero.

**La escala de recargos no existe en el sistema.** Es un campo que el operador
tipea en cada cobro, modo `'pct'` o `'pesos'`, guardado en las preferencias de
esa PC (`cobro_masivo_pct_transfer_info`, `cobro_masivo_transfer_cargo_modo`,
`cobro_masivo_informar_pct_transfer`) —
`lib/features/eventos/detalle_evento_masivo_screen.dart:2558-2570`.
La escala real (30k→1.000, 35k→1.500, 40k→2.000, 50k+→5%) está en la cabeza
del operador. Para la web hay que crearla como dato.

---

## Los cuatro problemas de integración

Esto es lo que hay que tener presente antes de escribir una línea.

**1. La lógica de escritura está soldada al SQLite local.**
`lib/core/database/local_database.dart:40` tira
`UnsupportedError('SQLite local no está soportado en entorno Web.')`.
`registrarPago` (`contratos_repository.dart:195-314`) corre entero adentro de
una transacción de ese SQLite. En web explota en la primera línea.

**Supabase es un espejo, no la fuente de verdad. No hay ningún trigger ni
función del lado servidor que recalcule nada.** Si la web inserta una fila en
`pagos_contrato_alumno`, el `saldo_deudor` no se actualiza: queda un pago
flotando y la deuda intacta.

**2. La imputación se decide por texto del concepto.**
`contratos_repository.dart:252,290,298` — `contains('base')` avanza cuotas del
plan, `contains('mesa')` imputa a mesa extra, `contains('silla')` a sillas.
Cualquier cosa que escriba la web tiene que respetar esa convención exacta o
el pago se imputa mal, en silencio.

**3. `line_kind` nunca llega a Supabase.** Se borra a propósito antes de
encolar (`contratos_repository.dart:341`, "sin columnas solo-locales"). Desde
la nube no se distingue una línea de mora ni una de cargo canal salvo por
convención de texto y por `monto_gross = 0`. Frágil.
También faltan en el whitelist de pull (`sync_engine.dart:604`):
`porcentaje_descuento` y `mora_cobrada_offset` de `contratos_alumnos`.

**4. El pull trae la tabla completa y pisa lo local.**
`sync_engine.dart:426` hace `select()` sin watermark, upsert de todo y borrado
de huérfanas. El push manda el `saldo_deudor` local en paralelo. Si la web y
la app escriben saldos las dos, se pisan sin aviso.

**Aparte, seguridad:** hoy el rol `authenticated` tiene acceso total a todas
las tablas (`supabase/solucion_seguridad_rls.sql`). Una web con sesión
autenticada dejaría a una familia leer la cartera entera. Y `/cotizar` ya
manda el bundle completo de la app de gestión al navegador de cualquiera —
para un catálogo se tolera, para plata conviene separar.

---

## Arquitectura propuesta

La lógica no es una pieza: son dos mitades pegadas.

**Mitad A — el cálculo. Ya es portable.** `CalculadoraFinanciera` y
`MoraCuotaCalculator` son funciones puras sobre un `ContratoAlumno`. No tocan
base de datos ni Flutter. Ya compilan al bundle web y ya corren en el
navegador. **La web puede saber todo hoy mismo** sin escribir una fórmula
nueva.

**Mitad B — la escritura. No se porta, se mueve.** No al navegador: al
servidor. Sacar los calculadores a un paquete Dart compartido (son puros, es
mover archivos) que usen los dos: la app de escritorio como ahora, y una
función del lado servidor que atienda la web. Misma fórmula, un solo lugar,
imposible que se desincronicen.

### Por qué la lógica no va en el navegador

- **El modelo local-first no significa nada en una pestaña.** La arquitectura
  asume una máquina de confianza que tiene la verdad. En un navegador cada
  familia arranca con su propia base local vacía y descartable.
- **La lógica en el cliente son sugerencias, no reglas.** Hoy el cliente es
  nuestra PC. Con público, el monto lo decide quien abre la consola.

### El flujo

1. La familia se identifica
2. Ve su estado de cuenta (calculado con los mismos calculadores)
3. Elige qué paga
4. Ve el total con el recargo desglosado aparte
5. Paga por Mercado Pago
6. Descarga el recibo

### Las tres reglas de la confirmación

Acá es donde se cometen todos los errores de estas integraciones:

- **El monto lo calcula el servidor, nunca el navegador.** La web manda "quiero
  pagar las cuotas 3, 4 y 5", no "quiero pagar 93.000". Si el monto viaja
  desde el browser, alguien lo edita.
- **El pago se confirma por webhook, no por el redirect de "pago exitoso"** —
  esa URL la escribe cualquiera a mano. Y el webhook tiene que volver a
  preguntarle a MP por el `payment_id` en vez de confiar en lo que le llegó.
- **Idempotencia.** MP reintenta los webhooks. `payment_id` como clave única, o
  se genera el cobro tres veces.

Y la mora crece por día: el monto final se calcula al armar el pago, nunca se
toma de lo que el navegador tenía en pantalla hace media hora.

### La decisión de fondo

La web **no** inserta en `pagos_contrato_alumno`. Inserta en una tabla nueva de
pagos declarados, y la app —que ya tiene toda la lógica de imputación, mora,
descuento y cuotas— los confirma con un botón.

Menos glamoroso que "se actualiza solo", pero es la diferencia entre reusar la
lógica y reescribirla en otro lenguaje para que se desincronice en tres meses.
La confirmación sigue siendo manual, pero pasa de *leer un WhatsApp, preguntar
cuánto, calcular el recargo, cargarlo* a *tocar confirmar*.

**Se puede probar sin cobrar de verdad:** Mercado Pago tiene sandbox con
credenciales y usuarios de prueba, y Supabase tiene branches. Eso tapa el
agujero de no tener entorno de prueba.

---

## Decisiones pendientes

Ninguna es técnica. Todas son de negocio y hay que cerrarlas antes de escribir
código.

**Sobre el recargo**

1. ¿Se mantiene la escala o se pasa a 5% fijo? Ojo que 5% fijo **es una suba**
   para los montos chicos: 30.000 pasaría de 1.000 a 1.500, 35.000 de 1.500 a
   1.750. De 40.000 para arriba no cambia nada. Es una decisión de precio, y en
   la web queda escrita y comparable — las familias hablan entre ellas.
2. Si se mantiene la escala: ¿qué pasa entre escalones? ¿32.500 paga 1.000 o
   1.500? Hoy se resuelve a ojo; la web no puede.
3. ¿El recargo va **por cuota** o **sobre el total seleccionado**? Tres cuotas
   de 30.000: ¿3.000 o 4.500? Es la decisión más importante de todas.
4. **Hace falta un mínimo.** Con entrega parcial, alguien puede pagar 8.000 y
   el 5% son 400, que puede no cubrir ni la comisión de MP —que cobra por
   transacción, no por monto. Nada impide cinco pagos de 8.000 en vez de uno de
   40.000: cinco comisiones.
5. ¿El recargo de la web es el mismo que el de transferencia manual al alias?
   Son canales con costo distinto (MP cobra comisión, la transferencia no).
   Puede ser legítimamente distinto —"recargo por pago online"— pero tiene que
   estar decidido y escrito, no aparecer cuando alguien compara.

**Sobre el resto**

6. **Identificación:** ¿DNI (requiere agregar columna y cargar el dato de todos)
   o teléfono (ya está) o link único por familia enviado por WhatsApp?
   El DNI no es secreto: quien sepa el de un chico ve cuánto debe esa familia.
   Si se va por DNI, mínimo pedir DNI + fecha de nacimiento, con límite de
   intentos y mensaje de error genérico.
7. **Medios de pago habilitados en MP:** la comisión de tarjeta —y sobre todo
   crédito en cuotas— se puede comer el recargo entero. Conviene restringir a
   dinero en cuenta y débito. Verificar la tabla vigente en la cuenta de MP,
   cambia seguido.
8. ¿Monto libre para entrega parcial, o solo cuotas enteras? Si la web solo
   deja cuotas completas, quien paga parcial sigue escribiendo por WhatsApp —
   justo lo que se quería evitar. Conviene mirar antes qué porcentaje de los
   pagos son parciales.
9. ¿Qué ve la familia además del saldo? ¿Historial de pagos? ¿Recibos viejos?

**Aparte:** todo lo que entra por MP queda registrado y sufre retenciones. No
es malo, pero cambia el neto contra la transferencia al alias y conviene
tenerlo en cuenta antes de fijar los porcentajes.
