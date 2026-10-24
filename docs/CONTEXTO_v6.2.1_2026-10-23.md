# La 6.2.1 (23 y 24-oct-2026): la foto del tótem, el camino en escuadra, el celular sin internet, congelar la mora, la limpieza y el evento particular

**Terminada el 24-oct.** El usuario pidió publicarla ese día ("hacelo ya la publicación"): primero los dos SQL, después
el release, la web y las PCs (las instala él y avisa).

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

### 3. El camino a la mesa, en escuadra

El usuario preguntó el 23-oct por la línea del camino en la llegada: "queda como rayas nomás, que apuntan al lugar,
muy desprolijo". No había cambiado desde la 6.0.0: iba por el atajo más corto, rozando las mesas y doblando en
cualquier ángulo. Pidió "línea recta y que doble, entonces queda más simétrico", y aprobó cómo quedó ("ahí me gusta
más").

- **`CaminoALaMesa`** busca solo a lo largo y a lo ancho, por el medio de los pasillos (cada celda cuesta un poco más
  cuanto más pegada a las sillas o a algo tapado: `holgura`, medida en dos pasadas) y con pocas vueltas (doblar cuesta
  4 pasos, volverse 30; la búsqueda va por celda y dirección de llegada).
- **Entre las sillas se pasa** (pregunta del usuario: "uno pasa como por afuera y entra otra vez; la idea es el camino
  que deberían seguir los familiares"). Medido en el salón de la Normal: contando las sillas, entre columnas de mesas
  no queda paso y entre filas quedan 22 a 33 cm; por ahí camina la gente, de costado. Lo que no se pisa es la mesa
  (`_cuerpo`, 1,15 radios); la zona de las sillas (hasta 1,35) cuesta un poco más que un pasillo libre
  (`_entreSillas`). Antes las sillas eran pared: 7 de las 78 mesas daban un rodeo de más del 25 % (la 76, 25,6 m
  contra 11,4 m). Ahora ninguna; la peor, la 67, camina 1,2 m de más.
- **Se adapta a cómo está armado el plano** (lo pidió el usuario: "puede ser 2 metros, puede ser que yo amplíe"): todo
  sale de dónde está cada mesa y de su radio. En un playón a medida con las mesas a 2 m y a 2,5 m, ningún camino pasa
  del 2 % sobre lo más corto. `tool/caminos_rodeo_test.dart` lo mide en los tres salones.
- **Sale del cartel del Ingreso enseguida**: sus celdas se pueden pisar pero cuestan (`enIngreso`), y el camino
  arranca donde lo deja, también si el punto de salida está justo afuera (`_desdeElBorde`, recorte de Liang-Barsky).
- **Fuera del hormigón** (un armado a medida) se puede pasar, pero cuesta (`fuera`): el camino va por adentro.
- **`sinEscalones`** saca las Z chicas (va, se corre un poco y sigue para el mismo lado) cuando se puede ir derecho sin
  pisar nada; **`_enEscuadra`** alinea el primer tramo con el ingreso y el último con el centro de la mesa.
- **El dibujo** (`PintorResaltado`, `caminoRedondeado`): la esquina apenas suavizada y una flecha en la punta, que
  acompaña a la línea mientras se dibuja.
- Sigue igual: nunca pisa otra mesa, termina en el borde de la mesa, sin paso va recto, y en el playón de 284 mesas
  tarda menos de medio segundo (`test/camino_a_la_mesa_test.dart`).
- Muestras nuevas: `tool/totem_muestra_test.dart`, "el camino a varias mesas, en grande" (seis mesas del salón de la
  Normal) y "el camino en un playón a medida, a 2 y a 2,5 m" (con el Ingreso donde lo pone el salón vacío).

### 4. Congelar la mora (24-oct)

Lo pidió el usuario el 23-oct a la noche: el que no pagó nada y viene a hacer un compromiso, "se le congela el precio, y
normalmente tienen mora". El plan, aprobado, en `C:\Users\lover\.claude\plans\seguimos-con-el-plan-eager-crayon.md`.

- **El copo de nieve** en la fila de cada alumno, solo en modo jefe (celeste si tiene algo congelado). Abre
  **Congelar** (las cuotas vencidas con su mora de hoy, "Todas, también las que se venzan", "Queda congelada en $X") o,
  con algo congelado, **Mora congelada**: Mantener ese precio o Recalcular, con los dos montos a la vista antes de
  tocar, y "Congelar otra cuota". `widgets/congelar_mora_dialog.dart`.
- **La cuenta resta días, nunca cambia una fecha** (`services/mora_congelada.dart`; `_diasQueCuentan` en
  `MoraCuotaCalculator`). Lo que se descongela con Recalcular vuelve a la cuenta de siempre solo en las cuotas que se
  deben: una pagada mientras estaba congelada queda como se cobró.
- **El ejemplo que confirmó el usuario** (PÉREZ, JUAN, cuota de $30.000) está tal cual en `test/mora_congelada_test.dart`:
  congela la 4 y la 5 el 23/10; al 2/11 siguen en $25.200 y $15.900 y la 6 está en $9.900; Mantener $41.100,
  Recalcular $47.100. También el alumno sin ningún pago que se compromete, y que **una mora perdonada no resucita**
  (lo preguntó él).
- **El aviso celeste**, para todos: "Mora congelada desde 23/10/2026 · C4, C5" en ESTADO DE DEUDA, la ventana de cobro y
  Mi Empresa → Cobro. La línea de la eximición pasa a decir "Sin mora hasta".
- **Tabla nueva `mora_congelada`** (SQLite v75 y `supabase/migrations/20261023210000_mora_congelada.sql`): una fila por
  alumno con id fijo, que nunca se borra. Sube y baja con lo del cobro. Lo congelado se carga en memoria al abrir,
  antes de la revisión de la mora y cuando llega de otra PC.
- **No congelar a nadie hasta que las tres PCs tengan la 6.2.1.**
- Muestras: `tool/congelar_mora_muestra_test.dart` (se le mandaron).

### 5. La limpieza (24-oct)

El usuario pidió dejar la versión "bien prolija" y eligió qué sacar:

- **Mi Empresa queda con FINANZAS y COBRO.** Sale OPERADORES (una sola cuenta Asesor, sin entrar desde abril) y
  PRESUPUESTOS (sigue en la barra lateral, en modo jefe).
- **"Restaurar / perdonar mora" queda solo como "Perdonar mora (por curso)".** "Restaurar (vencidos)" contaba dos veces la
  mora de todos los masivos (Buena Vista quedaba afuera porque estaba fijo en el código) y borraba perdones;
  "Individual" movía el Reg y ponía mora a mano, lo de TOÑANEZ.
- **El QR de cotizar** llevaba a la web vieja de Firebase (de marzo): ahora a la de Vercel.
- **Saneamiento** pide el PIN otra vez y arranca sin nada tildado.
- **El menú de la nube:** sin "Verificar nube" ni "Subir y bajar"; "Pull completo forzado" solo en modo jefe.
- El Centro de Comando dice EVENTOS (decía NUEVO EVENTO y abría la lista).
- **Sin `/op` ni las rutas `/operador` y `/recepcion_unified`** (esta abría Recepción en la web sin usuario).
  `/totem_display` queda: el tótem dentro de la ventana principal la usa.
- Código muerto afuera (la restauración de mora, la validación de DNI vieja del tótem, la caja fuerte retirada, egresos
  viejos, el buscador viejo del QR), la carpeta `scratch` y ~70 archivos sueltos de la raíz (dos binarios de 45 MB). Los
  documentos y SQL viejos, a `docs/archivo` y `supabase/archivo`.
- Se dejó `kListaPuertaHabilitada`: no molesta y tiene sus tests.
- `test/limpieza_621_test.dart` vigila que nada de eso vuelva.

### 6. El evento particular muestra todo lo de su presupuesto (24-oct)

Un cliente del usuario preguntó "dónde están los detalles que puse". En la nube (23-oct): 12 eventos salieron de un
presupuesto; 51 de sus 61 servicios tienen detalle y la pantalla no lo mostraba; 11 tienen lugar y no se veía; en 5
DETALLES DEL EVENTO desaparecía.

- La lista dice **SERVICIOS** (decía PROVEEDORES ASIGNADOS) y muestra el detalle de cada uno, los combos juntos, los
  extras con "EXTRA · no suma al total" y la cantidad tal cual (1,5). `widgets/servicios_del_evento.dart`.
- **El lugar** sale del presupuesto vinculado (sin migración); el solicitante va con teléfono y email; DETALLES DEL
  EVENTO siempre está, con EDITAR INFO.
- El PDF que se regenera desde el evento lleva el lugar, el WhatsApp y el Instagram del presupuesto.
- **Nunca dos eventos del mismo presupuesto**: confirmado dice VER EVENTO; confirmar otra vez devuelve el mismo; evento,
  renglones y estado en una transacción; el botón se apaga mientras crea; sin fecha la pide; sin cliente o sin
  presupuesto en la PC lo dice; al terminar abre el evento; un presupuesto con evento no se borra.
- Queda anotado, sin tocar: el total con extras en el Panel y los recibos (`docs/pendientes/total-con-extras.md`).

## Pruebas

- `flutter test`: **2.913 bien**.
- `flutter analyze`: 309 (eran 312: la limpieza sacó tres).
- **La migración sobre una copia de la base real** (`tool/verificar_migracion_v75_test.dart`, 24-oct, con la app
  cerrada): las 34 tablas idénticas (643 alumnos, 4.291 pagos), solo aparece `mora_congelada` vacía, el esquema de lo de
  antes igual, la vuelta a la 6.2.0 abre con los mismos datos, y la base real quedó con el mismo SHA-256.
- **El día a día, la versión de hoy contra la nueva**, sobre otra copia (`tool/cobro_igual_que_hoy_test.dart` en la
  6.2.0 y en la 6.2.1): cada alumno (ficha, mora por cuota, simulación del cobro, recibo) y las operaciones del día
  (cobrar cuota, mesa, sillas y mora, un abono y anular) dan **exactamente lo mismo**; las 16 diferencias son la carpeta
  de cada PDF, el número de versión y el de la base.
- **La revisión de la mora** (`tool/simulacro_revision_mora_test.dart`, las dos versiones): 643 alumnos, ninguno cambia,
  ninguna ficha sube, **ningún perdón cambia su eximición**.
- Las copias se borraron al terminar.

**Las novedades del release dicen "Nuevas capacidades en el modo jefe, limpieza"** (lo pidió el usuario).

## Falta

1. **Publicar**: los dos SQL antes que nada (`20261023200000_totem_config_foto.sql` y
   `20261023210000_mora_congelada.sql`), la versión 6.2.1 en `pubspec.yaml` y en el instalador, el release y la web. Las
   PCs las instala él. **No congelar nada hasta que las tres PCs tengan la 6.2.1.**
2. Que el usuario confirme cómo quedó el camino a la mesa.
3. El ensayo con el router de verdad: el celular sin internet, entero.

