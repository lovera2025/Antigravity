// Neón: bruma de dos colores, piso de grilla en perspectiva que avanza, marco
// doble con brillo y una luz que lo recorre. Es el fondo aprobado el 24-sep
// (docs/pendientes/totem-apariencias.md), pasado a Flutter.
//
// Uniformes, en el orden de `FondoTotem` (setFloat): uRes (0-1), uT (2),
// uA (3-5), uB (6-8), uP (9), uS (10), uD (11).
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uRes;
uniform float uT;
uniform vec3 uA;
uniform vec3 uB;
uniform float uP;
uniform float uS;
uniform float uD;

out vec4 fragColor;

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
  for (int i = 0; i < 5; i++) {
    v += a * n(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

float sdRB(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  // Flutter tiene el origen arriba; el diseño, abajo.
  fc.y = uRes.y - fc.y;
  vec2 uv = (fc - 0.5 * uRes) / uRes.y;
  float hz = -0.17;
  vec3 c = vec3(0.012, 0.004, 0.028);

  float f = fbm(vec2(uv.x * 1.6 + uT * 0.04, uv.y * 2.2 - uT * 0.03));
  c += mix(uB, uA, smoothstep(0.3, 0.75, f)) * 0.22 * f * step(hz, uv.y);
  c += uA * 0.75 * exp(-55.0 * abs(uv.y - hz)) + uB * 0.24 * exp(-10.0 * abs(uv.y - hz));

  if (uv.y < hz) {
    float d = hz - uv.y;
    float z = 0.32 / d;
    vec2 g = vec2(uv.x * z * 1.4, z + uT * 1.1);
    vec2 q = abs(fract(g + 0.5) - 0.5);
    // El ancho de la línea, calculado: `fwidth` puede no estar en el formato
    // que usan las PCs.
    vec2 w = vec2(1.4 * z, z * z / 0.32) * 1.3 / uRes.y;
    float ln = max(1.0 - smoothstep(0.0, w.x, q.x), 1.0 - smoothstep(0.0, w.y, q.y));
    float fd = smoothstep(0.0, 0.35, d);
    c += uA * ln * mix(0.15, 1.0, fd) + uA * 0.1 * exp(-d * 4.0);
  }

  vec2 sid = floor(fc / (2.5 * uD));
  float st = step(0.9975, h(sid)) * (0.4 + 0.6 * sin(uT * 2.5 + h(sid) * 50.0));
  c += vec3(0.9, 0.85, 1.0) * st * step(hz + 0.05, uv.y);

  vec2 p = fc - 0.5 * uRes;
  float dd = abs(sdRB(p, 0.5 * uRes - vec2(13.0 * uD), 16.0 * uD)) / uD;
  float core = exp(-dd * 0.8);
  float glw = exp(-dd * 0.11);
  c += mix(uA, vec3(1.0), 0.35) * core * 0.9 + uA * glw * 0.32;
  float d2 = abs(sdRB(p, 0.5 * uRes - vec2(21.0 * uD), 11.0 * uD)) / uD;
  c += uB * exp(-d2 * 1.3) * 0.45;
  float an = atan(p.y, p.x);
  float ch = exp(-4.0 * abs(mod(an - uT * 1.1 + 3.14159, 6.28318) - 3.14159));
  c += vec3(1.0) * ch * core * 1.4;

  c *= 0.94 + 0.06 * sin(fc.y / uD * 3.14159);
  c *= 1.0 - 0.5 * dot(uv * 0.85, uv * 0.85);
  c = c * uS + uA * uP * 0.25;
  fragColor = vec4(c, 1.0);
}
