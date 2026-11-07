# La 6.3.3: el sync en reposo

6-nov-2026 (noche). Rama **`release/6.3.x`** (creada desde el tag `v6.3.1`, en la carpeta `..\arguello_events_6.3.x`), después
de la 6.3.2; cada commit también en `feature/v4.6-cierre-por-sesiones`. Los documentos viven en la rama feature. El plan, con el
diseño aprobado al final: `docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`.

## Para retomar en otro chat

**Estado al 6-nov (noche): programada y probada en el sandbox; falta publicarla.** Siete commits, en las dos ramas, con la suite
entera en verde en las dos. Se publica **después** de la 6.3.2 (la mora, meta lunes 9-nov), con el procedimiento de siempre. Lo que
falta, abajo.

> Frase para retomar: "Seguimos con la 6.3.3: leé 'Para retomar en otro chat' de docs/CONTEXTO_v6.3.3_2026-11-06.md y decime en
> qué paso estamos."

## Por qué

El proyecto sigue en el plan Free de Supabase (una instancia Nano). Hasta la 6.3.2 cada PC le pedía a la nube unas 120 cosas por
minuto aunque nadie tocara nada: el coordinador bajaba 16 tablas cada 10 s, con un pedido de prueba antes y tres cuentas después, y
el latido de la caja subía cada minuto. Era el 95 % de lo que la app le pedía a la nube. La caída del 6-nov (15:51-16:13) no fue
por carga, pero esa carga de fondo es lo único que está en nuestra mano.

**Regla nueva: en reposo, silencio.** La nube se toca cuando algo cambia, al abrir, al volver a la ventana, al volver la red, antes
de cobrar, y con una red de seguridad espaciada.

## Qué cambió (los siete commits)

| # | Qué | Para el usuario |
|---|---|---|
| 1 | El reloj del motor (`RelojDelMotor`) y el arnés de pruebas | Nada todavía |
| 2 | La red de seguridad: lo del cobro cada 5 min (con la cuenta de borrados), lo de carga cada 30; vuelve la red → sube y baja | Al abrir, la revisión de borrados no corre dos veces |
| 3 | El coordinador sin reloj; la subida reintenta sola con espera creciente, para cualquier rol | No hay más consultas cada 10 s; lo que no sube se reintenta solo |
| 4 | El pulso como transporte: no se tira con la PC ocupada; si el canal se cortó más de 20 s, se pone al día | Un aviso de la otra PC ya no se pierde por llegar en mal momento |
| 5 | El latido cada 5 min (en uso 11, sin señales 20), con aviso "solo latido" | 12 subidas por hora por caja en vez de 60 |
| 6 | Sin ping antes de bajar o subir; la nube caída no marca la fila; la proyección se invalida solo con novedades | Un corte largo ya no deja cobros "trabados" |
| 7 | Los comentarios viejos ("el ciclo de 10 s lo cubre") y estos documentos | — |

**Lo que no cambió:** antes de cobrar y de abrir caja se baja todo, como siempre (`refreshBeforePayment`, `refreshBeforeOpen`); la
revisión de borrados de cada 10 minutos; `filasAPodar`; `invitados`, el tótem, Recepción y la central; la web.

**Qué ve el usuario de distinto:** casi nada, a propósito. Lo de la otra PC llega en 1 o 2 segundos por el aviso, como antes. Si el
aviso se pierde (se cortó internet justo ahí), un cambio puede tardar hasta 5 minutos en verse en vez de 10 segundos, salvo que
alguien vaya a cobrar (se baja todo) o vuelva a la ventana (se baja lo del cobro). La caja de la otra PC se ve en uso hasta 11
minutos después del último latido; en la misma PC, al volver a entrar con el PIN se retoma la caja abierta sin preguntar nada.

## Lo decidido al programar (distinto del plan)

- **Sin `marcarNubeCaida` ni sondeo.** El plan proponía frenar al motor con la nube caída y despertarlo con un sondeo propio. Si ese
  sondeo fallaba, la PC quedaba sin sincronizar. En cambio: la primera tabla de cada bajada hace de ping (si la nube no contesta,
  se corta con un solo pedido) y una nube caída no se le cuenta a la fila; el motor nunca queda esperando.
- **`_pullTable` no cambió de firma.** Para "solo con novedades" alcanzó con el aviso que ya existía (`cambiosBajadosStream`).
- **El canal del pulso no se re-suscribe a mano**: `supabase_flutter` reconecta solo; acá solo se mide el corte y se pone al día.
- **`puedeSubirSolo` desapareció**: la subida ya no mira el rol (la de los 2 s nunca lo miró).

## Las pruebas

`test/sync_en_reposo_test.dart` (25 casos) y `test/latido_sesion_test.dart` (4), con un reloj que avanza a mano
(`test/helpers/reloj_de_prueba.dart`) y una nube de mentira que cuenta cada pedido (`test/helpers/nube_de_prueba.dart`):

- **Reposo:** en 4 minutos y medio, ni un pedido; a los 5, exactamente las tablas del cobro y las 3 cuentas; a los 30, lo de carga;
  en media hora, ningún pedido de prueba.
- **El campo:** seis cobros sin internet esperan en la PC y suben todos solos al volver la red, sin dejar nada en la cola.
- **Lo que no sube:** se reintenta a los 30 s, 1, 2, 5 y 5 minutos; con la nube caída no suma intentos.
- **El aviso:** con la PC ocupada, a los 3 s baja exactamente lo avisado; un corte del canal de 25 s pone al día, uno de 10 s no.
- **El latido:** sube y avisa marcado; la otra PC lo baja sin refrescar pantallas; con un latido perdido la caja sigue en uso.
- **Refrescos:** una vuelta sin novedades no invalida la proyección ni refresca; una con una caja nueva, sí.

Tres pruebas viejas cambiaron, sin debilitarlas: la que vigilaba que Entradas y la barra suban solas (ahora sobre el motor), la que
fijaba el latido cada 60 s (ahora con los tiempos nuevos), y los nombres de tres pruebas de tablas que decían "cada 10 s". Una
prueba de Recepción que fallaba con la PC cargada se arregló en la rama del parche igual que en la feature el 6-nov.

## Lo que falta (en orden)

1. **Publicar la 6.3.2 primero** (`docs/CONTEXTO_v6.3.2_2026-11-09.md`).
2. **La versión:** `6.3.3+65` en `pubspec.yaml` y `installer/junior_eventos_setup.iss`, en las dos ramas. Tag `v6.3.3` sobre
   `release/6.3.x`.
3. **Foto de la mora "antes de 6.3.3"** (toda versión la lleva).
4. **El instalador y la web**, desde `..\arguello_events_6.3.x`, como en la 6.3.2.
5. **Instalar las tres PCs el mismo día** (las hace el usuario). Con versiones mezcladas, una PC vieja ve el latido de 5 minutos de
   una nueva como "sin señales" entre el minuto 1,5 y el 5: es solo el cartel, no cierra nada; igual, el mismo día.
6. **Foto "después"** y comparar.
7. **Verificar en la nube** (MCP de Supabase, logs), con la oficina abierta y nadie cobrando 20 minutos:
   ```sql
   select log_attributes['request.method'] as m, log_attributes['request.path'] as p, count(*) as n
   from logs where source = 'edge_logs'
   group by 1, 2 order by n desc
   ```
   Lo esperado por PC: `PATCH /rest/v1/sesiones_caja` unas 4 veces, cada tabla del cobro unas 4 veces, y **ningún**
   `GET /rest/v1/servicios` (era el pedido de prueba). Antes, la misma ventana daba unos 2.400 pedidos por PC.

**Sin SQL.** La etapa 6 (la red en una sola consulta) quedó en `docs/pendientes/sync-novedades-en-una-consulta.md`.

## Cuánto le pide cada PC a la nube en reposo

| | Hasta la 6.3.2 | 6.3.3 |
|---|---|---|
| El ciclo de 10 s | ~7.200 por hora | 0 |
| La red del cobro (16 tablas + 3 cuentas, cada 5 min) | — | 228 por hora |
| La red de carga (23 tablas, cada 30 min) | — | 46 por hora |
| La revisión de borrados (cada 10 min, no cambió) | ~150 a 300 por hora | igual |
| El latido, con caja abierta | 60 subidas + 60 pedidos de prueba por hora | 12 subidas por hora |
| **Total** | **~7.500 por hora** | **~430 a 590 por hora** |
