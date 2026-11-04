# La 6.3.0: el plano antes de los sorteos

2-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Plan: `docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md`. El orden de todo lo que
sigue: `docs/HOJA_DE_RUTA_2026-11-02.md`.

**Estado (4-nov): en publicación.** Se publica sola, antes que la barra, porque el usuario quería armar el plano el 4-nov y los
sorteos son en noviembre ("una sola versión cuando esté completo" cedió por eso: decisión del usuario el 3-nov). Ver "La
publicación (4-nov)", abajo.

## Qué más lleva la versión, dormido

La rama lleva también **operadores con permisos** (`docs/CONTEXTO_OPERADORES_2026-11-02.md`, etapas 1 a 3) y **la barra, etapas 1 a 4**
(`docs/CONTEXTO_BARRA_2026-11-02.md`). Salen así:
- **MODO CAJA pasa a OPERADOR.** Maxi y Juan entran igual, a Cobros, sin que nadie les dé nada (sin fila de permisos = Cobros solo).
- **En modo jefe, OPERADORES suma las casillas Cobros, Entradas y Barra.** Hasta la próxima versión: **no darle Entradas a nadie**
  (todavía deja anular una entrega: etapas 4 a 6) y **no crear operadores sin Cobros** hasta que las tres PCs tengan la 6.3.0.
- **Barra** se puede tildar pero no sirve: sin catálogo (etapa 7) la cajera no ve ninguna fiesta.
- **La base pasa de la v75 a la v77** (7 tablas nuevas, vacías). `copiaAntesDeMigrar` deja `antes_de_v76.db` o `antes_de_v77.db`.
  La 6.2.1 abre igual una base en la 77: volver atrás es reinstalarla.

## Qué se hizo

| Etapa | Qué cambia para el usuario | Dónde |
|---|---|---|
| 1 y 2 | Sin familias con mesa, los números se ordenan solos al guardar el salón, sin mover ninguna mesa. Un salón ya mezclado se arregla con abrirlo y guardar | `ArmarAMedida.ordenarNumeros`, `EditarArmado.paraGuardar` |
| 3 | El plano avisa cuántos saltos hay si los números no siguen el salón | `PlanoDeLaFiesta._avisoDeSaltos` |
| 4 | La barra de Acomodar: antes del sorteo reacomoda en vivo; después, o en el Canva, estira | `SesionAcomodo.moverLaBarra`, `PanelAcomodar` |
| 5 | Juntas y separadas marcadas en el plano y en papel, con P y A. Toda mesa de una familia separada lleva el apellido y, abajo, "→ la otra mesa". Casilla "Familias con adicional" en pantalla y al imprimir | `FamiliasEnElPlano`, `PintorPlano`, `PlanoPdf` |
| 6 | Al marcar "lejos" se elige qué tan lejos: cerca (viene elegida), a unas mesas o bien lejos. Lo pedido queda en el registro y en la planilla | `DistanciaLejos`, `SorteoConPlano._ordenLejos` |
| 7 | El recorrido entero como test | `test/recorrido_salon_test.dart` |
| 8 | Muestras | `tool/numeros_en_orden_muestra_test.dart` |

## Decisiones que no estaban en el plan

- **El apellido en toda mesa separada** (pedido del usuario el 2-nov, mirando la muestra: "la tercera de GOMEZ" no se sabía de
  quién era). Va en un renglón y la flecha en otro: un apellido largo se corta con "…", y el número de la otra mesa no se puede
  perder.
- **Sin internet no se ordena** (`leidoDeLaNube`). Esa PC no puede saber si la otra ya sorteó, y renumerar debajo de familias
  sentadas sería grave. Se ordena la próxima vez que se guarde con internet, y el aviso lo dice.
- **Con dos hojas la numeración es la serpentina de `acomodar` y `armar`** (la izquierda de A y de B, y la derecha de vuelta),
  no "toda la A y después la B": si no, ordenar cambiaría un salón recién acomodado.
- **El motor recibe un orden, no una regla nueva** (`OrdenLejos`). Reordena las candidatas de una mesa "lejos", sin sacar
  ninguna, así que lo que entra no cambia: `esFactible` y `seCompleta` siguen igual. Sin orden, el motor hace lo de siempre.
- **Sin decir qué tan lejos, es "bien lejos"**, lo de antes: lo usa quien llame al sorteo sin la opción. El diálogo siempre la
  manda, y ahí viene en "cerca".
- **"Lejos" se sigue marcando en el diálogo de SORTEO**, no en la ficha del alumno (lo recomendado en la pregunta 1 del plan).
  Marcarlo antes llevaría una tabla nueva y una migración, y va aparte.

## La medición (`tool/lejos_distancias_test.dart`)

A cuántos lugares (la distancia entre mesas) queda una mesa "lejos". 1.000 sorteos enteros por salón y 200 por división, con
20 familias "1 lejos" (6 en Puerto Viejo). "Sin decir", lo de antes, dio igual que "bien lejos" en todos los casos.

| Salón y modo | Cerca (mediana) | A unas mesas (entre 3 y 6) | Bien lejos (mediana) | Tocándose |
|---|---|---|---|---|
| Normal 138, entero | 2,0 | 98,0 % | 9,4 | 0 |
| Técnica, entero | 2,0 | 99,5 % | 8,6 | 0 |
| Puerto Viejo, entero | 2,0 | 98,2 % | 6,1 | 0 |
| Normal 138, por división | 2,0 | 98,0 % | 8,1 | 0 |
| Puerto Viejo, por división | 2,0 | 79,2 % | 3,2 | 0 |

Puerto Viejo por división da menos porque cada bloque es chico: la mesa no tiene adónde ir a esa distancia. Ahí el sorteo elige
la más cercana a lo pedido y lo dice con el apellido, como pide el plan.

## Cómo mirarlo sin publicar

```bash
flutter run -d windows -t tool/plano_prueba.dart
```

Es la pantalla del plano de verdad, con el plano real de Puerto Viejo y 35 alumnos inventados, sin base ni nube. Lo que se
guarda se queda en esa ventana. No abrir la app completa desde el código: usa la base y la nube de verdad.

## La publicación (4-nov)

Con el OK del usuario ("ahora podemos publicar", y "Sí, dale" para la foto y los SQL).

1. **VENDER de la barra cerrado** (el cambio que había quedado a medias el 3-nov): `c9fc4c0`. La suite entera: 3.400 tests en verde.
2. **La migración v77 sobre una copia de la base real** (`tool/verificar_migracion_v77_test.dart`, la app cerrada): de la v75 a la
   77; las 35 tablas de antes iguales fila por fila (643 alumnos, 4.592 pagos, 16 congelados); las 7 nuevas vacías; el esquema de
   lo de antes igual; la vuelta a la 6.2.1 y de nuevo a la 77 sin cambios; la base real con el mismo SHA-256.
3. **Versión `6.3.0+62`** en `pubspec.yaml` y en el instalador. Novedades: **"El plano, ordenado para los sorteos"**
   (`build/novedades_6.3.0.md`).
4. **Foto de la mora "antes de 6.3.0"**, 13:30: 643 alumnos, 26 congelados (eran 16 el 2-nov: el jefe congeló más con la 6.2.1).
   `foto_id` `1a906a4e-7953-4c59-96c9-192b378d5c82`.
5. **Los dos SQL**, 13:30, por `apply_migration` (`permisos_operador` y `barra`, lo mismo que los archivos del repo). Conteos
   antes y después iguales: 643 contratos, 4.729 pagos, 4 operadores con la misma huella, 209 sesiones, 30 eventos, 16 invitados,
   4 filas de `totem_config`. Las 7 tablas nuevas vacías, con RLS, su policy, un disparador de alta y uno de cambio, y fuera de
   Realtime. La oficina estaba cobrando: ningún pago entró entre los dos conteos.

**Falta:**
1. El instalador, el release y la web.
2. Que el usuario instale las tres PCs (el operario primero) y avise. **El plano se arma desde una PC con la 6.3.0.**
3. Foto "después de 6.3.0" y la comparación de la sección 3: tiene que dar vacío. Si no, mirar `mora_cambios`.

**Convivencia:** una PC con la 6.2.1 abre y guarda un salón ordenado sin problema, pero no ordena al guardar. El plano se toca
desde una PC con la versión nueva. El renglón del sorteo suma `_lejos`, que la 6.2.1 ignora porque empieza con guion bajo.

**La mora no se toca en toda esta versión:** ordenar y sortear escriben `planos_evento`, `sorteos_mesas` y los números de mesa.

**Sin plano también se sortea** (lo preguntó el usuario el 4-nov): SORTEO sin plano es el de siempre, por número de mesa, y la
planilla sale como siempre. Con plano, el sorteo sigue el salón dibujado y el resultado se ve en el plano, en el papel y en el tótem.

## La prueba con el mouse (2-nov, a pedido del usuario, que estaba en el celular)

Claude manejó `tool/plano_prueba.dart` con el mouse, en la PC, sin base ni nube. Se le sumaron a esa ventana el sorteo de verdad
(29 familias que piden justo las 35 mesas, dos "lejos": una cerca y una bien lejos) e IMPRIMIR, que deja el PDF en
`build/plano_prueba`.

| Paso | Resultado |
|---|---|
| Abrir el plano mezclado | Avisa los 13 saltos |
| Mover una mesa y guardar | Pasa de 13 saltos a 1; las mesas no se mueven |
| Lo mismo sin internet | No renumera (ver "Detalles", abajo) |
| La barra, sin soltar y al soltar | Reacomoda en vivo, "Entran las 35", y soltar es un paso de Deshacer |
| Sortear | Cápsulas, aros, P y A; tocar una mesa separada resalta la otra; la casilla apaga y prende |
| Con familias, mover y guardar | Ningún número cambia; la barra pasa a "Separar o juntar", con el motivo |
| Deshacer y guardar | Se ordena de nuevo, del 1 al 35, 1 salto |
| Imprimir en color, en blanco y negro y sin familias | Una hoja A4; se lee en los tres |

**Cuatro errores que los tests y las muestras no veían, los cuatro arreglados con su test y su rotura a propósito:**

1. **En pantalla, acercar no traía nunca el apellido ni la flecha.** El nivel de detalle salía de la escala de "ajustar a la
   pantalla", y el zoom agranda el dibujo por fuera. En un salón con el playón entero la mesa nunca llegaba a los 26 px. Era así
   desde la 6.0.0, aunque el código decía "con zoom como para leer el apellido". Ahora `VistaPlano.zoom`, con
   `NivelDetalle.zoomQueCuenta`, que da pocos valores: el salón se vuelve a pintar solo al cruzar un umbral.
2. **En papel, Puerto Viejo salía sin ningún apellido.** La letra tenía de tope el 52 % del radio de la mesa: 3,5 pt, debajo del
   mínimo de 4,3, y sobraba lugar. Ahora, si hay lugar a lo alto y a lo ancho (`apellidoMinimoAnchoPt`), va con la letra mínima.
   Con las mesas de verdad apretadas sigue sin apellidos y el pie lo dice.
3. **La flecha de la última fila quedaba afuera del recorte.** `PlanoPapel.marco(abajo:)` y `PlanoPdf.lugarDebajo` le hacen lugar.
4. **Los apellidos salían corridos de su mesa, y los de la derecha tocaban el borde.** El nombre de un sector va con letras
   separadas y en un PDF ese espaciado queda puesto: `_escribir` no lo volvía a cero.

**Por qué no se vieron antes:** la muestra del PDF recortaba el salón a las mesas, así que enseñaba apellidos que el papel de
verdad no traía. Ya no lo recorta.

**Detalles, sin arreglar** (no rompen nada; los decide el usuario):
- **A 4,1 m entran las 35, pero algunas quedan al lado de los camarines, y hay 4 saltos sin ningún aviso.** Es lo mejor que da esa
  distancia, así que `_avisoDeSaltos` no dice nada, y el sorteo corta en cada salto. A los 3 m de hoy no pasa.
- **Sin internet, "Antes de guardar" igual promete que los números se ordenan.** La pantalla no sabe que no hay internet hasta
  guardar; después de guardar, el aviso de la app sí lo dice bien.
- **Al soltar la barra, el panel baja** porque aparece el aviso de arriba, y la barra queda más abajo que donde se soltó.
- **En papel no se ve el borde derecho del hormigón:** el recorte llega hasta las mesas y solo se dice lo que sigue al fondo.

## Lo que no se comprobó

- **El PDF impreso en papel.** Se miró a tamaño real en pantalla (150 ppp), no impreso. La letra de los apellidos es de 4,3 pt: chica,
  y hay que verla en la impresora de la oficina antes del primer sorteo.
- **Los gestos con el dedo y el recorrido en dos PCs.** La prueba fue con un mouse, en una PC, sin nube.
- **Los otros dos estilos en esta ventana.** Se probó Arquitecto; Gala y Neón, solo con los tests.
- **`test/recepcion_suelta_canal_test.dart`**, que falló una vez: 10 de 10 corrido solo el 2-nov, y dos corridas completas en verde.
  Sigue sin explicación. Si vuelve a pasar, cambiarle la espera de 50 ms por un aviso.

## Lo pendiente, en orden

1. **El usuario dice si se publica la 6.3.0.** Ya se probó con el mouse (arriba); conviene imprimir un plano antes. Los sorteos de
   verdad son en noviembre y las fiestas desde el 1-dic. Publicar: la lista de arriba, con él presente.
2. **Operadores con permisos** (paso 3 de la hoja): Cobros, Entradas y Barra. El plan ya está corregido:
   `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`. Lleva una tabla nueva y la migración v76, que se prueba sobre una copia de su base con
   la app cerrada: hay que pedírselo.
3. **La app de hoy corriendo en una tablet** (etapa 0 del paso 4): ninguna tablet tiene la app, y es el riesgo más grande para el
   4-dic. Hace falta un Android conectado y una clave de firma propia.
4. **La impresora** (paso 1): llegó el 2-nov y ya imprimió desde la app: `docs/CONTEXTO_BARRA_2026-11-02.md`.
5. **El módulo de barra** (paso 4): plan aprobado, `docs/PLAN_BARRA_2026-11-03.md`.
6. **Entradas** (paso 5). La venta suelta es lo último.

**Queda abierto, sin apuro:** marcar "lejos" antes, en la ficha del alumno. Hoy se tilda en SORTEO. Llevaría una tabla nueva, y va
aparte si lo piden.
