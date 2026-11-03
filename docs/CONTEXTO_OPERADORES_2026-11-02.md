# Operadores con permisos (programado, SIN PUBLICAR)

2-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Plan: `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 1 a 3. El orden de todo:
`docs/HOJA_DE_RUTA_2026-11-02.md`, paso 3.

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
3. **La impresora y el plan de la barra**, cuando la impresora esté.
4. **Publicar**, cuando el usuario diga.
