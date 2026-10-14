// Cristal: gradiente líquido (el color del evento, violeta y azul) con grano
// fino. Es el fondo aprobado el 24-sep (docs/pendientes/totem-apariencias.md),
// pasado a Flutter. Mismos uniformes que el resto (ver totem_neon.frag).
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
  vec2 uv = fc / uRes;
  vec2 p = uv * vec2(uRes.x / uRes.y, 1.0) * 1.25;
  float t = uT * 0.07;
  vec2 q = vec2(fbm(p + t), fbm(p + vec2(5.2, 1.3) - t));
  vec2 r = vec2(fbm(p + 2.0 * q + vec2(1.7, 9.2) + t * 0.7),
                fbm(p + 2.0 * q + vec2(8.3, 2.8) - t * 0.6));
  float f = fbm(p + 2.4 * r);
  vec3 c = mix(vec3(0.02, 0.015, 0.06), vec3(0.10, 0.30, 0.95), smoothstep(0.25, 0.65, f));
  c = mix(c, vec3(0.50, 0.28, 1.0), smoothstep(0.3, 0.9, length(q)) * 0.85);
  c = mix(c, uA, smoothstep(0.55, 0.95, r.y) * 0.9);
  c *= 0.7 + 0.45 * f;
  c += (h(fc + fract(uT) * 100.0) - 0.5) * 0.035;
  c *= 1.0 - 0.4 * dot(uv - 0.5, uv - 0.5) * 2.0;
  // Usa todos los uniformes: uno sin usar lo saca el compilador y se corren
  // las posiciones de `setFloat`.
  c += (uB + vec3(uP)) * (uD * 1e-6);
  fragColor = vec4(c * uS, 1.0);
}
