# Operadores con permisos (programado, SIN PUBLICAR)

2-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Plan: `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 1 a 3. El orden de todo:
`docs/HOJA_DE_RUTA_2026-11-02.md`, paso 3.

## Para retomar en otro chat (8-nov, noche): Entradas 4 y 5, cerradas

> **Entradas 4 y 5 están cerradas en la rama, sin publicar.** La 5 (las roturas a propósito) se hizo el 8-nov a la noche: cada
> rotura dio rojo y el código volvió a quedar igual (abajo, "Las roturas de la etapa 5"). Plan general: **23 de 26 partes, 88 %**.
> Quedan **el aviso entre PCs** (`docs/SPEC_pulso_por_el_socket_2026-11-07.md`), **el aviso de papel** y **publicar la 6.4.0**
> (Entradas 6). Lo que no se puede comprobar en el sandbox queda para el día de la instalación, con el usuario: el sonido del aviso
> y la entrega en dos PCs de verdad (un operador de prueba solo de Entradas en una PC, la caja en la otra).

**Lo que hace ahora la entrega de entradas** (`RetiroEntradasScreen`):
- **Dos modos.** Desde la fiesta (la oficina) sigue igual: IR A COBRAR y EDITAR ALUMNO abren lo de siempre. Desde Entradas (el operador
  que entra con su PIN a entregar) abre **`RetiroEntradasScreen.mostrador`**: sin cobro ni edición.
- **Qué botones ve cada uno lo decide `PermisosDeEntrega`** (`eventos/services/permisos_de_entrega.dart`): oficina → cobrar y editar;
  mostrador → ni cobrar ni editar, PASAR A CAJA si tiene Cobros; **anular, solo con modo jefe, en los dos lugares**.
- **Si la familia debe, en el mostrador:** "Debe $X · cuotas y extras · mora. **Que pase por caja a saldar todo; cuando pague, la entrega
  se destraba sola.**" ENTENDIDO la deja en **"En caja"**; con Cobros, PASAR A CAJA la deja en "En caja" y lleva a la caja sin el PIN
  (cierra la entrega y llama a `pasarACaja()`).
- **"En caja"** (`entradas/services/en_caja.dart`, `enCajaProvider` por fiesta, en memoria, sobrevive a ir a la caja y volver): arriba
  de la entrega, las familias que deben ("PÉREZ · debe $70.000" o "pagó una parte · faltan $40.000"). **Cuando el pago baja de la otra PC
  (o de esta), salta en verde "PÉREZ pagó: ya podés entregar" con ENTREGAR y el sonido del sistema** (`SystemSound.alert`), una sola vez.
  Entregarle la saca de la lista; la ✕ también.
- **Si el diálogo de esa familia está abierto cuando paga, se cierra y se vuelve a abrir con los datos nuevos** (`VolverAAbrir`, por el
  `Listenable cuentaCambio`): solo si muestra el bloqueo, nunca con el formulario a medio llenar.
- **La línea "En vivo con la caja"** (o "Sin internet: lo que se cobre en la caja no llega hasta que vuelva"), solo en el mostrador.
- **Anular, doble llave:** el botón apagado con "Solo en modo jefe" (`kSoloEnModoJefe`), y `_anular` frena sin el permiso. **Ojo: en la
  oficina, quien está en la caja ya no anula una entrega: solo el jefe** (decidido el 30-oct).
- Los otros bloqueos, en el mostrador, dicen "Pedile al jefe que lo revise" y no tienen EDITAR ALUMNO ni "Cambiar acompañantes".
- `entregado_por` lleva el nombre del operador (ya lo hacía `quienOperaDe`; ahora con su test).
- La subida después de entregar o anular pasa por `subidaInmediataProvider` (lo mismo que hacía, reemplazable en los tests).

**Las pruebas, en el sandbox:** `test/retiro_entradas_screen_test.dart` (nuevo, la pantalla entera montada con
`test/helpers/entrega_en_memoria.dart`: tres familias, "la otra PC" que cobra con `cobrar()` y avisa como el pulso), `en_caja_test`,
`quien_opera_test`, `entrega_entradas_dialog_test` ampliado y `modo_entradas_cerrado_test` al día. **La ventana de prueba
`tool/entradas_prueba.dart`** (`flutter run -d windows -t tool/entradas_prueba.dart`): Carla (solo Entradas) a la izquierda y la otra
PC cobrando a la derecha. **El recorrido con el mouse (8-nov):** PÉREZ debe → ENTENDIDO → "En caja"; la otra PC cobra $30.000 → "pagó una
parte · faltan $40.000"; con su diálogo abierto, COBRAR TODO → el diálogo se volvió a abrir solo con el formulario y arriba "PÉREZ, JUAN
pagó: ya podés entregar"; entregado (talonario 2001, Madre) → el aviso se fue; GÓMEZ (ya retiró) → ANULAR apagado con "Solo en modo
jefe"; CORTAR INTERNET → la línea lo dice. **Encontró una cosa:** los botones del diálogo bloqueado quedaron a la izquierda; arreglado
(vuelven a ir a la derecha, como antes).

**Las roturas de la etapa 5 (8-nov, noche).** Cada una se metió en el código, se corrieron los tests, y se sacó; `git diff` quedó vacío:

| Rotura | Lo que la agarró |
|---|---|
| ANULAR prendido sin modo jefe (`PermisosDeEntrega.oficina`) | `entrega_entradas_dialog_test` y `retiro_entradas_screen_test`: falta el botón apagado |
| Sin el freno de `_anular` (la segunda llave) | `modo_entradas_cerrado_test`, que lee la pantalla |
| "Pagó" que no pasa nunca (`EnCaja.conDeudas`) | `en_caja_test` y dos de la pantalla entera: no salta "PÉREZ, JUAN pagó: ya podés entregar" |
| La entrega que no relee cuando baja el cobro de la otra PC | cuatro de la pantalla entera: el aviso, "pagó una parte", el diálogo que se vuelve a abrir y la entrega desde En caja |
| IR A COBRAR en el mostrador (`cobrarAca = true`) | nueve: el diálogo, la pantalla entera y `modo_entradas_cerrado_test` |

La suite entera, en verde (3.979 tests).

**No comprobado en el sandbox:** el sonido del aviso (en Windows es el "tin" del sistema), PASAR A CAJA con el mouse (lo cubre el test) y
**la prueba en dos PCs de verdad**, que queda para la instalación de la 6.4.0 en la oficina con el usuario.

**Estado: etapas 1 a 3 hechas y subidas a la rama. Sin versión, sin release, sin web, y el SQL sin correr. Las PCs siguen con la
6.2.1. Publicar, solo preguntándole antes al usuario.**

## Qué se hizo

| Etapa | Qué cambia para el usuario | Dónde |
|---|---|---|
| 1 | Cada operador puede tener sus permisos, con un registro de quién dio o sacó cada uno. Los de hoy no cambian | `PermisosEfectivos`, `PermisosOperadorRepository`, v76, `supabase/migrations/20261103120000_permisos_operador.sql` |
| 2 | OPERADORES, con las casillas Cobros, Entradas y Barra. El PIN repetido o el maestro se dice en la ficha | `operadores_caja_screen.dart`, `pin_de_operador.dart` |
| 3 | OPERADOR en vez de MODO CAJA. Un PIN y se despliegan las opciones. Quien tiene Entradas va a su pantalla | `AppRoleNotifier.buscarOperador`, `OpcionesDeEntrada`, `destinoDeEntrada`, `EntradasHomeScreen` |

## La migración, sobre una copia de la base real

`tool/verificar_migracion_v76_test.dart`, el 2-nov con la app cerrada (base en v75, 643 alumnos, 4.592 pagos, 4 operadores): ninguna
tabla cambió, el esquema de lo que ya existía quedó igual, se puede volver a la 6.2.1 y la base real terminó con el mismo SHA-256.

## La prueba con el mouse

`flutter run -d windows -t tool/operadores_prueba.dart`, sin base ni nube. Los PIN inventados están arriba de la ventana.

- Sin permisos (Leo): "Te faltan permisos: pedíselos al jefe", y no pasa de la entrada.
- Los tres (Tati): se despliegan COBROS, ENTRADAS y BARRA; Barra apagada, con el motivo.
- ENTRADAS, PASAR A CAJA con la caja por abrir, Cancelar (vuelve a Entradas), abrir la caja, ENTRADAS y PASAR A CAJA de nuevo, que la retoma
  sin pedir nada.
- OPERADORES en modo jefe: Cobros tildada en uno de hoy, los avisos al destildar, y el PIN repetido dentro de la ficha.
- Darle solo Entradas a un operador de hoy y entrar con su PIN: va derecho a Entradas, sin PASAR A CAJA.

La pantalla de Entradas abre un aviso en esa ventana, no la entrega de verdad: esa lee la base.

## Decisiones que no estaban en el plan

- **Uno nuevo viene con Cobros tildada.** Sin tocar las casillas queda como hasta hoy, y no hace falta el aviso de las PCs viejas cada vez.
  Se le puede destildar todo: "cargado sin permisos" sigue existiendo.
- **Solo Barra no entra, y dice que todavía no está.** Con Barra y otro permiso, Barra se ve apagada, con el motivo. Cuando esté el módulo,
  hay que sacar eso (`kBarraTodaviaNo`).
- **Ir de la caja a Entradas deja la caja abierta y latiendo.** Ir a entregar no es cerrar el turno; el latido sigue para que la otra PC no la
  crea muerta. Entrar directo a Entradas no abre ni mira ninguna caja.
- **Cancelar "Abrir caja" con Entradas vuelve a Entradas**, también si venía de elegir COBROS. Sin Entradas, a la pantalla de entrada, como hoy.
- **La fila del permiso de un operador dado de baja queda.** Nada se borra, y el id sale del operador.
- **`permisos_operador` baja cada 10 s y su registro cada minuto.** Los permisos tienen que estar antes de poner el PIN; el registro no apura.
- **Un PIN que no está en esta PC espera a la nube hasta 8 s** (`kEsperaDelPinEnLaNube`). Un PIN mal escrito con internet tarda eso como mucho.

## Antes de publicar esto

1. **Faltan las etapas 4 a 6 del plan para que Entradas sirva de verdad.** Hoy quien tiene solo Entradas:
   - **todavía puede ANULAR una entrega**: "anular, solo el jefe" es de la etapa 4;
   - ve IR A COBRAR y EDITAR ALUMNO en el diálogo, que solo le dicen qué hacer, sin el monto ni el aviso de "pagó: ya podés entregar".
2. **Correr el SQL antes de instalar**, con el OK del usuario y las consultas de su sección 3. Sin las tablas en la nube, lo que se cambie queda
   trabado en la cola, y "Lista para trabajar sin internet" no se pone al día.
3. **No crear operadores sin Cobros hasta que las tres PCs tengan la versión:** una PC vieja los deja entrar a cobrar. La ficha lo avisa.
4. Instalar: la migración v76 corre sola, y `copiaAntesDeMigrar` deja `antes_de_v76.db`.

**Se puede publicar la 6.3.0 (el plano) sin esto, o todo junto:** lo decide el usuario. Hoy está todo en la misma rama, así que publicar el plano
solo pediría separarlo. Lo que esperaría: terminar las etapas 4 a 6 y publicar todo en una.

## Lo que no se comprobó

- **La pantalla de Entradas con la base de verdad, y la entrega desde ahí.** La pantalla se probó con fiestas inventadas. `RetiroEntradasScreen` no
  cambió, pero no se abrió desde este camino.
- **El recorrido en dos PCs** (etapa 5 del plan): un PIN creado en otra PC y la subida de lo entregado se probaron con reemplazos, no con la nube real.
- **El menú ENTRADAS del panel de verdad:** en la ventana de prueba el panel es uno mínimo. Se comprobó leyendo el archivo.
- **Una tablet o un celular de verdad.** Hay un test con una pantalla de 360 px.

## Lo pendiente, en orden

1. **Entradas, etapas 4 a 6** (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`): la entrega según los permisos, "que pase por caja" con el monto, el aviso en
   vivo, anular solo el jefe y la prueba en dos PCs. Antes, la sección 7 del plan: la pregunta 3 (¿ve cuánto debe?) está sin contestar; se recomienda que sí.
2. **La app de hoy en una tablet** (etapa 0 del módulo de barra): hace falta un Android conectado y una clave de firma propia.
3. **La impresora y el plan de la barra:** ya llegó y el plan está aprobado (`docs/PLAN_BARRA_2026-11-03.md`). Este orden quedó viejo: va primero la barra, y
   Entradas es su etapa 11.
4. **Publicar**, cuando el usuario diga.
