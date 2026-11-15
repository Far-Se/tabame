#version 460 core
#include <flutter/runtime_effect.glsl>

// GroundGlassPainter float order:
// size (2), pointer (2), pointer active (1), focus center/half-size (4),
// rack (1), background, foreground, accent (3x3). No samplers.
// The selected row is a focal plane. Hex discs grow with defocus.
// A split prism follows the pointer and coincides on that plane.
uniform vec2 uSize;
uniform vec2 uPointer;
uniform float uPointerActive;
uniform vec4 uFocus;
uniform float uRack;
uniform vec3 uBackground;
uniform vec3 uForeground;
uniform vec3 uAccent;

out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float roundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float hexDist(vec2 p) {
  p = abs(p);
  return max(p.x * 0.8660254 + p.y * 0.5, p.y);
}

float defocusAt(vec2 p) {
  float band = 0.34;
  if (uFocus.w > 1.0) {
    vec2 center = vec2(uSize.x * 0.5, uFocus.y);
    vec2 halfSize = vec2(uSize.x * 0.5, max(uFocus.w, 1.0));
    float outside = roundedBox(p - center, halfSize, min(7.0, halfSize.y));
    band = smoothstep(0.0, 84.0, outside);
  }
  // The query and the footer stay on clear glass. Typing racks only the query.
  float searchZone = 1.0 - smoothstep(58.0, 86.0, p.y);
  float footer = smoothstep(uSize.y - 56.0, uSize.y - 32.0, p.y);
  float held = mix(band, 0.0, max(searchZone, footer));
  return clamp(held + searchZone * uRack * 0.9, 0.0, 1.0);
}

float grainAt(vec2 p) {
  float fine = hash(floor(p));
  float grit = hash(floor(p * 0.5 + 19.0));
  return fine * 0.65 + grit * 0.35;
}

float fresnelAt(vec2 p) {
  float radius = length(p - uSize * 0.5);
  float grit = hash(floor(p * 0.35));
  float ring = abs(fract(radius * 0.0072 + grit * 0.03) - 0.5);
  return smoothstep(0.455, 0.5, ring);
}

float discAt(vec2 p, float defocus) {
  if (defocus < 0.05) return 0.0;
  float scale = 72.0;
  vec2 cell = floor(p / scale);
  float amount = 0.0;
  for (int n = 0; n < 9; n++) {
    float index = float(n);
    vec2 id = cell + vec2(mod(index, 3.0) - 1.0, floor(index / 3.0) - 1.0);
    float chance = hash(id + 4.2);
    float gate = step(0.86, chance);
    vec2 center = (id + vec2(hash(id), hash(id + 9.0))) * scale;
    float radius = mix(1.2, 8.5, defocus) * mix(0.7, 1.0, hash(id + 2.0));
    float body = smoothstep(1.35, 0.15, hexDist(p - center) - radius);
    amount = max(amount, body * gate);
  }
  return amount * defocus;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float defocus = defocusAt(p);
  float luma = dot(uBackground, vec3(0.299, 0.587, 0.114));
  float night = 1.0 - smoothstep(0.28, 0.62, luma);

  vec2 sampleP = p;
  float prism = 0.0;
  float ring = 0.0;
  float splitLine = 0.0;
  float locked = 0.0;
  if (uPointerActive > 0.01) {
    vec2 delta = p - uPointer;
    float dist = length(delta);
    prism = 1.0 - smoothstep(26.0, 29.0, dist);
    float split = defocusAt(uPointer) * 7.0;
    float side = delta.y >= 0.0 ? 1.0 : -1.0;
    sampleP = mix(p, p + vec2(split * side, 0.0), step(0.001, prism));
    ring = smoothstep(1.5, 0.15, abs(dist - 28.0));
    splitLine = smoothstep(0.7, 0.0, abs(delta.y)) * (1.0 - smoothstep(26.0, 29.0, dist));
    locked = 1.0 - smoothstep(0.4, 5.5, split);
  }

  float grain = grainAt(sampleP);
  float tooth = hash(floor(p * 0.07));
  vec3 color = uBackground;
  color += (tooth - 0.5) * 0.014;
  color += (grain - 0.5) * mix(0.02, 0.007, defocus);
  color = mix(color, uForeground, fresnelAt(sampleP) * 0.045);

  float focused = (1.0 - defocus) * step(1.0, uFocus.w) * (1.0 - prism);
  color = mix(color, uBackground, focused * 0.55);
  color = mix(color, uAccent, focused * 0.04);

  vec3 lamp = mix(mix(uBackground, vec3(1.0), 0.55), uAccent, 0.42);
  float discs = discAt(p, defocus) * (1.0 - prism);
  color = mix(color, lamp, discs * mix(0.035, 0.08, night));

  vec3 patch = uBackground + (grainAt(sampleP) - 0.5) * 0.03;
  patch = mix(patch, uForeground, fresnelAt(sampleP) * 0.04);
  color = mix(color, patch, prism * uPointerActive * 0.88);
  color = mix(color, uAccent, ring * uPointerActive * mix(0.22, 0.62, locked));
  color = mix(color, uForeground, splitLine * uPointerActive * 0.28);

  vec2 uv = p / max(uSize, vec2(1.0));
  float vignette = smoothstep(0.58, 1.05, length((uv - 0.5) * vec2(1.15, 1.0)));
  color *= 1.0 - vignette * mix(0.05, 0.09, night) * (0.45 + defocus);

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
