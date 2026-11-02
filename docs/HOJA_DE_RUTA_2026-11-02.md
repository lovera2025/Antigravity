# Hoja de ruta, 2-nov-2026: qué sigue y en qué orden

Para arrancar en Claude Code. Cada paso tiene su plan en `docs/`; acá está solo el orden, por qué, y con qué frase
arrancar cada uno. **Antes de cada paso:** `git pull`, y en la PC `flutter analyze` y `flutter test` en verde.

Las fechas que mandan: **las fiestas son en diciembre** (Puerto Viejo, Técnica, Gregoria Morales y la Normal el 1-dic,
Buena Vista el 12-dic), los **sorteos de mesas son antes**, y **la barra debuta el 4-dic**.

## Lo que ya quedó hecho hoy, sin programar

- **La foto de la mora** en la nube (`supabase/mora_fotos.sql`, tabla `mora_fotos`): la primera, sacada el 2-nov con
  643 alumnos. **Antes y después de cada versión se saca una** y se compara (CLAUDE.md, sección SQL).
- **El registro de cada cambio a la mora** (`supabase/mora_cambios.sql`, tabla `mora_cambios` y su trigger, probados):
  cuando una mora reviva, ahí está la escritura que lo hizo. Es lo primero que se mira.
- **Todas las PCs en 6.2.1** (confirmado el 2-nov).

## El orden

### 1. La impresora de la barra (rama `feature/barra-impresora`, ya subida)

Es una prueba de hardware, no programación: `tool/impresora_prueba.dart`, con los dos paquetes y los permisos de
Android. Emparejar la Global, correr el arnés en un Android, tocar TICKET, ACENTOS, ANCHO y QR, y mirar el papel.
Decide tres cosas del módulo: la tabla de caracteres, cuántas letras entran por renglón, y si el QR nativo sale.
**Antes de pasar la rama a la de desarrollo, un `flutter build windows`**: `print_bluetooth_thermal` también se
compila para Windows y no tiene que molestar al programa de escritorio.

> Frase para Claude Code: "Estoy en la rama feature/barra-impresora con la Global emparejada. Corré `flutter analyze` y
> después `flutter run -d <android> -t tool/impresora_prueba.dart`. Si analyze marca algo de esc_pos_utils_plus o
> print_bluetooth_thermal, arreglalo antes."

### 2. El plano antes de los sorteos (`docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md`)

Va primero porque los sorteos de verdad son en noviembre y hoy Puerto Viejo tiene los números mezclados. Son seis
cosas, con la tabla "lo acordado → el test" en la sección 5b:
1. los números se ordenan solos al guardar el salón (antes del sorteo);
2. el aviso de los números que no siguen el salón;
3. la barra de Acomodar reacomoda en vivo antes del sorteo y estira después;
4. juntas y separadas marcadas en el plano, también en papel;
5. "lejos" con qué tan lejos (cerca, a unas mesas, bien lejos), con la medición de antes y después;
6. el recorrido entero como test.
**Sin SQL.** Una versión (propuesta: 6.3.0).

> Frase: "Programá docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md en el orden de su sección 5, una etapa por commit, con los
> tests de la sección 5b y roturas a propósito. No pases de etapa con un test en rojo. Al terminar, muestras."

### 3. Operadores con permisos (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 1 a 3)

La base de Entradas y de Barra: una sola lista de OPERADORES con las casillas Caja, Entradas y Barra; con el PIN se
despliegan las opciones; cargado sin permisos no entra. **Una tabla nueva** (`permisos_operador`, local v76 y nube,
con la migración probada sobre una copia de la base real) y el registro de quién dio qué permiso. Los operadores de
hoy siguen siendo de caja sin tocar nada. **Regla:** no crear operadores sin Caja hasta que las tres PCs tengan la
versión.

> Frase: "Programá las etapas 1 a 3 de docs/PLAN_MODO_ENTRADAS_2026-10-30.md (la tabla permisos_operador con su SQL
> sin correr, OPERADORES con las casillas Caja/Entradas/Barra, y la entrada con el PIN que despliega las opciones).
> Con los tests de la sección 5. La migración v76 se prueba sobre una copia de mi base, con la app cerrada: avisame
> cuando la necesites."

### 4. El módulo de barra (plan a escribir después del paso 1)

Para el 4-dic. Lo decidido el 2-nov: la app instalada en las tablets Android (la misma de Recepción), logueada una
vez con la cuenta de la empresa; la cajera entra con su PIN (permiso Barra), elige la fiesta, abre **su caja de
barra** (aparte de la de cuotas), conecta su Global y vende; cada tablet guarda en su base y sube cuando hay internet;
BARRA en modo jefe (PC y web del iPhone) arma la lista de precios y ve cuánto hizo cada caja (efectivo,
transferencia, mixto), por sede. Tres tablas nuevas (precios por fiesta, cajas de barra, ventas), con quién, cuándo
y desde qué dispositivo. Las tablets se preparan en la oficina con internet ("Lista para trabajar sin internet").

> Frase (cuando la impresora haya pasado): "Escribí el plan del módulo de barra como docs/PLAN_BARRA_<fecha>.md con lo
> decidido en docs/HOJA_DE_RUTA_2026-11-02.md (paso 4) y lo que dio la prueba de la impresora. Sin programar hasta mi
> OK."

### 5. Entradas (`docs/PLAN_MODO_ENTRADAS_2026-10-30.md`, etapas 4 a 6)

La entrega según los permisos, el aviso en vivo "pagó: ya podés entregar" cuando cobra la caja, anular solo el jefe.
La **venta de entradas sueltas** (sección 8) queda para cuando el jefe la termine de definir; es lo último.

### Con cada versión

1. Foto de la mora "antes de X.Y.Z".
2. Los SQL de la versión, con el OK del usuario.
3. Release, web e instalar las tres PCs el mismo día.
4. Foto "después de X.Y.Z" y la comparación: tiene que dar vacío. Si no, restaurar con la foto y mirar
   `mora_cambios` para ver qué escritura fue.
5. CONTEXTO de la versión y CLAUDE.md al día.
