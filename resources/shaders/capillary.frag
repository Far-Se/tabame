#version 460 core
#include <flutter/runtime_effect.glsl>

// Float slots match _CapillaryPainter: 26 floats, no texture captures.
uniform vec2 uSize;           // 0, 1
uniform float uKind;          // 2: paper, wash, search, overlay
uniform float uSelected;      // 3
uniform float uSelectionAge;  // 4
uniform float uReleaseAge;    // 5
uniform vec2 uPointer;        // 6, 7
uniform float uHovered;       // 8
uniform float uHoverAge;      // 9
uniform float uLeaveAge;      // 10
uniform vec3 uPress;          // 11..13: position, age
uniform vec2 uDrop0;          // 14, 15: search-edge x, age
uniform vec2 uDrop1;          // 16, 17
uniform vec2 uDrop2;          // 18, 19
uniform vec3 uPaper;          // 20..22
uniform vec3 uPigment;        // 23..25
out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float roundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Pigment follows the same stationary paper fibers at every stage. Only the
// absorption front changes; moving noise would make the sheet look like water.
float blot(vec2 p, vec2 origin, float age, vec2 stretch, float reach, float fibers, float grain) {
  if (age < 0.0 || age > 1.7) return 0.0;
  float spread = 1.0 - exp(-age * 5.0);
  float radius = 5.0 + reach * sqrt(spread);
  float distance = length((p - origin) / stretch) - radius + fibers * 3.5;
  float fill = 1.0 - smoothstep(-2.0, 3.0 + spread * 2.0, distance);
  float deposit = exp(-abs(distance + 1.5) * 0.48);
  float drying = 1.0 - smoothstep(0.18, 1.7, age);
  return (fill * (0.65 + grain * 0.2) + deposit * 0.25) * drying;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  float grain = noise(p * 0.83);
  float fiber = noise(p * vec2(0.075, 1.3));
  float pulp = noise(p * vec2(0.032, 0.095));
  float feather = (pulp - 0.5) * 2.0 + (fiber - 0.5) * 0.8;
  vec3 paper = uPaper + (grain - 0.5) * 0.024 + (fiber - 0.5) * 0.011;
  paper -= (1.0 - pulp) * vec3(0.004, 0.005, 0.008);

  if (uKind > 2.5) {
    // Premultiplied, almost transparent fibers over opaque plugin content.
    float alpha = (1.0 - grain) * 0.009 + (1.0 - fiber) * 0.003;
    fragColor = vec4(uPigment * alpha, alpha);
    return;
  }

  float ink = 0.0;
  float wet = 0.0;
  // The wash settles over the whole row at once. A low-resolution noise field
  // keeps the fade tactile without bringing back a directional sweep.
  float selectionFade = uSelected > 0.5
      ? 1.0 - exp(-uSelectionAge * 4.0)
      : 1.0 - smoothstep(0.0, 1.25, uReleaseAge);
  if (uKind > 0.5 && uKind < 1.5 && selectionFade > 0.001) {
    float pixelNoise = hash(floor(p / 2.5));
    float fade = smoothstep(0.02, 0.98, selectionFade + (pixelNoise - 0.5) * 0.12 + feather * 0.035);
    vec2 center = uSize * 0.5;
    float distance = roundedBox(
        p - center, vec2(max(0.0, uSize.x * 0.5 - 1.0), max(2.0, uSize.y * 0.5 - 6.0)), 5.0);
    distance += feather * 1.5;
    float fill = 1.0 - smoothstep(-1.5, 3.5, distance);
    float edge = exp(-abs(distance + 1.0) * 0.65);
    wet = exp(-uSelectionAge * 2.8) * uSelected;
    ink += fade * (fill * (0.12 + wet * 0.055 + grain * 0.025) + edge * 0.045);
  }

  float hover = mix(1.0 - smoothstep(0.0, 0.55, uLeaveAge),
                    1.0 - exp(-uHoverAge * 12.0), uHovered);
  float hoverDistance = length((p - uPointer) / vec2(1.35, 1.0)) - 19.0 + feather * 3.0;
  ink += (1.0 - smoothstep(-3.0, 12.0, hoverDistance)) * hover * 0.065;
  ink += blot(p, uPress.xy, uPress.z, vec2(1.2, 1.0), 27.0, feather, grain) * 0.17;

  if (uKind > 1.5) {
    // Three bounded deposits overlap along the lower search edge. Dense pigment
    // stays below the text, even during rapid typing or a long paste.
    float feed = blot(p, vec2(uDrop0.x, uSize.y + 3.0), uDrop0.y, vec2(2.4, 0.75), 24.0, feather, grain);
    feed += blot(p, vec2(uDrop1.x, uSize.y + 3.0), uDrop1.y, vec2(2.4, 0.75), 24.0, feather, grain);
    feed += blot(p, vec2(uDrop2.x, uSize.y + 3.0), uDrop2.y, vec2(2.4, 0.75), 24.0, feather, grain);
    ink += min(feed, 1.6) * smoothstep(0.55, 0.98, uv.y) * 0.44;
    float rule = exp(-abs(p.y - uSize.y + 2.0 + feather * 0.6) * 1.5);
    ink += rule * 0.32;
  } else if (uKind < 0.5) {
    // Slightly denser sizing at the sheet's edges, like pressed cotton paper.
    float edge = min(min(p.x, uSize.x - p.x), min(p.y, uSize.y - p.y));
    ink = ink * 0.45 + exp(-max(edge + feather, 0.0) * 0.45) * 0.07;
  }

  float limit = uKind > 1.5 ? mix(0.22, 0.65, smoothstep(0.6, 0.98, uv.y)) : 0.24;
  vec3 pigment = mix(uPigment, uPigment * vec3(0.84, 0.85, 0.93), wet);
  vec3 color = mix(paper, pigment, clamp(ink, 0.0, limit));
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
