#version 460 core
#include <flutter/runtime_effect.glsl>

// Float slots: size 0..1, phase 2, radius 3, mode 4, background 5..7,
// accent 8..10, CSS corner K 11. No texture capture: text stays on Flutter's
// normal render path. K matches LauncherCorners / CornerShapeBorder.
uniform vec2 uSize;
uniform float uPhase;
uniform float uRadius;
uniform float uMode;
uniform vec3 uBackground;
uniform vec3 uAccent;
uniform float uCorner;
out vec4 fragColor;

float launcherBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  if (radius < 0.001) {
    vec2 square = abs(p) - halfSize;
    return length(max(square, 0.0)) + min(max(square.x, square.y), 0.0);
  }
  // Away from the corner, all three shapes share the same straight edges.
  if (min(q.x, q.y) <= 0.0) return max(q.x, q.y) - radius;
  if (uCorner < 0.5) {
    // Exact distance to the bevel's diagonal, including its end points.
    vec2 start = vec2(0.0, radius);
    vec2 edge = vec2(radius, -radius);
    float t = clamp(dot(q - start, edge) / dot(edge, edge), 0.0, 1.0);
    return length(q - start - edge * t) * sign(q.x + q.y - radius);
  }
  if (uCorner < 1.5) return length(q) - radius;

  // CSS squircle: x^4 + y^4 = r^4 (K=2). Normalizing by the
  // gradient gives a distance estimate that keeps the glow width consistent.
  vec2 v = q / radius;
  float norm = sqrt(length(v * v));
  vec2 gradient = v * v * v / max(norm * norm * norm, 0.000001);
  return (norm - 1.0) * radius / max(length(gradient), 0.000001);
}

float segment(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

// Monoline lettering keeps the same distance-field bloom and moving light
// traces as the original symbols. Capital T, then lowercase a-b-a-m-e.
float tabameLetter(vec2 p, float index) {
  if (index < 0.5) {
    return min(segment(p, vec2(-5, -8), vec2(5, -8)), segment(p, vec2(0, -8), vec2(0, 7)));
  }
  vec2 bowl = p - vec2(0.0, 2.0);
  float ring = abs(length(bowl) - 5.0);
  if (index < 1.5 || (index > 2.5 && index < 3.5)) {
    return min(ring, segment(p, vec2(5, -3), vec2(5, 7)));
  }
  if (index < 2.5) {
    return min(ring, segment(p, vec2(-5, -8), vec2(-5, 7)));
  }
  if (index < 4.5) {
    // Two upper semicircles join the three stems of the lowercase m.
    vec2 arch = vec2(abs(p.x) - 2.5, p.y + 0.5);
    float arches = arch.y <= 0.0 ? abs(length(arch) - 2.5)
        : min(length(arch - vec2(-2.5, 0)), length(arch - vec2(2.5, 0)));
    float stems = min(segment(p, vec2(-5, -3), vec2(-5, 7)),
        min(segment(p, vec2(0, -0.5), vec2(0, 7)), segment(p, vec2(5, -0.5), vec2(5, 7))));
    return min(arches, stems);
  }
  // Open the lower-right side of the bowl and add the e's crossbar.
  if (bowl.x > 0.0 && bowl.y > 0.0 && bowl.y < bowl.x * 0.75) {
    ring = min(length(bowl - vec2(5, 0)), length(bowl - vec2(4, 3)));
  }
  return min(ring, segment(p, vec2(-5, 2), vec2(5, 2)));
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec3 coldWhite = mix(uAccent, vec3(0.9, 0.98, 1.0), 0.86);
  if (uMode > 1.5) {
    // Six letters centered in the existing strip, with space for the halo.
    float scale = max(min(uSize.x / 132.0, uSize.y / 32.0), 0.001);
    vec2 local = (pixel - uSize * 0.5) / scale;
    float index = clamp(floor((local.x + 54.0) / 18.0), 0.0, 5.0);
    vec2 p = local - vec2((index + 0.5) * 18.0 - 54.0, 0.0);
    float d = tabameLetter(p, index) * scale;
    float angle = atan(p.y + 0.0001, p.x + 0.0001);
    float trace = pow(0.5 + 0.5 * cos(angle - uPhase * 2.0 + index * 1.4), 12.0);
    float bloom = exp(-d * 0.35) * (0.3 + trace * 0.55);
    float core = exp(-d * d * 1.6);
    float alpha = clamp(bloom + core * 0.85, 0.0, 1.0);
    vec3 color = mix(uAccent, coldWhite, core * (0.35 + trace * 0.65));
    fragColor = vec4(color * alpha, alpha);
    return;
  }

  bool selection = uMode > 0.5;
  float inset = selection ? 1.5 : 12.0;
  vec2 halfSize = max(uSize * 0.5 - inset, vec2(1.0));
  float radius = clamp(uRadius, 0.0, min(halfSize.x, halfSize.y));
  vec2 p = pixel - uSize * 0.5;
  float distance = launcherBox(p, halfSize, radius);
  float edge = abs(distance);
  float inside = 1.0 - smoothstep(-0.7, 0.7, distance);
  float angle = atan(p.y / halfSize.y + 0.0001, p.x / halfSize.x + 0.0001);
  float moving = pow(0.5 + 0.5 * cos(angle - uPhase), 18.0);
  float opposite = pow(0.5 + 0.5 * cos(angle + uPhase - 3.141593), 24.0);
  float energy = 0.55 + moving * 0.7 + opposite * 0.4;

  // Narrow white-blue filament, a saturated halo and broader radiating waves.
  // Traveling hot spots provide visible movement without blinking the panel.
  float filament = exp(-edge * edge * 1.5);
  float halo = exp(-edge * (selection ? 0.22 : 0.18));
  float wave = 0.5 + 0.5 * sin(edge * 0.48 - uPhase * 3.0 + sin(angle * 5.0 + uPhase));
  float radiation = exp(-edge * 0.075) * wave * (moving + opposite) * 0.22;
  float exposure = clamp(halo * energy * 0.65 + radiation, 0.0, 0.88);
  vec3 fill = mix(uBackground, uAccent, selection ? 0.20 : 0.015);
  vec3 color = mix(fill, uAccent, exposure);
  color = mix(color, coldWhite, filament * min(energy, 1.0) * (selection ? 0.45 : 0.95));

  // Transparent space outside the frame contains real premultiplied bloom.
  float outer = clamp(halo * energy + radiation, 0.0, 1.0);
  outer *= 1.0 - smoothstep(7.0, 12.0, max(distance, 0.0));
  float alpha = max(inside, outer);
  fragColor = vec4(color * alpha, alpha);
}
