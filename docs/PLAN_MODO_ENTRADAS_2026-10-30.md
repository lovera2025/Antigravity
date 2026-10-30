# Plan: MODO ENTRADAS, operadores con PIN que solo entregan entradas

Fecha: 30-oct-2026. Rama: `feature/v4.6-cierre-por-sesiones`. **Plan para revisar: no programar sin el OK del
usuario** (ver las preguntas de la sección 7).

Leer antes: `CLAUDE.md` ("Roles y permisos", "El retiro de entradas"), `caja_sesiones/providers/app_role_provider.dart`,
`caja_sesiones/widgets/role_gate_screen.dart`, `eventos/retiro_entradas_screen.dart` y `eventos/services/retiro_entradas.dart`.

## 1. De dónde sale (mensaje del usuario, 30-oct)

> "Agregar otra sección con otros permisos: en modo jefe se podrá agregar a otras personas con un PIN, pero ya no
> para caja sino para vender entradas solamente. Que me muestre eso cuando se loguea, para las entradas, y si no le
> permite entregar esas entradas pasa a la sección de caja a saldar todo."

Lectura de este plan (a confirmar en la sección 7):
- "Vender entradas" es **entregar** las entradas y pulseras en la oficina (la pantalla de Retiro de entradas que ya
  existe, v72). Las entradas ya están pagas con el contrato; no se cobra nada nuevo en ese mostrador.
- "Pasa a la sección de caja" es que **la familia va a la caja** (otra persona, con su PIN de caja) a saldar lo que
  debe. El de entradas no cobra.

## 2. Cómo está hoy (leído en el código y en la nube, 30-oct)

- **La entrada a la app:** después del login de Supabase, `RoleGateScreen` ofrece **MODO JEFE** (PIN maestro) y
  **MODO CAJA** (PIN del operador, tabla `operadores_caja`). `AppRoleKind` es `none / jefe / caja`. Los dos van al
  `DashboardScreen`; modo caja ve menos cosas.
- **Los operadores** se crean en el menú → OPERADORES DE CAJA (`OperadoresCajaScreen`, solo modo jefe). El PIN se
  guarda **en texto** (ya anotado en la auditoría de seguridad).
- **Retiro de entradas** (`RetiroEntradasScreen`) se abre desde ENTRADAS en la barra de la fiesta. Bloquea la entrega
  (`RetiroEntradas.bloqueo`) si:
  - **debe** algo (cuotas, mesas o sillas extra, o mora);
  - la ficha y los pagos no coinciden;
  - no tiene mesa, o sus mesas no coinciden con la cuenta;
  - tiene más personas con cena que lugares.
- Con deuda, el diálogo de entrega ofrece **IR A COBRAR** (`IrACobrar`), que abre el cobro de siempre. Cobrar pide una
  caja abierta (`sesionCajaIdParaCobro`).
- **Cuando la caja cobra en otra PC, la pantalla de entradas se destraba sola**: ya escucha `pagos_contrato_alumno`,
  `contratos_alumnos` y `entradas_retiro` cuando bajan (`_tablasQueMiro`).
- La entrega anota quién la hizo (`entradas_retiro.entregado_por`, con `quienOpera`).
- En la nube, `operadores_caja`, `sesiones_caja` y `entradas_retiro` tienen RLS con política solo para
  `authenticated`.

## 3. Lo que se agrega

### 3a. Los operadores de entradas (modo jefe)

- El menú OPERADORES DE CAJA pasa a llamarse **OPERADORES**, con dos pestañas: **Caja** (lo de hoy, sin cambios) y
  **Entradas**: nombre, PIN, activo. Doble llave de modo jefe, como todo lo que da permisos.
- **Tabla aparte `operadores_entradas`**, no una columna nueva en `operadores_caja`. Motivo: una PC con la 6.2.1
  bajaría la fila, no conocería la columna, y **ese PIN entraría como caja**. Con una tabla aparte, una PC vieja no
  conoce a esos operadores y no los deja entrar: falla cerrada.
  - Columnas: `id` (uuid), `nombre`, `pin_hash`, `pin_sal`, `activo`, `created_at`, `updated_at`.
  - **El PIN no se guarda en texto:** SHA-256 de sal + PIN. Se compara en la PC, así que anda sin internet. Los PIN de
    caja siguen como están (es otro pendiente).
  - Un PIN nuevo no puede repetir uno de caja, uno de entradas ni el maestro: si no, `RoleGateScreen` no sabría a
    quién dejar entrar.
  - "Borrar" es `activo = false`, nunca un DELETE. Va en `_tablasSinRevisarBorrados`, con el motivo.

### 3b. MODO ENTRADAS en la entrada a la app

- `RoleGateScreen` suma un tercer botón, **MODO ENTRADAS**, con el mismo diálogo del PIN.
- `AppRoleKind.entradas` y `AppRoleNotifier.loginEntradas(pin)`. Igual que `loginCaja`, cierra el modo jefe
  (`adminAuth.logout()`). **No abre caja ni late.**
- `_RoleRouter` (`main.dart`): con `entradas`, va a **`EntradasHomeScreen`**, nunca al `DashboardScreen`.
- **`EntradasHomeScreen`**: arriba "ENTRADAS · NOMBRE" y SALIR. Abajo, las fiestas masivas que vienen, por fecha.
  Tocar una abre su `RetiroEntradasScreen` **en modo entradas**. No hay otro camino a otra pantalla.

### 3c. La pantalla de entradas en modo entradas

`RetiroEntradasScreen` recibe `onCobrar` y `onEditarAlumno` **opcionales**. Desde `EntradasHomeScreen` van en null:
- **Con deuda**, en lugar de IR A COBRAR, el diálogo dice: **"Debe $X. Que pase por caja a saldar todo; cuando
  pague, la entrega se destraba sola."** El monto sale de `DeudaAlumno.total`, el mismo que ve la caja.
- **Los otros bloqueos** (cuenta que no coincide, sin mesa, mesas que no coinciden, no entran) dicen lo de hoy, con
  "pedile al jefe que la revise", y sin botón de editar.
- **Entregar** queda igual (tramos del talonario, quién retira y el motivo si no es familiar). `entregado_por` lleva el
  nombre del operador de entradas: `quienOperaDe` lo tiene que conocer.
- **ANULAR ENTREGA:** ver la pregunta 3.
- La planilla de entrega se puede imprimir desde ahí (lo de hoy).

### 3d. Lo que no cambia

- La caja, los cobros, el cierre y el arqueo. `sesionCajaIdParaCobro` ya rechaza a quien no es caja ni jefe: aunque
  algo quedara mal conectado, **el de entradas no puede cobrar**. Un test lo deja escrito.
- `entradas_retiro`, `RetiroEntradas` (las reglas del bloqueo) y la pantalla en modo jefe y caja.
- `contratos_alumnos`: ninguna columna.

## 4. Datos y nube

- **Local v76:** `CREATE TABLE IF NOT EXISTS operadores_entradas`, con copia antes de migrar
  (`copiaAntesDeMigrar`) y `tool/verificar_migracion_v76_test.dart` sobre una copia de la base real (con la app
  cerrada: se le pide al usuario).
- **Nube:** `supabase/migrations/2026110x_operadores_entradas.sql`:
  - `CREATE TABLE IF NOT EXISTS`, trigger de `updated_at`, sin CHECK, sin clave foránea;
  - RLS prendido, con la misma política que `operadores_caja` (solo `authenticated`);
  - el ROLLBACK comentado arriba y las consultas de verificación al final.
  - **Se corre antes de instalar, con el OK del usuario en el momento.**
- Sync: entra en la lista de tablas que bajan y suben, como `operadores_caja`.

## 5. Reglas que hay que respetar

- Crear, cambiar o desactivar un operador de entradas: doble llave de modo jefe (`kSoloEnModoJefe` y
  `_frenaSinModoJefe()`).
- Un test que monte `_RoleRouter` con `entradas` y falle si aparece el `DashboardScreen`.
- Un test que lea `EntradasHomeScreen` y `RetiroEntradasScreen` y falle si en modo entradas aparece un camino al
  cobro o a editar al alumno.
- `test/borrados_de_otra_pc_test.dart` tiene que ver la tabla nueva.
- `flutter analyze` y los tests, en la PC.

## 6. Etapas (cada una cierra sola, con commit)

1. **Tabla, modelo y repositorio** (`operadores_entradas`, v76, el hash del PIN), sus tests y el SQL (sin correr).
2. **OPERADORES con dos pestañas**: alta, cambio de PIN, activar o desactivar, y que los PIN no choquen.
3. **MODO ENTRADAS**: el botón, `loginEntradas`, `AppRoleKind.entradas`, `_RoleRouter` y `EntradasHomeScreen`.
4. **La pantalla en modo entradas**: el aviso "que pase por caja", sin cobrar ni editar, `entregado_por` con su
   nombre.
5. **Prueba de punta a punta** en dos PCs: entradas en una y caja en la otra; la familia debe, va a caja, paga, y la
   entrega se destraba en la primera.
6. Migración probada, versión, CONTEXTO, CLAUDE.md, instalador. El SQL antes de instalar.

## 7. Preguntas para el usuario

1. **¿"Vender" es entregar?** Este plan supone que en ese mostrador solo se entregan las entradas que ya están en el
   contrato. Si también se venden entradas o sillas sueltas, se cobra: entonces es una caja (pregunta 2).
2. **Cuando no puede entregar porque debe:**
   - **A (recomendado):** la pantalla dice "Debe $X, que pase por caja" y la familia va a la caja (otra persona). El
     de entradas no toca plata.
   - **B:** el de entradas cobra él mismo esa deuda. Para eso necesita abrir su caja, con cambio inicial y arqueo al
     cerrar: es un operador de caja que además entrega.
   - **C:** como A, y además la PC de la caja muestra "Viene a saldar: FAMILIA, $X". Es más trabajo (un aviso entre
     PCs).
3. **¿Puede ANULAR una entrega?** Recomiendo que no: queda para el jefe (y para caja, como hoy).
4. **¿Ve cuánto debe la familia?** Recomiendo que sí, para decírselo. La pantalla ya tiene "ocultar montos" para quien
   no quiera mostrarlo.
5. **¿Todas las fiestas masivas, o el jefe elige cuáles ve cada operador?** Recomiendo todas: es más simple, y cada
   noche es una escuela.
