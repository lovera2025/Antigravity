# El chat del salón con el personal de la barra

**Estado:** pendiente, decidido y sin programar.
**Pedido el:** 2026-11-10 (noche), por el usuario.
**Postergado el:** 2026-11-10 (noche), por el usuario: "publicamos con lo ya verificado y listo, el chat lo dejaremos para después".

## Qué es

Hoy (6.5.0) el chat es **solo de la puerta**: la notebook de Recepción y los celulares de las recepcionistas, por la central de la
puerta (`lib/features/recepcion/chat/`, `ChatDeLaNoche` en la memoria de la notebook, sin tabla ni nube, anda sin internet). Las
tablets de la barra hablan con **otra** notebook (la central de la barra, `lib/features/barra/central/`) y no tienen chat.

El usuario pidió que el chat sume a **todo el personal de la barra** (cajeras y encargada), **con solapas para elegir a quién**: TODOS ·
RECEPCIÓN · BARRA. Dentro de BARRA: "Toda la barra", "Romi · Encargada", "Marta · Caja 2"…; dentro de RECEPCIÓN: "Toda la recepción" y
cada recepcionista.

**Recepción y la barra van en dos notebooks** (lo dijo él): hace falta un **puente** entre las dos centrales.

```
   NOTEBOOK DE RECEPCIÓN (la de la tele)            NOTEBOOK DE LA BARRA
   central de la puerta  ·  CHAT                    central de la barra  ·  CHAT
        │  wifi del salón                                │  wifi del salón
   celulares de las recepcionistas                  tablets de las cajeras y la encargada
        └──────────────  el puente: las dos notebooks se pasan los mensajes  ──────────────┘
```

## Por qué se postergó

Lleva varios días de trabajo (el puente entre notebooks, el chat por la central de la barra, las solapas, el globito en VENDER, LAS
CAJAS y BARRA → CAJAS) y probarlo con las tablets. El usuario prefirió publicar la 6.5.0 con lo que ya estaba programado y probado, y
hacer el chat después, en otra versión.

## Cómo hacerlo (el plan del 10-nov, aprobado en el chat)

1. **Maqueta antes de programar**: el chat con las solapas en un celular y en la tablet de la barra, con datos inventados. Esperar su OK.
2. **A quién se le habla.** `PuestoDelChat` gana el sector (puerta · barra) y `MensajeDePuesto.para` acepta, además de todos y una
   persona, "Toda la recepción" y "Toda la barra". Las reglas de quién ve qué, con sus tests.
3. **La barra entra por su central.** `CentralBarra` reparte el chat a sus tablets por la conexión que ya tienen (tipos nuevos `chat` y
   `puestos`) y `ClienteDeLaCentral` le da a la tablet su `ChatDelPuesto`. El nombre sale de quién entró con su PIN. **Quién lo mandó
   lo dice la conexión, no el mensaje.** Una tablet o una notebook con la versión anterior ignora lo nuevo y sigue vendiendo igual.
4. **El puente.** La notebook de Recepción busca por el wifi la central de la barra de esa fiesta (el camino de `buscar_central.dart`);
   se pasan quiénes están y los mensajes que le tocan al otro lado. **Lo privado entre dos del mismo sector no cruza.** Al conectarse o
   reconectarse se mandan lo que falta, sin repetir. Dirección a mano si el router no deja.
5. **Las pantallas.** Solapas en `HojaChat` (la misma en el celular, Recepción y la barra); el globito (`BotonChat`) y el cartel
   (`AvisoDelChat`) en VENDER, LAS CAJAS y BARRA → CAJAS, con vibración en la tablet y sonido en la notebook; el estado del puente en los
   paneles de las dos centrales.
6. **Pruebas de punta a punta en el sandbox**: las dos centrales de verdad en esta PC, celulares en pestañas del navegador y tablets
   simuladas. Lo que necesita aparatos (dos notebooks y una tablet en un router) queda para él, al instalar.

**Lo que no:** el iPhone por la web no entra al chat (una página de internet no llega a las notebooks del salón). Sin tabla ni nube:
dura la noche. Sin SQL.
