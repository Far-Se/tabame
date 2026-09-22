#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uLight;
uniform vec3 uBackground;
uniform vec3 uForeground;
uniform vec3 uAccent;
out vec4 fragColor;

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 uv = pixel / max(uSize, vec2(1.0));
  // Broad, oblique folds: a material response, not an animated wallpaper.
  vec2 p = (pixel - uSize * 0.5) / max(uSize.x, uSize.y);
  float phase = p.x * 19.0 + p.y * 6.0
      + sin(p.y * 5.0 + p.x * 2.0) * 1.4
      + dot(uLight, vec2(0.55, 0.3));
  float fold = 0.5 + 0.5 * sin(phase);
  float sheen = pow(fold, 8.0);
  float shadow = pow(1.0 - fold, 3.0);

  // Quiet center for scanning results. Most of the light belongs to the edges.
  float sides = smoothstep(0.15, 0.5, abs(uv.x - 0.5));
  float ends = smoothstep(0.28, 0.5, abs(uv.y - 0.5));
  float exposure = 0.10 + 0.90 * max(sides, ends * 0.65);
  vec3 color = mix(uBackground, uAccent, sheen * exposure * 0.11);
  color = mix(color, uForeground, sheen * exposure * 0.028);
  color *= 1.0 - shadow * exposure * 0.035;

  // Static sub-pixel grain breaks up banding without sparkling or crawling.
  float grain = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
  color += (grain - 0.5) * 0.002;
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
