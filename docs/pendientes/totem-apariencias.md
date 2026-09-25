# El tótem con cuatro apariencias: Neón, Cristal, Póster y Gala

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

El usuario priorizó el sorteo de noviembre. El tótem nuevo es para las fiestas de diciembre, y para los particulares.
El diseño está **cerrado y aprobado con maquetas**, así que al retomarlo no hay que rediseñar:
- se descartaron dos propuestas, una "muy básica" y otra que "no convence";
- después se eligió entre tres direcciones;
- el usuario pidió que estén **todas**, para elegir en cada evento: "así el programa es más completo";
- los fondos tienen que ser "profesionales, innovadores": nada de dibujitos.

## Qué se decidió

**Se elige una apariencia por evento** en "Personalizar tótem", en masivos y en particulares. Si nadie elige, va
**Neón en los masivos y Cristal en los particulares**. El tótem web no puede leer la modalidad (`eventos` no es
público), así que ahí, sin estilo elegido, va Cristal.

**Común a las cuatro:**

- **Sin "Ya llegaron":** sale el panel con la cascada de nombres, en el tótem del salón y en la vista de Recepción.
  Ocupaba mucho lugar, y quién llegó se ve en la lista de Recepción.
- **Espera:** a pantalla completa, con lo que ya se personaliza: foto, título, subtítulo, saludo, texto del QR y color.
- **Título:** si tiene dos palabras, la primera va chica y la segunda grande ("PROMOCIÓN" / "2026"). Si no, va entero
  a lo ancho.
- **Llegada:**
  - el saludo;
  - el nombre **en mayúsculas, como está cargado** (decisión del usuario);
  - la mesa como protagonista;
  - 7 s por persona, con cola: "N más en camino";
  - una línea abajo que marca el tiempo.
- **QR solo en particulares.** En los masivos ya no (decisión del usuario): los alumnos no tienen DNI y cualquiera
  podría marcar a otro desde su celular.
- **Barra del operador**, que aparece al mover el mouse: girar, kiosco ([totem-kiosco.md](totem-kiosco.md)), cuántos
  llegaron y el estado de internet. El contador sale de la vista del público.
- **Vertical y horizontal.**
- **Plano y guía:** queda lugar en la llegada para sumarlos cuando exista el plano, dibujados en el estilo de cada
  apariencia.

**Cada apariencia:**

| | Espera | Llegada |
|---|---|---|
| **Neón** | Bruma de dos colores, piso de grilla en perspectiva que avanza, marco doble con brillo y una luz que lo recorre. Título en letra de tubo (Tilt Neon), con una letra que titila cada tanto. Saludo como cartel en cursiva de neón (Neonderthaw). | El cartel se prende titilando, el nombre se enciende letra por letra, y el círculo de la mesa se dibuja con un fogonazo. |
| **Cristal** | Gradiente líquido (el color del evento, violeta y azul) con grano fino, detrás de una tarjeta de vidrio esmerilado con la foto, el título (Oswald) y el saludo. | La tarjeta se da vuelta y muestra el nombre y la mesa. |
| **Póster** | La foto del evento a pantalla completa, con zoom lento, grano, haces de luz y oscurecido abajo para letras grandes (Oswald). Sin foto, luces de fiesta desenfocadas en tres profundidades. | El nombre sube desde una máscara, y la mesa entra en una franja inclinada del color del evento. |
| **Gala** | Textura de seda oscura, haces de luz que barren y polvo dorado. La foto va en un anillo que gira; serif elegante (Cormorant Garamond) con un brillo que cruza el título. | Un haz baja sobre la mesa, el nombre aparece letra por letra y la mesa va en un medallón que se dibuja, con polvo de luz. |

**Colores:** el color del evento es el principal. El segundo neón sale solo: cian `#4FE3F0`, o rosa `#FF3CAC` si el
principal es frío (azul mayor que rojo y mayor que 0,6).

**Cómo se elige, en Personalizar** (`totem_config_sheet.dart`, ver
[recepcion-redisenio.md](recepcion-redisenio.md)):
- cuatro tarjetas con vista previa en vivo, que usan las mismas escenas, así que no puede mentir;
- "Ver una llegada";
- al guardar, la ventana del tótem cambia al instante, también sin internet, porque la config viaja por el puente
  (`notifyConfigUpdated`).

## Dónde se guarda

Una columna nueva, `totem_config.estilo`: `neon`, `cristal`, `poster` o `gala`. Vacía, va según el tipo del evento.

```sql
-- ROLLBACK: alter table public.totem_config drop constraint if exists totem_config_estilo_check;
-- ROLLBACK: alter table public.totem_config drop column if exists estilo;
alter table public.totem_config add column if not exists estilo text;
alter table public.totem_config add constraint totem_config_estilo_check
  check (estilo is null or estilo in ('neon', 'cristal', 'poster', 'gala'));
```

- **Hay que correrla antes de usar la versión nueva.** `TotemConfigRepository.guardar` hace un upsert con
  `toJson()`, y si la columna no existe, guardar la personalización falla.
- **La 4.9.9 y la 5.0.0 conviven:** ignoran la columna al leer, y su upsert no la manda, así que no la pisan.
- `TotemConfig` y `TotemConfigCache` suman `estilo`.
- `gradientePanel` queda sin uso y sale.

## Tipografías

El usuario dio el OK: **se bajan una sola vez y quedan dentro de la app**, en `assets/google_fonts/`, que ya está
declarada en `pubspec.yaml`. Todas son de Google Fonts con licencia OFL, con los nombres que espera el paquete
`google_fonts`:
- `TiltNeon-Regular.ttf`;
- `Neonderthaw-Regular.ttf`;
- `CormorantGaramond-SemiBold.ttf` y `CormorantGaramond-MediumItalic.ttf`;
- `Oswald-Regular.ttf` y `Oswald-Bold.ttf`. Hoy Oswald se baja de internet al abrir.

Outfit ya está.

## Cómo se arma

`lib/features/totem/estilos/`:
- `totem_estilo.dart`: las cuatro apariencias, el defecto por tipo, el segundo neón y la partición del título.
- `totem_escena.dart`: lo común, más la interfaz de cada apariencia (espera, llegada y fondo). Lo común es:
  - la cola y la línea de tiempo;
  - la barra;
  - el lugar del plano;
  - la carga del shader con su respaldo.
- `escena_neon.dart`, `escena_cristal.dart`, `escena_poster.dart` y `escena_gala.dart`.
- Los shaders en `shaders/*.frag`, declarados en `pubspec.yaml` bajo `flutter: shaders:`.

`totem_display.dart` y `totem_panel.dart` solo le pasan los datos a la escena. Hoy son unas 800 líneas duplicadas.
Sale lo que se reemplaza:
- el panel y la cascada;
- la bienvenida vieja y los pintores viejos;
- los modos de `TotemPanelMode`.

**La modalidad**, para el QR y el defecto:
- en la ventana del tótem la pasa `KioskLauncher`, leída de SQLite, al abrir y en `set_evento`;
- en Recepción se lee de SQLite.

**El shader se carga al abrir el tótem.** Si una PC no puede compilarlo, se usa un degradé del mismo color: nunca una
pantalla rota.

## Los shaders de la maqueta aprobada

Son WebGL2 (GLSL ES 3.00), tal como se aprobaron el 24-sep.

**Uniformes:**
- `uRes`: tamaño en píxeles;
- `uT`: tiempo en segundos;
- `uA`: color del evento, RGB de 0 a 1;
- `uB`: segundo neón;
- `uP`: fogonazo de la llegada, de 0 a 1, cerca de 1,15 s después de empezar;
- `uS`: atenuado. Vale 1 en espera y 0,55 durante la llegada; Cristal queda en 1;
- `uD`: densidad de píxeles.

**Para pasarlos a Flutter:**
- **Encabezado:** `#include <flutter/runtime_effect.glsl>`, y `out vec4 fragColor;` en vez de `o`.
- **Coordenadas:**
  - `gl_FragCoord.xy` pasa a `FlutterFragCoord().xy`;
  - Flutter tiene el origen arriba, así que hay que invertir: `fc.y = uRes.y - fc.y`;
  - pasar `uRes` en las mismas unidades que `FlutterFragCoord` y `uD = 1`.
- **Orden para `shader.setFloat(i, …)`:** uRes (0–1), uT (2), uA (3–5), uB (6–8), uP (9), uS (10), uD (11).
- **Si `fwidth` no compila** en el backend, usar el ancho analítico de la grilla de Neón:
  `vec2 w = vec2(1.4 * z, z * z / .32) * 1.3 / uRes.y;`.
- **Se cargan una vez** con `FragmentProgram.fromAsset`, se animan con un `Ticker` y se pintan con
  `canvas.drawRect(rect, Paint()..shader = shader)`.

**Prefijo común:**

```glsl
#version 300 es
precision highp float;
uniform vec2 uRes; uniform float uT; uniform vec3 uA; uniform vec3 uB;
uniform float uP; uniform float uS; uniform float uD;
out vec4 o;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
  return mix(mix(h(i),h(i+vec2(1.,0.)),f.x),mix(h(i+vec2(0.,1.)),h(i+vec2(1.,1.)),f.x),f.y);}
float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*n(p);p=p*2.03+vec2(1.7,9.2);a*=.5;}return v;}
float sdRB(vec2 p,vec2 b,float r){vec2 q=abs(p)-b+r;return length(max(q,0.))+min(max(q.x,q.y),0.)-r;}
```

**Neón:**

```glsl
void main(){
  vec2 fc=gl_FragCoord.xy; vec2 uv=(fc-.5*uRes)/uRes.y; float hz=-.17;
  vec3 c=vec3(.012,.004,.028);
  float f=fbm(vec2(uv.x*1.6+uT*.04,uv.y*2.2-uT*.03));
  c+=mix(uB,uA,smoothstep(.3,.75,f))*.22*f*step(hz,uv.y);
  c+=uA*.75*exp(-55.*abs(uv.y-hz))+uB*.24*exp(-10.*abs(uv.y-hz));
  if(uv.y<hz){
    float d=hz-uv.y; float z=.32/d; vec2 g=vec2(uv.x*z*1.4,z+uT*1.1);
    vec2 q=abs(fract(g+.5)-.5); vec2 w=fwidth(g)*1.3;
    float ln=max(1.-smoothstep(0.,w.x,q.x),1.-smoothstep(0.,w.y,q.y));
    float fd=smoothstep(0.,.35,d);
    c+=uA*ln*mix(.15,1.,fd)+uA*.1*exp(-d*4.);
  }
  vec2 sid=floor(fc/(2.5*uD)); float st=step(.9975,h(sid))*(.4+.6*sin(uT*2.5+h(sid)*50.));
  c+=vec3(.9,.85,1.)*st*step(hz+.05,uv.y);
  vec2 p=fc-.5*uRes;
  float dd=abs(sdRB(p,.5*uRes-vec2(13.*uD),16.*uD))/uD; float core=exp(-dd*.8),glw=exp(-dd*.11);
  c+=mix(uA,vec3(1.),.35)*core*.9+uA*glw*.32;
  float d2=abs(sdRB(p,.5*uRes-vec2(21.*uD),11.*uD))/uD; c+=uB*exp(-d2*1.3)*.45;
  float an=atan(p.y,p.x); float ch=exp(-4.*abs(mod(an-uT*1.1+3.14159,6.28318)-3.14159));
  c+=vec3(1.)*ch*core*1.4;
  c*=.94+.06*sin(fc.y/uD*3.14159);
  c*=1.-.5*dot(uv*.85,uv*.85);
  c=c*uS+uA*uP*.25;
  o=vec4(c,1.);
}
```

**Cristal:**

```glsl
void main(){
  vec2 uv=gl_FragCoord.xy/uRes; vec2 p=uv*vec2(uRes.x/uRes.y,1.)*1.25; float t=uT*.07;
  vec2 q=vec2(fbm(p+t),fbm(p+vec2(5.2,1.3)-t));
  vec2 r=vec2(fbm(p+2.*q+vec2(1.7,9.2)+t*.7),fbm(p+2.*q+vec2(8.3,2.8)-t*.6));
  float f=fbm(p+2.4*r);
  vec3 c=mix(vec3(.02,.015,.06),vec3(.10,.30,.95),smoothstep(.25,.65,f));
  c=mix(c,vec3(.50,.28,1.),smoothstep(.3,.9,length(q))*.85);
  c=mix(c,uA,smoothstep(.55,.95,r.y)*.9);
  c*=.7+.45*f;
  c+=(h(gl_FragCoord.xy+fract(uT)*100.)-.5)*.035;
  c*=1.-.4*dot(uv-.5,uv-.5)*2.;
  o=vec4(c*uS,1.);
}
```

**Póster** (en la app, la foto del evento va debajo con zoom lento, y este fondo queda para cuando no hay foto):

```glsl
vec3 lay(vec2 uv,float sc,float sd,float sp){
  vec2 g=uv*sc+vec2(uT*sp,uT*sp*.3); vec2 id=floor(g); vec2 f=fract(g); vec3 a=vec3(0.);
  for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
    vec2 o2=vec2(float(x),float(y)); vec2 ci=id+o2; float r=h(ci+sd); if(r<.45)continue;
    vec2 ps=o2+vec2(h(ci*1.37+sd),h(ci*2.11+sd))-f; float sz=mix(.18,.5,h(ci+sd*3.1));
    float d=length(ps); float dk=smoothstep(sz,sz*.8,d); float rm=smoothstep(sz*.72,sz*.95,d)*dk;
    vec3 col=mix(uA,mix(vec3(1.,.72,.42),vec3(1.,.42,.62),h(ci+7.)),.55);
    a+=col*(dk*.22+rm*.2)*(.65+.35*sin(uT*.8+r*30.));
  }
  return a;
}
void main(){
  vec2 uv=gl_FragCoord.xy/uRes; float z=1.+.06*sin(uT*.05);
  vec2 p=((uv-.5)/z+.5)*vec2(uRes.x/uRes.y,1.);
  vec3 c=mix(vec3(.05,.02,.07),vec3(.35,.12,.18),smoothstep(.1,.75,uv.y));
  c+=vec3(.9,.45,.25)*.25*exp(-8.*length(uv-vec2(.5,.62)));
  vec2 d=uv-vec2(.5,1.05); float an=atan(d.x,-d.y); float bm=0.;
  for(int i=0;i<4;i++){float fi=float(i);bm+=exp(-60.*abs(an-.45*sin(uT*.2+fi*1.7)))*.5;}
  c+=mix(uA,vec3(1.,.85,.7),.5)*bm*smoothstep(1.2,.2,length(d))*.5;
  c+=lay(p,2.2,1.,.02)*1.1+lay(p,4.,7.,.035)*.8+lay(p,7.,13.,.05)*.6;
  c+=(h(gl_FragCoord.xy+fract(uT)*91.)-.5)*.06;
  c=mix(c,vec3(.02,.01,.03),smoothstep(.55,0.,uv.y)*.85);
  c*=1.-.45*dot(uv-.5,uv-.5)*2.;
  o=vec4(c*uS,1.);
}
```

**Gala:**

```glsl
void main(){
  vec2 fc=gl_FragCoord.xy; vec2 uv=(fc-.5*uRes)/uRes.y; vec3 c=vec3(.018,.013,.026);
  float s=fbm(uv*2.2+vec2(fbm(uv*3.+uT*.02),fbm(uv*3.-uT*.017)));
  c+=vec3(.11,.085,.05)*smoothstep(.35,.95,s);
  vec2 d=uv-vec2(0.,.62); float an=atan(d.x,-d.y); float ry=0.;
  for(int i=0;i<3;i++){float fi=float(i);
    ry+=exp(-30.*abs(an-.55*sin(uT*.13+fi*2.1)))*(.55+.45*n(vec2(an*12.,uT*.25+fi)));}
  c+=uA*ry*.3*smoothstep(1.5,0.,length(d));
  c+=uA*.1*exp(-3.*length(uv-vec2(0.,.05)));
  vec2 g=fc/uRes.y*38.+vec2(0.,-uT*1.2); vec2 id=floor(g); vec2 f=fract(g)-.5;
  float rr=h(id); vec2 of=vec2(h(id+1.3),h(id+2.7))-.5; float dd=length(f-of*.7);
  float sp=smoothstep(.09,0.,dd)*step(.92,rr)*(.4+.6*sin(uT*2.+rr*30.));
  c+=mix(uA,vec3(1.,.95,.8),.55)*sp;
  c*=1.-.55*dot(uv,uv);
  c=c*uS+uA*uP*.18;
  o=vec4(c,1.);
}
```

## Cómo probarlo

- **Tests:**
  - `test/totem_estilo_test.dart`: defecto por tipo, segundo neón, estilo desconocido o vacío, ida y vuelta de
    `toJson`/`fromJson` y la partición del título;
  - `test/totem_escena_test.dart`, por apariencia:
    - espera y llegada sin desbordes a 360×640, 1080×1920 y 1920×1080;
    - no aparece "YA LLEGARON";
    - QR solo en particulares;
    - sin mesa no rompe;
    - con el shader no disponible, usa el degradé.
- **Muestras en PNG** con nombres ficticios (`tool/totem_muestra_test.dart`).
- **En la app,** con `flutter run -d windows`: recorrer las cuatro en Personalizar con "Ver una llegada" y **cancelar**
  sin guardar, porque es producción.
- **`flutter build web`**, para confirmar que los shaders compilan. El tótem web muestra lo nuevo recién cuando se
  publique la web, con OK del usuario.
