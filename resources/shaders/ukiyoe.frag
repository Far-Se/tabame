#version 460 core
#include <flutter/runtime_effect.glsl>

// Static print: size 0..1, material 2, paper 3..5, indigo 6..8,
// vermilion 9..11. Geometry and clipping belong to LauncherCorners in Dart.
uniform vec2 uSize;
uniform float uMaterial;
uniform vec3 uPaper;
uniform vec3 uInk;
uniform vec3 uRed;
out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
      mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float pigment(vec2 p) {
  // Long cuts in the block, varying pressure and small unprinted pores.
  float cuts = noise(vec2(p.x * 0.023, p.y * 0.85));
  float pressure = noise(p * 0.065);
  float pores = smoothstep(0.81, 0.96, hash(floor(p * 1.4)));
  return clamp(0.87 + pressure * 0.11 - cuts * 0.09 - pores * 0.14, 0.0, 1.0);
}

vec3 printInk(vec3 paper, vec3 ink, float coverage, vec2 p) {
  return mix(paper, ink, clamp(coverage * pigment(p), 0.0, 1.0));
}

float mountain(vec2 uv) {
  float slope = abs(uv.x - 0.76) / 0.15;
  float ridge = 0.23 + slope * 0.64;
  return smoothstep(ridge - 0.008, ridge + 0.008, uv.y) * (1.0 - smoothstep(0.87, 0.90, uv.y));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / max(uSize, vec2(1.0));
  // Paper is stable in local pixel coordinates: no clock, shimmer or crawl.
  float fine = hash(floor(p * 1.6)) - 0.5;
  float fibers = noise(vec2(p.x * 0.30, p.y * 0.035)) - 0.5;
  float pulp = noise(p * 0.018) - 0.5;
  vec3 paper = clamp(uPaper + vec3(fine * 0.023 + fibers * 0.021 + pulp * 0.018), 0.0, 1.0);
  vec3 color = paper;

  if (uMaterial > 1.5) {
    // A lightly loaded block for the active result; type stays sharp above it.
    float load = 0.15 + 0.045 * (1.0 - uv.x) + 0.02 * noise(p * 0.03);
    color = printInk(paper, uInk, load, p);
    float edge = min(p.y, uSize.y - p.y);
    float uneven = 0.5 + 0.6 * noise(vec2(p.x * 0.12, 9.0));
    float impression = 1.0 - smoothstep(uneven, uneven + 0.7, edge);
    color = printInk(color, uInk, impression * 0.36, p);
  } else if (uMaterial > 0.5) {
    // Bokashi-like sky: pigment fades into the paper instead of emitting light.
    color = printInk(paper, uInk, (1.0 - smoothstep(0.0, 0.70, uv.y)) * 0.23, p);

    vec2 sun = p - vec2(uSize.x * 0.88, uSize.y * 0.28);
    float sunRadius = min(uSize.y * 0.155, 16.0);
    float sunEdge = length(sun) - sunRadius + (noise(p * 0.22) - 0.5) * 0.7;
    color = printInk(color, uRed, (1.0 - smoothstep(-0.5, 0.6, sunEdge)) * 0.92, p);

    // A slightly offset color block peeks beyond the key outline.
    float mount = mountain(uv);
    float offsetMount = mountain(uv + vec2(0.0018, -0.007));
    color = printInk(color, uInk, offsetMount * 0.27, p);
    color = printInk(color, uInk, mount * 0.64, p);
    float snowLine = 0.38 + 0.025 * sin(uv.x * 165.0) + 0.018 * sin(uv.x * 280.0);
    float snow = mount * (1.0 - smoothstep(snowLine - 0.008, snowLine + 0.008, uv.y));
    color = mix(color, paper, snow * 0.93);

    // Three separately printed sea blocks with carved contour lines.
    for (int layer = 0; layer < 3; layer++) {
      float n = float(layer);
      float crest = 0.65 + n * 0.105 + sin(uv.x * 10.0 + n * 1.7) * (0.067 + n * 0.012);
      float y = (uv.y - crest) * uSize.y;
      float sea = smoothstep(-0.5, 0.8, y);
      vec3 blue = mix(uInk, paper, 0.38 - n * 0.15);
      color = printInk(color, blue, sea, p + vec2(n * 17.0, 0.0));
      float carved = 1.0 - smoothstep(0.25, 0.95, abs(sin(y * 0.49 + sin(uv.x * 21.0) * 0.4)) * 3.0);
      color = mix(color, paper, carved * sea * 0.40 * pigment(p));
      float foam = 1.0 - smoothstep(0.5, 1.5, abs(y));
      color = mix(color, paper, foam * 0.82);
    }

    // A hooked crest rises above the sea. Offset circles form the hollow curl.
    vec2 wave = p - vec2(uSize.x * 0.48, uSize.y * 0.70);
    float radius = uSize.y * 0.27;
    float outside = length(wave) - radius;
    float hollow = length(wave - vec2(radius * 0.36, -radius * 0.18)) - radius * 0.74;
    float curl = (1.0 - smoothstep(-0.6, 0.6, outside)) * smoothstep(-0.6, 0.6, hollow);
    curl *= 1.0 - smoothstep(radius * 0.10, radius * 0.72, wave.y);
    color = printInk(color, uInk, curl * 0.95, p);
    float rim = (1.0 - smoothstep(0.35, 1.3, abs(outside))) * curl;
    color = mix(color, paper, rim * 0.9);
  }

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
