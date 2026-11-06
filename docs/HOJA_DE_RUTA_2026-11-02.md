# Hoja de ruta, 2-nov-2026: qué sigue y en qué orden

Para arrancar en Claude Code. Cada paso tiene su plan en `docs/`; acá está solo el orden, por qué, y con qué frase
arrancar cada uno. **Antes de cada paso:** `git pull`, y en la PC `flutter analyze` y `flutter test` en verde.

Las fechas que mandan: **las fiestas son en diciembre** (Puerto Viejo, Técnica, Gregoria Morales y la Normal el 1-dic,
Buena Vista el 12-dic), los **sorteos de mesas son antes**, y **la barra debuta el 4-dic**.

## Lo que ya quedó hecho hoy, sin programar

- **La foto de la mora** en la nube (`supabase/mora_fotos.sql`, tabla `mora_fotos`): la primera, sacada el 2-nov con
  643 alumnos. **Antes y después de cada versión se saca una** y se compara (CLAUDE.md, sección SQL).
- **El registro de cada cambio a la mora** (`supabase/mora_cambios.sql`, tabla `mora_cambios` y su trigger, probados):
  cuando una mora reviva, ahí está la escritura que lo hizo. Es lo primero que se mira. Ya anotó su primer cobro real:
  ESPINOZA, FRANCISCO, el mismo 2-nov. Un cobro que no toca la mora no se anota, y está bien.
- **Todas las PCs en 6.2.1** (confirmado el 2-nov).
- **La base comparada con la foto, el 2-nov:** los mismos 643 alumnos y los mismos 16 congelados, sin ninguna mora
  revivida. Los únicos cambios son dos cobros normales.

## Dónde estamos (4-nov, noche)

| Paso | Estado |
|---|---|
| 1. La impresora | **Hecha el 3-nov:** papel mirado (acentos con la tabla 850, renglones por palabras, QR nativo, el isotipo); imprime desde la PC y desde un celular Android, y se conecta sola. `docs/CONTEXTO_BARRA_2026-11-02.md` |
| 2. El plano | **PUBLICADO el 4-nov en la 6.3.0** (y la 6.3.1 encima, con las entradas sin cargo solo de la mesa del contrato). **Instalado en las tres PCs**; la foto de la mora "después" dio vacía. `docs/CONTEXTO_v6.3.0_2026-11-02.md`, `docs/CONTEXTO_v6.3.1_2026-11-04.md` |
| 3. Operadores | Etapas 1 a 3 **publicadas apagadas** en la 6.3.0, con su SQL (v76) corrido. Hasta la próxima versión: nadie con Entradas, nadie sin Cobros. `docs/CONTEXTO_OPERADORES_2026-11-02.md` |
| 3b. El tótem con el salón y las sillas de la noche (5 y 6-nov, antes de la barra 5) | **Hecho en la rama.** El tótem (5-nov: salón entero y claro, el nombre que salta y se acomoda en la pista, los segundos en Personalizar y a mano en Recepción y en el celular) y **las sillas de la noche** (6-nov: la puerta anota cada silla con el vale de la barra, un solo candado para la PC y los celulares, y la traba en la oficina por fiesta sorteada). Dos SQL nuevos sin correr; falta probarlo con celulares de verdad. `docs/CONTEXTO_v6.4.0_2026-11-06.md` |
| 4. La barra | Etapas 1 a 4 **publicadas apagadas** en la 6.3.0, con su SQL (v77) corrido. **En la rama, sin publicar:** el stock de toda la fiesta, los dos diseños y 74 fotos de tragos y marcas. Sigue la 5 (reimprimir, anular). La tabla de lo que queda, en "Para retomar en otro chat" de `docs/CONTEXTO_BARRA_2026-11-02.md`. **Decisiones del 5-nov para sus etapas:** "Silla extra" como producto (la puerta suma la silla con el vale), la tilde "Encargada de barra", el selector COBROS · BARRA · ENTRADAS en el cierre de caja y una notebook central para la barra (en el CONTEXTO del tótem y las sillas) |
| 5. Entradas | Pendiente; va después de la barra (etapa 11 del plan de la barra) |
| Publicar | **Decidido el 4-nov: nada más hasta terminar todas las etapas**, y después una sola versión, preguntando. **6-nov: sin apuro de fecha** ("cuando salga nomás, ahora hay más tiempo") |

**Lo que sigue (6-nov):** las sillas de la noche quedaron hechas (`docs/CONTEXTO_v6.4.0_2026-11-06.md`); sigue
la etapa 5 de la barra (reimprimir con freno, anular también la cajera, el ticket con precios si lo piden) y probar si la impresora avisa que
le falta papel. Los SQL de v76 y v77 ya están en la nube: lo nuevo que necesite la nube va en tablas nuevas.

> Frase para Claude Code: "Seguimos con la barra: leé 'Para retomar en otro chat' de docs/CONTEXTO_BARRA_2026-11-02.md y pasame el plan corto de la
> etapa 5 antes de programar."

## El orden

**Publicar, solo con todo terminado y preguntándole antes al usuario** (2-nov). Mientras tanto se programa y se sube a
la rama de desarrollo, que no llega a las PCs.

### 1. La impresora de la barra (rama `feature/barra-impresora`, ya subida)

**Hecho el 3-nov** (`docs/CONTEXTO_BARRA_2026-11-02.md`). **Llegó el 2-nov: es una TP-POS58 por Bluetooth de bajo consumo, no una Global.**
Lo que sigue de este paso quedó viejo y queda como historia: la prueba no usó esa rama ni esos paquetes, sino `tool/impresora_prueba.dart` en
la rama de desarrollo, que corre en Windows y en Android.

Es una prueba de hardware, no programación: `tool/impresora_prueba.dart`, con los dos paquetes y los permisos de
Android. Emparejar la Global, correr el arnés en un Android, tocar TICKET, ACENTOS, ANCHO y QR, y mirar el papel.
Decide tres cosas del módulo: la tabla de caracteres, cuántas letras entran por renglón, y si el QR nativo sale. Al
arnés le falta un botón LOGO: el ticket lleva el logo de Junior Eventos, y en la Global va como imagen.
**Antes de pasar la rama a la de desarrollo, un `flutter build windows`**: `print_bluetooth_thermal` también se
compila para Windows y no tiene que molestar al programa de escritorio.

> Frase para Claude Code: "Estoy en la rama feature/barra-impresora con la Global emparejada. Corré `flutter analyze` y
> después `flutter run -d <android> -t tool/impresora_prueba.dart`. Si analyze marca algo de esc_pos_utils_plus o
> print_bluetooth_thermal, arreglalo antes."

### 2. El plano antes de los sorteos (`docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md`)

**Programado el 2-nov, sin publicar: `docs/CONTEXTO_v6.3.0_2026-11-02.md`. Falta que el usuario lo mire y diga si se publica.**
Los sorteos de verdad son en noviembre y hoy Puerto Viejo tiene los números mezclados. **El jefe eligió la serpentina el 2-nov.**
Son seis cosas, con la tabla "lo acordado → el test" en la sección 5b:
1. los números se ordenan solos al guardar el salón (antes del sorteo);
2. el aviso de los números que no siguen el salón;
3. la barra de Acomodar reacomoda en vivo antes del sorteo y estira después;
4. juntas y separadas marcadas en el plano, también en papel;
5. "lejos" con qué tan lejos (cerca, a unas mesas, bien lejos), con la medición de antes y después;
6. el recorrido entero como test.
**Sin SQL.** Una versión (propuesta: 6.3.0).

**Si aprieta el tiempo:** del 2-nov al 4-dic hay 32 días para los pasos 2, 3 y 4. Lo que los sorteos necesitan son las
etapas 1 a 3 del plan, con el recorrido, las muestras y la versión. Las etapas 4 a 6 se pueden pasar a otra versión; lo
decide el usuario cuando se llegue.

> Frase: "Programá docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md en el orden de su sección 5, una etapa por commit, con los
> tests de la sección 5b y roturas a propósito. No pases de etapa con un test en rojo. Al terminar, muestras."

### 3. Operadores con permisos (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 1 a 3)

**Programado el 2-nov, sin publicar y con el SQL sin correr: `docs/CONTEXTO_OPERADORES_2026-11-02.md`.** La migración v76 ya se probó sobre una copia de la base real. Lo que queda antes de usarlo es el paso 5.

La base de Entradas y de Barra: una sola lista de OPERADORES con las casillas **Cobros, Entradas y Barra** (nombres
elegidos el 2-nov: Cobros es la caja de cuotas de los eventos masivos, Barra es la caja de barra, y nada dice "Caja" a
secas); con el PIN se despliegan las opciones; cargado sin permisos no entra. **Una tabla nueva** (`permisos_operador`,
local v76 y nube, con la migración probada sobre una copia de la base real) y el registro de quién dio qué permiso.
**Los operadores de hoy (Maxi, Juan) no se tocan:** siguen de Cobros con su mismo PIN, sin volver a darles nada.
**Regla:** no crear operadores sin Cobros hasta que las tres PCs tengan la versión.

> Frase: "Programá las etapas 1 a 3 de docs/PLAN_MODO_ENTRADAS_2026-10-30.md (la tabla permisos_operador con su SQL
> sin correr, OPERADORES con las casillas Cobros/Entradas/Barra, y la entrada con el PIN que despliega las opciones).
> Con los tests de la sección 5. La migración v76 se prueba sobre una copia de mi base, con la app cerrada: avisame
> cuando la necesites."

### 4. El módulo de barra (`docs/PLAN_BARRA_2026-11-03.md`, aprobado el 2-nov)

Para el 4-dic. Lo decidido el 2-nov: la app instalada en las tablets Android, logueada una
vez con la cuenta de la empresa; la cajera entra con su PIN (permiso Barra), elige la fiesta, abre **su caja de
barra** (aparte de la de cuotas), conecta su Global y vende; cada tablet guarda en su base y sube cuando hay internet;
BARRA en modo jefe (PC y web del iPhone) arma la lista de precios y ve cuánto hizo cada caja (efectivo,
transferencia, mixto), por sede. Tablas nuevas (catálogo, precios por fiesta, cajas de barra, ventas), con quién,
cuándo y desde qué dispositivo. Las tablets se preparan en la oficina con internet ("Lista para trabajar sin internet").

**Etapa 0, antes de escribir el plan: la app de hoy corriendo en una tablet.** Hoy ninguna tablet tiene la app: los
celulares y tablets de la puerta usan la web, y Android nunca se publicó (último cambio en mayo, firma de debug). La
barra sería el primer Android en producción de una 6.x, y es el riesgo más grande para el 4-dic. Hay que verla
logueada, con una fiesta bajada y Recepción abierta sin internet. Y hace falta una clave de firma propia: con la de
debug, cambiar de PC de compilación obliga a desinstalar.

**Lo decidido con las maquetas (2-nov, aprobadas por el usuario):**
- **BARRA** es otra tarjeta del centro de comando, solo en modo jefe. La cajera no pasa por ahí: su PIN la lleva directo.
- **Vender:** se tocan los productos y se arma la cuenta. **Cobrar:** efectivo con "recibe" y vuelto; transferencia con
  la tilde "vi el comprobante"; mixto partido en dos y corregible. **Cerrar la caja:** pide el efectivo contado y anota
  la diferencia, sin corregir nada.
- **Responsive, en tablet y celular:** las pantallas siguen `CortesPantalla` (600 y 1.024 px, como Recepción). Celular:
  productos arriba y la cuenta abajo. Tablet: lado a lado. PC del jefe: catálogo, precios y cajas.
- **El catálogo:** BARRA → Catálogo carga los productos una vez (nombre y categoría). Por fiesta se eligen y se les pone
  precio. Las tablets bajan esa lista al prepararse.
- **El ticket** lleva el logo de Junior Eventos (`assets/icons/2.png`), el nombre y el valor de cada cosa, el total, el
  medio de pago, el número y el QR. Sale a la Global por Bluetooth y también como PDF, del mismo modelo.
- **Todo PDF de la barra sale en 58 mm y en A4:** el ticket, la lista de precios y el cierre de caja. En modo jefe se
  elige el tamaño al imprimir; la tablet manda el ticket a la Global y guarda el PDF.
- **El PIN tiene que andar en cualquier PC o tablet sin que entre el jefe.** Si el PIN no está acá y hay internet, se
  bajan operadores y permisos y se prueba otra vez. La tablet preparada en la oficina los trae bajados.

> Frase (cuando la impresora haya pasado): "Escribí el plan del módulo de barra como docs/PLAN_BARRA_<fecha>.md con lo
> decidido en docs/HOJA_DE_RUTA_2026-11-02.md (paso 4) y lo que dio la prueba de la impresora. Sin programar hasta mi
> OK."

### 5. Entradas (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 4 a 6)

La entrega según los permisos, el aviso en vivo "pagó: ya podés entregar" cuando cobra la caja, anular solo el jefe.
La **venta de entradas sueltas** (sección 8) queda para cuando el jefe la termine de definir; es lo último.

### Con cada versión

Nada de esto arranca sin preguntarle al usuario (2-nov).

1. Foto de la mora "antes de X.Y.Z".
2. Los SQL de la versión, con el OK del usuario.
3. Release, web e instalar las tres PCs el mismo día.
4. Foto "después de X.Y.Z" y la comparación: tiene que dar vacío. Si no, restaurar con la foto y mirar
   `mora_cambios` para ver qué escritura fue.
5. CONTEXTO de la versión y CLAUDE.md al día.
