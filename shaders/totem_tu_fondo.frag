// Tu fondo: la imagen del evento es el fondo, con su animación y su glitch.
// La animación es lo que hace la imagen misma (acercarse, recorrer, flotar,
// respirar, ondular); los demás efectos van encima y los pinta la escena
// (`escena_tu_fondo.dart`). Lo diseñado: docs/PLAN_TU_FONDO_2026-10-23.md.
//
// Uniformes, en el orden de `FondoPropio` (setFloat):
//   uRes (0-1)    el tamaño de la pantalla, en las unidades de FlutterFragCoord
//   uT (2)        segundos
//   uA (3-5)      el brillo de la paleta: el color del fogonazo de la llegada
//   uP (6)        el fogonazo, de 0 a 1
//   uS (7)        atenuado: 1 en la espera, 0,55 en una llegada
//   uTam (8-9)    el tamaño de la imagen, en píxeles
//   uMov (10)     la animación (`AnimacionFondo.index`): 0 quieta, 1 acercarse,
//                 2 recorrer, 3 flotar, 4 respirar, 5 ondular
//   uI (11)       cuánto se mueve, de 0 a 1
//   uO (12)       oscurecer, de 0 a 0,8
//   uCont (13)    1: la imagen entera al medio y alrededor la copia chica
//                 (una story en una tele horizontal); 0: cubre la pantalla
//   uFoco (14-15) lo importante de la imagen, de 0 a 1: hacia ahí se acerca o
//                 recorre
//   uSg (16)      para qué lado flota: 1 o -1
//   uG (17)       el glitch: 0 apagado; si no, su intensidad, de 0 a 1
// Samplers: uImg (0) la imagen, uChica (1) su copia chica y borrosa.
//
// Cada uniforme se usa: uno sin usar lo saca el compilador y se corren las
// posiciones de `setFloat`.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uRes;
uniform float uT;
uniform vec3 uA;
uniform float uP;
uniform float uS;
uniform vec2 uTam;
uniform float uMov;
uniform float uI;
uniform float uO;
uniform float uCont;
uniform vec2 uFoco;
uniform float uSg;
uniform float uG;
uniform sampler2D uImg;
uniform sampler2D uChica;

out vec4 fragColor;

const float PI = 3.14159265;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float n(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x),
             mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * n(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

// Va y vuelve, suave: 0, 1 a la mitad de [periodo], y 0 otra vez.
float vaiven(float t, float periodo) {
  return 0.5 - 0.5 * cos(2.0 * PI * t / periodo);
}

// Dónde se lee la imagen para el punto [q] (de 0 a 1 en la imagen), con la
// animación: en xy, y en z la luz (mayor que 1 al respirar).
vec3 animar(vec2 q, float aspecto) {
  float luz = 1.0;
  float i = uI;
  float m = floor(uMov + 0.5);
  if (m == 1.0) {
    // Acercarse: un zoom lento hacia lo importante, que va y vuelve.
    float s = 1.02 + (0.04 + 0.18 * i) * vaiven(uT, 2.0 * (30.0 - 14.0 * i));
    q = uFoco + (q - uFoco) / s;
  } else if (m == 2.0) {
    // Recorrer: agrandada, va y vuelve en la dirección de lo importante.
    float s = 1.16 + 0.06 * i;
    vec2 dir = uFoco - vec2(0.5);
    float largo = length(dir);
    dir = largo > 0.02 ? dir / largo : vec2(0.0, -1.0);
    float a = (0.6 + i) * 0.035 * -cos(2.0 * PI * uT / (2.0 * (32.0 - 14.0 * i)));
    q = vec2(0.5) + (q - vec2(0.5)) / s + dir * a;
  } else if (m == 3.0) {
    // Flotar: agrandada, se mece y gira apenas.
    float w = 2.0 * PI * uT / (26.0 - 10.0 * i);
    float giro = 0.0175 * i * uSg * sin(w);
    vec2 v = (q - vec2(0.5)) * vec2(aspecto, 1.0);
    v = vec2(v.x * cos(giro) - v.y * sin(giro), v.x * sin(giro) + v.y * cos(giro));
    q = vec2(0.5) + v / vec2(aspecto, 1.0) / 1.14;
    q -= vec2(0.024 * i * uSg * sin(w), 0.016 * i * sin(2.0 * w));
  } else if (m == 4.0) {
    // Respirar: late despacio, en tamaño y en luz.
    float e = vaiven(uT, 2.0 * (9.0 - 4.0 * i));
    q = vec2(0.5) + (q - vec2(0.5)) / (1.01 + (0.02 + 0.06 * i) * e);
    luz = 1.0 + 0.14 * i * e;
  } else if (m == 5.0) {
    // Ondular: como agua que corre por la imagen.
    q = vec2(0.5) + (q - vec2(0.5)) / 1.08;
    vec2 k = q * vec2(3.0 * aspecto, 3.0);
    float t = uT * 0.07;
    vec2 d = vec2(fbm(k + vec2(t, 0.0)), fbm(k + vec2(5.2, -1.3 * t))) - 0.5;
    q += d * (0.014 + 0.03 * i);
  }
  return vec3(q, luz);
}

vec3 leer(vec2 uv) {
  return texture(uImg, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 pant = fc / uRes;
  float aspP = uRes.x / uRes.y;
  float aspI = uTam.x / max(uTam.y, 1.0);

  // Dónde cae la imagen: cubriendo la pantalla, o entera al medio con los
  // bordes fundidos en la copia chica.
  vec2 cubre = aspI > aspP ? vec2(aspI / aspP, 1.0) : vec2(1.0, aspP / aspI);
  vec2 q;
  float dentro = 1.0;
  if (uCont > 0.5) {
    vec2 tam = aspI < aspP ? vec2(aspI / aspP, 1.0) : vec2(1.0, aspP / aspI);
    q = (pant - (vec2(1.0) - tam) * 0.5) / tam;
    vec2 borde = min(q, vec2(1.0) - q) / 0.07;
    dentro = clamp(aspI < aspP ? borde.x : borde.y, 0.0, 1.0);
  } else {
    q = (pant - (vec2(1.0) - cubre) * 0.5) / cubre;
  }

  vec3 animada = animar(q, aspI);
  vec2 uv = animada.xy;
  float luz = animada.z;

  // El glitch: en ráfagas cortas, franjas corridas y los colores separados.
  vec3 img;
  float fase = fract(uT / (6.0 - 2.5 * uG));
  if (uG > 0.0 && fase > 0.86 && fase < 0.94) {
    float franja = floor(pant.y * 18.0);
    float r = h(vec2(franja, floor(uT * 24.0)));
    vec2 corrido = uv + vec2(r > 0.55 ? (r - 0.5) * 0.08 * uG : 0.0, 0.0);
    float sep = 0.012 * uG;
    img = vec3(leer(corrido + vec2(sep, 0.0)).r,
               leer(corrido).g,
               leer(corrido - vec2(sep, 0.0)).b);
  } else {
    img = leer(uv);
  }
  vec3 c = img * luz;

  if (uCont > 0.5) {
    vec2 qr = (pant - (vec2(1.0) - cubre) * 0.5) / cubre;
    vec3 relleno = texture(uChica, clamp(qr, vec2(0.0), vec2(1.0))).rgb * 0.55;
    c = mix(relleno, c, dentro);
  }

  // Oscurecer: un degradé, más fuerte arriba (el título) y abajo. El mismo
  // que pinta `FondoPropio` sin shader.
  float y = pant.y;
  float a = y < 0.4
      ? mix(0.85, 0.45, y / 0.4)
      : (y < 0.72 ? mix(0.45, 0.6, (y - 0.4) / 0.32)
                  : mix(0.6, 1.0, (y - 0.72) / 0.28));
  c *= 1.0 - uO * a;

  c = c * uS + uA * uP * 0.25;
  fragColor = vec4(c, 1.0);
}
