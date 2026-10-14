// Gala: textura de seda oscura, haces de luz que barren y polvo dorado. Es el
// fondo aprobado el 24-sep (docs/pendientes/totem-apariencias.md), pasado a
// Flutter. Mismos uniformes que el resto (ver totem_neon.frag).
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

void main() {
  vec2 fc = FlutterFragCoord().xy;
  fc.y = uRes.y - fc.y;
  vec2 uv = (fc - 0.5 * uRes) / uRes.y;
  vec3 c = vec3(0.018, 0.013, 0.026);
  float s = fbm(uv * 2.2 + vec2(fbm(uv * 3.0 + uT * 0.02), fbm(uv * 3.0 - uT * 0.017)));
  c += vec3(0.11, 0.085, 0.05) * smoothstep(0.35, 0.95, s);
  vec2 d = uv - vec2(0.0, 0.62);
  float an = atan(d.x, -d.y);
  float ry = 0.0;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    ry += exp(-30.0 * abs(an - 0.55 * sin(uT * 0.13 + fi * 2.1))) *
          (0.55 + 0.45 * n(vec2(an * 12.0, uT * 0.25 + fi)));
  }
  c += uA * ry * 0.3 * smoothstep(1.5, 0.0, length(d));
  c += uA * 0.1 * exp(-3.0 * length(uv - vec2(0.0, 0.05)));
  vec2 g = fc / uRes.y * 38.0 + vec2(0.0, -uT * 1.2);
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  float rr = h(id);
  vec2 of = vec2(h(id + 1.3), h(id + 2.7)) - 0.5;
  float dd = length(f - of * 0.7);
  float sp = smoothstep(0.09, 0.0, dd) * step(0.92, rr) * (0.4 + 0.6 * sin(uT * 2.0 + rr * 30.0));
  c += mix(uA, vec3(1.0, 0.95, 0.8), 0.55) * sp;
  c *= 1.0 - 0.55 * dot(uv, uv);
  c = c * uS + uA * uP * 0.18;
  // Usa todos los uniformes: uno sin usar lo saca el compilador y se corren
  // las posiciones de `setFloat`.
  c += uB * (uD * 1e-6);
  fragColor = vec4(c, 1.0);
}
