# Unir los routers de las dos barras por wifi, sin cable (25-nov-2026)

Cada barra tiene su router **Mercusys MW305R** ("300 Mbps Multi-Mode"), en las dos puntas del salón, sin cable entre
ellos. Para que las tablets y la encargada de una barra vean la otra, el router de la Barra 2 se engancha por wifi al
de la Barra 1 (modo puente, WDS). Mercusys arregló en la V2 la estabilidad de ese modo, y los dos son la misma marca y
modelo. **Lo que no se sabe es si llegan de punta a punta: eso se prueba en el lugar.** Si no llegan, el programa
igual anda con cada barra sola (ver el plan del 25-nov).

Los nombres de los menús salen de la guía de Mercusys para otro modelo: en el MW305R pueden decir algo parecido.
Fuentes: [descargas del MW305R](https://www.mercusys.com/bg/download/mw305r/), [preguntas frecuentes de Mercusys sobre WDS](https://www.mercusys.com/cz/faq-130/).

Los wifi se llaman **Juniorbarra1** y **Juniorbarra2**, con la misma contraseña. Está bien así: mirando el wifi se
sabe a qué barra está conectada cada tablet.

## Antes de empezar

- Los dos routers prendidos y cerca (primero se prueba de cerca).
- En el celular, **los datos móviles apagados**: si no, al ver un wifi sin internet el celular se pasa a los datos y
  no abre las páginas de los routers.

## A. Router de la Barra 1 (Juniorbarra1)

1. Conectar el celular a **Juniorbarra1**.
2. Entrar a **`192.168.1.1`** con la contraseña de administrador.
3. En el wifi ("Wireless"), **"Channel" / "Canal"**: de "Auto" a **6**. Guardar.
   - Bien si al volver a entrar sigue en 6.

## B. Router de la Barra 2 (Juniorbarra2)

4. Conectar el celular a **Juniorbarra2** y entrar a **`192.168.1.1`**. Fijarse que diga Juniorbarra2.
5. **La dirección:** "Advanced" → "Network" → **"LAN"**: de `192.168.1.1` a **`192.168.1.2`**. Guardar (desconecta).
   - Bien si, conectado otra vez a Juniorbarra2, **`192.168.1.2`** abre la página del router.
6. **El puente:** "Advanced" → "Wireless" (2.4 GHz) → **"WDS Bridging"** → elegir **Juniorbarra1**, su contraseña,
   canal **6**; si ofrece cambiar el nombre de su wifi, **dejar Juniorbarra2**. "Finish".
   - Bien si el WDS dice "Conectado" o "Run".
   - Si el router tiene "Operation Mode" con **"Range Extender"**, es otra forma de lo mismo (hace solo los pasos 5 a 7),
     pero puede ponerle al wifi el nombre de la Barra 1.
7. **"Advanced" → "Network" → "DHCP Server" → Desactivado.** Guardar.

## C. La prueba

8. Celular en **Juniorbarra2**, entrar a **`192.168.1.1`**.
   - **Si abre la página del router de la Barra 1, están unidos.** Si además `192.168.1.2` abre el de la Barra 2,
     perfecto.
   - Si el celular no se termina de conectar a Juniorbarra2 ("sin dirección IP"), el puente no anduvo: después del
     paso 7 la dirección se la da el router 1 a través del puente.
   - "Conectado, sin internet" es normal.
9. **La distancia:** llevar el router de la Barra 2 a donde va a estar en el salón, esperar un minuto y repetir el 8.

**Si se traba:** el botón **Reset** del router de la Barra 2, unos 10 segundos: vuelve a fábrica (`192.168.1.1`) y se
empieza de nuevo desde el paso 4. El router de la Barra 1 no se toca.

## Estado

Pasado al usuario el 25-nov. Lo prueba en la oficina y avisa.
