// Póster: luces de fiesta desenfocadas en tres profundidades, haces de luz y
// oscurecido abajo para las letras grandes. En la app, si el evento tiene foto,
// la foto va encima con zoom lento y esto queda para cuando no hay. Es el fondo
// aprobado el 24-sep (docs/pendientes/totem-apariencias.md), pasado a Flutter.
// Mismos uniformes que el resto (ver totem_neon.frag).
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

vec3 lay(vec2 uv, float sc, float sd, float sp) {
  vec2 g = uv * sc + vec2(uT * sp, uT * sp * 0.3);
  vec2 id = floor(g);
  vec2 f = fract(g);
  vec3 a = vec3(0.0);
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 o2 = vec2(float(x), float(y));
      vec2 ci = id + o2;
      float r = h(ci + sd);
      // Sin `continue`: la celda vacía suma cero.
      float hay = step(0.45, r);
      vec2 ps = o2 + vec2(h(ci * 1.37 + sd), h(ci * 2.11 + sd)) - f;
      float sz = mix(0.18, 0.5, h(ci + sd * 3.1));
      float d = length(ps);
      float dk = smoothstep(sz, sz * 0.8, d);
      float rm = smoothstep(sz * 0.72, sz * 0.95, d) * dk;
      vec3 col = mix(uA, mix(vec3(1.0, 0.72, 0.42), vec3(1.0, 0.42, 0.62), h(ci + 7.0)), 0.55);
      a += hay * col * (dk * 0.22 + rm * 0.2) * (0.65 + 0.35 * sin(uT * 0.8 + r * 30.0));
    }
  }
  return a;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  fc.y = uRes.y - fc.y;
  vec2 uv = fc / uRes;
  float z = 1.0 + 0.06 * sin(uT * 0.05);
  vec2 p = ((uv - 0.5) / z + 0.5) * vec2(uRes.x / uRes.y, 1.0);
  vec3 c = mix(vec3(0.05, 0.02, 0.07), vec3(0.35, 0.12, 0.18), smoothstep(0.1, 0.75, uv.y));
  c += vec3(0.9, 0.45, 0.25) * 0.25 * exp(-8.0 * length(uv - vec2(0.5, 0.62)));
  vec2 d = uv - vec2(0.5, 1.05);
  float an = atan(d.x, -d.y);
  float bm = 0.0;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    bm += exp(-60.0 * abs(an - 0.45 * sin(uT * 0.2 + fi * 1.7))) * 0.5;
  }
  c += mix(uA, vec3(1.0, 0.85, 0.7), 0.5) * bm * smoothstep(1.2, 0.2, length(d)) * 0.5;
  c += lay(p, 2.2, 1.0, 0.02) * 1.1 + lay(p, 4.0, 7.0, 0.035) * 0.8 + lay(p, 7.0, 13.0, 0.05) * 0.6;
  c += (h(fc + fract(uT) * 91.0) - 0.5) * 0.06;
  c = mix(c, vec3(0.02, 0.01, 0.03), smoothstep(0.55, 0.0, uv.y) * 0.85);
  c *= 1.0 - 0.45 * dot(uv - 0.5, uv - 0.5) * 2.0;
  // Usa todos los uniformes: uno sin usar lo saca el compilador y se corren
  // las posiciones de `setFloat`.
  c += (uB + vec3(uP)) * (uD * 1e-6);
  fragColor = vec4(c * uS, 1.0);
}
