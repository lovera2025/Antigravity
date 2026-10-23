# La 6.2.1 (23-oct-2026): la foto y las frases del tótem, y el celular sin internet

**Programada y probada el 23-oct, sin publicar.** La idea del usuario es publicarla el 24-oct a la mañana, con su OK en
el momento: primero el SQL, después el release, la web y las PCs (las instala él y avisa).

## Qué lleva

### 1. La foto y las frases de la espera del tótem

Lo pidió el usuario el 23-oct, desde el celular, en tres pasos:

1. "el redondito de la foto": poder sacarlo, porque carga un fondo que ya trae su logo y en un evento masivo la
   pantalla tiene que quedar limpia; en un particular lo puede querer;
2. agrandarlo y achicarlo "con manijillas", hasta un tope lógico, y elegir la forma ("ovalado, cuadrado, triangular, lo
   que yo quiera"), en todas las apariencias;
3. ubicar las frases "por si se opaca o se esconde o le tapa la foto por el grandor", también con manijas para
   moverlas y para agrandarlas.

Lo hecho:

- **Mostrar la foto** (interruptor en Personalizar → FOTO DEL EVENTO). Apagada, no va ni la foto ni el logo de la
  empresa. Vale también en Póster, donde la foto es el fondo: sin ella van las luces.
- **Nueve formas** (`FormaFoto`, `estilos/forma_foto.dart`): círculo, óvalo, cuadrado, arco, corazón, hexágono, rombo,
  triángulo y **tal cual** (la imagen entera, sin recortar ni marco: para un logo sin fondo). Cada una es un contorno
  (`camino`) y una proporción; `FotoEvento` recorta, pinta el borde y, en "Tu fondo", el resplandor, con el mismo
  contorno. Una forma que esta versión no conoce se dibuja como círculo y se guarda como vino.
- **El tamaño de la foto**, del 50 al 300 % del de siempre (al 300 % mide más de la mitad del ancho de una tele
  vertical). **El de las frases**, del 50 al 200 %: `Escalado` (en `escena_totem.dart`) agranda el bloque de las
  frases ocupando lo que mide, así lo de abajo se corre y nada se pisa.
- **Dónde van**: la foto y las frases **juntas**, a cualquier lugar del espacio de cada apariencia (`Centrado` con
  `ubicacion`). Juntas, la foto nunca tapa las frases: la foto las empuja, y si todo no entra se achica entero. Si se
  quisieran separadas (la foto en un lugar y las frases en otro) es otra cosa: se podrían pisar, y en Cristal la foto
  está dentro de la tarjeta de vidrio.
- **En Personalizar**: sobre la vista, manijas en las esquinas de la foto y de las frases (`ManijasParaAgrandar`) y
  arrastre del conjunto (`ArrastrarParaUbicar`); en el panel, las formas, las barras de tamaño con − y +, y una grilla
  de nueve lugares con "Volver al medio" (`foto_en_personalizar.dart`). Las cuatro cosas las dibuja la misma escena
  del tótem por ganchos (`alrededorDeLaFoto`, `alrededorDelTexto`, `alrededorDelBloque`): el tótem del salón no los
  usa.
  - **La manija y el arrastre compiten**: Flutter espera el margen de un dedo (unos 36 px) antes de decidir, y ese
    primer tramo no cuenta. En la app no se nota; en un test, el gesto tiene que seguir después de ese tramo
    (`test/foto_en_personalizar_test.dart`).
- **Póster no cambia**: la forma, los tamaños y el lugar no se usan (lo dice el panel). En **Gala** el anillo que gira
  va con el círculo y crece con la foto; con otra forma, el borde dorado de esa forma. En "Tu fondo" el aclarado de
  detrás del texto sigue a las frases.
- **Cada evento arranca como hoy**: la foto, en círculo, al 100 %, frases al 100 %, al medio.

**La nube:** seis columnas vacías en `totem_config` (`supabase/migrations/20261023200000_totem_config_foto.sql`):
`mostrar_foto`, `foto_forma`, `foto_tamano`, `texto_tamano`, `ubicacion_x` y `ubicacion_y`. Sin NOT NULL, DEFAULT ni
CHECK, como `mostrar_musica` y las de "Tu fondo". **Se corre antes de instalar y de publicar la web**: la 6.2.1 las
manda al guardar Personalizar y, sin ellas, guardar falla. La 6.2.0 no las nombra al guardar: no las pisa.

### 2. El celular de la puerta, sin internet

El 23-oct el usuario hizo el ensayo que faltaba (`docs/pendientes/modo-local-sin-internet.md`): Recepción →
CELULARES, el QR con el celular y la red sin internet. **El celular llegó a la notebook (192.168.1.40:8787) y la
página quedó en blanco.** Los datos y las PCs, bien: no se marcó nada.

- **La causa:** Flutter en la web necesita una letra de base. Si la app no trae una familia llamada "Roboto", el motor
  la baja de `fonts.gstatic.com` al arrancar y **no dibuja nada hasta tenerla** (`loadAssetFonts`, en el motor web de
  Flutter). Sin internet ese pedido se queda esperando. `--no-web-resources-cdn` sirve CanvasKit desde la notebook,
  pero no cubre esta letra.
- **Reproducido en esta PC** con Edge sin ventana y sin salida a internet: con la página de la 6.2.0, en blanco; con
  internet, "¿Cómo te llamás?".
- **El arreglo:** la app trae su Roboto (`assets/fonts/Roboto-Regular.ttf`, la que viene con Flutter, licencia Apache
  al lado) como familia `Roboto` en `pubspec.yaml`. Probado igual, sin internet, con la conexión colgada y con la
  conexión que falla enseguida: dibuja. `test/puesto_sin_internet_test.dart` falla si se saca.
- **Queda un pedido a internet que no traba nada**: el motor busca una letra de símbolos (Noto Sans Symbols) para
  algún carácter de la primera pantalla. La pantalla se ve entera; sin internet, ese símbolo no se dibujaría. En el
  ensayo con el router de verdad, mirar las pantallas del celular.
- En Windows no cambia nada (la letra de base ahí es Segoe UI); en la web (Vercel) Roboto sale de la app en vez de
  Google: la misma letra.

## Pruebas

- `flutter test`: **2.826 bien**, también el de Recepción que a veces falla con la PC cargada.
- `flutter analyze`: 312, los mismos de la 6.2.0; ninguno en lo nuevo.
- Muestras (`tool/totem_muestra_test.dart`, grupo "La foto (6.2.1)" y "la foto: con foto, el logo tal cual y sin
  foto"), con una foto, un logo (una corona) y una story inventados, en `build/muestras_foto/`: las nueve formas, los
  tamaños, el corazón en cada apariencia, "Tu fondo" con y sin foto y con las frases abajo, y Personalizar con las
  manijas. Se le mandaron al usuario.

## Falta

1. **Publicar, con su OK en el momento**: el SQL (antes que nada), la versión 6.2.1 en `pubspec.yaml` y en el
   instalador, el release, la web y las PCs.
2. El ensayo con el router de verdad: el celular sin internet, entero.
3. **Pregunta abierta del usuario (23-oct):** la línea del camino a la mesa en la llegada se ve "como rayas,
   desprolija". No cambió: es la de la 6.0.0 (`CaminoALaMesa`, tramos rectos que doblan en ángulo al esquivar mesas).
   Se le ofreció emprolijarla (menos quiebres y curvas suaves); no está decidido.
