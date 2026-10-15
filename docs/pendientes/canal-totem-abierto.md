# El canal de avisos del tótem, abierto

**Estado:** pendiente
**Postergado el:** 2026-10-15 (quedó afuera de la sección 8 de la 6.0.0)

## Qué pasa

El tótem se entera al instante de cada ingreso por el canal de Realtime `totem_<evento>` (broadcast). El canal es
público: cualquiera con la clave pública de la web y el número del evento puede escucharlo y **mandar** por él.
El número del evento está en el QR de los particulares (`/lista?evento=<id>`).

- **Escuchar:** desde la sección 8 los avisos van sin DNI ni intentos (`Invitado.sinDatosPrivados`, en
  `InvitadosRepository._emitir` y en la página del QR). Lo que se ve es el nombre y la mesa de quien entra, lo
  mismo que muestra el tótem en el salón.
- **Mandar:** alguien podría hacer aparecer en la pantalla un saludo con un nombre inventado (`checkin`), sacar a
  alguien de la lista de la pantalla (`guest_removed`) o vaciarla (`list_reset`) hasta la próxima relectura
  (cada 20 s, de la nube por `totem_lista`). **No toca datos**: la lista de la puerta no cambia.

## Por qué se postergó

La sección 8 cerró lo que sí toca datos (leer y cambiar `invitados`, anotar en `accesos`, el DNI en los avisos).
Esto es solo pantalla, se arregla sola en 20 s, y cerrarlo bien cambia cómo se avisan las PCs, los celulares y el
tótem entre sí: no daba para meterlo en la misma sección.

## Qué habría que hacer

- **Canales privados de Realtime** (Realtime Authorization): `RealtimeChannelConfig(private: true)` y políticas
  sobre `realtime.messages`. Las PCs mandan con usuario; el tótem escucha con... no tiene usuario: habría que darle
  un JWT propio o que la nube mande el aviso (`realtime.send` desde `puerta_checkin`, y desde un disparador para lo
  que sube de las PCs).
- **Más simple, a medias:** que el tótem salude solo a quien está en su última lectura de `totem_lista` (o en la
  ficha, en un masivo) y espere la relectura para los demás. Cuidado: antes del sorteo, en un masivo, la fila se
  crea al ingresar (`ingresarDesdeLaPuerta`) y todavía no está en la lectura; la ficha sí la conoce.
- La ventana del tótem en la PC recibe lo que marca esa PC por el puente entre ventanas, que no pasa por la red:
  eso no se toca.
