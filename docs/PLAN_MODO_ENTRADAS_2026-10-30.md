# Plan: operadores con permisos (Caja, Entradas), un PIN y las opciones que le tocan

Fecha: 30-oct-2026. Rama: `feature/v4.6-cierre-por-sesiones`. **Plan para revisar: no programar sin el OK del
usuario** (ver las preguntas de la sección 7).

Leer antes: `CLAUDE.md` ("Roles y permisos", "El retiro de entradas"), `caja_sesiones/providers/app_role_provider.dart`,
`caja_sesiones/widgets/role_gate_screen.dart`, `eventos/retiro_entradas_screen.dart` y `eventos/services/retiro_entradas.dart`.

## 1. De dónde sale (mensajes del usuario, 30-oct)

> "Agregar otra sección con otros permisos: en modo jefe se podrá agregar a otras personas con un PIN, pero ya no
> para caja sino para vender entradas solamente. Que me muestre eso cuando se loguea, para las entradas, y si no le
> permite entregar esas entradas pasa a la sección de caja a saldar todo."

> "¿No deberíamos fusionar todo y elegir qué es lo que corresponde, más profesional? Fusionar, y se despliegan las
> opciones."

**Decidido el 30-oct:** no un modo aparte con su propia lista, sino **una sola lista de operadores, cada uno con sus
permisos**. Al entrar con su PIN, cada uno ve solo las opciones que tiene.

Lectura de este plan (a confirmar en la sección 7): "vender entradas" es **entregar** las entradas y pulseras en la
oficina (la pantalla de Retiro de entradas que ya existe, v72). Ya están pagas con el contrato.

## 2. Cómo está hoy (leído en el código y en la nube, 30-oct)

- **La entrada a la app:** después del login de Supabase, `RoleGateScreen` ofrece **MODO JEFE** (PIN maestro) y
  **MODO CAJA** (PIN del operador, tabla `operadores_caja`). `AppRoleKind` es `none / jefe / caja`. Los dos van al
  `DashboardScreen`; modo caja ve menos cosas.
- **Los operadores** se crean en el menú → OPERADORES DE CAJA (`OperadoresCajaScreen`, solo modo jefe). El PIN se
  guarda **en texto** (ya anotado en la auditoría de seguridad). En la PC, `sesiones_caja.operador_id` tiene clave
  foránea a `operadores_caja`.
- **Retiro de entradas** (`RetiroEntradasScreen`) se abre desde ENTRADAS en la barra de la fiesta. Bloquea la entrega
  (`RetiroEntradas.bloqueo`) si:
  - **debe** algo (cuotas, mesas o sillas extra, o mora);
  - la ficha y los pagos no coinciden;
  - no tiene mesa, o sus mesas no coinciden con la cuenta;
  - tiene más personas con cena que lugares.
- Con deuda, el diálogo de entrega ofrece **IR A COBRAR** (`IrACobrar`). Cobrar pide una caja abierta
  (`sesionCajaIdParaCobro`).
- **Cuando la caja cobra en otra PC, la pantalla de entradas se destraba sola**: ya escucha `pagos_contrato_alumno`,
  `contratos_alumnos` y `entradas_retiro` cuando bajan (`_tablasQueMiro`).
- La entrega anota quién la hizo (`entradas_retiro.entregado_por`, con `quienOpera`).
- En la nube, `operadores_caja`, `sesiones_caja` y `entradas_retiro` tienen RLS con política solo para
  `authenticated`.

## 3. Lo que se agrega

### 3a. OPERADORES, con permisos (modo jefe)

- El menú OPERADORES DE CAJA pasa a llamarse **OPERADORES**. Una sola lista; en cada uno, nombre, PIN, activo y sus
  **permisos**, con casillas:
  - **Caja**: cobrar, abrir y cerrar caja (lo de hoy);
  - **Entradas**: entregar entradas y pulseras.
  - **Puede quedar sin ninguno** (decidido el 30-oct): el jefe carga a la persona con su nombre y PIN y le da los
    permisos después. Hasta entonces, al entrar le sale **"Te faltan permisos: pedíselos al jefe"** y no pasa de ahí.
  - La lista queda abierta a otros permisos (la barra, por ejemplo), pero este plan suma solo Entradas.
- Doble llave de modo jefe, como todo lo que da permisos.
- **Los operadores siguen en `operadores_caja`** (la caja y sus sesiones los necesitan ahí, con su clave foránea).
  **Los permisos van en una tabla aparte, `permisos_operador`**: una fila por operador, con id fijo (el del operador),
  `caja` y `entradas` (0/1), `updated_at`.
  - **No es una columna nueva en `operadores_caja`**: esa fila se reescribe entera al editar y al bajar, y una PC más
    vieja la volvería a subir sin la columna (la misma trampa de `contratos_alumnos`).
  - **Sin fila, el operador es de caja sola**: los de hoy siguen igual, sin tocar nada. **Con fila y las dos casillas
    en 0, no tiene permisos.** Son dos cosas distintas y cada una lleva su test.

### 3b. La entrada a la app: un PIN y se despliegan las opciones

- `RoleGateScreen`: **MODO JEFE** queda igual. **MODO CAJA** pasa a ser **OPERADOR**, con el mismo diálogo del PIN.
- Con el PIN, según los permisos de ese operador:
  - **ninguno**: "Te faltan permisos: pedíselos al jefe", y vuelve a la pantalla de entrada;
  - **uno solo**: entra directo (Caja, con "Abrir caja" como hoy; o Entradas);
  - **los dos**: se despliegan **CAJA** y **ENTRADAS**, y elige.
- `AppRoleKind` suma `entradas`; `loginCaja` pasa a `loginOperador(pin)` y deja elegir. Entradas **no abre caja ni
  late**.
- `_RoleRouter` (`main.dart`): con `entradas`, va a **`EntradasHomeScreen`**, nunca al `DashboardScreen`.
- **`EntradasHomeScreen`**: arriba "ENTRADAS · NOMBRE" y SALIR. Abajo, las fiestas masivas que vienen, por fecha.
  Tocar una abre su `RetiroEntradasScreen` en modo entradas.
  - Si además tiene Caja: **PASAR A CAJA**, que abre su caja (o la retoma) y lo lleva al dashboard de caja. Desde la
    caja, **ENTRADAS** lo vuelve a llevar. Sin cerrar sesión ni volver a poner el PIN.

### 3c. Cuando no se puede entregar porque debe

Depende de los permisos de quien está en el mostrador:
- **Con Caja también:** el diálogo ofrece **COBRAR** como hoy; si no tiene la caja abierta, se la pide antes. Al
  terminar vuelve a la entrega, ya destrabada.
- **Solo Entradas:** en lugar de COBRAR dice **"Debe $X. Que pase por caja a saldar todo; cuando pague, la entrega se
  destraba sola."** El monto sale de `DeudaAlumno.total`, el mismo que ve la caja.

Los otros bloqueos (cuenta que no coincide, sin mesa, mesas que no coinciden, no entran) dicen lo de hoy, con
"pedile al jefe que la revise", y **sin editar al alumno** en modo entradas.

Entregar queda igual (tramos del talonario, quién retira y el motivo si no es familiar). `entregado_por` lleva el
nombre del operador: `quienOperaDe` tiene que conocer el modo entradas.

### 3d. Lo que no cambia

- La caja, los cobros, el cierre y el arqueo. `sesionCajaIdParaCobro` ya rechaza a quien no es caja ni jefe: en modo
  entradas no se puede cobrar aunque algo quede mal conectado. Un test lo deja escrito.
- `entradas_retiro`, `RetiroEntradas` (las reglas del bloqueo) y la pantalla en modo jefe.
- `contratos_alumnos` y `operadores_caja`: ninguna columna.

## 4. Datos, nube y convivencia

- **Local v76:** `CREATE TABLE IF NOT EXISTS permisos_operador`, con copia antes de migrar (`copiaAntesDeMigrar`) y
  `tool/verificar_migracion_v76_test.dart` sobre una copia de la base real (con la app cerrada: se le pide al usuario).
- **Nube:** `supabase/migrations/2026110x_permisos_operador.sql`:
  - `CREATE TABLE IF NOT EXISTS`, trigger de `updated_at`, sin CHECK, sin clave foránea;
  - RLS prendido, con la misma política que `operadores_caja` (solo `authenticated`);
  - el ROLLBACK comentado arriba y las consultas de verificación al final.
  - **Se corre antes de instalar, con el OK del usuario en el momento.**
- Sync: baja y sube como `operadores_caja`. Nunca se borra una fila: va en `_tablasSinRevisarBorrados`, con el motivo.
- **Convivencia con la 6.2.1:** una PC vieja no conoce los permisos y deja entrar a cualquier operador como caja.
  **Regla: no crear operadores sin Caja (solo Entradas, o sin permisos) hasta que las tres PCs tengan la versión
  nueva** (como "no congelar a nadie" en la 6.2.1). La pantalla de OPERADORES lo avisa al destildar Caja.
- El PIN sigue en texto, como hoy. Guardarlo cifrado es otro pendiente: no entra acá para no tocar el login de caja.

## 5. Reglas que hay que respetar

- Crear, cambiar o desactivar un operador o sus permisos: doble llave de modo jefe (`kSoloEnModoJefe` y
  `_frenaSinModoJefe()`).
- Un test que monte `_RoleRouter` con `entradas` y falle si aparece el `DashboardScreen`.
- Un test que lea `EntradasHomeScreen` y `RetiroEntradasScreen` y falle si, sin permiso de Caja, aparece un camino al
  cobro o a editar al alumno.
- Sin fila de permisos, el operador entra como caja, igual que hoy (test). Con la fila en 0, no entra (test).
- `test/borrados_de_otra_pc_test.dart` tiene que ver la tabla nueva.
- `flutter analyze` y los tests, en la PC.

## 6. Etapas (cada una cierra sola, con commit)

1. **Los permisos**: tabla `permisos_operador` (v76), modelo, repositorio, "sin fila = caja", tests y el SQL (sin
   correr).
2. **OPERADORES**: una lista, con las casillas Caja y Entradas, y el aviso de la convivencia.
3. **La entrada**: OPERADOR con su PIN, las opciones que se despliegan, `AppRoleKind.entradas`, `_RoleRouter` y
   `EntradasHomeScreen`, con PASAR A CAJA y ENTRADAS para quien tiene los dos.
4. **La entrega según los permisos**: COBRAR con Caja, "que pase por caja" sin Caja, sin editar al alumno,
   `entregado_por` con su nombre.
5. **Prueba de punta a punta**, en dos PCs: uno solo de Entradas en una, la caja en la otra; la familia debe, va a la
   caja, paga, y la entrega se destraba sola. Y uno con los dos permisos en una sola PC.
6. Migración probada, versión, CONTEXTO, CLAUDE.md, instalador. El SQL antes de instalar.

## 7. Preguntas para el usuario

1. **¿"Vender" es entregar?** Este plan supone que en ese mostrador solo se entregan las entradas que ya están en el
   contrato. Si también se venden entradas o sillas sueltas, eso se cobra, y lo hace quien tenga Caja.
2. **¿Puede anular una entrega quien tiene solo Entradas?** Recomiendo que no: queda para el jefe y para caja.
3. **¿Ve cuánto debe la familia?** Recomiendo que sí, para decírselo. La pantalla ya tiene "ocultar montos".
4. **¿Ve todas las fiestas masivas, o el jefe elige cuáles?** Recomiendo todas: es más simple, y cada noche es una
   escuela.
